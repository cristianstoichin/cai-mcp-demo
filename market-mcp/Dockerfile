# Local Cox-themed MCP server. Plain ESM Node (no build step) — npm install to
# resolve the MCP SDK + express + zod, then run server.js.
FROM node:20-slim
WORKDIR /app
COPY package.json ./
RUN npm install --omit=dev
COPY server.js ./
EXPOSE 3000
USER node
CMD ["node", "server.js"]
