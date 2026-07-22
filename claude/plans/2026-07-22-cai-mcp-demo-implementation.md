# cai-mcp-demo Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A complete, runnable demo repo where Kong Gateway 3.14 (Konnect hybrid mode) turns Cox Automotive REST APIs into governed MCP servers — REST→MCP conversion, tag-aggregated MCP endpoints, OAuth + consumer-group tool ACLs, RFC 8693 token exchange, OPA policy, and passthrough of external MCP servers, all discoverable via the Konnect MCP Registry.

**Architecture:** One `docker compose up` runs a Konnect hybrid data plane (`kong/kong-gateway:3.14.0.2`), Keycloak 26 (pre-baked realm), OPA, two Node/Express REST services, and one local Node MCP server. All Kong config is declarative decK (`kong/konnect.yaml`) synced to a Konnect control plane. `conversion-only` on REST routes + `listener` on `/mcp/*` routes avoids the `ai-mcp-oauth2`+conversion-listener footgun. Everything org-specific flows from `.env`.

**Tech Stack:** Kong Gateway 3.14 / Konnect, decK, Keycloak 26, OPA, Node 20 + Express, Docker Compose, MCP (streamable-HTTP).

## Global Constraints

- `_format_version: "3.0"` in `kong/konnect.yaml`; declarative decK only, no imperative Admin API in happy path.
- **Never** co-locate `ai-mcp-oauth2` with `ai-mcp-proxy` in `conversion-listener` mode. Use `conversion-only` (REST routes) + `listener` (`/mcp/*`) + `passthrough-listener` (remote routes).
- Canonical external base URL: `http://localhost:8000` — identical in Keycloak audiences, `ai-mcp-oauth2` `resource`, and registry entries.
- Zero hardcoded org IDs / CP names / region hostnames / PATs / cert contents anywhere. All from `.env`. Ship `.env.example` only; `.env` and `certs/*` gitignored.
- `.env` keys: `KONNECT_TOKEN`, `KONNECT_REGION`(=us), `KONNECT_CONTROL_PLANE_NAME`(=cai-mcp-demo), `KONNECT_CP_ENDPOINT`, `KONNECT_TP_ENDPOINT`, cert/key paths (=./certs/tls.crt,./certs/tls.key), Keycloak passwords, `REMOTE_MCP_URL`, `REMOTE_PUBLIC_MCP_URL`.
- Control-plane/decK API base `https://${KONNECT_REGION}.api.konghq.com`; MCP Registry base `https://klabs.${KONNECT_REGION}.api.konghq.com/v0/mcp-registries`.
- Pin exact image tags. Kong `3.14.0.2`. Keycloak `26.x` pinned to a patch at wiring time.
- **Rebuilds use `docker compose build --no-cache`** for any changed service before `up`/test (D7). Node services need no build step beyond `npm ci`.
- decK-rejected plugin field → fetch current reference from developer.konghq.com, correct schema, record discrepancy in `NOTES.md`.
- Verify model D1: build all phases + local static checks; user runs live phased verification.

---

## File Structure

```
cai-mcp-demo/
├── .env.example                     # every key, safe placeholders
├── .gitignore                       # (done) .env, certs/*, node_modules
├── docker-compose.yaml              # kong-dp, keycloak, opa, dealer-svc, finance-svc, market-mcp, deck(profile:tools)
├── README.md                        # quickstart, walkthrough, mermaid, troubleshooting, Known Issues
├── ARCHITECTURE.md                  # module/responsibility table
├── TECHSTACK.md                     # category/tech/rationale table
├── CLAUDE.md                        # project instructions mirror of ARCHITECTURE + TECH STACK
├── NOTES.md                         # doc-vs-reality discrepancies
├── certs/.gitkeep                   # (done) DP cert target dir
├── keycloak/realm-export.json       # cox-auto realm, fully pre-baked
├── opa/policies/mcp.rego            # default-allow + list_invoices group gate + commented business-hours
├── kong/konnect.yaml                # THE declarative config (services, routes, plugins, consumers, groups)
├── dealer-svc/{package.json,server.js,Dockerfile}   # /customers, /vehicles
├── finance-svc/{package.json,server.js,Dockerfile}  # /invoices, /floorplans
├── market-mcp/{package.json,server.js,Dockerfile}   # local Cox MCP server (streamable-HTTP)
├── konnect/mcp-registry/*.json      # create-registry + publish bodies (3 gateway + 2 remote)
├── scripts/
│   ├── konnect-bootstrap.sh         # create CP + gen/upload DP cert + print endpoints
│   ├── get-token.sh                 # ROPC token per persona via demo-cli
│   ├── registry-setup.sh            # create registry + publish + discovery GET
│   ├── claude-code-setup.sh         # emit `claude mcp add` lines for all servers
│   ├── demo.sh                      # numbered pause-between-steps walkthrough
│   ├── rebuild.sh                   # docker compose build --no-cache <svc> && up -d --force-recreate
│   ├── preflight.sh                 # tool + port + health checks
│   └── smoke-test.sh                # local static + running-stack assertions
├── claude/
│   ├── specs/2026-07-22-cai-mcp-demo-design.md   # (done)
│   ├── plans/2026-07-22-cai-mcp-demo-implementation.md  # this file
│   ├── DECISIONS.md
│   ├── NEXT-SESSION.md
│   └── handoff/{state,backlog,next,known-issues,shipped-log}.md
```

