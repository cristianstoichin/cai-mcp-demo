#!/usr/bin/env bash
set -uo pipefail

# =============================================================================
# setup.sh — one-shot first-run orchestrator for cai-mcp-demo.
#
#   ./scripts/setup.sh [--with-dashboard] [--with-registry] [--yes] [--force]
#
# Stages (each gated): preflight -> ensure .env -> bootstrap Konnect ->
# compose up -> wait for health -> deck sync -> wait for routes ->
# [opt-in add-ons] -> smoke test. Core stages abort on failure; add-ons and
# smoke are best-effort. Idempotent: safe to re-run.
# =============================================================================

GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${REPO_DIR}"

step(){ echo -e "\n${BLUE}==>${NC} ${1}"; }
ok(){   echo -e "${GREEN}[ok]${NC} $*"; }
warn(){ echo -e "${YELLOW}[warn]${NC} $*"; }
die(){  echo -e "${RED}[setup ERROR]${NC} $*" >&2; exit 1; }

WITH_DASHBOARD=false; WITH_REGISTRY=false; ASSUME_YES=false; FORCE=false
usage(){ cat <<EOF
Usage: ./scripts/setup.sh [options]
  --with-dashboard   Also install the Konnect analytics dashboard (best-effort)
  --with-registry    Also publish to the MCP Registry (best-effort; US Labs only)
  --yes, -y          Non-interactive: never prompt (requires .env pre-filled)
  --force            Regenerate + re-pin the data-plane cert (passed to bootstrap)
  --help, -h         Show this help
EOF
}
while [[ $# -gt 0 ]]; do
  case "$1" in
    --with-dashboard) WITH_DASHBOARD=true ;;
    --with-registry)  WITH_REGISTRY=true ;;
    --yes|-y)         ASSUME_YES=true ;;
    --force)          FORCE=true ;;
    --help|-h)        usage; exit 0 ;;
    *) die "unknown option: $1 (see --help)" ;;
  esac
  shift
done

echo -e "${BLUE}=== cai-mcp-demo setup ===${NC}"

# --- Stage 1: preflight tools --------------------------------------------------
step "1/9 Preflight tools"
missing=()
for t in docker curl jq python3 openssl; do
  command -v "$t" >/dev/null 2>&1 || missing+=("$t")
