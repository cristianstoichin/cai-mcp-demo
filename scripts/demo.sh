#!/usr/bin/env bash
set -uo pipefail

# demo.sh — a numbered, pause-between-steps walkthrough of the cai-mcp-demo.
# Each step prints what it proves, runs the real calls against the LIVE stack
# (Kong :8000 + Keycloak :8080), and waits for Enter. Run `scripts/preflight.sh`
# first; the stack must be up and `deck gateway sync` applied.
#
#   scripts/demo.sh            # interactive (pause between steps)
#   scripts/demo.sh --no-pause # run straight through (for recording)

GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; BOLD='\033[1m'; NC='\033[0m'
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
[[ -f "${REPO_DIR}/.env" ]] && { set -a; source "${REPO_DIR}/.env"; set +a; }
KONG="${KONG_URL:-http://localhost:8000}"
PAUSE=true
[[ "${1:-}" == "--no-pause" ]] && PAUSE=false

step() { echo ""; echo -e "${BOLD}${BLUE}=== $* ===${NC}"; }
note() { echo -e "${YELLOW}» $*${NC}"; }
run()  { echo -e "${GREEN}\$ $*${NC}"; eval "$*"; }
pause(){ $PAUSE && { echo ""; read -r -p "  [Enter to continue] " _; } || true; }

tok(){ "${SCRIPT_DIR}/get-token.sh" "$1" "${2:-}" --raw 2>/dev/null; }
# JSON-RPC helper against a Kong MCP listener (stateless single-POST works for the
# ai-mcp-proxy listeners; market-mcp remote is shown via the auth gate instead).
rpc(){ curl -s -X POST "${KONG}$1" -H "Authorization: Bearer $2" -H "Content-Type: application/json" -H "Accept: application/json, text/event-stream" -d "$3"; }
code(){ curl -s -o /dev/null -w "%{http_code}" -X POST "${KONG}$1" ${2:+-H "Authorization: Bearer $2"} -H "Content-Type: application/json" -H "Accept: application/json, text/event-stream" -d "$3"; }
names(){ sed 's/^data: //' | grep -o '"name":"[^"]*"' | sed 's/"name":"//;s/"//' | paste -sd, -; }

echo -e "${BOLD}Cox Automotive — governed MCP on Kong AI Gateway${NC}"
echo    "Kong: ${KONG}   Keycloak: ${KEYCLOAK_BASE:-http://localhost:8080}/realms/cox-auto"

# ---------------------------------------------------------------------------
step "1. REST OIDC gates — the raw APIs are protected before any MCP"
note "No token → 401; dana (dealers:read) → 200; dana on the finance API → 403 (scope+audience)."
DANA=$(tok dana)
run "curl -s -o /dev/null -w 'no-token  /api/dealers/customers -> %{http_code}\n' ${KONG}/api/dealers/customers"
run "curl -s -o /dev/null -w 'dana      /api/dealers/customers -> %{http_code}\n' -H 'Authorization: Bearer ${DANA}' ${KONG}/api/dealers/customers"
run "curl -s -o /dev/null -w 'dana      /api/finance/invoices  -> %{http_code}\n' -H 'Authorization: Bearer ${DANA}' ${KONG}/api/finance/invoices"
pause

# ---------------------------------------------------------------------------
step "2. REST → MCP conversion — same APIs, now MCP tools (tag-aggregated)"
note "/mcp/dealers = 2 tools, /mcp/finance = 2, /mcp/ops = 2 bundled (dealer+finance)."
OLIVIA=$(tok olivia)
echo -n "  /mcp/dealers tools: "; rpc /mcp/dealers "$OLIVIA" '{"jsonrpc":"2.0","id":1,"method":"tools/list"}' | names
echo -n "  /mcp/finance tools: "; rpc /mcp/finance "$OLIVIA" '{"jsonrpc":"2.0","id":1,"method":"tools/list"}' | names
echo -n "  /mcp/ops     tools: "; rpc /mcp/ops     "$OLIVIA" '{"jsonrpc":"2.0","id":1,"method":"tools/list"}' | names
pause

