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
- ✅ **RESOLVED (Phase 5, live):** Cross-audience issuance via standard exchange works — but NOT via the
  RFC 8693 `audience` request param. In Keycloak, the exchange `audience` param must name a **registered
  client** by clientId; `dealer-api`/`finance-api` are audience *strings* (from scope mappers), not
  clients, so passing `audience=dealer-api` returns `invalid_client / "Audience not found"`. Instead,
  request the **scopes** (`scope=dealers:read finance:read`): their `oidc-audience-mapper`s add
  `aud:[dealer-api,finance-api]` to the exchanged token, and `groups` is retained (default scope) for the
  listener ACL. So `ai-mcp-oauth2.token_exchange.request` sets `scopes` only, NO `audience`. The design
  §4.2 fallback (exchange on all three listeners) was NOT needed — exchange stays on `/mcp/ops` alone.

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

## Build findings (Phase 3) — all verified LIVE against the org
- ✅ **Tag aggregation works**: `config.server.tag` on a `listener` aggregates conversion-only tools by
  the plugin's **entity** `tags`. `/mcp/dealers`→2 (dealer-tools), `/mcp/finance`→2 (finance-tools),
  `/mcp/ops`→2 (bundle-tools = list_dealer_customers + list_invoices). Exactly as designed.
- 🔧 **Query params are namespaced `query_<name>`** in the generated MCP `inputSchema` (path→`path_`,
  etc.), and the schema is `additionalProperties:false`. So a `tools/call` argument is `query_region`,
  NOT `region`. demo.sh + docs must use the prefixed names. Verified via tools/list inputSchema.
- ✅ **Listener forwards the client bearer** (`forward_client_headers` default true) to the inner
  conversion route. So `tools/call` with a token whose audience+scope satisfy the inner OIDC gate
  returns upstream data directly; without a token the inner gate returns 401 (surfaced as MCP
  `HTTP call failed with status 401`). Implication: **token exchange is only required when the MCP
  token lacks the API audiences** (e.g. an mcp-ops-only token). dana/olivia tokens (which carry
  dealer-api/finance-api via the requested scopes) work by direct forwarding. Confirm the exchange
  path in Phase 5 with an mcp:use-only token.
- ✅ **Serviceless listener routes** (top-level `routes:` with no service) sync + function fine.

## Open doc-verify items (do before wiring the relevant task)
- [ ] Konnect control-plane create + DP client-cert (PKI/pinned) generate/upload API — for konnect-bootstrap.sh (Task 2.1)
- [ ] openid-connect bearer-only + scopes_required + audience field names (Task 2.3)
- [x] opa plugin: exact `input` document Kong sends (Task 5.2) — doc-verified by observation, see below
- [ ] passthrough-listener config fields + DeepWiki live protocol version ≥ 2025-06-18 (Task 5.3)

## Build findings (Phase 5.1 — introspection + token exchange on /mcp/ops) — verified LIVE
- ✅ **Introspection + token_exchange on one `ai-mcp-oauth2` instance works.** `/mcp/ops` sets
  `introspection_endpoint` (Keycloak `/protocol/openid-connect/token/introspect`) + `client_id`/
  `client_secret` (kong-exchange, `client_auth: client_secret_post`); `token_exchange.client_auth:
  inherit` reuses those creds. Introspection validation still surfaces `sub`/`preferred_username`/`groups`
  for `claim_to_header` and the listener's `access_token_claim_field: groups` ACL.
- 🔧 **Keycloak token-exchange `audience` param = a registered CLIENT, not an audience string** — see the
  RESOLVED note above. `token_exchange.request` carries `scopes: [dealers:read, finance:read]` only.
- ✅ **The exchange is the story direct-forwarding can't tell.** An `mcp:use`-only token (aud=[mcp-*,
  kong-exchange], NO dealer-api/finance-api) 403s the inner OIDC gate on `/mcp/dealers` (no exchange) but
  SUCCEEDS on `/mcp/ops`: Kong exchanges it → aud=[dealer-api,finance-api] + dealers:read/finance:read,
  forwarded via `passthrough_credentials`. Live matrix: olivia mcp:use-only → dealer+finance tools OK on
  /mcp/ops, 403 on /mcp/dealers; frank mcp:use-only → dealer tool ACL-DENY (exchanged token keeps
  groups=[finance]), finance tool OK. Kong log `[ai-mcp-oauth2] exchanging access token` on each ops call.
- ⚠️ **Subject token MUST carry `kong-exchange` in `aud`** or the exchange fails `invalid_client`. The
  `mcp:use` scope's `aud-kong-exchange` mapper (`included.client.audience: kong-exchange`) provides it, so
  every persona token that requested `mcp:use` is exchangeable. (client-audience mapper, not custom-audience.)
