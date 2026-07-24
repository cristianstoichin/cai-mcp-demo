# First-run Setup Orchestrator + RUNBOOK Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give a first-time Cox operator a single command (`scripts/setup.sh`) and a single doc (`RUNBOOK.md`) to go from clone → running, verified demo.

**Architecture:** A new `scripts/setup.sh` orchestrates the existing per-stage scripts behind gated stages (preflight → ensure-env → bootstrap → compose up → wait-health → deck sync → wait-routes → opt-in add-ons → smoke). `konnect-bootstrap.sh` gains an idempotent in-place `.env` writer so CP/TP endpoints are captured automatically. A concise `RUNBOOK.md` is the human "start here"; README stays the reference.

**Tech Stack:** Bash (`set -euo pipefail`), Docker Compose v2, decK (via compose `tools` profile), curl/jq/python3/openssl. Verification via `bash -n` (shellcheck optional — not installed here).

## Global Constraints

- **Zero hardcoded** org IDs / CP names / region hosts / PATs / cert contents. Everything from `.env`. (CLAUDE.md hard rule.)
- Canonical external base URL `http://localhost:8000` — unchanged.
- `setup.sh` **composes existing scripts**; it does not duplicate their logic.
- Add-ons (`install-dashboard.sh`, `registry-setup.sh`) are `set -euo pipefail` and exit non-zero on failure — setup.sh must run them **guarded** (best-effort, never abort the run).
- In-place `.env` edits must be **portable** (no `sed -i` — GNU/BSD differ): use temp file + `mv`, back up `.env` → `.env.bak` first, touch only the 4 target keys.
- All scripts resolve `REPO_DIR` relative to `BASH_SOURCE` and source `.env` the same way the existing scripts do.
- Commit messages: Conventional Commits; footer `Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>`.

---

## File Structure

| File | Responsibility |
|------|----------------|
| `scripts/konnect-bootstrap.sh` (modify) | Add `write_env_var` helper + call it for the 4 endpoint keys; keep the printed block |
| `scripts/setup.sh` (create) | One-shot gated orchestrator; flags `--with-dashboard --with-registry --yes/-y --force --help` |
| `RUNBOOK.md` (create) | Linear "start here" first-run guide |
| `README.md` (modify) | Point Quickstart at RUNBOOK; add `setup.sh` to repo-layout |
| `claude/DECISIONS.md` (modify) | Append the decision entry |
| `claude/handoff/shipped-log.md` (modify) | Append the ship entry |

---

## Task 1: Auto-write `.env` in `konnect-bootstrap.sh`

**Files:**
- Modify: `scripts/konnect-bootstrap.sh` (add a `write_env_var` helper near the other helpers ~line 51; call it in the "print the .env lines" section ~lines 126-139)

**Interfaces:**
- Consumes: existing vars `REPO_DIR`, `CP_ENDPOINT`, `TP_ENDPOINT`, `CP_HOST`, `TP_HOST`, and helper `endp_of`.
- Produces: side effect — the 4 keys `KONNECT_CP_ENDPOINT`, `KONNECT_CP_SERVER_NAME`, `KONNECT_TP_ENDPOINT`, `KONNECT_TP_SERVER_NAME` are set to their computed values in `${REPO_DIR}/.env`. Function `write_env_var KEY VALUE FILE` for reuse by `setup.sh`.

- [ ] **Step 1: Write the failing test** — a standalone harness that exercises the writer against a fixture, covering the two cases (empty key present; key already has a value).

Create `scripts/tests/test-write-env.sh`:

```bash
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
```

- [ ] **Step 2: Run it to verify it fails**

Run: `bash scripts/tests/test-write-env.sh`
Expected: FAIL — the `eval "$(awk ...)"` extracts nothing (marker + function absent), so `write_env_var` is undefined and every assertion fails / errors.

- [ ] **Step 3: Add the `write_env_var` helper to `konnect-bootstrap.sh`**

Insert immediately after the `kapi()` helper block (after line 68), wrapped in the marker comments the test greps for:

