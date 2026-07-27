# NEXT-SESSION.md — cai-mcp-demo

Slim boot context. Details live in `claude/handoff/` fragments (read on demand).

- **Branch:** `feat/cai-mcp-demo-build` (build in progress; merge to `main` when demo verified end-to-end)
- **Design spec:** `claude/specs/2026-07-22-cai-mcp-demo-design.md`
- **Plan:** `claude/plans/2026-07-22-cai-mcp-demo-implementation.md` (6 phases)
- **Konnect:** live CP `cai-mcp-demo` (id `<your-control-plane-id>`), region `us`.
  Shared PAT is in `~/workspace/github/aegis-insurance-ai-gateway-demo/secrets.env` (`DECK_KONNECT_TOKEN`).
  `.env` is already populated (gitignored); `certs/` already generated + pinned.
- **Dev loop:** edit → `./scripts/rebuild.sh <svc>` (always `--no-cache`) → `deck ... gateway sync` → verify LIVE
- **Sync:** `docker compose --profile tools run --rm deck gateway sync /config/konnect.yaml`
- **Token:** `./scripts/get-token.sh <dana|frank|olivia> [scope-override] [--raw]`

## Since last session (2026-07-24)

- **Overview view + cockpit intuitiveness pass SHIPPED + LIVE-verified (Playwright).** New default
  landing **Overview** (customer-facing: personas + tool matrix + 7 steps + verdict legend), and Demo
  rewritten (F1–F6): per-call identity **badges** (no more dead persona buttons), human step labels,
  honest per-call verdict labels (classifier untouched, U8). Copy is now sourced from `scenarios.js`
  (SSoT, U11) + `demo-ui/public/content.js`. Decisions U10/U11. Spec+plan dated 2026-07-24. 16/16 unit
  tests; all 7 Demo steps green live. Screenshots `verify-overview.png` / `verify-demo-step1.png`.
- **NEXT (UI):** confirm exact Cox palette hex (one-line CSS-var swap); optional favicon to silence the
  one benign console 404. Deeper Explore-mode polish is available if wanted.

## Earlier (2026-07-22)

- **demo-ui cockpit SHIPPED + LIVE-verified.** Cox-branded host-run cockpit (`demo-ui/`, launch with
  `scripts/ui.sh` → http://127.0.0.1:4000). Demo/Explore/Stack modes drive the real stack and visualize
  each governance decision (plugin-chain trace + token BEFORE/AFTER + verdict). Verified via Playwright
  across all three modes; verdict.js 7/7 unit test; 5 signatures re-verified live. Spec
  `claude/specs/2026-07-22-demo-ui-design.md`, plan `claude/plans/2026-07-22-demo-ui-implementation.md`.
- **ALL 6 PHASES COMPLETE + verified LIVE** (earlier): REST OIDC gates, REST→MCP conversion, token-claim
  ACL, RFC 8693 exchange on /mcp/ops, OPA argument policy, passthrough remotes, MCP Registry (5 servers),
  Konnect analytics dashboard (id 388e3b28-…). Details in `handoff/state.md` + NOTES.md.
- Stack UP (kong-dp, keycloak, dealer-svc, finance-svc, opa, market-mcp). demo-ui server may be running
  on :4000 (`lsof -ti :4000`); `.env` gained `UI_PORT` + `KONNECT_DASHBOARD_ID`.
- **NEXT:** confirm exact Cox palette hex (one-line swap in `demo-ui/public/styles.css`); run the whole
  demo on Cox's org (bootstrap → sync → registry-setup on a Labs org); then merge to `main`. See `handoff/next.md`.

## Fragments

| File | What |
|------|------|
| `handoff/state.md` | Live "what's working" snapshot |
| `handoff/next.md` | Suggested next priorities |
| `handoff/known-issues.md` | Known bugs + troubleshooting |
| `handoff/shipped-log.md` | Append-only ship history |
| `handoff/backlog.md` | Phase 2–6 task pointers |
