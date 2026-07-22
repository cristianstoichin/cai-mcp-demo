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
