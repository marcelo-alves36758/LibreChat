# Hero: configuração pública e privada

Esta mudança prepara a separação para revisão e homologação. Ela não aplica mudanças no
ambiente implantado. O responsável pelo ambiente precisa comparar a configuração efetiva
antes de promover a imagem: o Git não comprova quais overrides, variáveis, agentes ou bancos
estão sendo usados em produção.

## Contrato de configuração

| Conteúdo | Local | Entra no Git/imagem? |
| --- | --- | --- |
| Tema Ero, Nunito, CSS Hero | `custom/custom.css`, `custom/hero.css` | Sim; bytes preservados |
| Exemplo com campos `REPLACE_*` | `custom/librechat.example.yaml` | Git; excluído da imagem |
| YAML efetivo: recursos Azure, deployments, IDs de agentes, políticas | Arquivo privado fora do checkout | Não; bind mount somente leitura em `/run/secrets/hero-config.yaml` |
| Credenciais e demais variáveis do backend | Arquivo privado fora do checkout ou ambiente gerenciado | Não; arquivo montado somente leitura em `/app/.env` |
| Uploads, imagens enviadas e logs | Volumes de runtime já existentes | Não no build |

`CONFIG_PATH=/run/secrets/hero-config.yaml` é explícito na imagem e no Compose.
`HERO_CONFIG_FILE` e `HERO_ENV_FILE` são caminhos absolutos **no host do Docker/Dokploy**.
O Compose exige ambos e usa `create_host_path: false`: um arquivo ausente não vira um diretório.
Não há cópia de YAML de produção no Dockerfile nem fallback para o exemplo público.
Docker secrets ou outro secret store também podem montar os mesmos destinos; este Compose
usa arquivos locais, não promete criptografia de um secret store.

O entrypoint valida YAML, schema desta versão, referências de ambiente, configuração dos
grupos Azure e catálogo Hero antes de executar o backend. Falhas interrompem a inicialização.
O YAML não é renderizado com segredos: as chaves continuam como `${VARIAVEL}` e são resolvidas
pelo LibreChat. O preflight carrega o mesmo `.env` do backend, com precedência para o ambiente
do processo. Nunca passe credenciais em `ARG`, `ENV` do Dockerfile ou comandos de build.

## Migração a preparar em homologação

1. Identifique, sem imprimir os valores em logs, o `CONFIG_PATH` efetivo da implantação, o
   YAML realmente carregado, os mounts/overrides e as variáveis do backend e do RAG. Preserve
   uma cópia protegida e a identificação da imagem anterior para rollback. O Compose antigo
   montava um YAML em `/app/config/librechat.yaml`, enquanto o Dockerfile gravava outro em
   `/app/librechat.yaml`; o backend usa este último por padrão, salvo `CONFIG_PATH` externo.
2. Coloque cópias desses arquivos **fora do checkout e do contexto de build**, por exemplo
   em um diretório administrado no host. Restrinja o diretório e os arquivos ao administrador
   e à identidade que lê os mounts (tipicamente diretório `0700`, arquivo `0600`, adaptando
   UID/GID ao orquestrador). Não copie o `.env.example` como configuração de produção:
   ele contém defaults públicos. Preserve as chaves de criptografia existentes; trocá-las
   sem plano pode impedir a leitura de credenciais já armazenadas.
3. Configure `HERO_CONFIG_FILE` e `HERO_ENV_FILE` no ambiente de execução do Compose/Dokploy.
   Não confunda esses caminhos com `CONFIG_PATH` dentro do contêiner. O arquivo de ambiente
   mantém MongoDB, autenticação, armazenamento, ferramentas e demais valores efetivos.
4. Valide o YAML privado com `npm run validate:hero-config -- /caminho/absoluto/config.yaml`,
   em um contexto com as variáveis necessárias provisionadas. Para testar dotenv localmente,
   pode-se montar/copiar o arquivo como `.env` apenas no checkout de homologação ignorado;
   nunca comitá-lo nem exportar `docker compose config` completo para um log público.
5. Construa a imagem e execute os testes abaixo. Depois, somente em homologação, valide login
   SSO, os três agentes, conversa nova e antiga, memória, títulos, OCR, STT/TTS, uploads,
   pesquisa, ações, execução de código e artefatos. Verifique permissões dos agentes e
   dependências de seus documentos/ferramentas no banco; um ID no YAML não cria um agente.
6. A promoção para produção depende de autorização separada. Mantenha os volumes e banco
   existentes. Rollback usa a imagem e o contrato de mounts/configuração anteriores;
   não exige reescrever Git ou alterar dados.

### Compatibilidade identificada no YAML público anterior

