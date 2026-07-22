# dealer-svc — Node 20 Express mock API. No build step beyond `npm ci`.
FROM node:20-alpine

WORKDIR /app

# Install deps first for layer caching (busted by --no-cache rebuilds when code changes).
COPY package.json ./
RUN npm install --omit=dev --no-audit --no-fund

COPY server.js ./

ENV PORT=3000
EXPOSE 3000

CMD ["node", "server.js"]
