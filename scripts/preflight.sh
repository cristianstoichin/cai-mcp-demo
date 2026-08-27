#!/usr/bin/env bash
set -uo pipefail

# preflight.sh — verify tools, ports, and container health before the demo.
#   scripts/preflight.sh

GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'; NC='\033[0m'
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${REPO_DIR}"
[[ -f .env ]] && { set -a; source .env; set +a; }

PASS=0; FAIL=0; WARN=0
pass(){ echo -e "${GREEN}[PASS]${NC} $*"; PASS=$((PASS+1)); }
fail(){ echo -e "${RED}[FAIL]${NC} $*"; FAIL=$((FAIL+1)); }
warn(){ echo -e "${YELLOW}[WARN]${NC} $*"; WARN=$((WARN+1)); }

echo "=== cai-mcp-demo preflight ==="

# --- required tools ---
for t in docker curl jq python3; do
  command -v "$t" >/dev/null 2>&1 && pass "tool: $t" || fail "tool: $t (missing)"
done
docker compose version >/dev/null 2>&1 && pass "docker compose" || fail "docker compose plugin missing"

# --- .env + certs ---
[[ -f .env ]] && pass ".env present" || fail ".env missing (cp .env.example .env)"
[[ -n "${KONNECT_TOKEN:-}" ]] && pass "KONNECT_TOKEN set" || warn "KONNECT_TOKEN empty (bootstrap/sync/registry need it)"
[[ -f certs/tls.crt && -f certs/tls.key ]] && pass "DP certs present" || warn "certs/ missing (run scripts/konnect-bootstrap.sh)"

# --- container health ---
for svc in keycloak dealer-svc finance-svc kong-dp opa market-mcp custom-mcp; do
  st=$(docker compose ps --format '{{.Service}} {{.Status}}' 2>/dev/null | awk -v s="$svc" '$1==s{$1="";print}')
  if [[ -z "$st" ]]; then warn "container ${svc}: not running"
  elif echo "$st" | grep -qi "healthy\|Up"; then pass "container ${svc}:${st}"
  else fail "container ${svc}:${st}"; fi
done

# --- host ports reachable ---
check_http(){ curl -s -o /dev/null -w "%{http_code}" --max-time 3 "$1" 2>/dev/null; }
kc=$(check_http "http://localhost:8080/realms/cox-auto/.well-known/openid-configuration")
[[ "$kc" == "200" ]] && pass "keycloak discovery (8080) -> 200" || warn "keycloak discovery (8080) -> ${kc}"
kong=$(check_http "http://localhost:8000/")
[[ "$kong" =~ ^(404|401|200)$ ]] && pass "kong proxy (8000) responding (${kong})" || warn "kong proxy (8000) -> ${kong}"
opa=$(check_http "http://localhost:8181/health")
[[ "$opa" == "200" ]] && pass "opa (8181) -> 200" || warn "opa (8181) -> ${opa}"

echo ""
echo -e "Summary: ${GREEN}${PASS} pass${NC}, ${YELLOW}${WARN} warn${NC}, ${RED}${FAIL} fail${NC}"
[[ $FAIL -eq 0 ]] || exit 1
