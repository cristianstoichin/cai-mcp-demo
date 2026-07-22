#!/usr/bin/env bash
set -euo pipefail

# rebuild.sh — rebuild one or more compose services from scratch (NO cache) and
# recreate the containers. Enforces the project rule: a code change is never
# served from a stale image layer.
#
# Usage:
#   scripts/rebuild.sh                 # rebuild ALL buildable services
#   scripts/rebuild.sh dealer-svc      # rebuild just dealer-svc
#   scripts/rebuild.sh dealer-svc finance-svc market-mcp

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${REPO_DIR}"

echo "[rebuild] docker compose build --no-cache $*"
docker compose build --no-cache "$@"

echo "[rebuild] docker compose up -d --force-recreate $*"
docker compose up -d --force-recreate "$@"

echo "[rebuild] done."
