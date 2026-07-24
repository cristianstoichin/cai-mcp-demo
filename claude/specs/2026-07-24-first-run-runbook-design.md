# Design — First-run setup automation + runbook

**Date:** 2026-07-24
**Status:** Approved (brainstorm)
**Audience:** A Cox Automotive operator running this demo for the first time against *their* Konnect org.

## Problem

The repo is well-scripted and documented, but first-run friction remains:

1. `konnect-bootstrap.sh` **prints** the 4 CP/TP endpoint lines and makes the operator **manually
   paste** them into `.env` — error-prone and easy to get wrong.
2. Setup is 4–6 discrete commands (bootstrap → `up` → wait → `deck sync` → dashboard → registry →
   verify) with no single orchestrator and no health-gating between stages.
3. `README.md` is an excellent *reference* but dense — there is no linear "start here" runbook.
4. Konnect-side prerequisites (AI Gateway Enterprise entitlement, PAT scope, Labs → MCP Registry)
   cannot be scripted and need a clear human checklist.

## Goal

A Cox operator with only a Konnect PAT goes from clone → running, verified demo with **one command**
and **one short doc**.

## Decisions (from brainstorm)

| Decision | Choice |
|----------|--------|
| Automation shape | One-shot orchestrator `scripts/setup.sh` that **composes existing scripts** |
| Bootstrap `.env` | Auto-write CP/TP endpoints into `.env` in place (backup first); still print |
| Runbook location | New standalone `RUNBOOK.md`; README stays the reference |
| Missing token/region | Prompt interactively when TTY; fail fast with a clear message when non-TTY |
| Add-ons default | Dashboard + Registry are **opt-in** flags (they need org entitlements); core setup + smoke always run |

## Components

### 1. `scripts/setup.sh` (new) — the one-shot orchestrator

Idempotent and re-runnable. **Calls the existing per-stage scripts** rather than duplicating them.
Each stage is a pass/fail gate; a failed core stage aborts with a pointer to the fix.

Flow:

| # | Stage | Action | Gate |
|---|-------|--------|------|
| 1 | Preflight tools | Verify `docker`, `docker compose`, `curl`, `jq`, `python3`, `openssl` | Hard-fail w/ install hint |
| 2 | Ensure `.env` | `cp .env.example .env` if absent; if `KONNECT_TOKEN` missing/placeholder → **prompt** for PAT + region (write into `.env`). Non-TTY → fail w/ message | Hard-fail |
| 3 | Bootstrap Konnect | `konnect-bootstrap.sh` (now auto-writes endpoints) | Hard-fail |
| 4 | Bring up stack | `docker compose up -d` | Hard-fail |
| 5 | Wait-for-health | Poll Keycloak discovery=200, Kong proxy responding, OPA=200, upstream containers healthy. Bounded (~120s) | Hard-fail on timeout w/ `docker compose logs` hint |
| 6 | decK sync | `docker compose --profile tools run --rm deck gateway sync /config/konnect.yaml` | Hard-fail |
| 7 | Wait-for-routes | Poll an `/mcp/*` endpoint until Kong serves synced config (401 = live, bounded) | Hard-fail on timeout |
| 8 | Add-ons (opt-in) | `--with-dashboard` → `install-dashboard.sh`; `--with-registry` → `registry-setup.sh`. **Best-effort**: on failure print a "skipped — needs Labs/Enterprise entitlement" note and continue | Never aborts the run |
| 9 | Smoke test | `smoke-test.sh`; print final green "READY — next: `scripts/demo.sh` or `scripts/ui.sh`" | Report result; non-fatal |

Flags:
- `--with-dashboard` — also install the Konnect analytics dashboard (best-effort).
- `--with-registry` — also publish to the MCP Registry (best-effort; US-only Labs).
- `--yes` / `-y` — non-interactive; never prompt (for CI). Requires `.env` pre-filled.
- `--force` — passed through to `konnect-bootstrap.sh` (regenerate + re-pin cert).

Add-on scripts are `set -euo pipefail` (exit non-zero on failure), so setup.sh runs them guarded
(`if ! script; then warn; fi`) to keep best-effort semantics.

### 2. `konnect-bootstrap.sh` change — auto-write `.env`

After computing the 4 endpoint values, write them into `.env` in place:
- Back up `.env` → `.env.bak` first.
- Replace the 4 keys (`KONNECT_CP_ENDPOINT`, `KONNECT_CP_SERVER_NAME`, `KONNECT_TP_ENDPOINT`,
  `KONNECT_TP_SERVER_NAME`) with their computed values (works whether the key is empty or already set).
- Still print the block (so nothing is lost if `.env` is read-only or the operator prefers manual).
- Idempotent: re-running overwrites the same 4 keys cleanly. No other keys touched.

Portable in-place edit via a temp file + `mv` (avoids `sed -i` GNU/BSD differences).

### 3. `RUNBOOK.md` (new) — "start here"

Concise, linear, distinct from the reference README:

1. **Before you begin** (human-only, cannot be scripted):
   - Konnect org with **AI Gateway Enterprise** entitlement (tech preview) — required for
     `ai-mcp-oauth2`/`ai-mcp-proxy`.
   - A **PAT** with control-plane admin rights.
   - *(Only for `--with-registry`)* Konnect → Organization → Labs → **"Catalog - MCP Registry"** ON
     (US region only).
2. **Set up** — `cp .env.example .env` (or let setup do it) → `./scripts/setup.sh`
   (mention `--with-dashboard --with-registry` for the full experience).
3. **What setup.sh does** — the 9-stage table so the operator knows what is happening.
4. **Verify & run** — `scripts/preflight.sh`, then `scripts/demo.sh` (CLI story) or `scripts/ui.sh`
   (visual cockpit).
5. **Teardown / reset** — `docker compose down -v`; re-run `setup.sh`.
6. **When something fails** — short triage table pointing into README's fuller Troubleshooting
   (no duplication).

## Non-goals (YAGNI)

- Not rewriting the existing per-stage scripts — `setup.sh` composes them.
- Not touching demo-ui, Kong config, or the Keycloak realm.
- Not duplicating README troubleshooting — RUNBOOK links to it.
- No CI wiring beyond making `--yes` non-interactive-safe.

## Docs to update in the same change

- `README.md` — add `RUNBOOK.md` + `scripts/setup.sh` to repo-layout; point Quickstart at the runbook.
- `claude/DECISIONS.md` — append the decision (one-shot orchestrator + auto-write .env + RUNBOOK).
- `claude/handoff/shipped-log.md` — append the ship entry.

## Verification

- `bash -n scripts/setup.sh` and `shellcheck` clean.
- `docker compose config -q` still valid.
- Dry-run mental trace of each stage against existing script interfaces (verified: bootstrap reads
  `.env`, prints endpoints; add-ons + smoke read `.env` and take the flags noted above).
- Live end-to-end is the org owner's phased verification (per CLAUDE.md verification model).
