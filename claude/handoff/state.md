# state.md — what's working (overwrite in place)

_Updated 2026-07-22 (Phase 1)._

## Working
- `docker compose up -d keycloak dealer-svc finance-svc` — all three healthy.
- Keycloak `cox-auto` realm imports clean; discovery at `http://localhost:8080/realms/cox-auto`.
- `get-token.sh dana|frank|olivia` mints tokens with correct `sub`, `preferred_username`,
  `groups`, per-persona `scope`, and audience differentiation (dana→dealer-api, frank→finance-api,
  olivia→both; all have mcp-* + kong-exchange).
- dealer-svc: `/customers`(region filter), `/vehicles`(price_rank filter), `/health`.
- finance-svc: `/invoices`(status filter), `/floorplans`(due-soon/ok), `/health`.

## Not yet built
- Phase 2: konnect-bootstrap.sh, kong-dp DP env, kong/konnect.yaml (services/routes/OIDC), deck sync.
- Phase 3: ai-mcp-proxy conversion-only + listener.
- Phase 4: ai-mcp-oauth2 + consumers/groups + ACLs.
- Phase 5: token exchange + OPA + market-mcp + passthrough remotes.
- Phase 6: registry-setup.sh, claude-code-setup.sh, demo.sh, README finalize.
