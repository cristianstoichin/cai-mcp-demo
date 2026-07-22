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
