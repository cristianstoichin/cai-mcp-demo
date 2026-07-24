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

- **Phase 6 — registry + scripts + README.** MCP Registry live (cai-mcp-registry id
  e32046ce-ca93-4d02-aa40-eb9aa1eaca7b; 5 servers published/discoverable). Scripts: registry-setup,
  claude-code-setup, demo (7 steps), preflight (17/17), smoke-test (14/14). README finalized (mermaid,
  walkthrough, troubleshooting, Known Issues). ARCHITECTURE reconciled.

- **demo-ui cockpit — COMPLETE + LIVE-verified (Playwright), now ALSO a Compose service (U9).** Node/
  Express + vanilla-JS SPA, no build step. Two launch modes, both serve http://127.0.0.1:4000:
  (a) `docker compose up` — containerized `demo-ui` service, reaches Kong/Keycloak in-network; Stack
  execute actions host-only (status tiles still work via read-only docker.sock). (b) `scripts/ui.sh` —
  host-run, full Stack execute. Secrets server-side either way.
  Three modes: Demo (7-step stepper, hybrid trace + token BEFORE/AFTER on the exchange step), Explore
  (free persona/scope/endpoint/tool/args sandbox), Stack (compose status tiles + whitelisted SSE actions
  up/down/sync/preflight/smoke/registry-setup + Konnect dashboard deep-link). verdict.js classifier
  (7/7 unit test) maps all 5 live signatures; scenarios.js mirrors demo.sh. `.env` gained UI_PORT +
  KONNECT_DASHBOARD_ID (388e3b28-2162-4d9a-9e17-579045130708). Cox palette approximate (CSS-var swap).
- **demo-ui Overview + intuitiveness pass — SHIPPED + LIVE-verified (Playwright, 2026-07-24).** Added a
  4th mode **Overview** ("◉ Overview") as the **default landing** (U10): customer-facing personas +
  tool-permission matrix + the seven steps + verdict legend, rendered from `scenarios.js` (now the copy
  SSoT, U11) + new `public/content.js`. Demo mode rewritten (F1–F6): dead global persona buttons removed
  → per-call **identity badge**; human stepper labels (`railLabel`); `headline`+`proves` header;
  always-visible verdict legend; call rows lead with the honest per-call `verdictLabel` (never the raw
  classifier enum — U8 respected). New pure helpers in `public/trace.js` (identityBadge/verdictKind/
  verdictChip). Tests: `demo-ui/copy-and-render.test.js` (9) + verdict.js (7) = 16/16. Playwright live:
  all 7 Demo steps × 18 calls `got==expect`; Explore allow+deny; Stack tiles+dashboard; console clean
  (only benign favicon 404). Screenshots: `verify-overview.png`, `verify-demo-step1.png`.

## Not yet built
- **NOTHING core.** The 6-phase build + Konnect dashboard + demo-ui cockpit are COMPLETE and
  live-verified. Remaining is polish/handoff to Cox: run against their org (bootstrap → sync →
  registry-setup on a Labs-enabled US org), confirm exact Cox palette hex (one-line CSS-var swap in
  `demo-ui/public/styles.css`), and any demo-day narration tweaks.

## Key gotchas (see NOTES.md)
- Token exchange: request SCOPES not audience (Keycloak audience param must name a client); subject token
  must carry kong-exchange in aud (mcp:use scope provides it).
- claim_to_header base64-encodes ARRAY claims (groups → base64 JSON); rego json.unmarshal(base64.decode()).
- DeepWiki is stateless (no mcp-session-id); market-mcp is session-based. Passthrough handles both.
- OPA input body is at input.request.http.parsed_body (needs include_parsed_json_body_in_opa_input:true).
- Keycloak issuer pinned to keycloak:8080. Re-import realm edits via `up -d --force-recreate keycloak` (H2).
