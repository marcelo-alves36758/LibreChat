# Dockerfile — LibreChat FE+BE com patch de CSS robusto
FROM node:20-alpine AS base
WORKDIR /app

# Dependências de build
RUN apk add --no-cache python3 py3-pip build-base

# Opcional: bust de cache quando mudar o tema (pode passar --build-arg THEME_SHA=...)
ARG THEME_SHA=dev

# Instala dependências a partir dos manifests (instalação determinística)
COPY package.json package-lock.json ./
COPY api/package.json ./api/package.json
COPY client/package.json ./client/package.json
COPY packages/data-provider/package.json ./packages/data-provider/package.json
COPY packages/data-schemas/package.json ./packages/data-schemas/package.json
COPY packages/api/package.json ./packages/api/package.json
# copia sua config para dentro da imagem
COPY custom/librechat.yaml /app/librechat.yaml

RUN npm ci --no-audit

# garante que o arquivo está no lugar que o backend lê
RUN test -f /app/librechat.yaml && echo "OK: /app/librechat.yaml presente" || (echo "ERRO: /app/librechat.yaml ausente"; exit 1)

# Copia todo o código (inclui /custom/style.css e /custom/librechat.yaml)
COPY . .

# ---------- PATCH DE CSS (pré-build): tenta substituir arquivos-alvo comuns ----------
# Ajuste a lista se necessário; estes cobrem as variações mais frequentes no repo
RUN if [ -f /app/custom/style.css ]; then \
      echo ">> Aplicando custom/style.css (pré-build)"; \
      TARGETS="/app/client/src/style.css \
               /app/client/src/mobile.css \
               /app/client/src/styles/style.css \
               /app/packages/client/src/styles/style.css \
               /app/client/src/styles/index.css \
               /app/client/src/styles/globals.css \
               /app/client/src/styles/global.css \
               /app/client/src/styles/tailwind.css"; \
      REPLACED=0; \
      for t in $TARGETS; do \
        if [ -f \"$t\" ]; then \
          echo \"Substituindo: $t\"; \
          cp /app/custom/style.css \"$t\"; \
          REPLACED=1; \
        fi; \
      done; \
      if [ $REPLACED -eq 0 ]; then \
        echo \"Nenhum alvo encontrado antes do build — usaremos fallback pós-build\"; \
      fi; \
    fi

# ---------- Build do client (gera /app/client/dist) ----------
ENV NODE_OPTIONS="--max-old-space-size=2048"
RUN npm run frontend

# ---------- PATCH DE CSS (pós-build): fallback anexa o custom.css em TODOS os CSS do dist ----------
RUN if [ -f /app/custom/style.css ]; then \
      FILES=$(find /app/client/dist -type f -name "*.css" 2>/dev/null); \
      if [ -n "$FILES" ]; then \
        echo ">> Anexando custom/style.css em $(echo "$FILES" | wc -l) arquivo(s) CSS do dist"; \
        for f in $FILES; do \
          echo "Patching: $f"; \
          printf "\n/* ---- HERO CUSTOM PATCH ---- */\n" >> "$f"; \
          cat /app/custom/style.css >> "$f"; \
        done; \
      else \
        echo "WARN: Nenhum CSS encontrado no dist — verifique o build do client"; \
      fi; \
    fi

# Limpeza para imagem final menor
RUN npm prune --production && npm cache clean --force

# Runtime do backend
EXPOSE 3080
ENV HOST=0.0.0.0
CMD ["npm", "run", "backend"]
