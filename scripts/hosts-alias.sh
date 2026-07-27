#!/usr/bin/env bash
set -uo pipefail

# hosts-alias.sh — make the pinned Keycloak issuer hostname resolvable ON THE HOST.
#
# Why: the demo pins Keycloak's issuer to the internal docker name so the token `iss`
# is identical whether a token is minted on the host or validated by the Kong DP
# (docker-network `keycloak:8080`). See docker-compose.yaml + NOTES.md. Containers
# resolve `keycloak` via docker DNS; the HOST does not. That's invisible for the
# curl-with-bearer path (it uses localhost:8080), but the INTERACTIVE browser OAuth
# flow (Claude Code) is handed `http://keycloak:8080/...` authorization/token/discovery
# URLs straight from Keycloak's own metadata — so the host browser + the Claude Code
# process must resolve `keycloak` too. This pins `keycloak -> 127.0.0.1` in /etc/hosts
# (published port 8080 does the rest). It also overrides any stray corporate/VPN/MagicDNS
# resolution of the bare name `keycloak`, which is otherwise non-deterministic per machine.
#
# Usage:
#   scripts/hosts-alias.sh            # check + print the exact line to add (no changes)
#   scripts/hosts-alias.sh --apply    # add the entry to /etc/hosts (uses sudo; idempotent)
#   scripts/hosts-alias.sh --remove   # remove the entry (uses sudo)
#
# Only touches lines carrying the marker below, so it's easy to reverse and never
# clobbers unrelated /etc/hosts content.

GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'; NC='\033[0m'

HOSTS_FILE="/etc/hosts"
ALIAS_HOST="keycloak"
ALIAS_IP="127.0.0.1"
MARKER="# cai-mcp-demo (host must resolve the pinned Keycloak issuer for browser OAuth)"
LINE="${ALIAS_IP} ${ALIAS_HOST} ${MARKER}"

MODE="check"
case "${1:-}" in
  --apply)  MODE="apply" ;;
  --remove) MODE="remove" ;;
  ""|--check) MODE="check" ;;
  *) echo -e "${RED}[ERROR]${NC} unknown arg: $1 (use --apply | --remove | --check)" >&2; exit 1 ;;
esac

# Does /etc/hosts already map `keycloak` (our marker OR any other entry)?
existing_marker="$(grep -nE "^[0-9.]+[[:space:]]+${ALIAS_HOST}([[:space:]]|$).*cai-mcp-demo" "${HOSTS_FILE}" 2>/dev/null || true)"
existing_any="$(grep -nE "^[[:space:]]*[0-9.]+[[:space:]]+${ALIAS_HOST}([[:space:]]|$)" "${HOSTS_FILE}" 2>/dev/null || true)"

reachable() {
  curl -sf -o /dev/null "http://${ALIAS_HOST}:8080/realms/cox-auto/.well-known/openid-configuration" 2>/dev/null
}

case "${MODE}" in
  check)
    if [[ -n "${existing_marker}" ]]; then
      echo -e "${GREEN}[OK]${NC} ${HOSTS_FILE} already pins ${ALIAS_HOST} (cai-mcp-demo entry present)."
    elif [[ -n "${existing_any}" ]]; then
      echo -e "${YELLOW}[WARN]${NC} ${HOSTS_FILE} maps ${ALIAS_HOST} via a NON-cai-mcp-demo line:"
      echo "        ${existing_any}"
      echo "        If browser OAuth misbehaves, ensure it points at ${ALIAS_IP}."
    else
      echo -e "${YELLOW}[ACTION]${NC} ${ALIAS_HOST} is not pinned in ${HOSTS_FILE}. Add this line:"
      echo ""
      echo "    ${LINE}"
      echo ""
      echo -e "Run ${GREEN}scripts/hosts-alias.sh --apply${NC} to add it (you'll be prompted for sudo)."
    fi
    echo ""
    if reachable; then
      echo -e "${GREEN}[OK]${NC} host can reach http://${ALIAS_HOST}:8080 (Keycloak discovery responds)."
    else
      echo -e "${YELLOW}[INFO]${NC} host cannot currently reach http://${ALIAS_HOST}:8080."
      echo "       (Expected until you --apply AND the keycloak container is up on :8080.)"
    fi
    ;;

  apply)
    if [[ -n "${existing_marker}" ]]; then
      echo -e "${GREEN}[OK]${NC} already present — nothing to do."
    else
      if [[ -n "${existing_any}" ]]; then
        echo -e "${YELLOW}[WARN]${NC} a non-marker ${ALIAS_HOST} line already exists; appending our pinned entry anyway."
        echo "        (/etc/hosts uses the first match; review if resolution looks wrong: ${existing_any})"
      fi
      echo -e "${YELLOW}[INFO]${NC} appending to ${HOSTS_FILE} (sudo):"
      echo "    ${LINE}"
      printf '%s\n' "${LINE}" | sudo tee -a "${HOSTS_FILE}" >/dev/null \
        && echo -e "${GREEN}[OK]${NC} added." \
        || { echo -e "${RED}[ERROR]${NC} failed to write ${HOSTS_FILE}." >&2; exit 1; }
    fi
    echo ""
    if reachable; then
      echo -e "${GREEN}[OK]${NC} verified: host reaches http://${ALIAS_HOST}:8080 (Keycloak discovery responds)."
    else
      echo -e "${YELLOW}[INFO]${NC} entry added but discovery not reachable yet — is the keycloak container up? (docker compose up -d keycloak)"
    fi
    ;;

  remove)
    if [[ -z "${existing_marker}" ]]; then
      echo -e "${GREEN}[OK]${NC} no cai-mcp-demo ${ALIAS_HOST} entry to remove."
      exit 0
    fi
    echo -e "${YELLOW}[INFO]${NC} removing the cai-mcp-demo ${ALIAS_HOST} entry from ${HOSTS_FILE} (sudo)."
    # Delete only lines that carry BOTH the alias host and our marker.
    sudo sed -i.cai-bak -E "/^[0-9.]+[[:space:]]+${ALIAS_HOST}([[:space:]]|$).*cai-mcp-demo/d" "${HOSTS_FILE}" \
      && echo -e "${GREEN}[OK]${NC} removed (backup at ${HOSTS_FILE}.cai-bak)." \
      || { echo -e "${RED}[ERROR]${NC} failed to edit ${HOSTS_FILE}." >&2; exit 1; }
    ;;
esac
