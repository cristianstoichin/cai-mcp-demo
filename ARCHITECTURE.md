# ARCHITECTURE.md — cai-mcp-demo

Kong Gateway 3.14 (Konnect hybrid mode) turning Cox Automotive REST APIs into governed
MCP servers. One `docker compose up` runs everything except the Konnect control plane (SaaS).

## Request path

```
MCP client (curl / Claude Code)                Konnect control plane (SaaS)
        │  Bearer (Keycloak JWT)                        │  config push (decK sync)
        ▼                                               ▼
  Kong DP :8000  ──ai-mcp-oauth2──▶ consumer/group map, token exchange, OPA
        │                                               
        ├─ /mcp/dealers|finance|ops   (ai-mcp-proxy listener, aggregate by tag)
        ├─ /mcp/remote|remote-public  (ai-mcp-proxy passthrough-listener)
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
| `konnect/mcp-registry/*.json` | Registry create + publish bodies (3 gateway + remote servers). |
| `scripts/konnect-bootstrap.sh` | Create CP + generate/upload DP cert + print endpoints. |
| `scripts/get-token.sh` | Mint persona token (ROPC via demo-cli), decode + print claims. |
| `scripts/registry-setup.sh` | Create MCP Registry + publish + discovery GET. |
| `scripts/claude-code-setup.sh` | Emit `claude mcp add` lines for all servers. |
| `scripts/demo.sh` | Numbered, pause-between-steps walkthrough. |
| `scripts/rebuild.sh` | `docker compose build --no-cache` + force-recreate (D7). |
| `scripts/preflight.sh` / `smoke-test.sh` | Tool/port/health checks + local static assertions. |

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

Tags are Kong **entity** tags on the conversion-only plugin; the listener's `config.server.tag`
aggregates by them (see NOTES.md).

## Tool ACLs (two-tier, by consumer group)

| Tool | Allow | Deny |
|------|-------|------|
| `list_dealer_customers` | dealers, ops | — |
| `list_dealer_vehicles` | dealers, ops | finance |
| `list_invoices` | finance, ops | — |
| `list_floorplans` | finance | — (ops excluded on purpose) |

See `claude/specs/2026-07-22-cai-mcp-demo-design.md` for the full design and `NOTES.md` for
doc-vs-reality schema notes.