---

## PHASE 1 — Compose skeleton + mock services + Keycloak realm

**Phase deliverable:** `docker compose up` brings up keycloak + both REST services; personas mint tokens; both APIs answer with a valid JWT and reject bad scopes/audiences. (Kong not wired yet.)

### Task 1.1: Repo scaffolding docs
**Files:** Create `ARCHITECTURE.md`, `TECHSTACK.md`, `CLAUDE.md`, `NOTES.md`, `claude/DECISIONS.md`, `README.md` (skeleton), `claude/NEXT-SESSION.md`, `claude/handoff/*.md`.
- [ ] Author ARCHITECTURE.md module/responsibility table from the design doc §4.
- [ ] Author TECHSTACK.md category/tech/rationale table.
- [ ] Seed DECISIONS.md with D1–D7 (date 2026-07-22) + registry-host discrepancy.
- [ ] Seed NOTES.md with the doc-verification checklist (design §9) as an open list.
- [ ] Commit: `docs: scaffold project docs (architecture, techstack, decisions, notes)`.

### Task 1.2: dealer-svc
**Files:** Create `dealer-svc/{package.json,server.js,Dockerfile}`.
**Interfaces — Produces:** `GET /customers?region=` → `[{name,dealership,region,kbb_trade_in_interest}]`; `GET /vehicles?price_rank=` → `[{vin,make,model,days_on_lot,vauto_price_rank}]`; `GET /health` → `{status:"ok"}`. Listens on `:3000`. Logs every request's headers (JSON) to stdout so forwarded `X-User-*` claims are visible.
- [ ] Write `server.js` (Express, the two endpoints + `/health` + header-logging middleware), realistic Cox dummy JSON.
- [ ] `package.json` (express only), `Dockerfile` (node:20-alpine, `npm ci`, `CMD node server.js`).
- [ ] **Verify:** `docker compose build --no-cache dealer-svc && docker compose up -d dealer-svc`; `curl -s localhost:3001/customers | jq` returns array; `curl -s localhost:3001/health` = ok; `docker compose logs dealer-svc` shows header dump.
- [ ] Commit: `feat(dealer-svc): dealership customers + vehicles mock API`.

### Task 1.3: finance-svc
**Files:** Create `finance-svc/{package.json,server.js,Dockerfile}`.
**Interfaces — Produces:** `GET /invoices?status=` → `[{invoice_id,dealer,amount,status}]`; `GET /floorplans?status=` → `[{floorplan_line,utilization,next_audit_date}]`; `GET /health`. Listens `:3000`, same header-logging.
- [ ] Same pattern as 1.2 with finance dummy JSON.
- [ ] **Verify:** build `--no-cache`, up, curl both endpoints + health; logs show headers.
- [ ] Commit: `feat(finance-svc): invoices + floorplans mock API`.

### Task 1.4: Keycloak realm cox-auto
**Files:** Create `keycloak/realm-export.json`.
**Interfaces — Produces:** realm `cox-auto`; client scopes `dealers:read`/`finance:read`/`mcp:use` each with an audience mapper (dealer-api / finance-api / mcp-dealers|mcp-finance|mcp-ops); groups `dealers|finance|ops` emitted in `groups` claim; users `dana.dealer`/`frank.finance`/`olivia.ops` with group membership + `.env` passwords; clients `demo-cli`(confidential, direct-grant), `claude-code`(public, PKCE), `kong-exchange`(confidential, introspection + RFC 8693 standard token exchange).
- [ ] **Doc-verify first:** confirm Keycloak 26 standard token exchange enablement (client flag + policy) against current Keycloak docs; record in NOTES.md.
- [ ] Author realm JSON with all of the above; audience mappers on scopes; `groups` group-membership mapper; direct-grant on demo-cli; PKCE public claude-code; kong-exchange with token-exchange enabled.
- [ ] Commit: `feat(keycloak): pre-baked cox-auto realm (scopes, groups, users, clients)`.

