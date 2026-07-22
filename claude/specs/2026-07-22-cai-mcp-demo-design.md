# cai-mcp-demo — Design Spec

**Date:** 2026-07-22
**Author:** Paul Vergilis (Kong SE) + Claude
**Status:** Draft for approval
**Reference:** `~/workspace/github/aegis-insurance-ai-gateway-demo` (Konnect wiring + script patterns)

---

## 1. Purpose

A complete, runnable demo repo showing **Kong Gateway 3.14 (Konnect hybrid mode)** turning
plain REST APIs into **governed MCP servers** for a **Cox Automotive**-themed scenario.
Demonstrates: REST→MCP conversion, MCP tool aggregation by tag, OAuth-secured MCP
endpoints, consumer/group-based tool ACLs, RFC 8693 token exchange, OPA policy,
passthrough of external MCP servers, and Konnect MCP Registry discovery.

Built and tested first against **my** Konnect org, then handed to **Cox Automotive** to run
against **their** org. Therefore the repo is **100% Konnect-org portable**: zero hardcoded
org IDs, CP names/IDs, region hostnames, PATs, or cert contents. Everything flows from `.env`.

## 2. Non-negotiable constraints

1. **Never** put `ai-mcp-oauth2` on the same route as `ai-mcp-proxy` in **conversion-listener**
   mode (breaks as of GW 3.13). Design avoids conversion-listener entirely:
   `conversion-only` on API routes, `listener` on MCP routes, `passthrough-listener` on remote routes.
2. All Kong config is declarative decK (`kong/konnect.yaml`, `_format_version: "3.0"`) synced to
   Konnect. No imperative Admin API in the happy path.
3. One `docker compose up` for everything except Konnect.
4. Secrets + org-specific values come **only** from `.env` (ship `.env.example`). `certs/` and
   `.env` gitignored; only `.env.example` ships.
5. Canonical external base URL: `http://localhost:8000` — used consistently in Keycloak
   audiences, `ai-mcp-oauth2` `resource` fields, and registry entries.
6. Three-command setup for both me and Cox: fill `.env` → run `scripts/konnect-bootstrap.sh` → `docker compose up`.

## 3. Decisions (locked 2026-07-22)

| # | Decision | Rationale |
|---|----------|-----------|
| D1 | **Verification = full repo + local static checks.** I build all 6 phases; verify JSON/YAML/rego validity, `docker compose config`, node smoke tests, `deck gateway validate` (offline), realm-import structure. User runs live phased verification against their org. | No PAT available this session; matches how aegis was built (complete repo, user-tested). |
| D2 | **Two passthrough-listener routes.** `/mcp/remote` → local Cox-themed MCP server (in-compose, reliable default); `/mcp/remote-public` → DeepWiki (`https://mcp.deepwiki.com/mcp`). Both fronted by `ai-mcp-oauth2`. Remote URLs are `.env` vars. | Local server = offline/on-theme/demo-reliable; DeepWiki = genuine "govern a third-party MCP you don't own" story. Both stories, no single point of demo failure. |
| D3 | **Keycloak in-compose**, realm fully pre-baked (`realm-export.json`, `--import-realm`). | Spec requires zero manual clicks; aegis used cloud Okta but this repo must be self-contained. |
| D4 | **Consumer-group ACLs** on tools (`include_consumer_groups`, `consumer_groups_claim: [groups]`), not aegis's scope-claim ACLs. | Spec is explicit; shows persona/group entitlement filtering. |
| D5 | **Single `.env`** (spec) vs aegis's 3-file split. | Spec requires it. |
| D6 | **Agents used inline-sequential**, dispatching a domain agent only for self-contained chunks (node services, README). | Kong/Keycloak/OPA config is tightly interdependent; phased verification thread must stay coherent. |
| D7 | **Rebuilds always use `docker compose build --no-cache`.** Any change to service source or a Dockerfile → `--no-cache` rebuild of that service before `up`/test. `scripts/rebuild.sh` + `scripts/smoke-test.sh` enforce it (`--no-cache` build → `up -d --force-recreate`); README dev loop documents it. NOT wired as a per-edit hook (would rebuild on doc/yaml edits and each `--no-cache` build is slow); tied to the run/test step where staleness actually bites. | No stale binaries in the running stack — a cached layer masking a code change is a demo-day failure and a false "verified". |

## 4. Architecture

### 4.1 Compose services

