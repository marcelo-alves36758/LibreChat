# Dockerfile — LibreChat FE+BE (injeta custom.css no HTML, sem tocar no style.css)
FROM node:20-alpine AS base
WORKDIR /app

# Dependências de build (node-gyp etc.)
RUN apk add --no-cache python3 py3-pip build-base

# (opcional) bust de cache de tema
ARG THEME_SHA=dev

# Manifests — instalação determinística
COPY package.json package-lock.json ./
COPY api/package.json ./api/package.json
COPY client/package.json ./client/package.json
COPY packages/data-provider/package.json ./packages/data-provider/package.json
COPY packages/data-schemas/package.json ./packages/data-schemas/package.json
COPY packages/api/package.json ./packages/api/package.json

# Configuração do backend (custom config)
COPY custom/librechat.yaml /app/librechat.yaml

# Instala dependências
RUN npm ci --no-audit

# Asserção: config deve existir
RUN test -f /app/librechat.yaml \
  && echo "OK: /app/librechat.yaml presente" \
  || (echo "ERRO: /app/librechat.yaml ausente"; exit 1)

# Código do projeto (inclui /custom)
COPY . .

# ====== Incluir custom.css via <link> no index.html (sem sobrescrever style.css) ======
# Procura o CSS em ordem: custom/custom.css, custom/hero.css, custom/style.css
# Copia para public/custom.css e injeta <link ...> antes de </head> no index.html
RUN set -e; \
  SRC=""; \
  for C in /app/custom/custom.css /app/custom/hero.css /app/custom/style.css; do \
    if [ -f "$C" ]; then SRC="$C"; break; fi; \
  done; \
  if [ -z "$SRC" ]; then \
    echo "ERRO: não encontrei /app/custom/custom.css (ou hero.css/style.css)."; \
    exit 1; \
  fi; \
  echo ">> Usando CSS fonte: $SRC"; \
  FOUND_HTML=0; \
  for D in /app/client /app/packages/client; do \
    if [ -f "$D/index.html" ]; then \
      FOUND_HTML=1; \
      mkdir -p "$D/public"; \
      cp "$SRC" "$D/public/custom.css"; \
      # Injeta apenas se ainda não houver referência a custom.css
      if ! grep -Eq '/custom\.css|%BASE_URL%custom\.css' "$D/index.html"; then \
        echo ">> Injetando <link> em $D/index.html"; \
        sed -i "s#</head>#  <link rel=\"stylesheet\" href=\"%BASE_URL%custom.css\" />\n</head>#I" "$D/index.html"; \
      else \
        echo ">> Link para custom.css já existe em $D/index.html (nada a fazer)"; \
      fi; \
    fi; \
  done; \
  if [ $FOUND_HTML -eq 0 ]; then \
    echo "ERRO: index.html não encontrado em /app/client ou /app/packages/client."; \
    exit 1; \
  fi; \
  echo '>> custom.css copiado para public/ e link injetado com sucesso.'

# ====== Build do client ======
ENV NODE_OPTIONS="--max-old-space-size=2048"
RUN npm run frontend

# ====== Compat extra: stub de auth.json (silencia ENOENT sem impactar env/yaml) ======
RUN mkdir -p /app/api/data && \
    { [ -f /app/api/data/auth.json ] || echo '{}' > /app/api/data/auth.json; } && \
    echo "OK: /app/api/data/auth.json presente (stub se não existia)"

# ====== Limpeza ======
RUN npm prune --production && npm cache clean --force

# ====== Runtime do backend ======
EXPOSE 3080
ENV HOST=0.0.0.0
CMD ["npm", "run", "backend"]
