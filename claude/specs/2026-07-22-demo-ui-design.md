# demo-ui — design spec

**Date:** 2026-07-22 · **Status:** approved (brainstorm), pending implementation plan
**Depends on:** the completed 6-phase cai-mcp-demo (Kong :8000, Keycloak :8080, OPA, market-mcp).
**Visuals:** `claude/specs/visuals/2026-07-22-demo-ui/` (decision-viz, demo-layout).

## Goal

A local, **Cox-branded** web cockpit that drives the *real* governed-MCP stack and makes each
governance decision legible to a live audience — replacing the wall of `scripts/demo.sh` terminal
output. Every "Run" fires an actual call through Kong :8000; the UI shows the decision path, the
plain-language "why," the token claims (including before/after a token exchange), and the response.

## Decisions locked in brainstorm

| # | Decision | Notes |
|---|----------|-------|
| U1 | **Three modes** in one app: Demo (scripted 7-step story), Explore (free sandbox), Stack (ops control). | Left nav. |
| U2 | Governance-decision viz = **Hybrid**: plugin-chain **trace** hero → "why" → token before/after → response. | visual: decision-viz.html |
| U3 | Demo step navigation = **top stepper** (7 steps, click to jump, done→green). | visual: demo-layout.html |
| U4 | Stack mode has **execute buttons** (whitelisted) that shell out to existing scripts, output streamed to the UI. | Local-only safety surface. |
| U5 | **Cox-branded** — approximate Cox Automotive palette (blue/navy) via CSS variables (exact hex is a one-line swap). | Flagged as approximate. |
| U6 | **Host-run Node/Express** backend + **vanilla-JS SPA**, no build step. | Adds Node 20 as a host prereq. |
| U7 | Token exchange is visualized by an **out-of-band reproduction** against Keycloak (kong-exchange creds), labeled as "what Kong does internally" — Kong's literal internal exchanged token is never client-visible. | |

## Architecture

Host-run (NOT in Compose) so Stack mode can invoke `docker compose` / `deck` / the scripts directly
and reach Kong/Keycloak on `localhost`. Reads everything from `.env` (no new hardcoded values).

```
demo-ui/
├── package.json            # express + (dev) a tiny test runner; type: module; no build step
├── server.js               # Express app: static + the /api/* endpoints below
├── verdict.js              # response-signature → governance verdict (the one testable unit)
├── verdict.test.js         # unit test: known responses → expected verdict
├── scenarios.js            # the 7 Demo scenarios as DATA (single source of truth; mirrors demo.sh)
└── public/
    ├── index.html          # SPA shell (Cox chrome, left nav)
    ├── app.js              # router + Demo/Explore/Stack views; renders trace/verdict/token/response
    └── styles.css          # Cox palette via CSS variables
scripts/ui.sh               # launcher: node demo-ui/server.js (loads .env), prints the URL
```

### Backend endpoints (each does one thing)

| Endpoint | Job |
|----------|-----|
| `POST /api/mcp` | Body `{persona, scope?, path, method, tool?, args?}`. Mints the persona token (server-side), fires the JSON-RPC call to `${KONG}/…`, returns `{httpStatus, body, verdict}` (verdict from `verdict.js`). Keeps the browser off CORS and off secrets. |
| `POST /api/token` | Mint a persona token (Keycloak ROPC via demo-cli secret). Returns raw token + decoded claims. |
| `POST /api/token/decode` | Decode any JWT → claims (no verify; display only). |
| `POST /api/exchange-preview` | Reproduce the RFC 8693 exchange against Keycloak (kong-exchange creds, scopes only) → returns the exchanged token's claims for the **AFTER** panel. Labeled as a faithful reproduction. |
| `GET /api/registry` | Konnect MCP Registry discovery (PAT stays server-side). Returns the published servers. |
| `GET /api/status` | `docker compose ps` + per-container health; DP-connected heuristic. |
| `POST /api/stack/:action` | **Whitelisted** actions only — `up`,`down`,`sync`,`preflight`,`smoke`,`registry-setup` — mapped to the existing scripts/compose commands; stdout streamed to the UI via SSE. Rejects anything not in the map. |

