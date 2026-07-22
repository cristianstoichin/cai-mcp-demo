# next.md — suggested priorities

**The full 6-phase build is COMPLETE and LIVE-verified against the org.** No build work remains.

Suggested next steps (polish / handoff to Cox):
1. **Run against Cox's own Konnect org.** Fresh `.env` (their `KONNECT_TOKEN` + region) → `konnect-bootstrap.sh`
   → `docker compose up -d` → `deck gateway sync` → `registry-setup.sh` (needs their Labs "Catalog - MCP
   Registry" toggle, US only) → `preflight.sh` + `smoke-test.sh` + `demo.sh`.
2. **Merge `feat/cai-mcp-demo-build` → `main`** once demoed end-to-end on the target org.
3. **Optional polish:** Dev Portal publication of the APIs, Konnect analytics/dashboards, a recorded
   `demo.sh --no-pause` walkthrough, and any Cox-specific tool/data tweaks in dealer-svc/finance-svc/market-mcp.
4. **Interactive Claude Code OAuth (browser)** — currently curl-with-bearer works; the browser OAuth flow
   advertises `keycloak:8080` in protected-resource metadata (not host-resolvable). If a browser-based Claude
   Code hookup is wanted, expose Keycloak on a host-resolvable name and reconcile the issuer pin (NOTES.md Phase 2).

Working method unchanged: inline execution; --no-cache rebuilds; deck validate then sync; verify LIVE;
log doc-vs-reality in NOTES.md; commit per change.