done
docker compose version >/dev/null 2>&1 || missing+=("docker-compose-v2")
if [[ ${#missing[@]} -gt 0 ]]; then
  die "missing required tools: ${missing[*]}
  macOS:  brew install ${missing[*]/docker-compose-v2/}  (Docker Desktop provides docker + compose)
  Linux:  install docker, docker-compose-plugin, curl, jq, python3, openssl via your package manager"
fi
ok "all required tools present"

# --- Stage 2: ensure .env ------------------------------------------------------
step "2/9 Ensure .env"
if [[ ! -f .env ]]; then
  cp .env.example .env
  ok "created .env from .env.example"
fi
set -a; source .env; set +a
if [[ -z "${KONNECT_TOKEN:-}" || "${KONNECT_TOKEN}" == kpat_REPLACE_ME* ]]; then
  if [[ "$ASSUME_YES" == true || ! -t 0 ]]; then
    die "KONNECT_TOKEN is not set in .env. Edit .env (KONNECT_TOKEN + KONNECT_REGION) and re-run, \
or run interactively (a TTY) without --yes to be prompted."
  fi
  echo "Enter your Konnect Personal Access Token (kpat_...); it will be written to .env:"
  read -r -p "KONNECT_TOKEN: " _tok
  [[ -n "$_tok" ]] || die "no token entered."
  read -r -p "KONNECT_REGION [${KONNECT_REGION:-us}]: " _reg
  _reg="${_reg:-${KONNECT_REGION:-us}}"
  # reuse the portable writer from bootstrap (same marker block)
  eval "$(awk '/^# >>> write_env_var >>>/{f=1} f; /^# <<< write_env_var <<</{f=0}' scripts/konnect-bootstrap.sh)"
  write_env_var KONNECT_TOKEN  "$_tok" .env
  write_env_var KONNECT_REGION "$_reg" .env
  set -a; source .env; set +a
  ok "wrote KONNECT_TOKEN + KONNECT_REGION to .env"
fi
ok "KONNECT_TOKEN set; region=${KONNECT_REGION:-us}"

# --- Stage 3: bootstrap Konnect ------------------------------------------------
step "3/9 Bootstrap Konnect control plane + data-plane cert"
BOOTSTRAP_ARGS=(); [[ "$FORCE" == true ]] && BOOTSTRAP_ARGS+=(--force)
"${SCRIPT_DIR}/konnect-bootstrap.sh" "${BOOTSTRAP_ARGS[@]}" || die "bootstrap failed (see output above)."
set -a; source .env; set +a   # pick up the endpoints bootstrap just wrote
ok "control plane ready; endpoints in .env"

# --- Stage 4: bring up the stack ----------------------------------------------
step "4/9 docker compose up -d"
docker compose up -d || die "docker compose up failed."
ok "containers started"

# --- Stage 5: wait for health --------------------------------------------------
step "5/9 Wait for stack health"
poll(){ # poll DESC URL 'REGEX-of-acceptable-codes' TIMEOUT
  local desc="$1" url="$2" re="$3" timeout="${4:-120}" waited=0 code
  while (( waited < timeout )); do
    code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 3 "$url" 2>/dev/null)"
    [[ "$code" =~ $re ]] && { ok "${desc} (${code})"; return 0; }
    sleep 3; waited=$((waited+3))
  done
  return 1
}
poll "Keycloak discovery" "http://localhost:8080/realms/cox-auto/.well-known/openid-configuration" '^200$' 120 \
  || die "Keycloak did not become ready. Check: docker compose logs keycloak"
poll "OPA health" "http://localhost:8181/health" '^200$' 60 \
  || warn "OPA health not confirmed (non-fatal). Check: docker compose logs opa"
poll "Kong proxy" "http://localhost:8000/" '^(200|401|404)$' 120 \
  || die "Kong data plane not responding on :8000. Check: docker compose logs kong-dp"

# --- Stage 6: deck sync --------------------------------------------------------
step "6/9 Push declarative config (deck gateway sync)"
docker compose --profile tools run --rm deck gateway sync /config/konnect.yaml \
  || die "deck sync failed. Validate first: docker compose --profile tools run --rm deck gateway validate /config/konnect.yaml"
ok "config synced to the control plane"

# --- Stage 7: wait for routes to go live --------------------------------------
step "7/9 Wait for MCP routes to serve (data plane pulls config)"
# An unauthenticated MCP listener returns 401 once the config is live.
poll "MCP route /mcp/dealers" "http://localhost:8000/mcp/dealers" '^(401|400)$' 90 \
  || warn "MCP route not confirmed live yet (data plane may still be pulling). \
Give it a moment, then run: scripts/preflight.sh"

# --- Stage 8: optional add-ons (best-effort; never abort) ----------------------
step "8/9 Optional add-ons"
if [[ "$WITH_DASHBOARD" == true ]]; then
  if "${SCRIPT_DIR}/install-dashboard.sh"; then ok "analytics dashboard installed"
  else warn "dashboard install failed (needs AI Gateway Enterprise analytics). Skipping — non-fatal."; fi
else
  echo "  (skipped dashboard — pass --with-dashboard to enable)"
fi
if [[ "$WITH_REGISTRY" == true ]]; then
  if "${SCRIPT_DIR}/registry-setup.sh"; then ok "MCP Registry published"
  else warn "registry-setup failed (needs Konnect Labs 'Catalog - MCP Registry', US only). Skipping — non-fatal."; fi
else
  echo "  (skipped registry — pass --with-registry to enable)"
fi

# --- Stage 9: smoke test -------------------------------------------------------
step "9/9 Smoke test"
if "${SCRIPT_DIR}/smoke-test.sh"; then ok "smoke test passed"
else warn "smoke test reported failures (see above). The stack may still be usable."; fi

# --- Done ----------------------------------------------------------------------
cat <<EOF

$(echo -e "${GREEN}=== READY ===${NC}")
The governed MCP stack is up.  Next:
  • Guided CLI story : ./scripts/demo.sh
  • Visual cockpit   : ./scripts/ui.sh        (then open http://127.0.0.1:${UI_PORT:-4000})
  • Verify anytime   : ./scripts/preflight.sh
  • Tear down        : docker compose down -v
EOF
