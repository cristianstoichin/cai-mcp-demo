#!/usr/bin/env bash
set -uo pipefail

# smoke-test.sh — static config checks + a few live assertions against the stack.
#   scripts/smoke-test.sh              # static + live (if stack up)
#   scripts/smoke-test.sh --static     # static checks only (no running stack)

GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'; NC='\033[0m'
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${REPO_DIR}"
[[ -f .env ]] && { set -a; source .env; set +a; }
KONG="${KONG_URL:-http://localhost:8000}"
STATIC_ONLY=false; [[ "${1:-}" == "--static" ]] && STATIC_ONLY=true

PASS=0; FAIL=0
pass(){ echo -e "${GREEN}[PASS]${NC} $*"; PASS=$((PASS+1)); }
fail(){ echo -e "${RED}[FAIL]${NC} $*"; FAIL=$((FAIL+1)); }

echo "=== cai-mcp-demo smoke test (static) ==="

# 1. compose config valid
docker compose config -q >/dev/null 2>&1 && pass "docker compose config -q" || fail "docker compose config invalid"

# 2. deck gateway validate (offline)
if docker compose --profile tools run --rm -T deck gateway validate /config/konnect.yaml >/tmp/smoke-deck.txt 2>&1; then
  pass "deck gateway validate"
else
  fail "deck gateway validate ($(tail -1 /tmp/smoke-deck.txt))"
fi

# 3. opa policy compiles
if docker run --rm -v "${REPO_DIR}/opa/policies:/policies:ro" openpolicyagent/opa:1.4.2 check /policies >/dev/null 2>&1; then
  pass "opa check opa/policies"
else
  fail "opa check failed"
fi

# 4. JSON validity — realm + registry bodies
if python3 -c "import json;json.load(open('keycloak/realm-export.json'))" 2>/dev/null; then pass "realm-export.json valid"; else fail "realm-export.json invalid JSON"; fi
badjson=0
for f in konnect/mcp-registry/*.json; do python3 -c "import json;json.load(open('$f'))" 2>/dev/null || { fail "invalid JSON: $f"; badjson=1; }; done
[[ $badjson -eq 0 ]] && pass "registry bodies valid JSON"

# 5. registry publish description length (<=100, the live API limit)
overlen=0
for f in konnect/mcp-registry/publish-*.json; do
  L=$(python3 -c "import json;print(len(json.load(open('$f')).get('description','')))")
  [[ "$L" -le 100 ]] || { fail "$f description ${L}>100"; overlen=1; }
done
[[ $overlen -eq 0 ]] && pass "registry descriptions <=100 chars"

# 6. demo tool coverage — every REST->MCP converted tool must be exercised by the scripted
#    story, else the MCP "Tool usage" analytics tile silently under-reports the governed surface
#    (regression guard; see shipped-log 2026-07-27). Required: an ALLOW call in demo-ui
#    scenarios.js (what populates the dashboard) AND a tools/call in demo.sh (keep the two mirrored).
CONVERTED=$(grep -oE 'name: list_[a-z_]+' kong/konnect.yaml | sed 's/name: //' | sort -u)
miss_scen=""; miss_demo=""
for t in $CONVERTED; do
  grep -qE "tool: \"${t}\".*verdict: \"allow\"" demo-ui/scenarios.js || miss_scen="${miss_scen} ${t}"
  grep -qE "\"name\":\"${t}\"" scripts/demo.sh || miss_demo="${miss_demo} ${t}"
done
if [[ -z "$miss_scen" && -z "$miss_demo" ]]; then
  pass "demo exercises all converted tools ($(echo "$CONVERTED" | wc -w | tr -d ' '): $(echo $CONVERTED | tr '\n' ' '))"
else
  [[ -n "$miss_scen" ]] && fail "scenarios.js missing an ALLOW call for:${miss_scen}"
  [[ -n "$miss_demo" ]] && fail "demo.sh missing a tools/call for:${miss_demo}"
fi

$STATIC_ONLY && { echo ""; echo -e "Summary: ${GREEN}${PASS} pass${NC}, ${RED}${FAIL} fail${NC}"; [[ $FAIL -eq 0 ]] || exit 1; exit 0; }

echo ""
echo "=== live assertions (stack must be up + synced) ==="

# service /health in-network (avoids host port squatters)
for svc in dealer-svc finance-svc market-mcp; do
  if docker compose exec -T "$svc" node -e "require('http').get('http://localhost:3000/health',r=>process.exit(r.statusCode===200?0:1)).on('error',()=>process.exit(1))" 2>/dev/null; then
    pass "${svc} /health = 200"
  else
    fail "${svc} /health not 200"
  fi
done

# custom-mcp is Python — no `node` binary in that image, so use urllib for the same check.
if docker compose exec -T custom-mcp python -c "import urllib.request,sys; sys.exit(0 if urllib.request.urlopen('http://localhost:3000/health').status==200 else 1)" 2>/dev/null; then
  pass "custom-mcp /health = 200"
else
  fail "custom-mcp /health not 200"
fi

tok(){ "${SCRIPT_DIR}/get-token.sh" "$1" "${2:-}" --raw 2>/dev/null; }
code(){ curl -s -o /dev/null -w "%{http_code}" -X POST "${KONG}$1" ${2:+-H "Authorization: Bearer $2"} -H "Content-Type: application/json" -H "Accept: application/json, text/event-stream" -d "$3"; }

DANA=$(tok dana); OLIVIA=$(tok olivia)
if [[ -z "$DANA" ]]; then fail "could not mint tokens (Keycloak down?)"; else
  c=$(curl -s -o /dev/null -w "%{http_code}" "${KONG}/api/dealers/customers"); [[ "$c" == "401" ]] && pass "no-token REST -> 401" || fail "no-token REST -> ${c} (want 401)"
  c=$(curl -s -o /dev/null -w "%{http_code}" -H "Authorization: Bearer ${DANA}" "${KONG}/api/dealers/customers"); [[ "$c" == "200" ]] && pass "dana REST dealer -> 200" || fail "dana REST dealer -> ${c}"
  c=$(code /mcp/ops "$OLIVIA" '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"list_invoices","arguments":{}}}'); [[ "$c" == "200" ]] && pass "olivia list_invoices /mcp/ops -> 200" || fail "olivia list_invoices -> ${c}"
  c=$(code /mcp/ops "$OLIVIA" '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"list_invoices","arguments":{"query_status":"overdue"}}}'); [[ "$c" == "403" ]] && pass "OPA denies overdue filter -> 403" || fail "OPA overdue -> ${c} (want 403)"
  c=$(code /mcp/remote "" '{"jsonrpc":"2.0","id":1,"method":"tools/list"}'); [[ "$c" == "401" ]] && pass "/mcp/remote unauth -> 401" || fail "/mcp/remote unauth -> ${c}"
  # /mcp/custom — hand-written Python server behind a PER-TOOL ACL on a passthrough listener
  # (allow: [finance, dealers]). Guard both sides: dana+frank allowed, olivia (ops) DENIED —
  # ops is deliberately absent from the allow list. This is the documented access model.
  c=$(code /mcp/custom "" '{"jsonrpc":"2.0","id":1,"method":"tools/list"}'); [[ "$c" == "401" ]] && pass "/mcp/custom unauth -> 401" || fail "/mcp/custom unauth -> ${c}"
  FRANK=$(tok frank)
  cust='{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"hello_custom_tool","arguments":{}}}'
  for who in "dana:${DANA}:200" "frank:${FRANK}:200" "olivia:${OLIVIA}:403"; do
    name="${who%%:*}"; rest="${who#*:}"; tokn="${rest%:*}"; want="${rest##*:}"
    c=$(code /mcp/custom "$tokn" "$cust")
    [[ "$c" == "$want" ]] && pass "${name} hello_custom_tool /mcp/custom -> ${want}" || fail "${name} hello_custom_tool -> ${c} (want ${want})"
  done
fi

echo ""
echo -e "Summary: ${GREEN}${PASS} pass${NC}, ${RED}${FAIL} fail${NC}"
[[ $FAIL -eq 0 ]] || exit 1
