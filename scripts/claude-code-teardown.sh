#!/usr/bin/env bash
set -uo pipefail

# claude-code-teardown.sh — the inverse of claude-code-setup.sh. Unregister the demo's
# MCP servers from Claude Code (both bearer and browser modes register the same 5 names),
# and optionally remove the /etc/hosts `keycloak` alias.
#
#   scripts/claude-code-teardown.sh              # print the `claude mcp remove` lines
#   scripts/claude-code-teardown.sh --apply      # actually remove the servers
#   scripts/claude-code-teardown.sh --apply --with-hosts   # also remove the /etc/hosts alias (sudo)
#
# This does NOT stop the stack or touch the repo — it only undoes the client-side hookup.
# Stack teardown is `docker compose down [-v]`. The browser flow may also cache an OAuth
# token in your system keychain; `claude mcp remove` drops the server entry, and this
# script prints a reminder for the cached credential.

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

APPLY=false; WITH_HOSTS=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    --apply) APPLY=true ;;
    --with-hosts) WITH_HOSTS=true ;;
    *) echo -e "${RED}[ERROR]${NC} unknown arg: $1 (use --apply | --with-hosts)" >&2; exit 1 ;;
  esac
  shift
done

if $APPLY && ! command -v claude >/dev/null 2>&1; then
  echo -e "${RED}[ERROR]${NC} 'claude' CLI not found but --apply given." >&2; exit 1
fi

# Must match the SERVERS names in claude-code-setup.sh.
NAMES=(cox-dealers cox-finance cox-ops cox-market cox-deepwiki)

echo -e "${YELLOW}# Unregister cai-mcp-demo MCP servers from Claude Code${NC}"
echo ""
for name in "${NAMES[@]}"; do
  echo "claude mcp remove ${name}"
  if $APPLY; then
    if claude mcp remove "${name}" >/dev/null 2>&1; then
      echo -e "${GREEN}#  ✓ removed ${name}${NC}"
    else
      echo -e "${YELLOW}#  – ${name} was not registered (nothing to remove)${NC}"
    fi
  fi
  echo ""
done

if $WITH_HOSTS; then
  echo -e "${YELLOW}# Removing the /etc/hosts keycloak alias${NC}"
  if $APPLY; then
    "${SCRIPT_DIR}/hosts-alias.sh" --remove
  else
    echo "${SCRIPT_DIR}/hosts-alias.sh --remove"
  fi
  echo ""
fi

if $APPLY; then
  echo -e "${GREEN}[OK]${NC} client-side hookup removed."
  echo -e "${YELLOW}# Reminders:${NC}"
  echo -e "${YELLOW}#  - Browser mode caches an OAuth token in your system keychain; run '/mcp' in${NC}"
  echo -e "${YELLOW}#    Claude Code to clear it, or delete the MCP entry in Keychain Access.${NC}"
  echo -e "${YELLOW}#  - To stop the stack:  docker compose down   (add -v for a full reset).${NC}"
  $WITH_HOSTS || echo -e "${YELLOW}#  - The /etc/hosts alias was kept (harmless); re-run with --with-hosts to remove it.${NC}"
else
  echo -e "${YELLOW}# (re-run with --apply to execute these; add --with-hosts to also remove the alias)${NC}"
fi
