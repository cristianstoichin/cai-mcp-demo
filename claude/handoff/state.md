# state.md — what's working (overwrite in place)

_Updated 2026-07-22 (through Phase 4, LIVE-verified against org)._

## Working (live against Konnect CP cai-mcp-demo / 007f4c01…)
- Stack UP: kong-dp (connected to Konnect), keycloak, dealer-svc, finance-svc.
- konnect-bootstrap.sh: created CP + pinned self-signed PKI DP cert; endpoints in .env; certs/ present.
- OIDC gates on REST routes: no-token 401 / dana 200 / dana->finance 403 (scope+aud).
- MCP: tools/list = dealers 2, finance 2, ops 2-bundled (tag aggregation).
- tools/call round-trips to upstream (query_<name> arg namespacing; forward_client_headers).
- Aegis-style token-claim ACL (acl_attribute_type: oauth_access_token, access_token_claim_field: groups):
  olivia(ops)->list_floorplans DENY; frank->dealer tools DENY; allowed calls return data.
- ai-mcp-oauth2: JWKS, insecure_relaxed_audience_validation, passthrough_credentials, claim_to_header
  X-User-Id/Name (forwarded to upstream, verified). No Kong consumers.

## Not yet built
- Phase 5: /mcp/ops introspection + token_exchange; opa + opa/policies/mcp.rego; market-mcp;
  /mcp/remote + /mcp/remote-public passthrough routes.
- Phase 6: registry-setup.sh, claude-code-setup.sh, demo.sh, README finalize.

## Key gotchas (see NOTES.md)
- Keycloak issuer pinned to keycloak:8080 (host+DP agreement). Re-import realm edits via
  `docker compose up -d --force-recreate keycloak` (ephemeral H2).
- Host debug ports .env-overridable (3001 squatter). Verify contended svc in-network.
- ai-mcp-oauth2 enforces RFC-8707 resource-aud unless insecure_relaxed_audience_validation:true.