O exemplo público preserva a interface, memória, catálogo, políticas, limites, uploads e
opções de ferramentas existentes, mas não pode substituir a configuração efetiva sem revisão.
As alterações de estrutura a seguir estão explícitas para evitar uma migração silenciosa:

- `azureOpenAI` e `custom` pertencem a `endpoints`, no mesmo nível de `agents`. No arquivo
  anterior estavam dentro de `agents`; não eram utilizados como endpoints pelo carregador.
- Cada grupo Azure não serverless precisa de `instanceName`. Todos os modelos precisam de
  deployment e versão, próprios ou herdados do grupo. Os nomes reais ficam no arquivo privado.
- `validateAzureGroups` exige nomes de modelo únicos entre grupos. O exemplo mantém os nomes
  primários e usa sufixo `-secondary` para o segundo grupo. Isso **não** cria failover automático.
  Revise qualquer agente que use um alias secundário antes da promoção; IDs e definições dos
  agentes no banco não foram alterados por esta mudança.
- IDs do catálogo precisam ser literais no YAML privado. Não substitua por `${HERO_AGENT_ID}`:
  esta versão não interpola esse campo como interpola credenciais de endpoints.
- O bloco legado `endpoints.azureOpenAI.embeddings` e várias opções em `agents.tools` não
  fazem parte do schema nativo desta versão. Foram preservados no exemplo como contexto de
  migração, sem prometer que tenham efeito. Confira o serviço RAG e as ferramentas dos agentes.
  A validação nativa aceita/descarta campos desconhecidos em alguns objetos; PASS não prova
  que toda opção legada seja aplicada.

Os nomes de ambiente existentes para chaves foram mantidos: `AZURE_API_KEY`,
`CUSTOM_AZURE2_API_KEY`, `AZURE_MISTRAL_OCR_API_KEY`, `AZURE_VISION_EASTUS2_API_KEY`,
`AZURE_DOCINTEL_EASTUS2_API_KEY`, `JINA_API_KEY` e `JINA_BASE_URL`. Outros serviços podem
precisar de variáveis adicionais presentes apenas na implantação.

## Verificação reproduzível

```sh
npm ci --no-audit --no-fund
npm run frontend
npm run check:hero-public
npm run test:hero-config
npm exec --workspace=api -- jest server/services/Config/loadCustomConfig.spec.js --runInBand --silent
docker compose config --quiet
docker build --build-arg THEME_SHA=review -t hero-config-review .
docker run --rm --entrypoint node hero-config-review config/hero/check-build.cjs --image
```

Os dois últimos comandos verificam o contrato da imagem sem iniciar serviços ou acessar Azure.
O Dockerfile copia `custom/custom.css` antes do build e o injeta como último CSS em `</head>`;
`check:hero-build` compara os bytes de origem e saída e verifica a ordem. `npm run frontend`
isolado não executa a injeção específica do Dockerfile. `docker compose config --quiet` exige
os dois caminhos privados provisionados, mas não inicia contêineres.

O workflow `hero-config.yml` faz build sem segredos, valida Compose, verifica falha sem
configuração privada e escaneia novos commits com Gitleaks 8.30.1. O binário tem SHA256 fixado.
Não publica imagem, não solicita credenciais de Azure e não faz deploy. Os workflows antigos
do repositório continuam existindo: revise seus gatilhos antes de merge/promoção.

## Limites e riscos

- Remover o YAML da nova árvore não remove blobs, commits antigos, forks, clones, caches,
  imagens já publicadas ou logs. Qualquer limpeza de histórico ou registry requer autorização.
- Metadados Azure e IDs de agentes facilitam reconhecimento. Sozinhos não comprovam acesso;
  a proteção depende de autenticação, permissões de agentes, rede e chaves.
- Configuração montada fica acessível ao processo e ao administrador do host. Dumps de memória,
  backups e logs de outras camadas precisam de proteção própria. O carregador deixou de
  registrar YAML completo e erros com trechos de conteúdo; isto não é uma auditoria de todos
  os logs de requisições, ferramentas ou SDKs.
- O navegador ainda precisa receber nomes, capacidades e IDs autorizados do catálogo. Separar
  o arquivo do Git não torna esses metadados invisíveis para usuários legítimos da aplicação.
- Nunito continua sendo carregada da origem externa já usada no CSS. Não houve redesenho da
  marca nem alteração dos arquivos visuais. Imagens/logos servidos por volumes não estavam no Git.
- Testes offline não provam conectividade Azure, validade de chaves, agentes existentes,
  permissões, SSO, OCR, áudio ou funcionalidades ponta a ponta. A homologação é necessária.

Veja [o relatório desta auditoria](audit-2026-10-08.md) para escopo, evidências e resultados.