- 🔧 **Exchange client creds reach decK via compose env**, never hardcoded: `docker-compose.yaml` deck
  service exports `DECK_KONG_EXCHANGE_CLIENT_ID`(=kong-exchange) + `DECK_KONG_EXCHANGE_SECRET`(from .env);
  `kong/konnect.yaml` reads them with `${{ env "..." }}`. client_id is a fixed realm artifact like the
  `keycloak:8080` issuer; only the secret is sensitive.

## Build findings (Phase 5.2 — OPA on /mcp/ops) — input doc-verified BY OBSERVATION, verified LIVE
- ✅ **Exact OPA input document Kong 3.14 sends** (captured via OPA `decision_logs.console=true`, not
  guessed). Query path `POST /v1/data/mcp/allow`, decision reads the boolean at `data.mcp.allow`:
  ```
  input.request.http.method            "POST"
  input.request.http.path              "/mcp/ops"
  input.request.http.headers           { lower-cased keys: authorization, x-user-id, x-user-name,
                                         x-user-groups, content-type, ... }
  input.request.http.parsed_body       { jsonrpc, method:"tools/call", params:{name, arguments} }
  input.request.http.querystring/scheme/host/port/tls, input.client_ip
  ```
  Body is at `input.request.http.parsed_body` (present only with `include_parsed_json_body_in_opa_input:
  true`) — NOT `input.request.body`. So the rego reads `params.name` (tool) + `params.arguments` there.
- 🔧 **`claim_to_header` base64-encodes a NON-scalar claim.** `sub`/`preferred_username` (strings) forward
  as plain `x-user-id`/`x-user-name`; the `groups` ARRAY forwards as **base64-encoded JSON**:
  `["ops"]` → `x-user-groups: WyJvcHMiXQ==`. The rego must `json.unmarshal(base64.decode(header))` — a
  comma-split silently mis-parses and denies everyone (observed: OPA returned `result:false` for ops until
  fixed). This is a genuine trap; verified by the decision log.
- ✅ **OPA sees the EXCHANGED bearer** in `authorization` (azp=kong-exchange, aud=[dealer-api,finance-api],
  groups retained) — the opa plugin runs AFTER ai-mcp-oauth2's exchange. So `claim_to_header groups` and
  the exchanged token agree on the caller's groups.
- ✅ **OPA-decides case that the tool ACL cannot express:** Rule 2 denies `list_invoices` when arg
  `query_status=overdue` — the ACL is tool-grained, only OPA sees call arguments. Live: olivia
  list_invoices → 200, `+query_status=overdue` → **403 `{"message":"unauthorized"}`**, list_dealer_customers
  → 200. (Query args are namespaced `query_<name>` — Phase-3 finding — so the rego checks `query_status`.)
- ✅ **Hot-reload proven:** OPA runs `run --server -w ./policies`; editing `mcp.rego` (appending a deny for
  list_dealer_customers) flipped the live result to 403 with NO deck sync ("Processed file watch event" in
  the OPA log), reverted back to 200 on undo. This is the OPA value prop — policy iterates without touching
  Kong.
- ⚠️ **Rule 1 (finance/ops-only for list_invoices) is shadowed by the tool ACL on /mcp/ops** (ACL
  `allow:[finance,ops]` denies a dealers-only caller before OPA runs), so it's verified OFFLINE via
  `opa eval` against the observed input, not live. It stays as the "same entitlement, externalized" teaching
  point; Rule 2 is the live OPA-is-the-decider proof.

## Build findings (Phase 4) — aegis-style ACL, verified LIVE
- ✅ **Switched to aegis scope/claim ACL** (reverses D4, at Paul's request). `ai-mcp-proxy` **listener**
  carries `acl_attribute_type: oauth_access_token` + `access_token_claim_field: groups`; per-tool
  `acl.allow/deny` (bare group names) stay on the conversion-only tools; the listener enforces at
  `tools/call`. No Kong consumers/consumer_groups. `acl_attribute_type`/`access_token_claim_field`
  must be on the LISTENER, not conversion-only (per reference).
- ✅ `ai-mcp-oauth2` still validates the token (JWKS) + maps identity to `X-User-Id`/`X-User-Name`
  via `claim_to_header` even with `consumer_optional: true` and no consumers defined (identity headers
  are independent of consumer mapping). `insecure_relaxed_audience_validation: true` +
  `passthrough_credentials: true` remain (listener relaxes RFC-8707 resource-audience; inner OIDC
  enforces scope+audience on the forwarded token).
- ✅ **Live matrix**: dana→dealer OK; frank→finance OK; olivia(ops)→list_floorplans DENY (allow:[finance]);
  frank→dealer tool DENY (allow:[dealers,ops]); olivia→list_invoices OK. `[ai-mcp-proxy] MCP ACL: denying`
  logged on denials. tools/list is NOT ACL-filtered — enforcement is at call time.
