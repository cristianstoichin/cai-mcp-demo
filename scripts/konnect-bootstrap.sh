#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# konnect-bootstrap.sh — one-time Konnect setup for cai-mcp-demo.
#
# Given only KONNECT_TOKEN (+ region + CP name) from .env, this:
#   1. Finds or creates the Gateway control plane (PKI auth mode).
#   2. Generates a self-signed data-plane cert/key into ./certs (if absent).
#   3. Pins that cert to the control plane (PKI mode: self-signed = its own trust anchor).
#   4. Prints the CP/telemetry endpoint lines to paste into .env.
#
# Idempotent: re-running finds the existing CP and skips cert gen/upload unless --force.
# Portable: nothing here is org-specific — everything comes from .env, so this works
# identically for my org and for the customer's org.
#
# Docs (verified 2026-07-22 via Konnect Control Planes API v2):
#   POST /v2/control-planes                          create_control_plane
#   GET  /v2/control-planes?filter[name][eq]=NAME    list_control_planes
#   POST /v2/control-planes/{id}/dp-client-certificates   create_dataplane_certificate
#   response: result.config.{control_plane_endpoint,telemetry_endpoint}
# =============================================================================

GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'; NC='\033[0m'
info() { echo -e "${YELLOW}[bootstrap]${NC} $*" >&2; }
ok()   { echo -e "${GREEN}[bootstrap]${NC} $*" >&2; }
die()  { echo -e "${RED}[bootstrap ERROR]${NC} $*" >&2; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
[[ -f "${REPO_DIR}/.env" ]] && { set -a; source "${REPO_DIR}/.env"; set +a; }

FORCE=false
[[ "${1:-}" == "--force" ]] && FORCE=true

for tool in curl jq openssl; do
  command -v "$tool" >/dev/null 2>&1 || die "'$tool' is required but not installed."
done

: "${KONNECT_TOKEN:?Set KONNECT_TOKEN in .env (a Konnect PAT with control-plane admin rights).}"
[[ "${KONNECT_TOKEN}" == kpat_REPLACE_ME* ]] && die "KONNECT_TOKEN is still the placeholder — set a real PAT in .env."
REGION="${KONNECT_REGION:-us}"
CP_NAME="${KONNECT_CONTROL_PLANE_NAME:-cai-mcp-demo}"
CERT_DIR="${REPO_DIR}/${CERT_HOST_DIR:-./certs}"
CERT_DIR="$(cd "$(dirname "${CERT_DIR}")" 2>/dev/null && pwd)/$(basename "${CERT_DIR}")" || CERT_DIR="${REPO_DIR}/certs"
API="https://${REGION}.api.konghq.com/v2"
AUTH="Authorization: Bearer ${KONNECT_TOKEN}"

info "region=${REGION}  control-plane='${CP_NAME}'  api=${API}"

# --- helper: authenticated curl that fails loudly on non-2xx --------------------
kapi() { # kapi METHOD PATH [json-body]
  local method="$1" path="$2" body="${3:-}"
  local args=(-sS -X "$method" "${API}${path}" -H "$AUTH" -H "Content-Type: application/json")
  [[ -n "$body" ]] && args+=(-d "$body")
  local out code
  out="$(curl "${args[@]}" -w $'\n%{http_code}')" || die "network error calling ${method} ${path}"
  code="$(tail -n1 <<<"$out")"; body="$(sed '$d' <<<"$out")"
  if [[ ! "$code" =~ ^2 ]]; then
    case "$code" in
      401) die "401 Unauthorized — KONNECT_TOKEN is invalid or expired." ;;
      403) die "403 Forbidden — the PAT lacks control-plane admin rights (or wrong region '${REGION}')." ;;
      404) die "404 Not Found — check KONNECT_REGION ('${REGION}') is correct for your org." ;;
      *)   die "HTTP ${code} from ${method} ${path}: $(jq -r '.detail // .message // .' <<<"$body" 2>/dev/null || echo "$body")" ;;
    esac
  fi
  printf '%s' "$body"
}

# --- 1. find or create the control plane ---------------------------------------
info "looking for control plane '${CP_NAME}'..."
LIST="$(kapi GET "/control-planes?filter%5Bname%5D%5Beq%5D=${CP_NAME}&page%5Bsize%5D=50")"
CP_ID="$(jq -r --arg n "$CP_NAME" '.data[] | select(.name==$n) | .id' <<<"$LIST" | head -n1)"

