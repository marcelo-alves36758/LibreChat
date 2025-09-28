# Dockerfile — LibreChat FE+BE (seguro) com injeção de custom.css no dist
FROM node:20-alpine AS base
WORKDIR /app

# Dependências de build
RUN apk add --no-cache python3 py3-pip build-base

# Opcional: bust de cache quando mudar o tema (passe --build-arg THEME_SHA=...)
ARG THEME_SHA=dev

# Manifests — instalação determinística
COPY package.json package-lock.json ./
COPY api/package.json ./api/package.json
COPY client/package.json ./client/package.json
COPY packages/data-provider/package.json ./packages/data-provider/package.json
COPY packages/data-schemas/package.json ./packages/data-schemas/package.json
COPY packages/api/package.json ./packages/api/package.json

# Copia a config para onde o backend REALMENTE lê
COPY custom/librechat.yaml /app/librechat.yaml

RUN npm ci --no-audit

# Asserção: a config precisa existir no caminho correto
RUN test -f /app/librechat.yaml \
  && echo "OK: /app/librechat.yaml presente" \
  || (echo "ERRO: /app/librechat.yaml ausente"; exit 1)

# Código do projeto (inclui a pasta custom/)
COPY . .

# ====== Build do client (gera /app/client/dist) ======
ENV NODE_OPTIONS="--max-old-space-size=2048"
RUN npm run frontend

# ====== Injeção segura do tema (pós-build) ======
# Usamos custom/custom.css (apenas os patches) como /assets/hero.css,
# e injetamos um <link> no index.html para garantir última prioridade.
RUN if [ -f /app/custom/custom.css ]; then \
      echo ">> Injetando /assets/hero.css (patches) e linkando no index.html"; \
      mkdir -p /app/client/dist/assets; \
      cp /app/custom/custom.css /app/client/dist/assets/hero.css; \
      if [ -f /app/client/dist/index.html ]; then \
        # injeta o link antes de </head>
        sed -i 's#</head>#  <link rel="stylesheet" href="/assets/hero.css">\n</head>#' /app/client/dist/index.html; \
      else \
        echo "WARN: /app/client/dist/index.html não encontrado"; \
      fi; \
    else \
      echo "WARN: /app/custom/custom.css não encontrado; nenhum patch de CSS será aplicado"; \
    fi

# Asserções: se houver custom.css, hero.css e o link DEVEM existir
RUN if [ -f /app/custom/custom.css ]; then \
      test -f /app/client/dist/assets/hero.css \
        || (echo "ERRO: /app/client/dist/assets/hero.css ausente"; exit 1); \
      grep -q 'assets/hero.css' /app/client/dist/index.html \
        || (echo "ERRO: link para hero.css não foi injetado no index.html"; exit 1); \
    fi

# ====== Limpeza ======
RUN npm prune --production && npm cache clean --force

# ====== Runtime do backend ======
EXPOSE 3080
ENV HOST=0.0.0.0
CMD ["npm", "run", "backend"]
