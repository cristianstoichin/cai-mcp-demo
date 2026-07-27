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

## Build findings (Konnect dashboard) — verified LIVE against org
- ✅ **Upload = `POST /v2/dashboards` with header `X-Konnect-Beta: true`.** Envelope:
  `{name, labels, definition:{preset_filters:[{field:control_plane,operator:in,value:[<cp_id>]}], tiles[]}}`.
  Strip each tile's `id` before POST (Konnect assigns them). Created "Cox Automotive: Governed MCP"
  (id 388e3b28-…) live; GET returns all 6 tiles. Mirrors aegis `konnect/dashboards/mcp-analytics.json`.
- ✅ **MCP tile schema**: `definition.chart.{type,chart_title}` + `definition.query.{datasource, metrics[],
  dimensions[], filters[], limit?}`. Chart types used: `single_value`, `donut`, `top_n`, `horizontal_bar`,
  `timeseries_line`. Datasource **`agentic_usage`**; dimensions `mcp_tool_name` / `gateway_service`; metrics
  `request_count`, `response_latency_average`, `upstream_latency_average`, `error_rate` (error_rate = the
  governance-denial signal). Charts populate only after MCP traffic flows + Konnect ingests it (short delay).
- ⚠️ Advanced Analytics + the `agentic_usage` datasource are org-tier/region dependent; the beta dashboards
  API needs the `X-Konnect-Beta` header. Script prints a helpful message on failure.

## Build findings (Phase 6.1 — MCP Registry) — verified LIVE against org
- ✅ Registry create/publish/discover paths confirmed live: `POST /v0/mcp-registries` (create body
  `{name, display_name, description}`), `POST /{id}/v0.1/publish` (server manifest), `GET /{id}/v0.1/servers`
  (discovery). Created `cai-mcp-registry` and published+discovered all 5 servers.
- 🔧 **Publish `description` is capped at 100 chars** — a longer one 400s with
  `{field:description, rule:max_length, maximum:100}`. All 5 publish bodies trimmed to ≤100. (Title/name
  had no issue at our lengths.) Server manifest shape that works: `{name (reverse-DNS, e.g.
  com.cox-automotive/dealer-mcp), title, description(≤100), version, remotes:[{type:"streamable-http", url}]}`.
- ✅ Registry entries advertise the canonical `http://localhost:8000/mcp/*` (per the hard rule) — the URL a
  host-side client (Claude Code) connects to. Registry id is written to `.env` as `KONNECT_MCP_REGISTRY_ID`.
- 🔧 **5 servers, not 4** — published dealers/finance/ops/remote AND remote-public (the plan's Task 6.1 text
  said 4 but the File-Structure note said "3 gateway + 2 remote" = 5; the complete set is more faithful and
  the third-party DeepWiki entry is a good "governed remote" story). registry-setup.sh publishes all 5.

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
- [x] Konnect control-plane create + DP client-cert (PKI/pinned) generate/upload API (Task 2.1) — verified (Phase 2)
- [x] openid-connect bearer-only + scopes_required + audience field names (Task 2.3) — verified (Phase 2)
- [x] opa plugin: exact `input` document Kong sends (Task 5.2) — doc-verified by observation, see below
- [x] passthrough-listener config fields + DeepWiki live protocol version ≥ 2025-06-18 (Task 5.3) — verified, see below

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

