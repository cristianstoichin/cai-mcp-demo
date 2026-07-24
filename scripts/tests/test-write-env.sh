#!/usr/bin/env bash
# Isolated test for write_env_var: idempotent, portable, touches only the target key.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
PASS=0; FAIL=0
pass(){ echo "[PASS] $*"; PASS=$((PASS+1)); }
fail(){ echo "[FAIL] $*"; FAIL=$((FAIL+1)); }

# Source only the helper by extracting it from the script (keeps one source of truth).
eval "$(awk '/^# >>> write_env_var >>>/{f=1} f; /^# <<< write_env_var <<</{f=0}' "${REPO_DIR}/scripts/konnect-bootstrap.sh")"

tmp="$(mktemp)"
printf 'FOO=keep\nKONNECT_CP_ENDPOINT=\nBAR=alsokeep\n' > "$tmp"

write_env_var KONNECT_CP_ENDPOINT "abc.example:443" "$tmp"
grep -q '^KONNECT_CP_ENDPOINT=abc.example:443$' "$tmp" && pass "sets empty key" || fail "sets empty key"
grep -q '^FOO=keep$' "$tmp" && grep -q '^BAR=alsokeep$' "$tmp" && pass "leaves other keys" || fail "leaves other keys"

# Idempotent + overwrite-existing-value
write_env_var KONNECT_CP_ENDPOINT "xyz.example:443" "$tmp"
[[ "$(grep -c '^KONNECT_CP_ENDPOINT=' "$tmp")" == "1" ]] && pass "no duplicate key" || fail "no duplicate key"
grep -q '^KONNECT_CP_ENDPOINT=xyz.example:443$' "$tmp" && pass "overwrites value" || fail "overwrites value"

# Appends when key absent
write_env_var NEW_KEY "v1" "$tmp"
grep -q '^NEW_KEY=v1$' "$tmp" && pass "appends missing key" || fail "appends missing key"

rm -f "$tmp"
echo "Summary: ${PASS} pass, ${FAIL} fail"
[[ $FAIL -eq 0 ]]
