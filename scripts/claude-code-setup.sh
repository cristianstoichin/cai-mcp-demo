#!/usr/bin/env bash
set -euo pipefail

# claude-code-setup.sh — emit `claude mcp add` lines to register the demo's MCP
# servers with Claude Code. Two auth modes:
#
#   BEARER (default) — each server gets a short-lived Keycloak token (ROPC) for a
#   suitable persona, injected as an Authorization header. Non-interactive; best for
#   scripted/stage demos.
#   BROWSER (--browser) — no tokens; each server is registered against the pre-built
#   `claude-code` public client so Claude Code drives the real OAuth authorization-code
#   flow (you log in as a persona in the browser). This is the "harness gets a proper
#   token the real way" story.
#
#   scripts/claude-code-setup.sh              # print bearer commands (copy/paste)
#   scripts/claude-code-setup.sh --apply      # also run them
#   scripts/claude-code-setup.sh --persona olivia   # force one persona (bearer mode)
#   scripts/claude-code-setup.sh --browser    # print browser-OAuth commands
#   scripts/claude-code-setup.sh --browser --apply  # register, then `/mcp` to log in
#
# Bearer mode: dealers → dana, finance → frank, ops/remote/remote-public → olivia
# (both groups). Tokens are short-lived; re-run to refresh. All servers point at Kong
# (:8000) with the streamable-http transport, so ALL access stays governed either way.
# Browser mode requires the host to resolve `keycloak` — run scripts/hosts-alias.sh --apply.

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
[[ -f "${REPO_DIR}/.env" ]] && { set -a; source "${REPO_DIR}/.env"; set +a; }
KONG="${KONG_URL:-http://localhost:8000}"

APPLY=false; FORCE_PERSONA=""; BROWSER=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    --apply) APPLY=true ;;
    --browser) BROWSER=true ;;
    --persona) FORCE_PERSONA="${2:-}"; shift ;;
    *) echo -e "${RED}[ERROR]${NC} unknown arg: $1" >&2; exit 1 ;;
  esac
  shift
done

if $APPLY && ! command -v claude >/dev/null 2>&1; then
  echo -e "${RED}[ERROR]${NC} 'claude' CLI not found but --apply given." >&2; exit 1
fi

tok(){ "${SCRIPT_DIR}/get-token.sh" "$1" --raw 2>/dev/null; }

# name : path : default-persona
SERVERS=(
  "cox-dealers:/mcp/dealers:dana"
  "cox-finance:/mcp/finance:frank"
  "cox-ops:/mcp/ops:olivia"
  "cox-market:/mcp/remote:olivia"
  "cox-deepwiki:/mcp/remote-public:olivia"
  # Hand-written Python MCP server, per-tool ACL allow:[finance,dealers]. Default persona is
  # dana (allowed) — do NOT default this one to olivia: ops is not in the allow list, so her
  # catalog for cox-custom is EMPTY and the server would look broken in a bearer-mode demo.
  "cox-custom:/mcp/custom:dana"
)

# ---------------------------------------------------------------------------
# BROWSER mode — register against the `claude-code` public client and let Claude
# Code run the OAuth authorization-code flow. Keycloak has Dynamic Client
# Registration disabled, so a static --client-id is required (DCR would fail with
# "Incompatible auth server: does not support dynamic client registration").
# ---------------------------------------------------------------------------
if $BROWSER; then
  CLIENT_ID="${CLAUDE_CODE_CLIENT_ID:-claude-code}"
  DISCO="http://keycloak:8080/realms/${KEYCLOAK_REALM:-cox-auto}/.well-known/openid-configuration"
  echo -e "${YELLOW}# Claude Code BROWSER OAuth registration for cai-mcp-demo (Kong @ ${KONG})${NC}"
  echo -e "${YELLOW}# Auth server: ${CLIENT_ID} @ Keycloak (authorization code + PKCE).${NC}"
  echo ""
  if ! curl -sf -o /dev/null "$DISCO" 2>/dev/null; then
    echo -e "${RED}# WARNING: the host cannot resolve/reach keycloak:8080.${NC}"
    echo -e "${RED}#   Browser OAuth needs it — run:  scripts/hosts-alias.sh --apply${NC}"
    echo ""
  fi
  for entry in "${SERVERS[@]}"; do
    IFS=':' read -r name path _persona <<<"$entry"
    cmd="claude mcp add --transport http ${name} ${KONG}${path} --client-id ${CLIENT_ID}"
    echo "$cmd"
    if $APPLY; then
      claude mcp add --transport http "${name}" "${KONG}${path}" --client-id "${CLIENT_ID}" \
        && echo -e "${GREEN}#  ✓ registered ${name}${NC}" || echo -e "${RED}#  ✗ failed ${name}${NC}"
    fi
    echo ""
  done
  echo -e "${YELLOW}# Next: run '/mcp' in Claude Code and complete the browser login as a persona:${NC}"
  echo -e "${YELLOW}#   dana.dealer | frank.finance | olivia.ops  (password: \$DEMO_PASSWORD)${NC}"
  echo -e "${YELLOW}# The first login seeds a Keycloak SSO session the other servers reuse; to demo a${NC}"
  echo -e "${YELLOW}# different persona, re-authenticate. Governance is enforced by the logged-in${NC}"
  echo -e "${YELLOW}# identity's groups at the tool ACL (e.g. dana is ACL-denied on cox-finance).${NC}"
  $APPLY || echo -e "${YELLOW}# (re-run with --browser --apply to execute these, or copy/paste them)${NC}"
  exit 0
fi

# ---------------------------------------------------------------------------
# BEARER mode (default) — short-lived ROPC token per persona, injected as a header.
# ---------------------------------------------------------------------------
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
