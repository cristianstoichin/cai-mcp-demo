#!/usr/bin/env bash
set -euo pipefail

# get-token.sh — mint a Keycloak access token for a demo persona (ROPC via demo-cli).
#
# Usage:
#   scripts/get-token.sh <dana|frank|olivia> [scope-override] [--raw]
#
#   dana    -> dana.dealer   (group dealers)  default scope: openid dealers:read mcp:use
#   frank   -> frank.finance (group finance)  default scope: openid finance:read mcp:use
#   olivia  -> olivia.ops    (group ops)      default scope: openid dealers:read finance:read mcp:use
#
#   scope-override : pass an explicit space-separated scope string to prove the
#                    negative paths (e.g. a dealer-only token hitting a finance route -> 403).
#   --raw          : print only the raw access token (for TOKEN=$(... --raw)).
#
# Reads KEYCLOAK_BASE, DEMO_PASSWORD, DEMO_CLI_SECRET from .env (or the environment).

GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'; NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
[[ -f "${REPO_DIR}/.env" ]] && { set -a; source "${REPO_DIR}/.env"; set +a; }

KEYCLOAK_BASE="${KEYCLOAK_BASE:-http://localhost:8080}"
REALM="${KEYCLOAK_REALM:-cox-auto}"
CLIENT_ID="${DEMO_CLI_CLIENT_ID:-demo-cli}"
CLIENT_SECRET="${DEMO_CLI_SECRET:-demo-cli-secret-change-me}"
PASSWORD="${DEMO_PASSWORD:-Demo1234!}"
TOKEN_URL="${KEYCLOAK_BASE}/realms/${REALM}/protocol/openid-connect/token"

for tool in curl jq; do
  command -v "$tool" >/dev/null 2>&1 || { echo -e "${RED}[ERROR]${NC} '$tool' is required." >&2; exit 1; }
done

RAW=false; PERSONA=""; SCOPE_OVERRIDE=""
for arg in "$@"; do
  case "$arg" in
    --raw) RAW=true ;;
    dana|frank|olivia) PERSONA="$arg" ;;
    *) SCOPE_OVERRIDE="$arg" ;;
  esac
done
[[ -z "$PERSONA" ]] && { echo -e "${RED}[ERROR]${NC} persona required: dana | frank | olivia" >&2; exit 1; }

case "$PERSONA" in
  dana)   USERNAME="dana.dealer";   DEFAULT_SCOPE="openid dealers:read mcp:use" ;;
  frank)  USERNAME="frank.finance"; DEFAULT_SCOPE="openid finance:read mcp:use" ;;
  olivia) USERNAME="olivia.ops";    DEFAULT_SCOPE="openid dealers:read finance:read mcp:use" ;;
esac
SCOPE="${SCOPE_OVERRIDE:-$DEFAULT_SCOPE}"

[[ "$RAW" == false ]] && echo -e "${YELLOW}[INFO]${NC} ${USERNAME} @ ${TOKEN_URL} (scope: ${SCOPE})" >&2

RESPONSE="$(curl -sf -X POST "$TOKEN_URL" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "grant_type=password" \
  -d "client_id=${CLIENT_ID}" \
  -d "client_secret=${CLIENT_SECRET}" \
  -d "username=${USERNAME}" \
  -d "password=${PASSWORD}" \
  --data-urlencode "scope=${SCOPE}")" || {
    echo -e "${RED}[ERROR]${NC} token request failed. Is Keycloak up (docker compose up -d keycloak) and .env correct?" >&2
    exit 1
  }

ACCESS_TOKEN="$(echo "$RESPONSE" | jq -r '.access_token // empty')"
if [[ -z "$ACCESS_TOKEN" ]]; then
  echo -e "${RED}[ERROR]${NC} no access_token: $(echo "$RESPONSE" | jq -r '.error_description // .error // "unknown"')" >&2
  exit 1
fi

if [[ "$RAW" == true ]]; then printf '%s' "$ACCESS_TOKEN"; exit 0; fi

# Decode + pretty-print the JWT payload (base64url, padded).
payload_b64="$(echo "$ACCESS_TOKEN" | cut -d. -f2 | tr '_-' '/+')"
pad=$(( (4 - ${#payload_b64} % 4) % 4 )); payload_b64="${payload_b64}$(printf '=%.0s' $(seq 1 $pad 2>/dev/null))"
echo ""
echo -e "${GREEN}[OK]${NC} token for ${USERNAME}"
echo "--- JWT payload (claims) ---"
echo "$payload_b64" | base64 -d 2>/dev/null | jq '{sub, preferred_username, groups, scope, aud, azp, exp}' 2>/dev/null || echo "(decode failed)"
echo ""
echo -e "${YELLOW}[export line]${NC}"
echo "export TOKEN='${ACCESS_TOKEN}'"
