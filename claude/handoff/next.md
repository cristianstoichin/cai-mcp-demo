# next.md — suggested priorities

**The full 6-phase build is COMPLETE and LIVE-verified against the org.** No build work remains.

Suggested next steps (polish / handoff to Cox):
1. **Run against Cox's own Konnect org.** Fresh `.env` (their `KONNECT_TOKEN` + region) → `konnect-bootstrap.sh`
   → `docker compose up -d` → `deck gateway sync` → `registry-setup.sh` (needs their Labs "Catalog - MCP
   Registry" toggle, US only) → `preflight.sh` + `smoke-test.sh` + `demo.sh`.
2. **Merge `feat/cai-mcp-demo-build` → `main`** once demoed end-to-end on the target org.
3. **Optional polish:** Dev Portal publication of the APIs, Konnect analytics/dashboards, a recorded
   `demo.sh --no-pause` walkthrough, and any Cox-specific tool/data tweaks in dealer-svc/finance-svc/market-mcp.
4. ~~**Interactive Claude Code OAuth (browser)**~~ — **DONE (2026-07-27).** `scripts/hosts-alias.sh --apply`
   pins `keycloak`→127.0.0.1 on the host; `scripts/claude-code-setup.sh --browser` registers the servers
   against the pre-built `claude-code` public client (auth code + PKCE). Single-issuer `keycloak:8080`
   preserved, no Kong change. Final browser click-through is a live/human step. See README → *Hook Claude
   Code up* and NOTES.md (2026-07-27 browser OAuth).

Working method unchanged: inline execution; --no-cache rebuilds; deck validate then sync; verify LIVE;
log doc-vs-reality in NOTES.md; commit per change.
