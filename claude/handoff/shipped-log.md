# shipped-log.md — append-only

- **2026-07-22** — Repo init + design spec + phased plan.
- **2026-07-22** — Phase 1: dealer-svc + finance-svc mock APIs, Keycloak cox-auto realm
  (scopes/groups/users/3 clients + self-owned identity scope), compose subset, .env.example,
  get-token.sh, rebuild.sh. Verified locally: tokens mint with correct claims; APIs answer.
- **2026-07-22** — Phase 2: konnect-bootstrap.sh (CP find/create + PKI self-signed DP cert
  gen/pin + endpoint printing), kong-dp hybrid DP env in compose, kong/konnect.yaml (2 services,
  4 routes, openid-connect bearer-only gates). Pinned Keycloak issuer to keycloak:8080 so host+DP
  agree (verified). Mocks now own /api/dealers/* + /api/finance/* (strip_path:false). deck file
  validate passes offline.
- **2026-07-22** — Phases 1+2 VERIFIED LIVE against org (CP 007f4c01…): bootstrap created CP + pinned
  cert, DP connected, deck sync clean, auth matrix 401/200/403/200 all correct.
- **2026-07-22** — Phase 3: ai-mcp-proxy conversion-only on 4 REST routes (entity tags + OpenAPI
  params + log_audits) + 3 serviceless listener routes (server.tag aggregation, include_consumer_groups).
  LIVE-verified: tools/list = 2/2/2-bundled; tools/call round-trips to upstream with a forwarded bearer
  (query_<name> arg namespacing). deck file validate + gateway sync pass.
- **2026-07-22** — Phase 4 (aegis-style): ai-mcp-oauth2 on all 3 listeners (JWKS, relaxed audience,
  passthrough, claim_to_header X-User-*) + token-claim tool ACL (acl_attribute_type: oauth_access_token,
  access_token_claim_field: groups). Reverses D4 per request; no Kong consumers. LIVE-verified allow+deny
  matrix; X-User-* forwarded. deck sync clean.
- **2026-07-22** — Phase 5.1: /mcp/ops upgraded to introspection (kong-exchange confidential client) +
  RFC 8693 standard token exchange (client_auth: inherit). Exchange requests scopes only (Keycloak's
  `audience` param wants a registered client, not an audience string — logged in NOTES.md). LIVE-verified:
  an mcp:use-only token 403s the inner gate on /mcp/dealers but succeeds on /mcp/ops (exchanged token
  carries dealer-api+finance-api); ACL still enforces on the exchanged token's groups claim
  (frank→dealer DENY, frank→finance OK). Exchange creds injected via compose env (never hardcoded).
- **2026-07-22** — Phase 5.2: OPA on /mcp/ops. opa/policies/mcp.rego (default allow; entitlement rule +
  argument-level rule denying list_invoices?query_status=overdue; commented business-hours). opa plugin
  (include_parsed_json_body_in_opa_input) + claim_to_header groups→X-User-Groups. Input document
  doc-verified BY OBSERVATION (OPA decision_logs) — caught claim_to_header base64-encoding array claims.
  OPA runs -w (hot-reload). LIVE-verified: overdue filter → 403 while list_invoices/list_dealer_customers
  → 200; hot-reload flip took effect with no deck sync. opa check + deck validate pass.
- **2026-07-22** — Phase 5.3: market-mcp (plain-ESM Node MCP server, Streamable HTTP, tools
  market_price_check + days_supply_lookup) + two passthrough-listener routes: /mcp/remote → market-mcp
  (we own), /mcp/remote-public → DeepWiki (third-party). Both fronted by ai-mcp-oauth2 (JWKS gate,
  passthrough_credentials:false — internal token not leaked to remotes); upstreams via decK url: shorthand
  from .env. LIVE-verified: both 401 unauth; /mcp/remote tools/list+tools/call returns market data;
  /mcp/remote-public proxies DeepWiki (protocol 2025-06-18, stateless) tools/list. **Phase 5 COMPLETE.**
- **2026-07-22** — Phase 6.1: MCP Registry. konnect/mcp-registry/ (create + 5 publish bodies) +
  registry-setup.sh (idempotent create → publish → discover). LIVE-verified against org: cai-mcp-registry
  created, all 5 servers published + discoverable. Found publish description ≤100 chars (NOTES.md).
- **2026-07-22** — Phase 6.2: scripts. demo.sh (7-step walkthrough), claude-code-setup.sh (5 mcp-add
  lines), preflight.sh, smoke-test.sh. LIVE: preflight 17/17, smoke 14/14, demo clean end-to-end.
- **2026-07-22** — Phase 6.3: README finalized (mermaid, walkthrough w/ expected outputs, troubleshooting,
  Known Issues); ARCHITECTURE.md reconciled to token-claim ACL + OPA argument rule + 5 registry servers;
  all NOTES.md doc-verify items closed. **Phase 6 COMPLETE — full 6-phase build done + live-verified.**
- **2026-07-22** — Konnect analytics dashboard: konnect/dashboards/cai-mcp-analytics.json (6 tiles —
  MCP volume, calls by server, top servers w/ error/denial rate, avg latency, tool usage, latency-by-tool;
  agentic_usage datasource) + scripts/install-dashboard.sh (POST /v2/dashboards, X-Konnect-Beta, CP looked
  up by name, tiles wrapped w/ preset_filters). LIVE-verified: created "Cox Automotive: Governed MCP"
  (id 388e3b28-…), GET returns 6 tiles; generated MCP traffic for the charts. Finding logged in NOTES.md.
- **2026-07-22** — **demo-ui cockpit** (spec `claude/specs/2026-07-22-demo-ui-design.md`, plan
  `claude/plans/2026-07-22-demo-ui-implementation.md`). Host-run Node/Express + vanilla-JS SPA, no
  build step: `demo-ui/` (server.js + config/keycloak/kong/registry/stack adapters + verdict.js +
  scenarios.js + public/{index,app,trace,styles}); launcher `scripts/ui.sh`. Three modes — Demo
  (7-step stepper), Explore (free sandbox), Stack (status + whitelisted SSE actions + Konnect
  dashboard deep-link). LIVE-verified against the running stack via Playwright: Step-1 (401/200/403),
  Step-4 exchange BEFORE/AFTER token panels, Explore OPA-deny (query_status=overdue), Stack preflight
  17/17 streamed. All 5 verdict signatures re-verified live through `/api/mcp` (NOTES.md demo-ui block);
  verdict.js unit test 7/7. Cox palette approximate (CSS-var swap). `.env` gained UI_PORT +
  KONNECT_DASHBOARD_ID (=388e3b28-2162-4d9a-9e17-579045130708 for this org).
- **2026-07-22** — **demo-ui containerized** (reverses U6 → DECISIONS U9). Added `demo-ui` as a Compose
  service (multi-stage `demo-ui/Dockerfile`, mirrors the aegis dashboard) so `docker compose up` runs
  the whole demo in one command; reaches Kong/Keycloak in-network (kong-dp:8000 / keycloak:8080),
  published host-local on 127.0.0.1:4000. `scripts/ui.sh` host-run RETAINED. Split by capability:
  Demo/Explore/Registry/Exchange identical in both modes; Stack **execute** actions are host-only
  (UI_IN_CONTAINER guard + UI note — a container mustn't tear down its own compose project); Stack
  **status** works in-container via read-only /var/run/docker.sock + `docker ps` (label-filtered).
  LIVE-verified: built --no-cache, up healthy, all 5 verdict signatures + exchange + registry(5) +
  status(6) correct through the container; Playwright confirmed the in-container Stack note renders.

## 2026-07-24 — Konnect Observability fixed + per-identity attribution
- Empty dashboards → `log_statistics: true` on ai-mcp-proxy (agentic_usage was never emitted).
- Serviceless-listener tiles re-keyed to `route` + `response_latency_average`.
- Per-identity attribution: proved dashboard `consumer` dim needs REAL consumers (credential_claim + consumer_groups_claim both empty; aegis confirms). Added 3 consumers (analytics-only; authz still the groups claim). **Verified live — consumer tile shows all three.** DECISIONS U12.

## 2026-07-27 — Step 3 exercises all three personas on MCP (consumer-tile fix)
- **Root cause:** the "Tool calls by consumer" tile is fed by MCP `agentic_usage` (only `/mcp/*`
  listener traffic, which carries `consumer_claim`/`consumer_by`). In the scripted 7-step story
  (demo.sh + demo-ui), **dana made only REST calls** (Step 1) and **frank's only MCP call was a
  403 ACL-deny** — so running the scenarios alone never surfaced dana (and made frank flaky) on the
  tile. U12's "all three verified" came from ad-hoc calls, not the scripted demo.
- **Fix:** Step 3 now runs `dana → list_dealer_customers @ /mcp/dealers` (ALLOW) and
  `frank → list_invoices @ /mcp/finance` (ALLOW) before the existing olivia-allow / frank-deny rows.
  All three personas now generate attributable MCP traffic from the scripted story; the ACL step also
  reads stronger (each persona CAN call its own group's tools, CANNOT call others'). Edits demo.sh +
  scenarios.js identically. Static-verified (ACL allow-lists, 16/16 demo-ui tests); live consumer-tile
  confirmation is the org-owner's UI check.

## 2026-07-24 — First-run setup orchestrator + RUNBOOK
- `scripts/setup.sh` — one-shot gated flow (preflight → ensure-env → bootstrap → up → wait-health →
  deck sync → wait-routes → opt-in add-ons → smoke). Flags: `--with-dashboard --with-registry --yes --force`.
- `konnect-bootstrap.sh` now auto-writes CP/TP endpoints into `.env` (portable, idempotent; `.env.bak` backup).
- `RUNBOOK.md` — standalone first-run guide (prereqs incl. Konnect entitlements → setup → verify → teardown).
- README points Quickstart at RUNBOOK; `scripts/tests/test-write-env.sh` covers the env writer.
