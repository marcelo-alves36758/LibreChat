# Dockerfile (FE + BE, com fallback de CSS)
FROM node:20-alpine AS base
WORKDIR /app
RUN apk add --no-cache python3 py3-pip build-base

# (opcional) força rebuild quando você muda o tema
ARG THEME_SHA=dev

# Instala dependências para build
COPY package.json package-lock.json ./
COPY api/package.json ./api/package.json
COPY client/package.json ./client/package.json
COPY packages/data-provider/package.json ./packages/data-provider/package.json
COPY packages/data-schemas/package.json ./packages/data-schemas/package.json
COPY packages/api/package.json ./packages/api/package.json
RUN npm ci --no-audit

# Copia o restante do código (inclui a pasta custom/)
COPY . .

# DEBUG opcional (pode remover depois)
RUN echo "=== LISTANDO /app/custom ===" && ls -lah /app/custom || true
RUN echo "=== PROCURANDO CSS no projeto (até 4 níveis) ===" && find /app -maxdepth 4 -name "*.css" | sed -n '1,80p'

# ---------- PATCH DE CSS (pré-build): tenta substituir alvos comuns ----------
RUN if [ -f /app/custom/style.css ]; then \
      echo ">> Aplicando custom/style.css (pré-build)"; \
      TARGETS="/app/client/src/styles/style.css \
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
        echo \"Nenhum alvo encontrado antes do build — seguiremos com fallback pós-build\"; \
      fi; \
    fi

# ---------- Build do client ----------
ENV NODE_OPTIONS="--max-old-space-size=2048"
RUN npm run frontend

# ---------- PATCH DE CSS (pós-build): fallback anexa no dist ----------
RUN if [ -f /app/custom/style.css ]; then \
      if ls /app/client/dist/assets/*.css >/dev/null 2>&1; then \
        echo \">> Anexando custom/style.css em /app/client/dist/assets/*.css\"; \
        for f in /app/client/dist/assets/*.css; do \
          echo \"Patching: $f\"; \
          printf \"\n/* ---- HERO CUSTOM PATCH ---- */\n\" >> \"$f\"; \
          cat /app/custom/style.css >> \"$f\"; \
        done; \
      else \
        echo \"WARN: Nenhum CSS encontrado em /app/client/dist/assets — verifique build do client\"; \
      fi; \
    fi

# Limpeza
RUN npm prune --production && npm cache clean --force

EXPOSE 3080
ENV HOST=0.0.0.0
CMD ["npm", "run", "backend"]
