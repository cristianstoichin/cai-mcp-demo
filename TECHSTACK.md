# TECHSTACK.md — cai-mcp-demo

| Category | Technology | Version (pinned) | Rationale |
|----------|-----------|------------------|-----------|
| API Gateway | Kong Gateway (Konnect hybrid DP) | `3.14.0.2` | Target platform; AI MCP plugins (ai-mcp-proxy, ai-mcp-oauth2) ship in 3.14. Konnect hybrid = customer's real topology. |
| Gateway config | decK | `v1.53.0` | Declarative GitOps sync to Konnect; `deck gateway validate/sync`. No imperative Admin API. |
| Identity | Keycloak | `26.2` | Self-contained OIDC IdP; realm pre-baked via `--import-realm`. KC26 standard token exchange (RFC 8693 V2) for the /mcp/ops exchange. |
| External policy | Open Policy Agent | `1.4.2` | Demonstrates Kong `opa` plugin delegating tool-call authz to an external policy engine. |
| Upstream services | Node.js + Express | Node `20-alpine`, express `^4.19` | Minimal mock REST APIs; `npm install` only, no build step. |
| Local MCP server | Node.js (streamable-HTTP MCP) | Node `20-alpine` | Reliable on-theme passthrough target for `/mcp/remote`. |
| Custom MCP server | Python + MCP SDK (`mcp`) | Python `3.12-slim`, `mcp==2.0.0` | Hand-written MCP server for `/mcp/custom` — shows Kong governing a custom tool it did not generate, in a second language. **`mcp` 2.x uses `mcp.server.mcpserver.MCPServer`; `mcp.server.fastmcp` no longer exists** (see NOTES.md). |
| Remote MCP (public) | DeepWiki MCP | `mcp.deepwiki.com` | Third-party MCP server for the "govern something you don't own" story. |
| Orchestration | Docker Compose | v2 | One `docker compose up`; `tools` profile for the deck one-shot. |
| Konnect APIs | Control Plane API + MCP Registry (Labs) | `v2` / `v0` (`klabs`) | CP create + DP cert (bootstrap); MCP Registry publish/discovery (tech preview). |

Every version above is pinned to an exact patch tag in `docker-compose.yaml`. Update this table
and `docker-compose.yaml` in the same commit whenever the stack changes.
