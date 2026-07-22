#!/usr/bin/env bash
set -euo pipefail

# install-dashboard.sh — upload the Cox "Governed MCP" analytics dashboard to Konnect.
#
#   POST https://${KONNECT_REGION}.api.konghq.com/v2/dashboards  (X-Konnect-Beta: true)
#   Docs: https://developer.konghq.com/api/konnect/dashboards/
#
# Reads KONNECT_TOKEN + KONNECT_REGION + KONNECT_CONTROL_PLANE_NAME from .env; looks up the
# control-plane id by name (no hardcoded ids) and scopes the dashboard to it via preset_filters.
# The dashboard definition lives in konnect/dashboards/cai-mcp-analytics.json.
#
# NOTE: tiles use the `agentic_usage` datasource (MCP analytics) — data appears only after MCP
# traffic has flowed through Kong and Konnect has ingested it (a short delay). Creating the
# dashboard succeeds immediately; the charts populate once there is traffic.

GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'; NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
DASH_FILE="${REPO_DIR}/konnect/dashboards/cai-mcp-analytics.json"
[[ -f "${REPO_DIR}/.env" ]] && { set -a; source "${REPO_DIR}/.env"; set +a; }

REGION="${KONNECT_REGION:-us}"
TOKEN="${KONNECT_TOKEN:-${DECK_KONNECT_TOKEN:-}}"
CP_NAME="${KONNECT_CONTROL_PLANE_NAME:-cai-mcp-demo}"
DASH_NAME="${DASHBOARD_NAME:-Cox Automotive: Governed MCP}"
API="https://${REGION}.api.konghq.com"

for tool in curl python3; do
  command -v "$tool" >/dev/null 2>&1 || { echo -e "${RED}[ERROR]${NC} '$tool' is required." >&2; exit 1; }
done
[[ -z "${TOKEN}" ]] && { echo -e "${RED}[ERROR]${NC} KONNECT_TOKEN not set (fill .env)." >&2; exit 1; }
[[ -f "${DASH_FILE}" ]] || { echo -e "${RED}[ERROR]${NC} missing ${DASH_FILE}" >&2; exit 1; }
AUTH="Authorization: Bearer ${TOKEN}"

# ---------------------------------------------------------------------------
# Step 1 — resolve control-plane id by name (portable; nothing hardcoded)
# ---------------------------------------------------------------------------
echo -e "${YELLOW}[1/2]${NC} Resolving control plane '${CP_NAME}'"
CP_ID=$(curl -s "${API}/v2/control-planes?filter%5Bname%5D%5Beq%5D=${CP_NAME}" -H "${AUTH}" \
  | python3 -c "import sys,json; d=json.load(sys.stdin).get('data',[]); print(d[0]['id'] if d else '')" 2>/dev/null || true)
[[ -z "${CP_ID}" ]] && { echo -e "${RED}[ERROR]${NC} control plane '${CP_NAME}' not found (run konnect-bootstrap.sh first)." >&2; exit 1; }
echo -e "${GREEN}  ${CP_ID}${NC}"

# ---------------------------------------------------------------------------
# Step 2 — wrap the tiles into the /v2/dashboards envelope and POST
# ---------------------------------------------------------------------------
echo -e "${YELLOW}[2/2]${NC} Creating dashboard '${DASH_NAME}'"
PAYLOAD="$(python3 -c "
import json,sys
src=json.load(open('${DASH_FILE}'))
tiles=src.get('tiles',[])
for t in tiles: t.pop('id',None)  # Konnect assigns tile ids
payload={
  'name': '${DASH_NAME}',
  'labels': {'demo': 'cai-mcp-demo'},
  'definition': {
    'preset_filters': [{'field':'control_plane','operator':'in','value':['${CP_ID}']}],
    'tiles': tiles,
  },
}
print(json.dumps(payload))
")"

resp=$(curl -s -w "\n%{http_code}" -X POST "${API}/v2/dashboards" \
  -H "${AUTH}" -H "Content-Type: application/json" -H "X-Konnect-Beta: true" \
  -d "${PAYLOAD}")
code=$(echo "${resp}" | tail -1); body=$(echo "${resp}" | sed '$d')

if [[ "${code}" =~ ^2 ]]; then
  DID=$(echo "${body}" | python3 -c "import sys,json; print(json.load(sys.stdin).get('id','?'))" 2>/dev/null || echo "?")
  echo -e "${GREEN}  ✓ created${NC} (id: ${DID})"
  echo ""
  echo -e "${GREEN}Done.${NC} View it in Konnect → Analytics → Dashboards. Charts populate once MCP"
  echo "traffic has flowed (run scripts/demo.sh a few times, then wait a minute for ingestion)."
else
  echo -e "${RED}  ✗ create failed (HTTP ${code})${NC}"
  echo "${body}" | python3 -m json.tool 2>/dev/null || echo "${body}"
  echo -e "${YELLOW}Note:${NC} MCP analytics dashboards are a Konnect Advanced Analytics feature — confirm your"
  echo "org tier + region (${REGION}) support the agentic_usage datasource + the beta dashboards API."
  exit 1
fi