```bash
# >>> write_env_var >>>
# write_env_var KEY VALUE FILE — set KEY=VALUE in FILE in place, portably.
# Replaces the line if KEY exists (empty or not), appends if absent. Touches
# only KEY. No sed -i (GNU/BSD differ): rewrite via awk to a temp file + mv.
write_env_var() {
  local key="$1" val="$2" file="$3" tmp
  [[ -f "$file" ]] || : > "$file"
  tmp="$(mktemp)"
  awk -v k="$key" -v v="$val" '
    $0 ~ "^"k"=" { print k"="v; found=1; next }
    { print }
    END { if (!found) print k"="v }
  ' "$file" > "$tmp" && mv "$tmp" "$file"
}
# <<< write_env_var <<<
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `bash scripts/tests/test-write-env.sh`
Expected: `Summary: 5 pass, 0 fail` (exit 0).

- [ ] **Step 5: Wire the writer into the "print the .env lines" section**

In the final section (~lines 126-143), immediately *before* the existing `cat >&2 <<EOF ... DONE.` block, add a backup + four writes to `${REPO_DIR}/.env`, and add one line to the printed guidance noting `.env` was updated. Replace the section so it both writes and prints:

```bash
# --- 4. write + print the .env lines -------------------------------------------
ENV_FILE="${REPO_DIR}/.env"
CP_ENDP="$(endp_of "$CP_ENDPOINT")"; TP_ENDP="$(endp_of "$TP_ENDPOINT")"
if [[ -f "$ENV_FILE" ]]; then
  cp "$ENV_FILE" "${ENV_FILE}.bak"
  write_env_var KONNECT_CP_ENDPOINT    "$CP_ENDP" "$ENV_FILE"
  write_env_var KONNECT_CP_SERVER_NAME "$CP_HOST" "$ENV_FILE"
  write_env_var KONNECT_TP_ENDPOINT    "$TP_ENDP" "$ENV_FILE"
  write_env_var KONNECT_TP_SERVER_NAME "$TP_HOST" "$ENV_FILE"
  ok "wrote CP/TP endpoints into .env (backup at .env.bak)."
else
  info "no .env found — printing endpoints for you to add manually."
fi

cat >&2 <<EOF

$(echo -e "${GREEN}[bootstrap] DONE.${NC}") Control plane '${CP_NAME}' is ready (${CP_ID}).
These values are now in .env (and printed below):
------------------------------------------------------------------
EOF
cat <<EOF
KONNECT_CP_ENDPOINT=${CP_ENDP}
KONNECT_CP_SERVER_NAME=${CP_HOST}
KONNECT_TP_ENDPOINT=${TP_ENDP}
KONNECT_TP_SERVER_NAME=${TP_HOST}
EOF
cat >&2 <<EOF
------------------------------------------------------------------
Then: docker compose up -d   &&   docker compose --profile tools run --rm deck gateway sync /config/konnect.yaml
(or just run ./scripts/setup.sh to do everything.)
EOF
```

Delete the previous `# --- 4. print the .env lines ---` block (old lines 126-143) so only this one remains.

- [ ] **Step 6: Verify syntax + re-run the writer test**

Run: `bash -n scripts/konnect-bootstrap.sh && bash scripts/tests/test-write-env.sh`
Expected: no syntax errors; `Summary: 5 pass, 0 fail`.

- [ ] **Step 7: Verify `.gitignore` keeps `.env.bak` out of git**

Run: `git check-ignore .env.bak || echo "NOT IGNORED"`
Expected: prints `.env.bak` (ignored). If it prints `NOT IGNORED`, add `.env.bak` to `.gitignore` in this step before committing.

- [ ] **Step 8: Commit**

