# demo-ui — Cox governed-MCP cockpit. Multi-stage (mirrors the aegis dashboard).
# Runs as a Compose service reaching Kong/Keycloak on the in-network hostnames.
# No build step (vanilla-JS SPA) — the "dev" stage just runs the Node server.

FROM node:20-alpine AS base
WORKDIR /app
COPY package*.json ./

# --- dev/run stage: prod deps + docker CLI (read-only status tiles) ---
FROM base AS dev
# docker-cli lets /api/status read `docker ps` via the mounted socket. Read-only;
# Stack execute actions are host-only (see server.js + README).
RUN apk add --no-cache docker-cli

# Dependencies. Corporate TLS interception (e.g. Zscaler) can break the PUBLIC npm
# registry from inside a build container — `npm ci` then dies with
# UNABLE_TO_GET_ISSUER_CERT_LOCALLY — while the HOST npm works because it is pointed at
# an internal Artifactory mirror. So: prefer a `node_modules/` supplied by the build
# context (populate it once with `cd demo-ui && npm install --omit=dev`), and only fall
# back to installing inside the container. `node_modules/` is deliberately NOT in
# .dockerignore for this reason. See NOTES.md 2026-08-12.
COPY . .
RUN if [ -f node_modules/express/index.js ]; then \
      echo "deps: using node_modules from build context"; \
    else \
      echo "deps: no usable node_modules in context — installing in-container" && \
      npm ci --omit=dev; \
    fi
# Fail the BUILD, not the container, if deps are still unusable. The previous
# `npm ci || npm install` masked a half-finished install and shipped an image whose
# node_modules/express/ was an EMPTY DIRECTORY — the container then crash-looped on
# ERR_MODULE_NOT_FOUND at runtime. Assert it here instead.
RUN test -f node_modules/express/index.js || (echo "FATAL: express missing from node_modules" && exit 1)

EXPOSE 4000
CMD ["node", "server.js"]
