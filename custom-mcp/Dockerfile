# Hand-written Python MCP server (Streamable HTTP) — the /mcp/custom passthrough target.
# Mirrors market-mcp/Dockerfile: no build step, install deps then run the module.
FROM python:3.12-slim
WORKDIR /app
ENV PYTHONUNBUFFERED=1 PIP_NO_CACHE_DIR=1
COPY requirements.txt ./
RUN pip install --no-cache-dir -r requirements.txt
COPY server.py ./
EXPOSE 3000
# python:slim has no stock unprivileged user (unlike node:slim's `node`), so make one.
RUN useradd --create-home --uid 10001 appuser
USER appuser
CMD ["python", "server.py"]