| Service | Image / build | Host port | Notes |
|---------|---------------|-----------|-------|
| `kong-dp` | `kong/kong-gateway:3.14.0.2` (pinned) | 8000, 8443 | Hybrid DP, all config from `.env`, cert pair mounted at `/etc/secrets/kong-cluster-cert` |
| `keycloak` | `quay.io/keycloak/keycloak:26.x` | 8080 | `start-dev --import-realm`, realm from `./keycloak/realm-export.json` |
| `opa` | `openpolicyagent/opa` | 8181 | `run --server --addr :8181 ./policies`, policies from `./opa/policies/` |
| `dealer-svc` | Node 20 + Express (`npm ci`) | 3001 | `/customers`, `/vehicles`; logs received headers |
| `finance-svc` | Node 20 + Express | 3002 | `/invoices`, `/floorplans`; logs received headers |
| `market-mcp` | Node 20 (MCP server, streamable-HTTP) | 3003 | Local Cox-themed MCP for `/mcp/remote` passthrough (vAuto/market tools) |
| `deck` | `kong/deck` (profile `tools`) | — | One-shot `deck gateway sync kong/konnect.yaml` |

### 4.2 Kong topology

**Two REST services, four API routes (conversion-only):**

| Route | Path | Service | Tool | Tags | Scope gate | Audience |
|-------|------|---------|------|------|-----------|----------|
| dealer-customers | `/api/dealers/customers` | dealer-svc | `list_dealer_customers` | dealer-tools, bundle-tools | dealers:read | dealer-api |
| dealer-vehicles | `/api/dealers/vehicles` | dealer-svc | `list_dealer_vehicles` | dealer-tools | dealers:read | dealer-api |
| finance-invoices | `/api/finance/invoices` | finance-svc | `list_invoices` | finance-tools, bundle-tools | finance:read | finance-api |
| finance-floorplans | `/api/finance/floorplans` | finance-svc | `list_floorplans` | finance-tools | finance:read | finance-api |

Each API route: `openid-connect` (bearer-only, issuer discovery against internal Keycloak,
`scopes_required`, audience verification) + `ai-mcp-proxy` (`mode: conversion-only`, one tool w/
one optional query param, plugin-level tags) + tool ACL + `logging.log_audits: true`.

**Three MCP listener routes (aggregate by tag):**

| Route | server.tag | Auth mode |
|-------|-----------|-----------|
| `/mcp/dealers` | dealer-tools | `ai-mcp-oauth2` JWKS validation |
| `/mcp/finance` | finance-tools | `ai-mcp-oauth2` JWKS validation |
| `/mcp/ops` | bundle-tools | `ai-mcp-oauth2` introspection (kong-exchange creds) + token exchange + OPA |

`/mcp/ops` only: `passthrough_credentials: true`, `token_exchange.enabled: true` → Keycloak token
endpoint (`client_auth: inherit`) so mcp-ops-audience token is exchanged for dealer-api/finance-api
tokens satisfying the inner OIDC gates. Fallback documented: if token flow without passthrough fails
OIDC on the inner conversion routes, enable token exchange on all three listeners and document why.

**Two passthrough-listener routes (D2):** `/mcp/remote` (local `market-mcp`), `/mcp/remote-public`
(DeepWiki). Both fronted by `ai-mcp-oauth2`.

All `/mcp/*`: `resource: http://localhost:8000/mcp/<name>`,
`authorization_servers: ["http://localhost:8080/realms/cox-auto"]` (external, client-facing),
JWKS/introspection endpoint pointing at **internal** `http://keycloak:8080/...`,
`consumer_claim: [preferred_username]`, `consumer_by: [username]`,
`consumer_groups_claim: [groups]`, `consumer_groups_optional: false`,
`claim_to_header: sub→X-User-Id, preferred_username→X-User-Name`.

### 4.3 Consumers / groups / ACLs

Consumers `dana.dealer`, `frank.finance`, `olivia.ops`; groups `dealers`, `finance`, `ops`.

| Tool | ACL |
|------|-----|
| `list_dealer_customers` | allow dealers, ops |
| `list_dealer_vehicles` | allow dealers, ops; explicit deny finance |
| `list_invoices` | allow finance, ops |
| `list_floorplans` | allow finance only (not ops — "even admins don't see everything") |

### 4.4 Keycloak realm `cox-auto`

- Scopes `dealers:read`, `finance:read`, `mcp:use` each with audience mapper
  (dealer-api / finance-api / mcp-dealers|mcp-finance|mcp-ops).
- Groups `dealers`, `finance`, `ops` in a `groups` claim (group-membership mapper).
- Users: `dana.dealer` (dealers), `frank.finance` (finance), `olivia.ops` (ops, all scopes).
- Clients: `demo-cli` (confidential, direct-grant), `claude-code` (public, PKCE),
  `kong-exchange` (confidential; introspection + RFC 8693 standard token exchange).
- **Verify** Keycloak 26 standard token exchange mechanism (client flag + audience/scope policy)
  against current Keycloak docs before baking the realm.

