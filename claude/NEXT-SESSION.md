# NEXT-SESSION.md — cai-mcp-demo

Slim boot context. Details live in `claude/handoff/` fragments (read on demand).

- **Branch:** `feat/cai-mcp-demo-build` (build in progress; merge to `main` when demo verified end-to-end)
- **Design spec:** `claude/specs/2026-07-22-cai-mcp-demo-design.md`
- **Plan:** `claude/plans/2026-07-22-cai-mcp-demo-implementation.md` (6 phases)
- **Konnect:** live CP `cai-mcp-demo` (id `007f4c01-74b6-44ff-810e-4620e01be51b`), region `us`.
  Shared PAT is in `~/workspace/github/aegis-insurance-ai-gateway-demo/secrets.env` (`DECK_KONNECT_TOKEN`).
  `.env` is already populated (gitignored); `certs/` already generated + pinned.
- **Dev loop:** edit → `./scripts/rebuild.sh <svc>` (always `--no-cache`) → `deck ... gateway sync` → verify LIVE
- **Sync:** `docker compose --profile tools run --rm deck gateway sync /config/konnect.yaml`
- **Token:** `./scripts/get-token.sh <dana|frank|olivia> [scope-override] [--raw]`

## Since last session (2026-07-22)

- **Phases 1–5 COMPLETE + verified LIVE against the org.** Phases 1–4 as before (OIDC matrix, MCP
  conversion 2/2/2-bundled, aegis-style token-claim ACL, X-User-* forwarded).
- **Phase 5.1** — /mcp/ops introspection + RFC 8693 token exchange (kong-exchange): an mcp:use-only token
  reaches dealer+finance tools on /mcp/ops but 403s on /mcp/dealers. Exchange requests SCOPES only (Keycloak
  audience param = a registered client). ACL still enforces on the exchanged token's groups.
- **Phase 5.2** — OPA on /mcp/ops: mcp.rego (argument-level deny of list_invoices?query_status=overdue,
  live 403) + entitlement rule + commented business-hours; opa runs `-w` (hot-reload proven live). Input
  document doc-verified by observation (caught claim_to_header base64-encoding array claims).
- **Phase 5.3** — passthrough remotes: /mcp/remote → local market-mcp (Cox tools), /mcp/remote-public →
  DeepWiki (third-party, protocol 2025-06-18, stateless). ai-mcp-oauth2 gate, passthrough_credentials:false.
- Stack UP (kong-dp, keycloak, dealer-svc, finance-svc, opa, market-mcp). All Phase-5 findings in NOTES.md.
- **NEXT: Phase 6** — MCP Registry (registry-setup.sh, klabs host) + claude-code-setup.sh + demo.sh +
  preflight/smoke + README (quickstart, walkthrough, mermaid, Known Issues). See handoff/next.md.

## Fragments

| File | What |
|------|------|
| `handoff/state.md` | Live "what's working" snapshot |
| `handoff/next.md` | Suggested next priorities |
| `handoff/known-issues.md` | Known bugs + troubleshooting |
| `handoff/shipped-log.md` | Append-only ship history |
| `handoff/backlog.md` | Phase 2–6 task pointers |
