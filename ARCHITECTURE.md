# ARCHITECTURE.md — cai-mcp-demo

Kong Gateway 3.14 (Konnect hybrid mode) turning Cox Automotive REST APIs into governed
MCP servers. One `docker compose up` runs everything except the Konnect control plane (SaaS).

## Request path

```
MCP client (curl / Claude Code)                Konnect control plane (SaaS)
        │  Bearer (Keycloak JWT)                        │  config push (decK sync)
        ▼                                               ▼
  Kong DP :8000  ──ai-mcp-oauth2──▶ token validation, token exchange (RFC 8693), OPA
                 ──ai-mcp-proxy───▶ token-claim tool ACL (groups claim; no Kong consumers)
        │                                               
        ├─ /mcp/dealers|finance|ops   (ai-mcp-proxy listener, aggregate by tag)
        ├─ /mcp/remote|remote-public|custom  (ai-mcp-proxy passthrough-listener)
        └─ /api/dealers/*, /api/finance/*  (openid-connect + ai-mcp-proxy conversion-only)
                    │
                    ▼
        dealer-svc / finance-svc / market-mcp (upstream)
```

## Modules

| Path | Responsibility |
|------|----------------|
| `docker-compose.yaml` | All services: kong-dp, keycloak, opa, dealer-svc, finance-svc, market-mcp, deck (tools profile). |
| `.env.example` | Every org-specific/secret value. Copy to `.env`. Nothing org-specific lives elsewhere. |
| `keycloak/realm-export.json` | Pre-baked `cox-auto` realm: scopes (`dealers:read`/`finance:read`/`mcp:use`), `identity`+`groups` scopes, groups, 3 users, 3 clients (demo-cli/claude-code/kong-exchange). |
| `kong/konnect.yaml` | Declarative decK config — services, routes, OIDC gates, ai-mcp-proxy (conversion-only + listener + passthrough), ai-mcp-oauth2, consumers, groups, ACLs, OPA plugin. |
| `opa/policies/mcp.rego` | External policy for `/mcp/ops` (deny `list_invoices` unless finance/ops). |
| `dealer-svc/` | Node/Express mock: `GET /customers`, `GET /vehicles`, `/health`. Logs inbound headers. |
| `finance-svc/` | Node/Express mock: `GET /invoices`, `GET /floorplans`, `/health`. Logs inbound headers. |
| `market-mcp/` | Local Cox-themed MCP server (streamable-HTTP) — passthrough target for `/mcp/remote`. |
| `custom-mcp/` | Hand-written **Python** MCP server (streamable-HTTP, stateless) — passthrough target for `/mcp/custom`. One tool, `hello_custom_tool`, gated by a per-tool ACL (`allow: [finance, dealers]`) declared on the passthrough listener. Proves the gateway governs — and group-restricts — custom tools it did not generate, in any language. |
| `konnect/mcp-registry/*.json` | Registry create + 5 publish bodies (dealers, finance, ops, remote, remote-public). |
| `scripts/konnect-bootstrap.sh` | Create CP + generate/upload DP cert + print endpoints. |
| `scripts/get-token.sh` | Mint persona token (ROPC via demo-cli), decode + print claims. |
| `scripts/registry-setup.sh` | Create MCP Registry + publish + discovery GET. |
| `scripts/claude-code-setup.sh` | Emit `claude mcp add` lines for all servers. |
| `scripts/demo.sh` | Numbered, pause-between-steps walkthrough. |
| `scripts/rebuild.sh` | `docker compose build --no-cache` + force-recreate (D7). |
| `scripts/preflight.sh` / `smoke-test.sh` | Tool/port/health checks + local static assertions. |
| `scripts/ui.sh` | Launch the demo-ui cockpit (sources `.env`, `npm install` on first run, runs the host server). |
| `demo-ui/server.js` | Host-run Express (binds `127.0.0.1`): serves `public/` + the `/api/*` endpoints; secrets stay server-side. |
| `demo-ui/config.js` | Env-derived config (mirrors the scripts' defaults) + the persona contract. |
| `demo-ui/keycloak.js` / `kong.js` / `registry.js` / `stack.js` | Thin I/O adapters: token mint/exchange/decode; MCP+REST calls; Konnect registry discovery; whitelisted stack-action SSE runner. |
| `demo-ui/verdict.js` (+ `.test.js`) | Pure response-signature → governance verdict classifier (the one unit-tested module). Coarse taxonomy (U8) — untouched by the copy layer. |
| `demo-ui/scenarios.js` | The 8 Demo steps as data — single source of truth for both Demo **and** Overview (U11). Carries the customer-facing copy: `headline`/`proves`/`why`/`railLabel` per scene, `identity`/`verdictLabel` per call. Mirrors `demo.sh`. |
| `demo-ui/copy-and-render.test.js` | Node `--test`: scenarios copy integrity, `content.js` (personas/matrix) vs `konnect.yaml`, and the pure `trace.js`/`overview.js` string-builders. |
| `demo-ui/public/` | Vanilla-JS SPA, no build step: `index.html` shell; `app.js` router (default → Overview) + Overview/Demo/Explore/Stack views; `content.js` customer-facing static copy (personas, tool matrix, verdict legend — no secrets); `overview.js` Overview landing view (`overviewHTML` pure builder + DOM attach); `trace.js` hybrid-panel renderer + pure presentation helpers (`identityBadge`/`verdictKind`/`verdictChip`); `styles.css` (Cox palette via CSS variables). |
| `demo-ui/Dockerfile` | Multi-stage (mirrors the aegis dashboard). The `demo-ui` compose service reaches Kong/Keycloak on the in-network hostnames; published host-local on `127.0.0.1:4000`; read-only Docker socket for the Stack status tiles. Stack execute actions are host-only (`scripts/ui.sh`). |

## Kong topology (services → routes → plugins)

| Route | Path | Mode / auth | Tool(s) | Tags |
|-------|------|-------------|---------|------|
| dealer-customers | `/api/dealers/customers` | conversion-only + OIDC (dealers:read, dealer-api) | `list_dealer_customers` | dealer-tools, bundle-tools |
| dealer-vehicles | `/api/dealers/vehicles` | conversion-only + OIDC | `list_dealer_vehicles` | dealer-tools |
| finance-invoices | `/api/finance/invoices` | conversion-only + OIDC (finance:read, finance-api) | `list_invoices` | finance-tools, bundle-tools |
| finance-floorplans | `/api/finance/floorplans` | conversion-only + OIDC | `list_floorplans` | finance-tools |
| mcp-dealers | `/mcp/dealers` | listener + ai-mcp-oauth2 (JWKS) | aggregates `dealer-tools` | — |
| mcp-finance | `/mcp/finance` | listener + ai-mcp-oauth2 (JWKS) | aggregates `finance-tools` | — |
| mcp-ops | `/mcp/ops` | listener + ai-mcp-oauth2 (introspection + exchange) + OPA | aggregates `bundle-tools` | — |
| mcp-remote | `/mcp/remote` | passthrough-listener + ai-mcp-oauth2 → market-mcp | — | — |
| mcp-remote-public | `/mcp/remote-public` | passthrough-listener + ai-mcp-oauth2 → DeepWiki | — | — |
| mcp-custom | `/mcp/custom` | passthrough-listener + ai-mcp-oauth2 → custom-mcp (Python) | `hello_custom_tool` (ACL matched by name) | — |

Tags are Kong **entity** tags on the conversion-only plugin; the listener's `config.server.tag`
aggregates by them (see NOTES.md).

## Tool ACLs (by the token's `groups` claim — no Kong consumers)

The `ai-mcp-proxy` listener sets `acl_attribute_type: oauth_access_token` +
`access_token_claim_field: groups`; per-tool `acl.allow/deny` (bare group names) match values in the
validated (and, on `/mcp/ops`, post-exchange) token's `groups` claim. Deny wins. Enforced at **both**
`tools/list` — the advertised catalog is filtered to the tools the caller may call, so a denied tool is
simply absent — **and** `tools/call`, where a direct call to a filtered-out tool still returns `403`.
Live-verified on Kong EE 3.14.0.2; see NOTES.md (2026-07-28).

| Tool | Allow | Deny |
|------|-------|------|
| `list_dealer_customers` | dealers, ops | — |
| `list_dealer_vehicles` | dealers, ops | finance |
| `list_invoices` | finance, ops | — |
| `list_floorplans` | finance | — (ops excluded on purpose) |
| `hello_custom_tool` | finance, dealers | — (ops excluded on purpose) |

Plus, on `/mcp/ops` only, an external **OPA** policy (`opa/policies/mcp.rego`) adds an argument-level rule
(deny `list_invoices` when `query_status=overdue`) that the tool ACL cannot express.

See `claude/specs/2026-07-22-cai-mcp-demo-design.md` for the full design and `NOTES.md` for
doc-vs-reality schema notes.
