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
