# known-issues.md

- Host port squatter can shadow `127.0.0.1:3001` (etc.) over Docker's bind for localhost curls.
  Real traffic uses Kong :8000; override `DEALER_SVC_PORT`/`FINANCE_SVC_PORT`/`MARKET_MCP_PORT` in `.env`.
  Verify contended services in-network: `docker compose exec finance-svc node -e "..."`.
- Keycloak dev mode uses ephemeral H2 (no volume): `--import-realm` only re-imports on a fresh
  container. To re-apply realm edits: `docker compose up -d --force-recreate keycloak`.
- Keycloak built-in `basic`/`profile` scopes aren't reliably linked on import when `defaultClientScopes`
  is set explicitly — we use a self-owned `identity` scope for `sub`+`preferred_username`. See NOTES.md.
- `ai-mcp-oauth2` + MCP Registry are tech preview (AI Gateway Enterprise / Konnect Labs, US-only registry).
