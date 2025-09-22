# v0.8.0-rc4

# Base node image
FROM node:20-alpine AS node

# Install jemalloc
RUN apk add --no-cache jemalloc
RUN apk add --no-cache python3 py3-pip uv

# Set environment variable to use jemalloc
ENV LD_PRELOAD=/usr/lib/libjemalloc.so.2

# Add `uv` for extended MCP support
COPY --from=ghcr.io/astral-sh/uv:0.6.13 /uv /uvx /bin/
RUN uv --version

RUN mkdir -p /app && chown node:node /app
WORKDIR /app

USER node

COPY --chown=node:node package.json package-lock.json ./
COPY --chown=node:node api/package.json ./api/package.json
COPY --chown=node:node client/package.json ./client/package.json
COPY --chown=node:node packages/data-provider/package.json ./packages/data-provider/package.json
COPY --chown=node:node packages/data-schemas/package.json ./packages/data-schemas/package.json
COPY --chown=node:node packages/api/package.json ./packages/api/package.json

RUN \
    # Allow mounting of these files, which have no default
    touch .env ; \
    # Create directories for the volumes to inherit the correct permissions
    mkdir -p /app/client/public/images /app/api/logs /app/uploads ; \
    npm config set fetch-retry-maxtimeout 600000 ; \
    npm config set fetch-retries 5 ; \
    npm config set fetch-retry-mintimeout 15000 ; \
    npm ci --no-audit

COPY --chown=node:node . .

# === ADIÇÃO: copia o librechat.yaml "baked" e prepara fallback ===
# Coloque seu librechat.yaml na raiz do repo (mesmo nível do Dockerfile)
# Ele será usado como padrão, mas pode ser sobrescrito por um bind/file mount.
COPY --chown=node:node librechat.yaml /app/librechat.baked.yaml
# Queremos usar /app/librechat.yaml. Se não existir no runtime (sem mount),
# copiamos do baked na entrada (ver ENTRYPOINT).
ENV CONFIG_PATH=/app/librechat.yaml
###############

RUN \
    # React client build
    NODE_OPTIONS="--max-old-space-size=2048" npm run frontend; \
    npm prune --production; \
    npm cache clean --force

# Node API setup
EXPOSE 3080
ENV HOST=0.0.0.0
CMD ["npm", "run", "backend"]


# === ADIÇÃO: entrypoint que garante um CONFIG_PATH válido ===
# Usa root apenas para criar/ajustar o arquivo na inicialização
USER root
RUN printf '%s\n' \
'#!/bin/sh' \
'set -e' \
'# se não existir /app/librechat.yaml mas existir o baked, copie' \
'if [ ! -f "$CONFIG_PATH" ] && [ -f /app/librechat.baked.yaml ]; then' \
'  cp /app/librechat.baked.yaml "$CONFIG_PATH";' \
'fi' \
'exec su node -c "npm run backend"' \
> /entrypoint.sh && chmod +x /entrypoint.sh
USER node

ENTRYPOINT ["/entrypoint.sh"]

# Optional: for client with nginx routing
# FROM nginx:stable-alpine AS nginx-client
# WORKDIR /usr/share/nginx/html
# COPY --from=node /app/client/dist /usr/share/nginx/html
# COPY client/nginx.conf /etc/nginx/conf.d/default.conf
# ENTRYPOINT ["nginx", "-g", "daemon off;"]
