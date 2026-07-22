# next.md — suggested priorities

**Phase 5 is COMPLETE + LIVE-verified.** Next is **Phase 6** (registry + Claude Code + README + demo):

1. **Task 6.1 — MCP Registry.** `konnect/mcp-registry/*.json` (create body `cai-mcp-registry` + publish
   bodies for /mcp/dealers, /mcp/finance, /mcp/ops, /mcp/remote) + `scripts/registry-setup.sh`. Base
   `https://klabs.${KONNECT_REGION}.api.konghq.com/v0/mcp-registries`; idempotent create → publish 4 →
   discovery GET `.../v0.1/servers`; helpful 404 message if Labs not enabled. (Registry is US-only tech
   preview; verify create/publish/discover paths against aegis setup-mcp-registry.sh — see NOTES.md/DECISIONS.)
2. **Task 6.2 — Claude Code + demo/preflight/smoke.** `scripts/claude-code-setup.sh` emits `claude mcp add
   --transport http <name> <url> --header "Authorization: Bearer <tok>"` for dealers/finance/ops/remote.
   `scripts/demo.sh` numbered pause-between-steps (401/200/403 raw curls → tools/list 2/2/2-bundled →
   registry discovery → audience-mismatch 401 → token-exchange proof via logs → ACL diff + denied call →
   OPA deny→allow). `scripts/preflight.sh` (tools/ports/health) + `scripts/smoke-test.sh` (docker compose
   config -q, deck validate, opa check, node /health, JSON validity).
3. **Task 6.3 — README + finalize.** Quickstart for a fresh 3rd-party Konnect org (Labs toggle; AI Gateway
   Enterprise licensing note; three-command flow), walkthrough mirroring demo.sh with expected outputs,
   mermaid architecture diagram, troubleshooting, Known Issues. Reconcile NOTES.md; update handoff + shipped-log.

Working method: inline execution; --no-cache rebuilds; deck file validate then gateway sync; verify LIVE
against the org (PAT already in .env); log every doc-vs-reality finding in NOTES.md; commit per task.

Note: registry-setup.sh must run on the klabs host / with a Labs-enabled org — verify live there.
