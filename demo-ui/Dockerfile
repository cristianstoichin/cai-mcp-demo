# demo-ui — Cox governed-MCP cockpit. Multi-stage (mirrors the aegis dashboard).
# Runs as a Compose service reaching Kong/Keycloak on the in-network hostnames.
# No build step (vanilla-JS SPA) — the "dev" stage just runs the Node server.

FROM node:20-alpine AS base
WORKDIR /app
COPY package*.json ./

# --- dev/run stage: install prod deps + docker CLI (read-only status tiles) ---
FROM base AS dev
# docker-cli lets /api/status read `docker ps` via the mounted socket. Read-only;
# Stack execute actions are host-only (see server.js + README).
RUN apk add --no-cache docker-cli
RUN npm ci --omit=dev || npm install --omit=dev
COPY . .
EXPOSE 4000
CMD ["node", "server.js"]
