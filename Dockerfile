# Dockerfile — LibreChat FE+BE (compatível) substitui style.css por custom/hero.css + sanitização
FROM node:20-alpine AS base
WORKDIR /app

# Dependências de build
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

RUN npm ci --no-audit

# Asserção: config deve existir
RUN test -f /app/librechat.yaml \
  && echo "OK: /app/librechat.yaml presente" \
  || (echo "ERRO: /app/librechat.yaml ausente"; exit 1)

# Código do projeto (inclui /custom)
COPY . .

# ====== Substituição do CSS base (pré-build) ======
# Fonte: custom/hero.css (ou custom/style.css fallback)
# Alvos (ordem): client/src/style.css, client/src/hero.css, packages/client/src/styles/style.css
RUN set -e; \
  if [ -f /app/custom/hero.css ]; then SRC="/app/custom/hero.css"; \
  elif [ -f /app/custom/style.css ]; then SRC="/app/custom/style.css"; \
  else echo "ERRO: nem /app/custom/hero.css nem /app/custom/style.css encontrados"; exit 1; fi; \
  echo ">> CSS fonte: $SRC"; \
  TARGETS='/app/client/src/style.css /app/client/src/hero.css /app/packages/client/src/styles/style.css'; \
  REPLACED=0; \
  for T in $TARGETS; do \
    if [ -f "$T" ]; then \
      echo ">> Substituindo $T por $SRC"; \
      cp "$SRC" "$T"; \
      # --- Sanitização: LF, remover BOM, NBSP -> espaço ---
      sed -i 's/\r$//' "$T"; \
      # remove BOM se existir
      sed -i '1s/^\xEF\xBB\xBF//' "$T"; \
      # NBSP (C2 A0) -> espaço ASCII
      perl -0777 -pe "s/\x{C2}\x{A0}/ /g" -i "$T"; \
      REPLACED=1; \
    fi; \
  done; \
  if [ $REPLACED -eq 0 ]; then \
    echo "ERRO: nenhum alvo de CSS encontrado nos caminhos conhecidos."; \
    echo "Verifique onde está o stylesheet principal no seu fork e ajuste o Dockerfile."; \
    exit 1; \
  fi; \
  echo ">> Primeiras linhas do CSS aplicado:"; head -n 12 "$SRC"

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
