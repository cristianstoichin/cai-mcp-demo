#!/usr/bin/env bash
set -euo pipefail

# ui.sh — launch the demo-ui cockpit. Sources .env (like every other script),
# installs deps on first run, then runs the host-side Node server. Prints the URL.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
UI_DIR="${REPO_DIR}/demo-ui"

[[ -f "${REPO_DIR}/.env" ]] && { set -a; source "${REPO_DIR}/.env"; set +a; }

command -v node >/dev/null 2>&1 || { echo "[ERROR] Node 20+ is required (host prereq)." >&2; exit 1; }

if [[ ! -d "${UI_DIR}/node_modules" ]]; then
  echo "[INFO] Installing demo-ui dependencies (first run)…"
  ( cd "${UI_DIR}" && npm install --no-audit --no-fund )
fi

PORT="${UI_PORT:-4000}"
echo "[INFO] demo-ui → http://127.0.0.1:${PORT}"
exec node "${UI_DIR}/server.js"