# ---------------------------------------------------------------------------
step "3. Persona tool ACL — filtering by the token's groups claim (no Kong consumers)"
note "Each persona may call their own group's tools; frank (finance) may NOT call a dealer tool."
FRANK=$(tok frank)
echo -n "  dana   list_dealer_customers via /mcp/dealers -> "; rpc /mcp/dealers "$DANA"   '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"list_dealer_customers","arguments":{}}}' | grep -q 'count' && echo -e "${GREEN}ALLOW (data)${NC}" || echo -e "${RED}?${NC}"
echo -n "  frank  list_invoices via /mcp/finance         -> "; rpc /mcp/finance "$FRANK"  '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"list_invoices","arguments":{}}}' | grep -q 'count' && echo -e "${GREEN}ALLOW (data)${NC}" || echo -e "${RED}?${NC}"
echo -n "  olivia list_invoices via /mcp/ops             -> "; rpc /mcp/ops "$OLIVIA" '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"list_invoices","arguments":{}}}' | grep -q 'count' && echo -e "${GREEN}ALLOW (data)${NC}" || echo -e "${RED}?${NC}"
echo -n "  frank  list_dealer_customers via /mcp/ops     -> HTTP "; code /mcp/ops "$FRANK" '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"list_dealer_customers","arguments":{}}}'; echo -e " ${YELLOW}(403 = ACL deny)${NC}"
pause

# ---------------------------------------------------------------------------
step "4. RFC 8693 token exchange — /mcp/ops bridges an mcp:use-only token to the APIs"
note "A token with ONLY 'mcp:use' lacks the dealer-api/finance-api audiences the inner gates need."
note "On /mcp/ops Kong exchanges it (introspection client) so the call reaches the API; on /mcp/dealers it can't."
MCPONLY=$(tok olivia "openid mcp:use")
echo -n "  mcp:use-only olivia -> /mcp/ops list_dealer_customers     -> "; rpc /mcp/ops "$MCPONLY" '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"list_dealer_customers","arguments":{}}}' | grep -q 'count' && echo -e "${GREEN}ALLOW — exchanged${NC}" || echo -e "${RED}?${NC}"
echo -n "  mcp:use-only olivia -> /mcp/dealers list_dealer_customers -> "; rpc /mcp/dealers "$MCPONLY" '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"list_dealer_customers","arguments":{}}}' | grep -qo 'status 403' && echo -e "${YELLOW}inner-gate 403 — no exchange here${NC}" || echo -e "${RED}?${NC}"
$PAUSE && echo -e "  ${YELLOW}(tip: docker compose logs kong-dp | grep 'exchanging access token')${NC}"
pause

# ---------------------------------------------------------------------------
step "5. External OPA policy on /mcp/ops — a rule the tool ACL cannot express"
note "OPA denies list_invoices when the call argument query_status=overdue, even for a permitted caller."
echo -n "  olivia list_invoices (no filter)              -> HTTP "; code /mcp/ops "$OLIVIA" '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"list_invoices","arguments":{}}}'; echo " (200)"
echo -n "  olivia list_invoices query_status=overdue     -> HTTP "; code /mcp/ops "$OLIVIA" '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"list_invoices","arguments":{"query_status":"overdue"}}}'; echo -e " ${YELLOW}(403 = OPA deny; opa/policies/mcp.rego hot-reloads with no Kong sync)${NC}"
pause

# ---------------------------------------------------------------------------
step "6. Passthrough remotes — govern MCP servers Kong did not convert"
note "/mcp/remote → local market-mcp (Cox tools); /mcp/remote-public → DeepWiki (third-party). Both require a cox-auto token."
echo -n "  /mcp/remote        unauth -> HTTP "; code /mcp/remote "" '{"jsonrpc":"2.0","id":1,"method":"tools/list"}'; echo " (401)"
echo -n "  /mcp/remote-public authed tools -> "; rpc /mcp/remote-public "$OLIVIA" '{"jsonrpc":"2.0","id":1,"method":"tools/list"}' | names
pause

# ---------------------------------------------------------------------------
step "7. MCP Registry discovery — the servers are catalogued in Konnect"
if [[ -n "${KONNECT_MCP_REGISTRY_ID:-}" && -n "${KONNECT_TOKEN:-}" ]]; then
  API="https://klabs.${KONNECT_REGION:-us}.api.konghq.com/v0/mcp-registries/${KONNECT_MCP_REGISTRY_ID}/v0.1/servers"
  curl -s "${API}" -H "Authorization: Bearer ${KONNECT_TOKEN}" | python3 -c "
import sys,json
d=json.load(sys.stdin); servers=d.get('servers', d.get('data', []))
print(f'  {len(servers)} server(s) discoverable in the registry:')
for s in servers:
    x=s.get('server', s); r=x.get('remotes',[{}])
    print(f\"    - {x.get('name','?')}  ->  {r[0].get('url','?')}\")
" 2>/dev/null || echo "  (discovery parse failed)"
else
  note "Run scripts/registry-setup.sh first (needs Konnect Labs MCP Registry). Then KONNECT_MCP_REGISTRY_ID in .env."
fi
echo ""
echo -e "${GREEN}${BOLD}Demo complete.${NC} Hook Claude Code up with: scripts/claude-code-setup.sh"