## Build findings (Phase 5.3 — passthrough-listener remotes) — verified LIVE
- ✅ **passthrough-listener upstream = the Kong SERVICE the route is attached to** (NOT a plugin config
  field). Both remote routes hang off a service whose `url:` (decK shorthand) expands to
  protocol/host/port/path — `remote-market-mcp-service` → `${REMOTE_MCP_URL}` (http://market-mcp:3000/mcp),
  `remote-public-mcp-service` → `${REMOTE_PUBLIC_MCP_URL}` (https://mcp.deepwiki.com/mcp). `strip_path:true`
  so `/mcp/remote[-public]` → the service's own `/mcp` path. Mirrors the aegis policy-mcp/claims wiring.
- ✅ `tools[]` is OPTIONAL in passthrough-listener (only needed for per-tool ACL matching). We omit it →
  transparent proxy of ALL upstream tools. `server` config is ignored in passthrough (state lives on the
  upstream MCP server, per reference). Kept `logging.log_audits` + `request/response_buffering:false` (SSE).
- ✅ **ai-mcp-oauth2 fronts both remotes as a pure auth gate** (JWKS, `insecure_relaxed_audience_validation`,
  `consumer_optional`). `passthrough_credentials: false` — Kong validates the cox-auto token and does NOT
  forward it to the remote MCP (don't leak an internal token to a third party you're governing). Live: both
  routes 401 unauth; a valid `mcp:use` token proxies through. This is the "govern a remote MCP" story.
- ✅ **DeepWiki (third-party) live protocol = `2025-06-18`** (serverInfo DeepWiki 2.14.3), meets the
  ≥2025-06-18 bar. Tools: `ask_question`, `read_wiki_contents`, `read_wiki_structure`.
- 🔧 **DeepWiki is STATELESS** — it returns NO `mcp-session-id` header (direct OR through Kong), so a
  session-less `tools/list` works. market-mcp (session-based, aegis pattern) DOES return `mcp-session-id`
  and needs the init→notifications/initialized→session handshake. Passthrough handles both models; demo
  clients must not assume every remote issues a session id.
- ✅ **market-mcp**: plain-ESM Node (no tsc) `@modelcontextprotocol/sdk` StreamableHTTPServerTransport at
  `/mcp`, tools `market_price_check` + `days_supply_lookup`, `/health` for the container check. Live via
  Kong: tools/list + `tools/call market_price_check {make:Ford,model:F-150}` returns the market band.

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

## Build findings (demo-ui) — verdict signatures re-verified LIVE
- ✅ All 5 verdict signatures reproduced through the demo-ui server (`POST /api/mcp`) against the
  running stack, and `verdict.js classify()` matches every one:
  - `401` + `{"message":"Unauthorized"}`  → **auth-fail** (ai-mcp-oauth2 gate; no/invalid token).
  - `403` (body ≠ `{"message":"unauthorized"}`)  → **acl-deny**. Verified live there are TWO body
    shapes for this: the **REST OIDC** scope/aud gate returns JSON `{"message":"Forbidden"}` (Step 1),
    while the **MCP tool ACL** deny returns raw HTML `<html>…403 Forbidden…</html>` (Step 3). The
    classifier keys off "403 that is NOT `{"message":"unauthorized"}`", so both shapes classify as
    acl-deny; only OPA's `{"message":"unauthorized"}` is special-cased. (The spec table's "HTML body"
    was right for the MCP ACL; the REST gate is JSON.)
  - `403` + `{"message":"unauthorized"}`  → **opa-deny** (external OPA policy).
  - `200` + JSON-RPC `isError:true`, text `HTTP call failed with status 403`  → **inner-gate-deny**
    (the token lacks the API audience; the case token-exchange fixes on /mcp/ops). MUST read the body,
    not the status.
  - `200` + `result.content`/`result.tools`  → **allow**.
- 🔧 Two distinct 403 body shapes (both → acl-deny, verified via Playwright): REST OIDC gate = JSON
  `{"message":"Forbidden"}`; MCP tool-ACL = raw HTML `403 Forbidden`. The classifier is shape-agnostic
  (any 403 that isn't OPA's `{"message":"unauthorized"}`), so no code change needed. (Supersedes an
  earlier draft note that claimed the ACL body was only JSON.)
- ✅ Exchange BEFORE/AFTER reproduced out-of-band (`/api/exchange-preview`, U7): mcp:use-only token
  aud=[mcp-finance,mcp-ops,kong-exchange,mcp-dealers] → after aud=[dealer-api,finance-api],
  scope=dealers:read finance:read, groups=[ops] retained, azp flips demo-cli→kong-exchange.
- ✅ Stack SSE stream verified live (preflight 17/17 streamed to the browser terminal); ANSI color
  codes are stripped server-side in stack.js so the browser terminal shows clean text.

## Build findings (demo-ui) — Overview + intuitiveness pass (2026-07-24), re-verified LIVE
- 🔑 **Two separate concerns, deliberately (U11 vs U8).** The customer-facing **verdict label** is now
  per-call data (`scenarios.js verdictLabel`) — e.g. Step-1 call-3 reads "403 · REST scope/audience
  gate", Step-3 call-2 reads "403 · tool ACL — group not allowed". The **classifier** (`verdict.js`) is
  UNCHANGED and still coarse (both of those are `acl-deny` by signature — the two 403 body shapes above
  are indistinguishable). The label is what a human reads; the enum is only used for the live-match
  check. Never surface the raw enum to the customer.
- ✅ **Playwright live verification (fresh `--no-cache` demo-ui image).** Overview is the default route
  and renders personas + the 4-tool matrix (✓/✕ matches `konnect.yaml` allow-lists exactly) + 7 steps +
  legend, customer-safe (no internal callouts). Demo has **zero** persona buttons (F1); every call shows
  the right identity badge (Step-1 call-1 = "no token", not a persona). All **7 Demo steps × 18 calls
  returned `got == expect`** live (trust chip "✓ matches expected · live call" on every row); trace
  present on every call; Step-4 shows token BEFORE/AFTER. Explore allow+deny correct; Stack tiles +
  dashboard link resolve. Console clean except a benign `favicon.ico` 404. Screenshots: `verify-overview.png`,
  `verify-demo-step1.png`.

## Doc-vs-reality (2026-07-24) — empty Konnect Observability dashboards → missing log_statistics
- **Symptom:** the "Governed MCP" analytics dashboard (id 388e3b28…) showed nothing, despite live
  traffic, config synced, and the DP's analytics **reqlog** telemetry websocket connected
  (`wss://…tp.konghq.com:443/v1/analytics/reqlog` — verified in `docker compose logs kong-dp`).
- **Root cause:** every tile in `konnect/dashboards/cai-mcp-analytics.json` uses the **`agentic_usage`**
  datasource (Kong MCP analytics), which is only populated when the `ai-mcp-proxy` plugin logs
  statistics. Our plugins had `logging: { log_audits: true }` **only** — no `log_statistics`. So Kong
  emitted zero agentic records; the datasource stayed empty regardless of traffic. Confirmed by diff vs
  the aegis reference (`kong/deck.yaml`: every ai-mcp-proxy has `logging.log_statistics: true`) and
  aegis `konnect/README.md:102` ("`agentic_usage` … requires … `log_statistics: true`").
- **Fix:** add `log_statistics: true` to all 9 `ai-mcp-proxy` `logging:` blocks; `deck gateway sync`
  (accepted — Updated 13). Kept **statistics only**, NOT `log_payloads` (that ships request/response
  bodies — customer/invoice data — to analytics; unnecessary for these tiles + a PII footgun).
- **agentic_usage feeds off MCP tool CALLS** (`tools/call`, populates `mcp_tool_name`) — REST calls and
  `tools/list` don't fill the tool-name tiles. Ingest lag ~1–5 min; verify in the Konnect dashboard UI
  (deep-link from Stack mode), not via API (the agentic query endpoint isn't publicly exposed — all
  `/vN/analytics/explore` probes 404).
- **Open items to confirm in the UI:** (a) whether the org/region has the Advanced-Analytics
  entitlement for `agentic_usage` (if still empty after ingest, this is the next suspect); (b) the
  `gateway_service` dimension may be sparse for the serviceless listener routes; (c) sanity-check
  tool-call counts aren't double-counted (conversion-only vs listener emission) — scope `log_statistics`
  to the serving plugins only if inflated.

## Doc-vs-reality (2026-07-24) — MCP dashboard: serviceless routes + virtual consumers
- **Empty "by MCP server" / "upstream latency" tiles → serviceless listener routes.** Our aggregated
  `/mcp/*` listener routes have NO gateway_service, so agentic_usage `gateway_service` and
  `upstream_latency_average` are always empty. Fix (dashboard-only, no Kong change): key those tiles on
  **`route`** (shows `mcp-ops`/`mcp-dealers`/`mcp-finance`) and **`response_latency_average`**. Verified
  live: "Calls by governed MCP server", "Top MCP servers", "Avg MCP latency" all populate after the swap.
  aegis's `mcp-analytics.json` uses gateway_service/upstream_latency because ITS MCP routes sit on
  services; ours are serviceless by the conversion-only+listener split — so re-key to `route`.
- **Virtual consumers do NOT populate agentic analytics `consumer` — TESTED, FAILED.** `credential_claim`
  (on openid-connect AND ai-mcp-oauth2; "derive virtual credentials … in case the consumer mapping is not
  used") creates a claim-derived credential WITHOUT a Kong consumer entity. Set
  `credential_claim: [preferred_username]` on all 3 listeners (removed consumer_claim so it unambiguously
  engaged), synced, fired persona-tagged tool calls → the dashboard `consumer`-dimension tile stayed
  **"No data"** while route/tool/latency dims populated. Conclusion: virtual credentials serve
  rate-limiting (their documented purpose) but the agentic `consumer` dimension needs a **real Kong
  consumer entity**. Reverted credential_claim (never committed). Per-identity analytics ⇒ real consumers
  (mapped via `consumer_claim: [preferred_username]`) or stay consumer-less (identity lives in the cockpit
  badges). Authz is unaffected either way (token `groups` claim). See [[agentic-usage-needs-log-statistics]].

## Doc-vs-reality (2026-07-24) — agentic dashboard consumer dim needs REAL consumers
- **Settled by 3 live tests + aegis.** The `agentic_usage` DASHBOARD `consumer`/`consumer_group`
  dimensions populate ONLY from real Kong consumer entities:
  - `credential_claim: [preferred_username]` (virtual/pseudo-consumer, no entity) → consumer tile EMPTY.
  - `consumer_groups_claim: [groups]` + 3 consumer-group entities → consumer_group tile shows "empty"
    (all calls bucketed under empty; dimension is valid but not populated by dynamic claim mapping).
  - **Real consumers** (aegis `kong/deck.yaml` has `consumers:` + `consumer_claim: preferred_username`)
    → the reference's `consumer` tile works. Adopted the same: 3 consumers (dana.dealer/frank.finance/
    olivia.ops), no credentials, mapped via the listeners' existing consumer_claim+consumer_by.
- **Reconciles the Slack thread** (kongstrong #… 2026-06-23, Hal + Jack Tysoe): consumer-less attribution
  IS possible, but for OTHER surfaces — `credential_claim` → AI-RLA rate-limit/cost counters (Hal:
  "may not appear in Konnect Analytics dashboards which expect real Consumer entities"); consumer_groups_claim
  → request LOGS / Observability→Requests (Jack: "under logging it will show consumer groups"). Neither
  feeds the agentic DASHBOARD tiles.
- **Authz unaffected** by adding consumers: the ai-mcp-proxy ACL is `acl_attribute_type: oauth_access_token`
  (groups claim); a resolved consumer is used only for analytics/identity. Verified 24/24 `allow` after each
  change. No standalone `acl` plugin exists to trip on consumer membership.
- ✅ **VERIFIED LIVE (2026-07-24):** the 'Tool calls by consumer' tile shows all three (dana.dealer / frank.finance / olivia.ops). Real-consumer attribution confirmed end-to-end.

## Doc-vs-reality (2026-07-27) — consumer + tool tiles only populate from actual MCP tool calls
- **A consumer/tool only appears on the agentic tiles if that identity makes a `tools/call` through a
  `/mcp/*` listener.** The scripted 7-step story originally had **dana on REST-only** (Step 1, `/api/*`,
  no consumer mapping) and **frank on a single 403 ACL-deny**, so running the scenarios never surfaced
  dana on the consumer tile (U12's "all three" earlier came from ad-hoc calls). Fixed: Step 3 now runs a
  successful MCP tool call for dana AND frank, and exercises **all 4 converted tools** (dana calls both
  dealer tools, frank both finance tools) — `list_dealer_vehicles` is only reachable via /mcp/dealers,
  `list_floorplans` only via /mcp/finance (/mcp/ops bundles only customers+invoices). demo.sh +
  demo-ui/scenarios.js edited identically. Added a `smoke-test.sh` static guard (#6) that fails if the
  demo doesn't `tools/call` every converted tool from kong/konnect.yaml.
- ✅ Consumer tile re-verified: shows all three.
- ⚠️ **OPEN:** the 'Tool usage' tile (`mcp_tool_name`, filter = `not_empty`, NOT a name whitelist) still
  showed only the 2 historically-called tools (customers, invoices) after all 4 were called live — even
  though the new calls succeed, count in request_count, and are consumer-attributed (dana=2). Config is
  identical across the 3 listeners and all 4 conversion plugins have `log_statistics: true`, so config is
  NOT the cause. Working hypothesis: **ingestion lag on first-seen `mcp_tool_name` dimension values**.
  Fired a timestamped burst (6× each of vehicles+floorplans) to re-check after ingest. If still absent
  after ~10 min → genuine ai-mcp-proxy emission issue; fetch the plugin's statistics reference from
  developer.konghq.com (don't guess the schema).