```bash
git add scripts/konnect-bootstrap.sh scripts/tests/test-write-env.sh
git commit -m "feat(bootstrap): auto-write CP/TP endpoints into .env (portable, idempotent)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 2: `scripts/setup.sh` one-shot orchestrator

**Files:**
- Create: `scripts/setup.sh`

**Interfaces:**
- Consumes: `scripts/konnect-bootstrap.sh`, `scripts/smoke-test.sh`, `scripts/install-dashboard.sh`, `scripts/registry-setup.sh`, `docker compose`, `.env`, `.env.example`.
- Produces: an executable entrypoint. Exit 0 only if all core stages (1-7) pass. Add-on and smoke failures are reported but non-fatal.

- [ ] **Step 1: Create the script skeleton with arg parsing, `--help`, and stage helpers**

Create `scripts/setup.sh`:

```bash
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
```

- [ ] **Step 2: Verify syntax of the skeleton**

Run: `bash -n scripts/setup.sh`
Expected: no output (valid). Then `bash scripts/setup.sh --help` prints usage and exits 0.

- [ ] **Step 3: Add Stage 1 (preflight tools) + Stage 2 (ensure .env, interactive prompt)**

Append to `scripts/setup.sh`:

```bash
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
```

- [ ] **Step 4: Verify syntax**

Run: `bash -n scripts/setup.sh`
Expected: no output.

- [ ] **Step 5: Add Stage 3 (bootstrap) + Stage 4 (compose up)**

Append:

```bash
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
```

- [ ] **Step 6: Add Stage 5 (wait-for-health) with a bounded poll helper**

Append:

```bash
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
```

- [ ] **Step 7: Add Stage 6 (deck sync) + Stage 7 (wait-for-routes)**

Append:

```bash
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
```

- [ ] **Step 8: Add Stage 8 (opt-in add-ons, best-effort) + Stage 9 (smoke) + final summary**

Append:

```bash
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
```

- [ ] **Step 9: Make executable + full syntax check**

Run:
```bash
chmod +x scripts/setup.sh
bash -n scripts/setup.sh && ./scripts/setup.sh --help
```
Expected: no syntax errors; help text prints and exits 0.

- [ ] **Step 10: Non-TTY guard check (fast, no live calls)**

Run: `printf '' | env -i PATH="$PATH" bash -c 'cd "'"$REPO_DIR"'" && ./scripts/setup.sh --yes' ; echo "exit=$?"`
Expected: if `.env` lacks a real `KONNECT_TOKEN`, it dies at Stage 2 with the "edit .env and re-run" message and a non-zero exit — proving the non-interactive guard works. (If your `.env` already has a valid token it will proceed past Stage 2; that's fine — Ctrl-C is safe.)

- [ ] **Step 11: Commit**

```bash
git add scripts/setup.sh
git commit -m "feat(setup): one-shot gated orchestrator (preflight->bootstrap->up->sync->smoke)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 3: `RUNBOOK.md`

**Files:**
- Create: `RUNBOOK.md`

**Interfaces:**
- Consumes: `scripts/setup.sh` (Task 2), the existing scripts, README Troubleshooting.
- Produces: the human "start here" doc. No code depends on it.

- [ ] **Step 1: Write `RUNBOOK.md`**

Create `RUNBOOK.md`:

