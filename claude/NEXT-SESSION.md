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

- **Phases 1–4 COMPLETE + verified LIVE against the org.** DP connected; deck sync clean; OIDC matrix
  401/200/403; MCP tools/list = 2/2/2-bundled; tools/call round-trips; **aegis-style token-claim tool
  ACL** (allow/deny matrix correct); X-User-* forwarded.
- **ACL approach changed at Paul's request:** reverted D4 → aegis scope/claim ACL (`acl_attribute_type:
  oauth_access_token` + `access_token_claim_field: groups`); no Kong consumers. See DECISIONS.md.
- Stack is currently UP (kong-dp, keycloak, dealer-svc, finance-svc). market-mcp/opa not built yet.
- **NEXT: Phase 5** — token_exchange + OPA on /mcp/ops, local market-mcp, two passthrough remote routes.

## Fragments

| File | What |
|------|------|
| `handoff/state.md` | Live "what's working" snapshot |
| `handoff/next.md` | Suggested next priorities |
| `handoff/known-issues.md` | Known bugs + troubleshooting |
| `handoff/shipped-log.md` | Append-only ship history |
| `handoff/backlog.md` | Phase 2–6 task pointers |
