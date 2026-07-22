# CLAUDE.md — cai-mcp-demo

Project instructions for Claude Code. Mirrors ARCHITECTURE.md + TECHSTACK.md; keep in sync.

## What this is

A runnable demo: **Kong Gateway 3.14 (Konnect hybrid) turns Cox Automotive REST APIs into
governed MCP servers** — REST→MCP conversion, tag-aggregated MCP endpoints, OAuth + consumer-group
tool ACLs, RFC 8693 token exchange, OPA policy, and passthrough of external MCP servers, discoverable
via the Konnect MCP Registry. Built against my Konnect org, handed to Cox to run against theirs.

## Hard rules

- **Never** co-locate `ai-mcp-oauth2` with `ai-mcp-proxy` in `conversion-listener` mode (GW 3.13+ breaks). Use `conversion-only` (REST) + `listener` (`/mcp/*`) + `passthrough-listener` (remotes).
- **Zero hardcoded** org IDs / CP names / region hosts / PATs / cert contents anywhere. Everything from `.env`. Ship `.env.example` only; `.env` + `certs/*` gitignored.
- Canonical external base URL `http://localhost:8000` — identical in Keycloak audiences, `ai-mcp-oauth2` `resource`, and registry entries.
- All Kong config is declarative decK (`kong/konnect.yaml`, `_format_version: "3.0"`). No imperative Admin API in the happy path.
- **Rebuilds use `docker compose build --no-cache`** for any changed service before up/test (D7). Use `scripts/rebuild.sh`.
- If decK/Konnect rejects a plugin field, fetch the current reference from developer.konghq.com and correct the schema — record the discrepancy in `NOTES.md`. Do not guess AI-MCP plugin schemas from memory; they change fast.

## Architecture

See ARCHITECTURE.md for the full module + Kong-topology tables. Tech versions in TECHSTACK.md.

## Setup (three commands)

```bash
cp .env.example .env          # fill KONNECT_TOKEN + region
scripts/konnect-bootstrap.sh  # create CP, gen/upload DP cert, print endpoints to append to .env
docker compose up             # everything except Konnect
docker compose --profile tools run --rm deck gateway sync /config/konnect.yaml
```

## Verification model

Build full repo + local static checks (`docker compose config`, `deck gateway validate`, `opa check`,
node smoke tests, JSON validity); the org owner runs the live phased verification. See
`claude/plans/2026-07-22-cai-mcp-demo-implementation.md` for the 6-phase gate list.

## Docs to keep current

`ARCHITECTURE.md`, `TECHSTACK.md`, `README.md` (with Known Issues), `NOTES.md` (doc-vs-reality),
`claude/DECISIONS.md` (append-only), `claude/NEXT-SESSION.md` + `claude/handoff/*`.