if [[ -n "$CP_ID" && "$CP_ID" != "null" ]]; then
  ok "found existing control plane: ${CP_ID}"
  CP_OBJ="$(kapi GET "/control-planes/${CP_ID}")"
  CP_JSON="$(jq '.' <<<"$CP_OBJ")"
else
  info "not found — creating (cluster_type=CLUSTER_TYPE_CONTROL_PLANE, auth_type=pki_client_certs)..."
  CP_JSON="$(kapi POST "/control-planes" "$(jq -n --arg n "$CP_NAME" '{
      name: $n,
      description: "cai-mcp-demo — Kong AI Gateway MCP demo (Cox Automotive)",
      cluster_type: "CLUSTER_TYPE_CONTROL_PLANE",
      auth_type: "pki_client_certs"
    }')")"
  CP_ID="$(jq -r '.id' <<<"$CP_JSON")"
  ok "created control plane: ${CP_ID}"
fi

CP_ENDPOINT="$(jq -r '.config.control_plane_endpoint' <<<"$CP_JSON")"
TP_ENDPOINT="$(jq -r '.config.telemetry_endpoint' <<<"$CP_JSON")"
[[ -z "$CP_ENDPOINT" || "$CP_ENDPOINT" == "null" ]] && die "could not read control_plane_endpoint from CP response."

# host:port + server name (strip scheme, ensure :443)
host_of()  { sed -E 's#^https?://##; s#/.*$##; s#:.*$##' <<<"$1"; }
endp_of()  { local h; h="$(host_of "$1")"; printf '%s:443' "$h"; }
CP_HOST="$(host_of "$CP_ENDPOINT")"; TP_HOST="$(host_of "$TP_ENDPOINT")"

# --- 2. generate the data-plane cert/key (self-signed) -------------------------
mkdir -p "$CERT_DIR"
if [[ -f "${CERT_DIR}/tls.crt" && -f "${CERT_DIR}/tls.key" && "$FORCE" == false ]]; then
  info "cert already present at ${CERT_DIR}/tls.{crt,key} (use --force to regenerate)."
  GENERATED=false
else
  info "generating self-signed data-plane cert/key -> ${CERT_DIR}/tls.{crt,key}"
  openssl req -new -x509 -nodes -newkey rsa:2048 -days 1095 \
    -subj "/CN=${CP_NAME}-dp/O=cai-mcp-demo" \
    -keyout "${CERT_DIR}/tls.key" -out "${CERT_DIR}/tls.crt" >/dev/null 2>&1 \
    || die "openssl failed to generate the cert."
  chmod 600 "${CERT_DIR}/tls.key"
  GENERATED=true
fi

# --- 3. pin the cert to the control plane (skip if unchanged) -------------------
if [[ "$GENERATED" == true || "$FORCE" == true ]]; then
  info "pinning data-plane certificate to the control plane..."
  CERT_PEM="$(cat "${CERT_DIR}/tls.crt")"
  kapi POST "/control-planes/${CP_ID}/dp-client-certificates" \
    "$(jq -n --arg c "$CERT_PEM" --arg t "${CP_NAME}-dp" '{cert: $c, title: $t}')" >/dev/null
  ok "certificate pinned."
else
  info "cert unchanged — leaving existing pinned certificate(s) in place."
fi

# --- 4. print the .env lines ---------------------------------------------------
cat >&2 <<EOF

$(echo -e "${GREEN}[bootstrap] DONE.${NC}") Control plane '${CP_NAME}' is ready (${CP_ID}).

Append these to your .env (replacing the empty placeholders):
------------------------------------------------------------------
EOF
cat <<EOF
KONNECT_CP_ENDPOINT=$(endp_of "$CP_ENDPOINT")
KONNECT_CP_SERVER_NAME=${CP_HOST}
KONNECT_TP_ENDPOINT=$(endp_of "$TP_ENDPOINT")
KONNECT_TP_SERVER_NAME=${TP_HOST}
EOF
cat >&2 <<EOF
------------------------------------------------------------------
Then: docker compose up -d   &&   docker compose --profile tools run --rm deck gateway sync /config/konnect.yaml
EOF
