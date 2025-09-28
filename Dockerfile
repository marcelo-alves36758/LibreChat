# Base
FROM node:20-alpine AS base
WORKDIR /app

# Dependências do build
RUN apk add --no-cache python3 py3-pip build-base

# Copia manifests (instalação determinística)
COPY package.json package-lock.json ./
COPY api/package.json ./api/package.json
COPY client/package.json ./client/package.json
COPY packages/data-provider/package.json ./packages/data-provider/package.json
COPY packages/data-schemas/package.json ./packages/data-schemas/package.json
COPY packages/api/package.json ./packages/api/package.json

# Instala TODAS deps (dev + prod) para build
RUN npm ci --no-audit

# Copia código
COPY . .

# Substitui o style.css original pelo seu (se existir esse caminho)
# Ajuste se o projeto estiver em outro caminho de styles
RUN if [ -f /app/custom/style.css ]; then \
      echo ">> Aplicando custom/style.css"; \
      cp /app/custom/style.css /app/client/src/styles/style.css; \
    fi

# Build do client (gera /app/client/dist)
ENV NODE_OPTIONS="--max-old-space-size=2048"
RUN npm run frontend

# Limpa dev deps e cache para imagem final mais leve
RUN npm prune --production && npm cache clean --force

# Runtime
EXPOSE 3080
ENV HOST=0.0.0.0
CMD ["npm", "run", "backend"]
