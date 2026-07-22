# state.md — what's working (overwrite in place)

_Updated 2026-07-22 (through Phase 5, LIVE-verified against org)._

## Working (live against Konnect CP cai-mcp-demo / 007f4c01…)
- Stack UP: kong-dp (connected), keycloak, dealer-svc, finance-svc, opa, market-mcp.
- konnect-bootstrap.sh: created CP + pinned self-signed PKI DP cert; endpoints in .env; certs/ present.
- OIDC gates on REST routes: no-token 401 / dana 200 / dana->finance 403 (scope+aud).
- MCP conversion: tools/list = dealers 2, finance 2, ops 2-bundled (tag aggregation). tools/call round-trips
  (query_<name> arg namespacing; forward_client_headers).
- Aegis-style token-claim ACL (acl_attribute_type: oauth_access_token, access_token_claim_field: groups):
  allow/deny matrix correct on all three listeners.
- ai-mcp-oauth2 JWKS on dealers/finance; identity via claim_to_header X-User-Id/Name (no Kong consumers).
- **Phase 5.1 — /mcp/ops introspection + RFC 8693 token exchange (kong-exchange).** mcp:use-only token
  reaches dealer+finance tools on /mcp/ops (exchange adds dealer-api/finance-api aud) but 403s on
  /mcp/dealers (no exchange). Exchange requests SCOPES only (Keycloak audience param = a client). ACL
  enforces on the exchanged token's groups claim.
- **Phase 5.2 — OPA on /mcp/ops.** opa/policies/mcp.rego (default allow; entitlement rule; argument-level
  rule denying list_invoices?query_status=overdue; commented business-hours). opa plugin
  (include_parsed_json_body_in_opa_input) + claim_to_header groups→X-User-Groups. OPA runs `-w` (hot-reload).
  Live: overdue → 403, others → 200; hot-reload flip works with no deck sync. Input doc-verified by observation.
- **Phase 5.3 — passthrough remotes.** /mcp/remote → market-mcp (own), /mcp/remote-public → DeepWiki
  (third-party, protocol 2025-06-18, stateless). ai-mcp-proxy passthrough-listener; ai-mcp-oauth2 gate;
  passthrough_credentials:false. Both 401 unauth; authed tools/list + market-mcp tools/call work.

## Not yet built
- Phase 6: registry-setup.sh (klabs host) + konnect/mcp-registry/*.json bodies; claude-code-setup.sh;
  demo.sh; preflight.sh; smoke-test.sh; README finalize (quickstart + walkthrough + mermaid + Known Issues).

## Key gotchas (see NOTES.md)
- Token exchange: request SCOPES not audience (Keycloak audience param must name a client); subject token
  must carry kong-exchange in aud (mcp:use scope provides it).
- claim_to_header base64-encodes ARRAY claims (groups → base64 JSON); rego json.unmarshal(base64.decode()).
- DeepWiki is stateless (no mcp-session-id); market-mcp is session-based. Passthrough handles both.
- OPA input body is at input.request.http.parsed_body (needs include_parsed_json_body_in_opa_input:true).
- Keycloak issuer pinned to keycloak:8080. Re-import realm edits via `up -d --force-recreate keycloak` (H2).
