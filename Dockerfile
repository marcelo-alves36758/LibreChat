# Dockerfile — LibreChat FE+BE (injeta custom.css como último CSS)
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

# ====== Injeta custom.css no build do frontend (sem tocar no style.css) ======
# Coloca custom.css em client/public para ser copiado ao dist
RUN set -e; \
  CUSTOM_SRC="/app/custom/custom.css"; \
  PUB_DIR="/app/client/public"; \
  if [ ! -f "$CUSTOM_SRC" ]; then \
    echo "ERRO: custom/custom.css não encontrado. Coloque seu CSS em /custom/custom.css"; \
    exit 1; \
  fi; \
  mkdir -p "$PUB_DIR"; \
  cp "$CUSTOM_SRC" "$PUB_DIR/custom.css"; \
  echo ">> custom.css copiado para client/public/ (entrará no build)."

# ====== Build do client ======
ENV NODE_OPTIONS="--max-old-space-size=2048"
RUN npm run frontend

# ====== Garante custom.css no dist e injeta como último CSS ======
RUN set -e; \
  DIST_DIR="/app/client/dist"; \
  INDEX_HTML="$DIST_DIR/index.html"; \
  # Alguns toolchains podem mover assets; garanta que exista em /dist/
  if [ ! -f "$DIST_DIR/custom.css" ]; then \
    if [ -f "/app/client/public/custom.css" ]; then \
      cp "/app/client/public/custom.css" "$DIST_DIR/custom.css"; \
    else \
      echo "ERRO: custom.css não encontrado após build"; exit 1; \
    fi; \
  fi; \
  # Injeta link imediatamente antes de </head> (último CSS na página)
  if [ -f "$INDEX_HTML" ]; then \
    echo ">> Injetando <link rel=\"stylesheet\" href=\"/custom.css?v=$THEME_SHA\"> no dist/index.html"; \
    sed -i '/<\/head>/i \ \ <link rel="stylesheet" href="/custom.css?v='"$THEME_SHA"'" />' "$INDEX_HTML"; \
  else \
    echo "ERRO: dist/index.html não encontrado. Verifique o comando de build do frontend."; \
    exit 1; \
  fi; \
  echo '>> custom.css injetado com sucesso como último CSS.'

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
