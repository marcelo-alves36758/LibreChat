# Dockerfile — LibreChat FE+BE (substitui style.css por custom/hero.css)
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

# ====== Substituir style.css pelo hero.css (design refeito) ======
# Procura style.css nas bases conhecidas e sobrescreve com /custom/hero.css
RUN set -e; \
  HERO_SRC="/app/custom/hero.css"; \
  if [ ! -f "$HERO_SRC" ]; then \
    echo "ERRO: custom/hero.css não encontrado. Coloque seu CSS em /custom/hero.css"; \
    exit 1; \
  fi; \
  FOUND_CSS=0; \
  for D in /app/client /app/packages/client; do \
    for TARGET in "$D/src/style.css" "$D/style.css" "$D/src/styles.css"; do \
      if [ -f "$TARGET" ]; then \
        echo ">> Substituindo $TARGET por $HERO_SRC"; \
        cp "$HERO_SRC" "$TARGET"; \
        FOUND_CSS=1; \
      fi; \
    done; \
  done; \
  if [ $FOUND_CSS -eq 0 ]; then \
    echo "ERRO: style.css não encontrado em /app/client ou /app/packages/client."; \
    echo "Verifique o caminho do CSS do frontend e ajuste o bloco de substituição se necessário."; \
    exit 1; \
  fi; \
  echo '>> style.css substituído com sucesso pelo custom/hero.css.'

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
