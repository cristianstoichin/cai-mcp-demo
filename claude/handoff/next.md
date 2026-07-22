# next.md — suggested priorities

**Phase 5** (per plan) — build + LIVE-verify each against the org:
1. `/mcp/ops` ai-mcp-oauth2: switch to introspection (kong-exchange creds) + `token_exchange.enabled`
   (aegis style: request.audience [dealer-api, finance-api], request.scopes). Prove exchange with an
   `mcp:use`-ONLY token (no API audiences) — that's the case direct-forwarding can't satisfy.
2. `opa` plugin on `/mcp/ops` → `http://opa:8181/v1/data/mcp/allow`; write `opa/policies/mcp.rego`
   (default allow; deny tools/call for list_invoices unless token groups include finance|ops; commented
   business-hours rule). Doc-verify the exact OPA input document Kong sends first.
3. `market-mcp` (local Node streamable-HTTP MCP, Cox tools) + `/mcp/remote` (passthrough → market-mcp)
   and `/mcp/remote-public` (passthrough → DeepWiki), both fronted by ai-mcp-oauth2. Verify DeepWiki
   protocol >= 2025-06-18 live.

**Phase 6** — registry-setup.sh (klabs host), claude-code-setup.sh, demo.sh, README finalize + mermaid.

Working method: inline execution; --no-cache rebuilds; deck file validate then gateway sync; verify LIVE
against the org (PAT already in .env); log every doc-vs-reality finding in NOTES.md.
