#!/usr/bin/env bash
set -euo pipefail

# claude-code-setup.sh — emit `claude mcp add` lines to register the demo's MCP
# servers with Claude Code, each with a bearer token for a suitable persona.
#
#   scripts/claude-code-setup.sh            # print the commands (copy/paste)
#   scripts/claude-code-setup.sh --apply    # also run them
#   scripts/claude-code-setup.sh --persona olivia   # force one persona for all
#
# By default each server gets a token from the persona that can use it:
#   dealers → dana, finance → frank, ops/remote/remote-public → olivia (both groups).
# Tokens are short-lived; re-run to refresh. Remote MCP servers are added with the
# streamable-http transport pointed at Kong (:8000), so ALL access stays governed.

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
[[ -f "${REPO_DIR}/.env" ]] && { set -a; source "${REPO_DIR}/.env"; set +a; }
KONG="${KONG_URL:-http://localhost:8000}"

APPLY=false; FORCE_PERSONA=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --apply) APPLY=true ;;
    --persona) FORCE_PERSONA="${2:-}"; shift ;;
    *) echo -e "${RED}[ERROR]${NC} unknown arg: $1" >&2; exit 1 ;;
  esac
  shift
done

command -v claude >/dev/null 2>&1 || $APPLY && command -v claude >/dev/null 2>&1 || {
  $APPLY && { echo -e "${RED}[ERROR]${NC} 'claude' CLI not found but --apply given." >&2; exit 1; }
}

tok(){ "${SCRIPT_DIR}/get-token.sh" "$1" --raw 2>/dev/null; }

# name : path : default-persona
SERVERS=(
  "cox-dealers:/mcp/dealers:dana"
  "cox-finance:/mcp/finance:frank"
  "cox-ops:/mcp/ops:olivia"
  "cox-market:/mcp/remote:olivia"
  "cox-deepwiki:/mcp/remote-public:olivia"
)

echo -e "${YELLOW}# Claude Code MCP registration for cai-mcp-demo (Kong @ ${KONG})${NC}"
echo -e "${YELLOW}# Tokens are short-lived — re-run this script to refresh.${NC}"
echo ""
for entry in "${SERVERS[@]}"; do
  IFS=':' read -r name path persona <<<"$entry"
  persona="${FORCE_PERSONA:-$persona}"
  token="$(tok "$persona")"
  if [[ -z "$token" ]]; then echo -e "${RED}# skip ${name}: could not mint ${persona} token (is Keycloak up?)${NC}"; continue; fi
  cmd="claude mcp add --transport http ${name} ${KONG}${path} --header \"Authorization: Bearer ${token}\""
  echo "$cmd"
  if $APPLY; then
    claude mcp add --transport http "${name}" "${KONG}${path}" --header "Authorization: Bearer ${token}" \
      && echo -e "${GREEN}#  ✓ added ${name}${NC}" || echo -e "${RED}#  ✗ failed ${name}${NC}"
  fi
  echo ""
done
$APPLY || echo -e "${YELLOW}# (re-run with --apply to execute these, or copy/paste them)${NC}"