```markdown
# RUNBOOK — Running cai-mcp-demo for the first time

This is the **start-here** guide. For deep reference (per-step demo expectations,
plugin-schema notes, full troubleshooting) see [README.md](./README.md) and [NOTES.md](./NOTES.md).

> **What you get:** Kong Gateway (Konnect hybrid) turning REST APIs into governed MCP servers —
> OAuth-gated, token-claim tool ACLs, RFC 8693 exchange, OPA policy, remote-MCP passthrough,
> discoverable in the Konnect MCP Registry, with a Konnect analytics dashboard.

## 1. Before you begin (human-only — cannot be scripted)

You need a **Konnect organization** with:

| Requirement | Why | Where |
|-------------|-----|-------|
| **AI Gateway Enterprise** entitlement (tech preview) | `ai-mcp-oauth2` / `ai-mcp-proxy` plugins require it | Konnect org tier |
| A **Personal Access Token (PAT)** with control-plane admin rights | Bootstrap + config sync + dashboard | Konnect → *your avatar* → Personal Access Tokens |
| *(only for `--with-registry`)* **Labs → "Catalog - MCP Registry"** = ON | Publish/discover MCP servers | Konnect → Organization → Labs (US region only) |

Local tools: **Docker + Docker Compose v2**, `curl`, `jq`, `python3`, `openssl`.
(`setup.sh` checks these and tells you what's missing.)

## 2. Set up (one command)

```bash
git clone <this-repo> && cd cai-mcp-demo
./scripts/setup.sh
```

On first run with no `.env`, setup copies `.env.example → .env` and **prompts** for your
`KONNECT_TOKEN` + region, then runs the whole flow. For the full experience (analytics + registry):

```bash
./scripts/setup.sh --with-dashboard --with-registry
```

Prefer to fill `.env` yourself first? Edit `KONNECT_TOKEN` and `KONNECT_REGION` in `.env`, then
`./scripts/setup.sh --yes` (non-interactive).

## 3. What `setup.sh` does

| Stage | Action |
|-------|--------|
| 1 Preflight | Verify docker/compose/curl/jq/python3/openssl |
| 2 Ensure `.env` | Create from example; prompt for PAT + region if missing |
| 3 Bootstrap | Create the Konnect control plane, generate + pin the data-plane cert, **write CP/TP endpoints into `.env`** |
| 4 Up | `docker compose up -d` (Kong DP, Keycloak, OPA, mock APIs, market-mcp, demo-ui) |
| 5 Wait-health | Poll Keycloak, OPA, Kong until ready |
| 6 Sync | `deck gateway sync` — push the declarative config |
| 7 Wait-routes | Poll until the data plane serves the MCP routes |
| 8 Add-ons | *(opt-in)* install dashboard / publish registry — best-effort |
| 9 Smoke | `smoke-test.sh` static + live checks |

Idempotent — safe to re-run. It writes a `.env.bak` before touching `.env`.

## 4. Verify & run the demo

```bash
./scripts/preflight.sh     # tools, container health, port reachability
./scripts/demo.sh          # guided 7-step CLI walkthrough (pauses between steps)
./scripts/ui.sh            # OR the visual cockpit at http://127.0.0.1:4000
```

Mint a token and call a governed endpoint directly:

```bash
TOKEN=$(./scripts/get-token.sh olivia --raw)
curl -s http://localhost:8000/mcp/ops -H "Authorization: Bearer $TOKEN" \
  -H 'Content-Type: application/json' -H 'Accept: application/json, text/event-stream' \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/list"}'
```

## 5. Tear down / reset

```bash
docker compose down -v     # stop + remove volumes (Keycloak is ephemeral H2 anyway)
./scripts/setup.sh         # re-run to rebuild
```

The Konnect control plane persists across teardowns (it's SaaS). `setup.sh`/bootstrap are
idempotent and will reuse it.

## 6. When something fails

| Symptom | First move |
|---------|-----------|
| Missing tool at Stage 1 | Install it (setup prints the hint), re-run |
| Stage 3 bootstrap 401/403 | `KONNECT_TOKEN` invalid/expired or wrong `KONNECT_REGION` — fix in `.env`, re-run |
| Stage 5 Keycloak/Kong timeout | `docker compose logs keycloak` / `kong-dp`; re-run once Docker settles |
| Stage 6 deck sync error | `docker compose --profile tools run --rm deck gateway validate /config/konnect.yaml` |
| Every token 401s at Kong | Keep the `iss` pin — see README → Troubleshooting |
| `--with-registry` 404/permission | Enable Labs "Catalog - MCP Registry" (US only) |

Full troubleshooting and per-step demo expectations: **[README.md](./README.md)**.
Doc-vs-reality plugin facts: **[NOTES.md](./NOTES.md)**.
```

- [ ] **Step 2: Sanity-check the doc references exist**

Run:
```bash
for f in README.md NOTES.md scripts/setup.sh scripts/demo.sh scripts/ui.sh scripts/preflight.sh scripts/get-token.sh; do
  [[ -e "$f" ]] && echo "ok: $f" || echo "MISSING: $f"
done
```
Expected: every line `ok:` (no `MISSING:`).

- [ ] **Step 3: Commit**

```bash
git add RUNBOOK.md
git commit -m "docs(runbook): add first-run RUNBOOK.md (start-here guide)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 4: Update README + DECISIONS + shipped-log

**Files:**
- Modify: `README.md` (Quickstart intro + repo-layout `scripts/` line)
- Modify: `claude/DECISIONS.md`
- Modify: `claude/handoff/shipped-log.md`

**Interfaces:**
- Consumes: Tasks 1-3 deliverables.
- Produces: docs pointing at the new entrypoint. No code depends on these.

- [ ] **Step 1: Point README Quickstart at the RUNBOOK**

In `README.md`, immediately under the `## Quickstart` heading, add this line before the existing code block:

