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

- **ALL 6 PHASES COMPLETE + verified LIVE against the org.** The demo is fully built and runnable.
- **Phase 6** — MCP Registry live (cai-mcp-registry, 5 servers published/discoverable); scripts
  registry-setup + claude-code-setup + demo (7 steps) + preflight (17/17) + smoke-test (14/14); README
  finalized (mermaid, walkthrough, troubleshooting, Known Issues). Next: run on Cox's org, then merge to main.
- **Phases 1–5** — REST OIDC gates, REST→MCP conversion (2/2/2-bundled), token-claim ACL, RFC 8693
  exchange on /mcp/ops, OPA argument policy, passthrough remotes. Details in `handoff/state.md` + NOTES.md.
- Stack UP (kong-dp, keycloak, dealer-svc, finance-svc, opa, market-mcp). Registry id in `.env`.
- **NEXT:** run on Cox's org (bootstrap → sync → registry-setup on a Labs org), then merge to `main`.
  See `handoff/next.md`.

## Fragments

| File | What |
|------|------|
| `handoff/state.md` | Live "what's working" snapshot |
| `handoff/next.md` | Suggested next priorities |
| `handoff/known-issues.md` | Known bugs + troubleshooting |
| `handoff/shipped-log.md` | Append-only ship history |
| `handoff/backlog.md` | Phase 2–6 task pointers |