### Task 1.5: docker-compose (Phase-1 subset) + .env.example + get-token.sh
**Files:** Create `docker-compose.yaml` (keycloak, dealer-svc, finance-svc for now), `.env.example`, `scripts/get-token.sh`, `scripts/rebuild.sh`.
- [ ] compose: keycloak `start-dev --import-realm` (realm mounted read-only), host 8080; dealer-svc 3001→3000, finance-svc 3002→3000; healthchecks; `env_file: .env`.
- [ ] `.env.example` with every Global-Constraints key + persona passwords + placeholders.
- [ ] `get-token.sh <dana|frank|olivia> [audience-scope]` — ROPC via demo-cli, decode+print JWT + `export` line (adapt from aegis get-token.sh).
- [ ] `rebuild.sh <svc...>` — `docker compose build --no-cache "$@" && docker compose up -d --force-recreate "$@"`.
- [ ] **Verify (Phase-1 gate):** `docker compose config -q` passes; `cp .env.example .env`; `docker compose up -d`; Keycloak discovery `curl -s localhost:8080/realms/cox-auto/.well-known/openid-configuration | jq .issuer`; `./scripts/get-token.sh dana` mints a token whose payload shows `groups:["dealers"]`, scope `dealers:read`, aud `dealer-api`; a bad-scope request (dana asking finance scope) is refused by Keycloak.
- [ ] Commit: `feat(compose): phase-1 stack (keycloak + mock services) + get-token`.

---

## PHASE 2 — decK services/routes/OIDC + DP hybrid

**Phase deliverable:** DP connects to Konnect; `deck gateway validate` passes; the 4 REST routes enforce OIDC (401 no token / 200 valid / 403 wrong scope|audience).

### Task 2.1: konnect-bootstrap.sh
**Files:** Create `scripts/konnect-bootstrap.sh`.
- [ ] **Doc-verify first:** Konnect control-plane create API + DP client-cert (pinned/PKI) generate-upload endpoints under `https://${KONNECT_REGION}.api.konghq.com`; record in NOTES.md.
- [ ] Script: require `KONNECT_TOKEN`+region from `.env`; create CP `$KONNECT_CONTROL_PLANE_NAME` if absent (idempotent); generate keypair, upload DP cert (pki/pinned), write `certs/tls.crt`+`certs/tls.key`; fetch + print `KONNECT_CP_ENDPOINT`/`KONNECT_TP_ENDPOINT` to append to `.env`. Helpful failure if API 401/404.
- [ ] **Verify:** `bash -n` clean; shellcheck clean; dry-run prints intended calls (guarded so it no-ops without a real token).
- [ ] Commit: `feat(scripts): konnect-bootstrap (CP create + DP cert gen/upload)`.

### Task 2.2: kong-dp service + DP env in compose
**Files:** Modify `docker-compose.yaml` (+kong-dp), `.env.example` (DP vars).
- [ ] Add kong-dp `kong/kong-gateway:3.14.0.2`, hybrid env from `.env` (`KONG_ROLE=data_plane`, `KONG_DATABASE=off`, `KONG_CLUSTER_MTLS=pki`, `KONG_KONNECT_MODE=on`, `KONG_ROUTER_FLAVOR=expressions`, `KONG_CLUSTER_CONTROL_PLANE=${KONNECT_CP_ENDPOINT}`, telemetry endpoint, `KONG_CLUSTER_CERT/_KEY=/etc/secrets/kong-cluster-cert/tls.*`), mount `./certs:/etc/secrets/kong-cluster-cert:ro`, ports 8000/8443, `kong health` healthcheck.
- [ ] **Verify:** `docker compose config -q`; (live, user) DP shows connected in Konnect after bootstrap.
- [ ] Commit: `feat(compose): kong-dp hybrid data plane`.