### The verdict classifier (`verdict.js`) — the tricky unit

Kong returns a status + body; each outcome has a **distinct signature** (already documented in
`NOTES.md`). The classifier maps signature → which trace node lit red/green + the "why":

| Signature | Verdict |
|-----------|---------|
| HTTP `401` | auth fail at `ai-mcp-oauth2` (no/invalid token) |
| HTTP `403` + HTML body `…403 Forbidden…` | **tool ACL** deny (token `groups` not in the tool's allow) |
| HTTP `403` + JSON `{"message":"unauthorized"}` | **OPA** deny |
| HTTP `200` + JSON-RPC `isError:true`, text `HTTP call failed with status 403` | **inner-gate** deny (missing scope/audience → the case token-exchange fixes) |
| HTTP `200` + `result.content` with data | **allow** (all gates passed) |

Note the inner-gate failure is an HTTP `200` with `isError` in the JSON-RPC body — the classifier
MUST inspect the body text, not just the HTTP status. Optionally enrich the exchange step by peeking
recent `kong-dp` logs for `[ai-mcp-oauth2] exchanging access token` (nice-to-have, not required).

### Frontend

Vanilla JS SPA, tiny hash router, three views sharing the same primitives:

- **Trace renderer** — nodes (persona → oauth2 → [exchange] → ACL → [OPA] → upstream) coloured from
  the verdict; the exchange node is highlighted when present.
- **Token panel** — claims; BEFORE/AFTER side-by-side on the exchange scenario (AFTER from `/api/exchange-preview`).
- **Verdict + response** — "why" line and the raw response body.

Views:
- **Demo** — top stepper over `scenarios.js`; persona switcher; ▶ Run; the hybrid panel. Scenarios are
  data (persona, scope, path, tool, args, narration, expected verdict) — the single source of truth,
  mirroring `demo.sh`'s seven steps.
- **Explore** — the same panel without the stepper: choose persona + scope + endpoint + tool + args → Run.
- **Stack** — status tiles + the whitelisted execute buttons with streamed output.

## Config & security

- All config from `.env` (`KONNECT_TOKEN`, Keycloak secrets, `KONG_URL` default `http://localhost:8000`,
  `KEYCLOAK_BASE`, `KONNECT_MCP_REGISTRY_ID`, region). Nothing org-specific added elsewhere.
- **Local-only tool, no UI auth** (binds `127.0.0.1`). Stack actions are a fixed whitelist → no arbitrary
  command execution. Secrets (PAT, client secrets) never reach the browser — they live in the backend only.

## Testing / verification

- **Unit:** `verdict.test.js` — feed the known response signatures above, assert the mapped verdict.
- **Live plumbing:** the existing `scripts/smoke-test.sh` already exercises the calls the UI wraps
  (401/200, OPA 403, remote 401); reuse it as the integration check.
- **Manual:** walk all three modes against the running stack; each Demo step's on-screen verdict must
  match the real HTTP outcome (spot-check against `demo.sh`).

## Explicitly out of scope (YAGNI)

No auth on the UI, no persistence/history, no framework/bundler, no multi-user, no editing rego/Kong
config from the UI (Stack only runs the existing scripts), no Docker packaging of the UI itself.

## Open items to verify during build

- [ ] Confirm each verdict signature against the live stack before trusting the classifier (statuses/bodies
      can shift with plugin versions — re-verify, per the project's doc-vs-reality discipline).
- [ ] Confirm `/api/stack` streaming works for the long-running `up`/`sync` actions (SSE keep-alive).
- [ ] Cox exact palette hex (approximate until confirmed; CSS variables make it a one-line change).
