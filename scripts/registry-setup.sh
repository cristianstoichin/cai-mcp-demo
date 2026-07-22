#!/usr/bin/env bash
set -euo pipefail

# registry-setup.sh — create the Konnect MCP Registry and publish the demo's MCP
# servers, then list what's discoverable.
#
#   Base: https://klabs.${KONNECT_REGION}.api.konghq.com/v0/mcp-registries  (US, Tech Preview)
#   Enable: Konnect → Organization → Labs → "Catalog - MCP Registry" → ON
#   Docs:   https://developer.konghq.com/catalog/mcp-registry/
#
# Idempotent: reuses the registry if it already exists; re-publishing a server
# version is a no-op/update. Reads KONNECT_TOKEN + KONNECT_REGION from .env.
#
# NOTE: the registry entries advertise http://localhost:8000/mcp/* (the canonical
# external base URL). A discovering client (e.g. Claude Code on your host) connects
# there. Run this from a host that can reach the Konnect Labs API for your region.

GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'; NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
BODIES="${REPO_DIR}/konnect/mcp-registry"
[[ -f "${REPO_DIR}/.env" ]] && { set -a; source "${REPO_DIR}/.env"; set +a; }

REGION="${KONNECT_REGION:-us}"
TOKEN="${KONNECT_TOKEN:-${DECK_KONNECT_TOKEN:-}}"
API="https://klabs.${REGION}.api.konghq.com/v0/mcp-registries"
REGISTRY_NAME="$(python3 -c "import json;print(json.load(open('${BODIES}/create-registry.json'))['name'])")"

for tool in curl python3; do
  command -v "$tool" >/dev/null 2>&1 || { echo -e "${RED}[ERROR]${NC} '$tool' is required." >&2; exit 1; }
done
[[ -z "${TOKEN}" ]] && { echo -e "${RED}[ERROR]${NC} KONNECT_TOKEN not set (fill .env)." >&2; exit 1; }
AUTH="Authorization: Bearer ${TOKEN}"

# The 5 servers to publish (body file : friendly label).
PUBLISH=(
  "publish-dealers.json:dealers (/mcp/dealers)"
  "publish-finance.json:finance (/mcp/finance)"
  "publish-ops.json:ops bundled (/mcp/ops)"
  "publish-remote.json:market remote (/mcp/remote)"
  "publish-remote-public.json:deepwiki remote-public (/mcp/remote-public)"
)

# ---------------------------------------------------------------------------
# Step 1 — find or create the registry
# ---------------------------------------------------------------------------
echo -e "${YELLOW}[1/3]${NC} Find-or-create registry '${REGISTRY_NAME}' @ ${API}"
list_code=$(curl -s -o /tmp/cai-registries.json -w "%{http_code}" "${API}" -H "${AUTH}")
if [[ "${list_code}" != "200" ]]; then
  echo -e "${RED}[ERROR]${NC} List registries returned HTTP ${list_code}." >&2
  echo "Is 'Catalog - MCP Registry' enabled in Konnect Labs for region '${REGION}'? (Tech Preview, US only.)" >&2
  cat /tmp/cai-registries.json >&2; exit 1
fi

REGISTRY_ID=$(python3 -c "
import json,sys
name=sys.argv[1]
for r in json.load(open('/tmp/cai-registries.json')).get('data',[]):
    if r.get('name')==name: print(r['id']); break
" "${REGISTRY_NAME}" 2>/dev/null || true)

if [[ -n "${REGISTRY_ID}" ]]; then
  echo -e "${GREEN}  exists${NC}: ${REGISTRY_ID}"
else
  create=$(curl -s -w "\n%{http_code}" -X POST "${API}" -H "${AUTH}" \
    -H "Content-Type: application/json" -d @"${BODIES}/create-registry.json")
  code=$(echo "${create}" | tail -1); body=$(echo "${create}" | sed '$d')
  [[ "${code}" =~ ^2 ]] || { echo -e "${RED}[ERROR]${NC} create failed HTTP ${code}:" >&2; echo "${body}" >&2; exit 1; }
  REGISTRY_ID=$(echo "${body}" | python3 -c "import sys,json;print(json.load(sys.stdin)['id'])")
  echo -e "${GREEN}  created${NC}: ${REGISTRY_ID}"
fi

# ---------------------------------------------------------------------------
# Step 2 — publish each server (POST /{id}/v0.1/publish)
# ---------------------------------------------------------------------------
echo -e "${YELLOW}[2/3]${NC} Publishing ${#PUBLISH[@]} servers"
for entry in "${PUBLISH[@]}"; do
  file="${entry%%:*}"; label="${entry#*:}"
  resp=$(curl -s -w "\n%{http_code}" -X POST "${API}/${REGISTRY_ID}/v0.1/publish" \
    -H "${AUTH}" -H "Content-Type: application/json" -d @"${BODIES}/${file}")
  code=$(echo "${resp}" | tail -1); body=$(echo "${resp}" | sed '$d')
  if [[ "${code}" =~ ^2 ]]; then
    echo -e "  ${GREEN}✓${NC} ${label}"
  else
    echo -e "  ${RED}✗${NC} ${label} (HTTP ${code}): $(echo "${body}" | python3 -c 'import sys,json;print(json.load(sys.stdin).get("message",sys.stdin.read()))' 2>/dev/null || echo "${body}")"
  fi
done

# ---------------------------------------------------------------------------
# Step 3 — discovery (GET /{id}/v0.1/servers)
# ---------------------------------------------------------------------------
echo -e "${YELLOW}[3/3]${NC} Discovery — GET /${REGISTRY_ID}/v0.1/servers"
curl -s "${API}/${REGISTRY_ID}/v0.1/servers" -H "${AUTH}" | python3 -c "
import sys,json
data=json.load(sys.stdin)
servers=data.get('servers', data.get('data', []))
print(f'  {len(servers)} server(s) discoverable:')
for s in servers:
    d=s.get('server', s)
    remotes=d.get('remotes',[])
    url=remotes[0].get('url','?') if remotes else '?'
    print(f\"    - {d.get('name','?')} v{d.get('version','?')}  ->  {url}\")
" 2>/dev/null || echo "  (could not parse discovery response)"

echo ""
echo -e "${GREEN}Done.${NC} Registry: ${REGISTRY_ID}"
echo -e "${YELLOW}[append to .env]${NC} KONNECT_MCP_REGISTRY_ID=${REGISTRY_ID}"
