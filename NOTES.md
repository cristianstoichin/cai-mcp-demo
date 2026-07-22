# NOTES.md — doc-vs-reality log

Records where official docs (developer.konghq.com, keycloak.org) differed from
assumptions or from the `aegis-insurance-ai-gateway-demo` reference, plus verified
schema facts the AI-MCP plugins depend on (these change fast — re-verify per release).

Legend: ✅ verified against current docs · ⚠️ provisional / verify live · 🔧 discrepancy corrected

---

## Verified schema facts (2026-07-22)

### ai-mcp-proxy (developer.konghq.com/plugins/ai-mcp-proxy/reference/) ✅
- `config.mode`: `conversion-only` | `listener` | `passthrough-listener` | `conversion-listener`.
- **conversion-only** `config.tools[]`: `description` (required), `name`, `parameters` (OpenAPI param objects),
  `path`/`method`/`scheme`/`host`/`headers`/`query`, `request_body`/`responses`, `annotations`,
  `acl.{allow[],deny[]}` (deny wins).
- **listener** `config.server`: `tag` ("used to filter the exported MCP tools"), `timeout`,
  `forward_client_headers`, `session`.
- `config.include_consumer_groups` (bool): lets ACL `allow/deny` reference consumer **group** names.
- `config.logging`: `log_audits`, `log_statistics`, `log_payloads`.
- 🔧 **Tag mechanism**: there is NO tag field inside `config`. Tag filtering uses the Kong **entity**
  `tags:` array (sibling of `name:`/`config:` on the plugin) — the listener's `config.server.tag`
  aggregates conversion-only plugin instances that carry that entity tag. So set
  `tags: [dealer-tools, bundle-tools]` at the plugin entity level, `config.server.tag: dealer-tools`
  on the listener. (Spec's "plugin-level tags" = decK entity tags.)

### ai-mcp-oauth2 (developer.konghq.com/plugins/ai-mcp-oauth2/reference/) ✅
- Required: `authorization_servers[]` (client-facing AS id), `resource`.
- Discovery: `metadata_endpoint` (default `$resource/.well-known/oauth-protected-resource`),
  `metadata_discovery_endpoint` (ends with `/.well-known/openid-configuration` or `/.well-known/oauth-authorization-server`).
- Validation mode: set `jwks_endpoint` for JWKS validation (auto-discovered if omitted); set
  `introspection_endpoint` to force introspection (required for opaque tokens). Keycloak issues JWTs,
  so `/mcp/dealers` + `/mcp/finance` use JWKS (omit introspection_endpoint), `/mcp/ops` sets
  `introspection_endpoint` to demo introspection.
- `client_id`/`client_secret`/`client_auth` (`client_secret_basic|client_secret_post|...`).
- `consumer_claim[]`, `consumer_by[]` (`custom_id|id|username`), `consumer_optional`,
  `consumer_groups_claim[]`, `consumer_groups_optional`.
- `claim_to_header[]` = array of `{claim, header}` objects (mutually exclusive with `upstream_headers`).
- `passthrough_credentials` (bool).
- `token_exchange`: `enabled`, `token_endpoint` (required), `client_auth` (`inherit` reuses
  introspection client creds), `request.audience[]`, `request.scopes[]`.

### Keycloak 26 standard token exchange (keycloak.org/securing-apps/token-exchange) ✅
- Standard Token Exchange **V2 is default-on** in KC 26 — no `--features` startup flag (that was legacy V1).
- Enabled per requesting client via client attribute **`"standard.token.exchange.enabled": "true"`**
  in the client's `attributes` block of the realm export.
- ⚠️ **Requirement that shapes the realm**: the subject token presented to the exchange endpoint MUST
  carry the requesting client (`kong-exchange`) in its `aud`. Therefore the `mcp:use` audience mapper
  must include `kong-exchange` alongside `mcp-ops` — otherwise the `/mcp/ops` exchange fails. Encoded a
  dedicated audience mapper for `kong-exchange` on the `mcp:use` scope.
- ⚠️ Cross-audience (`audience=dealer-api|finance-api`) issuance via standard exchange to be confirmed
  live in Phase 5; fallback documented in design §4.2 (enable token_exchange on all three listeners).

## Discrepancies from the aegis reference
- 🔧 **MCP Registry host**: aegis `setup-mcp-registry.sh` uses `https://klabs.us.api.konghq.com/v0/mcp-registries`
  (NOT the aegis README's stale `us.api.konghq.com/v2`). Paths: create `POST /v0/mcp-registries`,
  publish `POST /{id}/v0.1/publish`, discover `GET /{id}/v0.1/servers`. US region only; Labs tech preview.

## Build findings (Phase 1)
- 🔧 **Keycloak built-in scopes not reliably linked on realm import.** Setting an explicit
  `defaultClientScopes` list on a client detaches the built-in `basic`/`profile` scopes, so
  `sub` and `preferred_username` never appeared in access tokens and requesting `scope=profile`
  failed (`invalid_scope`). Fix: a **self-owned `identity` client scope** (mappers
  `oidc-sub-mapper` + `oidc-usermodel-property-mapper` for username) assigned as a default scope
  to every client. Guarantees `sub` + `preferred_username` independent of built-in-scope import
  behavior. ai-mcp-oauth2 `consumer_claim:[preferred_username]` + `claim_to_header:sub` depend on this.
- ⚠️ **Phase-1 "reject bad scopes" is a Phase-2 gate.** Keycloak alone does not 403 on scope; it
  just omits the audience for unrequested scopes (verified: dana without `finance:read` has no
  `finance-api` aud). Scope enforcement/403 happens at the Kong `openid-connect` gate (Phase 2).
- 🔧 **Host port collisions.** A stray local dev process can squat `127.0.0.1:3001` and win over
  Docker's `0.0.0.0:3001` for localhost, so host curls miss the container. Host debug ports are now
  `.env`-overridable (`DEALER_SVC_PORT`/`FINANCE_SVC_PORT`/`MARKET_MCP_PORT`); real traffic uses Kong
  :8000 regardless. Verify services in-network (`docker compose exec <peer> node -e ...`) when a host
  port is contended.

## Build findings (Phase 2)
- ✅ **openid-connect bearer-only fields** (developer.konghq.com/plugins/openid-connect/reference/):
  `issuer`, `auth_methods:[bearer]`, `scopes_claim:[scope]`(default), `scopes_required[]`,
  `audience_claim:[aud]`(default), `audience_required[]`, `disable_session:[bearer]`.
- 🔧 **Issuer must be identical + reachable from host AND the Kong DP.** Host mints tokens via
  `localhost:8080`; the DP validates via the docker network (`keycloak:8080`). If Keycloak's issuer
  floats with the request host, host-minted tokens (`iss=localhost:8080`) fail the DP's JWKS/issuer
  check → 401. Fix: **pin `KC_HOSTNAME: http://keycloak:8080`** + `KC_HOSTNAME_STRICT:false`.
  Verified: discovery issuer = `http://keycloak:8080/realms/cox-auto` from both host and network;
  host backchannel minting still works; minted `iss` matches. So `openid-connect.issuer` and
  `ai-mcp-oauth2.authorization_servers` both use `http://keycloak:8080/realms/cox-auto`.
  Caveat: client-facing protected-resource metadata will advertise `keycloak:8080` (not host-resolvable)
  — only matters for the interactive Claude Code browser OAuth (Phase 6); curl-with-bearer is unaffected.
- ✅ **Konnect CP + DP-cert API** (Control Planes API v2 via kong-konnect MCP): create
  `POST /v2/control-planes {name, cluster_type:"CLUSTER_TYPE_CONTROL_PLANE", auth_type:"pki_client_certs"}`;
  response `result.config.{control_plane_endpoint,telemetry_endpoint}`; pin DP cert
  `POST /v2/control-planes/{id}/dp-client-certificates {cert,title}`. A self-signed cert works in PKI
  mode (self-issued trust anchor) — the standard Kong hybrid approach. `list_control_planes` supports
  `filter[name][eq]` for idempotent find-or-create.
- **Routing choice:** REST routes use `strip_path:false` and the mock services own their real API paths
  (`/api/dealers/*`, `/api/finance/*`) → 1:1 route→upstream mapping, no rewrite needed. Two services,
  four routes per spec.
- **decK scope:** no `select_tags` — the demo runs on a **dedicated** control plane (bootstrap creates
  `cai-mcp-demo`), so `deck gateway sync` manages the whole CP. Functional entity `tags` on ai-mcp-proxy
  plugins (dealer-tools/finance-tools/bundle-tools) remain, for `server.tag` aggregation.

## Open doc-verify items (do before wiring the relevant task)
- [ ] Konnect control-plane create + DP client-cert (PKI/pinned) generate/upload API — for konnect-bootstrap.sh (Task 2.1)
- [ ] openid-connect bearer-only + scopes_required + audience field names (Task 2.3)
- [ ] opa plugin: exact `input` document Kong sends (Task 5.2)
- [ ] passthrough-listener config fields + DeepWiki live protocol version ≥ 2025-06-18 (Task 5.3)