### 4.5 OPA

`opa/policies/mcp.rego`: default allow; deny `tools/call` for `list_invoices` unless token
roles/groups include `finance` or `ops`; commented-out business-hours rule. Match the exact input
document Kong's `opa` plugin sends (verify against OPA plugin docs). `/mcp/ops` calls
`http://opa:8181/v1/data/mcp/allow`.

## 5. Auth / token flow (happy path)

1. Client gets a Keycloak token (scope `mcp:use`, audience `mcp-ops`) via `demo-cli` (curl) or
   `claude-code` (PKCE).
2. Client hits `/mcp/ops`. `ai-mcp-oauth2` validates (introspection), maps consumer + groups,
   sets `X-User-Id`/`X-User-Name`.
3. `tools/call` → `ai-mcp-proxy` listener resolves the tagged conversion route; group ACL + OPA gate.
4. Kong exchanges (RFC 8693) the mcp-ops token for a dealer-api/finance-api token; inner conversion
   route's `openid-connect` gate passes; REST call executes; result marshalled back as MCP.

## 6. Konnect portability

`.env` keys: `KONNECT_TOKEN`, `KONNECT_REGION` (default `us`), `KONNECT_CONTROL_PLANE_NAME`
(default `cai-mcp-demo`), `KONNECT_CP_ENDPOINT`, `KONNECT_TP_ENDPOINT`, cert/key paths
(default `./certs/tls.crt` / `./certs/tls.key`), Keycloak passwords, `REMOTE_MCP_URL`,
`REMOTE_PUBLIC_MCP_URL`.

- Control-plane / decK API base: `https://${KONNECT_REGION}.api.konghq.com`.
- **MCP Registry API base: `https://klabs.${KONNECT_REGION}.api.konghq.com/v0/mcp-registries`**
  (verified from aegis `setup-mcp-registry.sh`; the aegis README's `us.api.konghq.com/v2` path is stale).
- `scripts/konnect-bootstrap.sh`: given PAT + region, create CP if absent, generate/upload DP cert,
  write cert/key to `./certs/`, print CP/TP endpoints to append to `.env`. **Net-new** vs aegis
  (which populated certs by hand from the UI) — verify against current control-plane + DP-cert API docs.

## 7. Scripts

`get-token.sh <dana|frank|olivia> [audience-scope]`, `registry-setup.sh`, `claude-code-setup.sh`,
`demo.sh` (numbered pause-between-steps walkthrough), `konnect-bootstrap.sh`, plus a
`preflight.sh` + `smoke-test.sh` for local verification (D1).

## 8. Phase plan (verify each before next)

1. **Compose skeleton + mock services + Keycloak realm** — tokens mint; both APIs answer with valid
   JWTs and reject bad scopes.
2. **decK services/routes/OIDC** — `deck gateway validate` then sync; curl matrix (401/200/403).
3. **conversion-only + listener MCP plugins** — `tools/list` + `tools/call` on all listeners via plain
   curl JSON-RPC before auth.
4. **`ai-mcp-oauth2` + consumer/group mapping + ACLs** — persona-based filtering.
5. **Token exchange + OPA + passthrough remote(s)**.
6. **registry-setup.sh + claude-code-setup.sh + README + demo.sh**.

At every phase, if decK/Konnect rejects a plugin field, fetch the current config reference from
developer.konghq.com and correct the schema — record doc-vs-reality discrepancies in `NOTES.md`.

## 9. Doc-verification checklist (before wiring each)

- [ ] `ai-mcp-proxy` `conversion-only` / `listener` fields: `server.tag`, `include_consumer_groups`, tool ACL shape
- [ ] `ai-mcp-oauth2` JWKS vs introspection config; internal-vs-external issuer/jwks hostnames
- [ ] consumer-group ACL form
- [ ] `opa` plugin input document shape
- [ ] Keycloak 26 standard token exchange (RFC 8693) enablement
- [ ] MCP Registry `klabs` host + `/v0` create, `/v0.1/publish`, `/v0.1/servers` paths
- [ ] Konnect control-plane create + DP-cert generate/upload API (for bootstrap)
- [ ] DeepWiki live protocol version ≥ 2025-06-18

## 10. Project scaffolding (per global CLAUDE.md)

`ARCHITECTURE.md`, `TECHSTACK.md`, `CLAUDE.md`, `README.md` (with Known Issues), `NOTES.md`,
`claude/DECISIONS.md`, `claude/specs/` (this doc + archived visuals), `claude/NEXT-SESSION.md` +
`claude/handoff/` fragments. Git repo initialized; `.gitignore` covers `.env`, `certs/`, `node_modules`.
