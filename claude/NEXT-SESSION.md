# NEXT-SESSION.md — cai-mcp-demo

Slim boot context. Details live in `claude/handoff/` fragments (read on demand).

- **Branch:** `feat/cai-mcp-demo-build` (build in progress; merge to `main` when demo verified end-to-end)
- **Design spec:** `claude/specs/2026-07-22-cai-mcp-demo-design.md`
- **Plan:** `claude/plans/2026-07-22-cai-mcp-demo-implementation.md` (6 phases)
- **Dev loop:** edit → `./scripts/rebuild.sh <svc>` (always `--no-cache`) → verify
- **Local stack (no Konnect):** `docker compose up -d keycloak dealer-svc finance-svc`
- **Token:** `./scripts/get-token.sh <dana|frank|olivia>`

## Since last session (2026-07-22)

- Repo initialized; design spec + phased plan committed.
- **Phase 1 COMPLETE + verified locally:** dealer-svc/finance-svc (Cox mock APIs, header-logging),
  Keycloak `cox-auto` realm (scopes/groups/users/3 clients), compose subset, `.env.example`,
  `get-token.sh`, `rebuild.sh`. Tokens mint with correct `sub`/`preferred_username`/`groups`/`aud`.
- Verified all AI-MCP plugin schemas against developer.konghq.com (see NOTES.md).

## Fragments

| File | What |
|------|------|
| `handoff/state.md` | Live "what's working" snapshot |
| `handoff/next.md` | Suggested next priorities |
| `handoff/known-issues.md` | Known bugs + troubleshooting |
| `handoff/shipped-log.md` | Append-only ship history |
| `handoff/backlog.md` | Phase 2–6 task pointers |