```markdown
> **First time? Start with [RUNBOOK.md](./RUNBOOK.md)** — it wraps everything below in one command
> (`./scripts/setup.sh`). The steps here are the manual equivalent / reference.
```

- [ ] **Step 2: Add `setup.sh` to the README repo-layout scripts line**

In `README.md` repo layout, find the `scripts/` bullet (lists `konnect-bootstrap`, `get-token`, …)
and add `setup` at the front so it reads:

```markdown
- `scripts/` — `setup` (one-shot orchestrator), `konnect-bootstrap`, `get-token`, `rebuild`,
  `registry-setup`, `install-dashboard`, `claude-code-setup`, `demo`, `preflight`, `smoke-test`,
  `ui` (launches the demo-ui cockpit).
```

- [ ] **Step 3: Verify README edits landed**

Run: `grep -q 'RUNBOOK.md' README.md && grep -q 'setup.*one-shot orchestrator' README.md && echo OK`
Expected: `OK`.

- [ ] **Step 4: Append a DECISIONS.md table row**

`claude/DECISIONS.md` is a Markdown **table** (`| Date | Decision | Rationale | Scope | Links |`).
Append this single row as the last line of the table (keep it on one physical line):

```markdown
| 2026-07-24 | Add `scripts/setup.sh` (gated 9-stage one-shot orchestrator composing existing scripts) + standalone `RUNBOOK.md`; `konnect-bootstrap.sh` auto-writes CP/TP endpoints into `.env`. | Repo was fully scripted but first-run needed 4-6 discrete commands + a manual copy-paste of bootstrap output into `.env` — the main friction handing the demo to Cox. One idempotent entrypoint + a linear "start here" doc removes it without duplicating the scripts. Add-ons (dashboard/registry) stay opt-in flags: they need org entitlements (AI Gateway Enterprise / US-only Labs) and must not fail the core run. | Onboarding / scripts | specs/2026-07-24-first-run-runbook-design.md, plans/2026-07-24-first-run-runbook.md |
```

- [ ] **Step 5: Append a shipped-log entry**

Append to `claude/handoff/shipped-log.md` (append-only; match its existing dated-entry style):

```markdown
## 2026-07-24 — First-run setup orchestrator + RUNBOOK
- `scripts/setup.sh` — one-shot gated flow (preflight → ensure-env → bootstrap → up → wait-health →
  deck sync → wait-routes → opt-in add-ons → smoke). Flags: `--with-dashboard --with-registry --yes --force`.
- `konnect-bootstrap.sh` now auto-writes CP/TP endpoints into `.env` (portable, idempotent; `.env.bak` backup).
- `RUNBOOK.md` — standalone first-run guide (prereqs incl. Konnect entitlements → setup → verify → teardown).
- README points Quickstart at RUNBOOK; `scripts/tests/test-write-env.sh` covers the env writer.
```

- [ ] **Step 6: Commit**

```bash
git add README.md claude/DECISIONS.md claude/handoff/shipped-log.md
git commit -m "docs: point README at RUNBOOK; log setup-orchestrator decision + ship

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Final verification (after all tasks)

- [ ] `bash -n scripts/setup.sh scripts/konnect-bootstrap.sh` — both clean.
- [ ] `bash scripts/tests/test-write-env.sh` — `5 pass, 0 fail`.
- [ ] `./scripts/setup.sh --help` — prints usage.
- [ ] `docker compose config -q` — still valid.
- [ ] All new doc cross-links resolve (RUNBOOK → README/NOTES/scripts all exist).
- [ ] Live end-to-end (`./scripts/setup.sh` against a real Konnect org) — **org owner's phased
      verification** per CLAUDE.md; not run in this build.

## Self-review notes (author)

- **Spec coverage:** Component 1 → Task 2; Component 2 → Task 1; Component 3 → Task 3; doc updates → Task 4. ✔
- **Placeholder scan:** every code step shows full content; no TBD/TODO. ✔
- **Type/name consistency:** `write_env_var KEY VALUE FILE` defined in Task 1, reused verbatim in Task 2 Stage 2; `poll DESC URL REGEX TIMEOUT` defined once and reused. ✔
- **Best-effort semantics:** add-ons + smoke guarded with `if ! …; then warn`; only Stages 1-7 `die`. ✔
```