### Task 2.3: kong/konnect.yaml — services, routes, OIDC + deck one-shot
**Files:** Create `kong/konnect.yaml`, add `deck` service (profile `tools`) to compose.
**Interfaces — Produces:** services `dealer-svc`(http://dealer-svc:3000)/`finance-svc`(:3000); routes dealer-customers `/api/dealers/customers`, dealer-vehicles `/api/dealers/vehicles`, finance-invoices `/api/finance/invoices`, finance-floorplans `/api/finance/floorplans`; each with `openid-connect` (bearer-only, issuer `http://keycloak:8080/realms/cox-auto` discovery, `scopes_required`, audience verify).
- [ ] **Doc-verify first:** `openid-connect` bearer-only + `scopes_required` + audience field names against reference; NOTES.md.
- [ ] Author `_format_version:"3.0"`, `_konnect.control_plane_name: ${{ env "DECK_..." }}`, services + 4 routes + OIDC plugin per route (dealers:read/dealer-api, finance:read/finance-api).
- [ ] compose `deck` one-shot: `kong/deck` image, profile `tools`, cmd `gateway sync /config/konnect.yaml`, env `DECK_KONNECT_TOKEN`/CP name, mount `./kong:/config`.
- [ ] **Verify (Phase-2 gate):** `docker compose run --rm deck gateway validate /config/konnect.yaml` passes; (live, user) `deck gateway sync`; curl matrix: no token→401, `get-token dana`→200 on dealer routes, dana token on finance route→403 (scope), finance token on dealer route→403.
- [ ] Commit: `feat(kong): services, routes, OIDC gates + deck sync`.

---

## PHASE 3 — conversion-only + listener MCP plugins (pre-auth)

**Phase deliverable:** `tools/list` returns 2/2/2-bundled tools on the three listeners; `tools/call` works via plain curl JSON-RPC — before any MCP auth.

### Task 3.1: ai-mcp-proxy conversion-only on the 4 REST routes
**Files:** Modify `kong/konnect.yaml`.
- [ ] **Doc-verify first:** `ai-mcp-proxy` `mode: conversion-only` fields — single `tools` entry, description, OpenAPI-style params, plugin-level `tags`, `logging.log_audits`; NOTES.md.
- [ ] Add per route: tool `list_dealer_customers`(tags dealer-tools,bundle-tools)/`list_dealer_vehicles`(dealer-tools)/`list_invoices`(finance-tools,bundle-tools)/`list_floorplans`(finance-tools); one optional query param each (region/status); `logging.log_audits:true`.
- [ ] **Verify:** `deck gateway validate` passes.
- [ ] Commit: `feat(kong): ai-mcp-proxy conversion-only on REST routes`.

### Task 3.2: ai-mcp-proxy listener routes /mcp/{dealers,finance,ops}
**Files:** Modify `kong/konnect.yaml`.
- [ ] **Doc-verify first:** `mode: listener`, `server.tag`, `include_consumer_groups` fields (listener example); NOTES.md.
- [ ] Add 3 listener routes: `/mcp/dealers`(server.tag dealer-tools), `/mcp/finance`(finance-tools), `/mcp/ops`(bundle-tools), `include_consumer_groups:true`.
- [ ] **Verify (Phase-3 gate):** `deck gateway validate`; (live) JSON-RPC `tools/list` on each listener → dealers 2 tools, finance 2, ops 4 (bundled); a `tools/call list_dealer_customers` returns dealer JSON.
- [ ] Commit: `feat(kong): ai-mcp-proxy listener routes (tag-aggregated)`.

---

## PHASE 4 — ai-mcp-oauth2 + consumer/group mapping + tool ACLs

**Phase deliverable:** persona-based filtering — dana/frank/olivia see and can call only their permitted tools.

### Task 4.1: consumers + consumer groups
**Files:** Modify `kong/konnect.yaml`.
- [ ] Add consumers `dana.dealer`/`frank.finance`/`olivia.ops`; consumer groups `dealers`/`finance`/`ops` with memberships matching Keycloak.
- [ ] **Verify:** `deck gateway validate`.
- [ ] Commit: `feat(kong): consumers + consumer groups`.

### Task 4.2: ai-mcp-oauth2 on /mcp/dealers + /mcp/finance (JWKS)
**Files:** Modify `kong/konnect.yaml`.
- [ ] **Doc-verify first:** `ai-mcp-oauth2` JWKS-validation config + internal-vs-external issuer/jwks host handling; NOTES.md.
- [ ] Add to both: `resource: http://localhost:8000/mcp/<name>`, `authorization_servers:["http://localhost:8080/realms/cox-auto"]`, jwks endpoint → `http://keycloak:8080/...`, `consumer_claim:[preferred_username]`, `consumer_by:[username]`, `consumer_groups_claim:[groups]`, `consumer_groups_optional:false`, `claim_to_header` sub→X-User-Id / preferred_username→X-User-Name.
- [ ] **Verify:** `deck gateway validate`; (live) unauth `tools/list`→401; dana token→200.
- [ ] Commit: `feat(kong): ai-mcp-oauth2 JWKS on dealers + finance listeners`.

### Task 4.3: tool ACLs (two-tier)
**Files:** Modify `kong/konnect.yaml`.
- [ ] **Doc-verify first:** two-tier ACL form (default allow + per-tool deny) for consumer groups; NOTES.md.
- [ ] `list_dealer_customers` allow dealers,ops; `list_dealer_vehicles` allow dealers,ops + deny finance; `list_invoices` allow finance,ops; `list_floorplans` allow finance only.
- [ ] **Verify (Phase-4 gate):** `deck gateway validate`; (live) dana sees dealer tools not finance; olivia sees bundle minus `list_floorplans`; denied `tools/call` returns ACL error.
- [ ] Commit: `feat(kong): two-tier tool ACLs by consumer group`.

---

## PHASE 5 — token exchange + OPA + passthrough remotes

**Phase deliverable:** ops token-exchange lets `/mcp/ops` calls satisfy inner OIDC gates; OPA denies then allows; both passthrough remote routes work behind `ai-mcp-oauth2`.

### Task 5.1: ai-mcp-oauth2 on /mcp/ops (introspection) + token exchange
**Files:** Modify `kong/konnect.yaml`, `.env.example`.
- [ ] Add `/mcp/ops` `ai-mcp-oauth2`: introspection (`introspection_endpoint` + kong-exchange client creds), `passthrough_credentials:true`, `token_exchange.enabled:true` → Keycloak token endpoint, `client_auth:inherit`, request audience dealer-api/finance-api.
- [ ] **Verify:** `deck gateway validate`; (live) olivia `tools/call list_dealer_customers` on `/mcp/ops` succeeds (inner OIDC satisfied by exchanged token). **If it fails OIDC on inner routes:** enable token_exchange on dealers+finance listeners too, document why in NOTES.md (design §4.2 fallback).
- [ ] Commit: `feat(kong): ai-mcp-oauth2 introspection + RFC 8693 exchange on /mcp/ops`.

### Task 5.2: OPA policy + opa plugin on /mcp/ops
**Files:** Create `opa/policies/mcp.rego`; modify `docker-compose.yaml` (+opa), `kong/konnect.yaml` (+opa plugin).
- [ ] **Doc-verify first:** `opa` plugin input document shape Kong sends; NOTES.md.
- [ ] `mcp.rego` package `mcp`: default `allow=true`; deny `tools/call` for `list_invoices` unless groups/roles include finance|ops; commented business-hours rule. Match Kong's input doc.
- [ ] compose opa `openpolicyagent/opa` `run --server --addr :8181 ./policies`, mount `./opa/policies`.
- [ ] `opa` plugin on `/mcp/ops` → `http://opa:8181/v1/data/mcp/allow`.
- [ ] **Verify:** `opa check opa/policies`; `deck gateway validate`; (live) `list_invoices` via ops denied for a non-finance/ops caller, allowed for olivia; flip commented rule works.
- [ ] Commit: `feat(opa): mcp.rego + opa plugin on /mcp/ops`.

### Task 5.3: market-mcp + two passthrough-listener routes
**Files:** Create `market-mcp/{package.json,server.js,Dockerfile}`; modify `docker-compose.yaml`, `kong/konnect.yaml`, `.env.example`.
- [ ] **Doc-verify first:** `passthrough-listener` config + DeepWiki live protocol version ≥2025-06-18; NOTES.md.
- [ ] `market-mcp` streamable-HTTP MCP server, Cox tools (e.g. `market_price_check`, `days_supply_lookup`), listens `:3000`.
- [ ] compose market-mcp 3003→3000. `kong/konnect.yaml`: `/mcp/remote` passthrough → `${REMOTE_MCP_URL}` (default http://market-mcp:3000/mcp), `/mcp/remote-public` → `${REMOTE_PUBLIC_MCP_URL}` (default https://mcp.deepwiki.com/mcp); `ai-mcp-oauth2` in front of both.
- [ ] **Verify (Phase-5 gate):** build `--no-cache market-mcp`; `deck gateway validate`; (live) `tools/list` on `/mcp/remote` returns market tools; `/mcp/remote-public` returns DeepWiki tools; both 401 unauth.
- [ ] Commit: `feat: local market-mcp + two passthrough-listener remote routes`.

---

## PHASE 6 — registry + Claude Code + README + demo

**Phase deliverable:** registry publishes + discovers 5 servers; Claude Code hookup emitted; README + demo.sh mirror each other; preflight/smoke green.

### Task 6.1: registry bodies + registry-setup.sh
**Files:** Create `konnect/mcp-registry/*.json`, `scripts/registry-setup.sh`.
- [ ] Registry create body `cai-mcp-registry`; publish bodies for `/mcp/dealers`,`/mcp/finance`,`/mcp/ops`,`/mcp/remote` (remotes streamable-http at `http://localhost:8000/mcp/...`).
- [ ] `registry-setup.sh`: base `https://klabs.${KONNECT_REGION}.api.konghq.com/v0/mcp-registries`; idempotent create → publish 4 → discovery GET `.../v0.1/servers` pretty-printed; helpful message if 404 (Labs not enabled).
- [ ] **Verify:** `bash -n`; shellcheck; JSON valid; (live) run → 4 servers listed.
- [ ] Commit: `feat(scripts): MCP Registry create + publish + discovery`.

### Task 6.2: claude-code-setup.sh + demo.sh
**Files:** Create `scripts/claude-code-setup.sh`, `scripts/demo.sh`, `scripts/preflight.sh`, `scripts/smoke-test.sh`.
- [ ] `claude-code-setup.sh` emits `claude mcp add --transport http <name> <url> --header "Authorization: Bearer <tok>"` for dealers/finance/ops + remote.
- [ ] `demo.sh` numbered pause-between-steps: (1) 401/200/403 raw-API curls, (2) tools/list on 3 listeners (2/2/2-bundled), (3) registry discovery, (4) audience-mismatch 401 finance token on /mcp/dealers, (5) token-exchange proof via logs, (6) ACL diff dana vs olivia + denied call, (7) OPA deny→allow.
- [ ] `preflight.sh` (tools+ports+health, adapt aegis) and `smoke-test.sh` (local static: `docker compose config -q`, `deck gateway validate`, `opa check`, node `/health`, JSON validity of realm+registry bodies).
- [ ] **Verify:** `bash -n` all; `./scripts/smoke-test.sh` green on the running stack.
- [ ] Commit: `feat(scripts): claude-code-setup, demo, preflight, smoke-test`.

### Task 6.3: README + finalize docs
**Files:** Modify `README.md`, `ARCHITECTURE.md`, `NOTES.md`, `claude/NEXT-SESSION.md` + handoff fragments.
- [ ] README: quickstart for a fresh 3rd-party Konnect org (Labs toggle for MCP Registry; AI Gateway Enterprise licensing note for `ai-mcp-oauth2`; three-command flow), walkthrough mirroring demo.sh with expected outputs, mermaid architecture diagram, troubleshooting (DP-not-connecting/cert, realm-import failures, audience 401 localhost/hostname mismatch, tech-preview status of ai-mcp-oauth2 + MCP Registry), Known Issues section.
- [ ] Reconcile NOTES.md with every discrepancy found; update handoff fragments + shipped-log.
- [ ] Commit: `docs: README quickstart + walkthrough + troubleshooting; finalize notes`.

---

## Self-Review

**Spec coverage:** every spec section maps to a task — compose services (1.2/1.3/1.4/2.2/5.2/5.3), realm (1.4), decK services/routes/OIDC (2.3), conversion-only+listener (3.1/3.2), ai-mcp-oauth2+consumers+groups+ACL (4.1–4.3), token exchange+OPA+passthrough (5.1–5.3), registry+claude-code+demo+README (6.1–6.3), bootstrap+portability (2.1, Global Constraints), NOTES.md discipline (every "doc-verify first"). No gaps.

**Placeholders:** none — every task has concrete files, field lists, and verify commands. Config file *contents* are authored at execution (declarative YAML/JSON, not unit-testable), which is why tasks specify exact fields/values rather than pasted 2000-line blobs.

**Type/name consistency:** service hostnames (`dealer-svc`/`finance-svc`/`market-mcp` on `:3000`), tool names (`list_dealer_customers`/`list_dealer_vehicles`/`list_invoices`/`list_floorplans`), tags (`dealer-tools`/`finance-tools`/`bundle-tools`), routes, groups, and `.env` keys are used identically across all phases and match the design doc.
