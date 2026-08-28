# NEXT-SESSION.md — cai-mcp-demo

Slim boot context. Details live in `claude/handoff/` fragments (read on demand).

- **Branch:** `main` (build merged; 6 phases + cockpit LIVE-verified against my org)
- **Design spec:** `claude/specs/2026-07-22-cai-mcp-demo-design.md`
- **Plan:** `claude/plans/2026-07-22-cai-mcp-demo-implementation.md` (6 phases)
- **Konnect:** live CP `cai-mcp-demo` (id `<your-control-plane-id>`), region `us`.
  Shared PAT is in `~/workspace/github/aegis-insurance-ai-gateway-demo/secrets.env` (`DECK_KONNECT_TOKEN`).
  `.env` is already populated (gitignored); `certs/` already generated + pinned.
- **Dev loop:** edit → `./scripts/rebuild.sh <svc>` (always `--no-cache`) → `deck ... gateway sync` → verify LIVE
- **Sync:** `docker compose --profile tools run --rm deck gateway sync /config/konnect.yaml`
- **Token:** `./scripts/get-token.sh <dana|frank|olivia> [scope-override] [--raw]`

## Since last session (2026-08-28)

- **Custom Python MCP server is in** (`custom-mcp/`, `mcp==2.0.0`, streamable-HTTP **stateless**),
  governed at `/mcp/custom` by `ai-mcp-proxy` **passthrough-listener** + `ai-mcp-oauth2`, carrying a
  **per-tool group ACL on a passthrough server**: `hello_custom_tool` `allow: [finance, dealers]`, so
  dana + frank may call it and **olivia (ops) is denied and filtered out of `tools/list`**. The route
  also has `consumer_claim`/`consumer_by` so Konnect analytics attributes the call to a person.
  Decisions 2026-08-12 + its same-day amendment; registry body `publish-custom.json`.
- **Counts moved with it: the repo is now 8 demo steps and 6 MCP servers.** Custom got its own scene in
  `scenarios.js` + `demo.sh`; `registry-setup.sh` PUBLISH, `claude-code-setup.sh` SERVERS and
  `claude-code-teardown.sh` NAMES each carry 6 entries.
- **Present** (2026-07-27) is the cockpit's 5th mode — self-driven tell-show-tell over the same
  `scenarios.js` scenes (`demo-ui/public/present.js`).
- **Doc-drift pass (this session; static checks only — Docker was down).** Fixed step/server counts in
  `README.md`, `ARCHITECTURE.md`, `RUNBOOK.md`, `claude/handoff/claude-code-demo.md`,
  `scripts/registry-setup.sh` and the Overview lede; added a `demo-ui` row to `TECHSTACK.md` and
  `custom-mcp`/`demo-ui`/Present to the ARCHITECTURE module map + README mermaid; rewrote the stale
  `konnect.yaml` comment that claimed `/mcp/custom` had **no** tool ACL; added `hello_custom_tool` to the
  Overview permission matrix with a `copy-and-render.test.js` assertion on its allow-list (18/18 pass).
- **NEXT:** `handoff/state.md` + `handoff/next.md` are still pre-custom-mcp and quote live-run counts
  (`preflight 17/17`, `smoke-test 14/14`) taken before the custom-mcp checks existed. Refresh them
  **after** a real `./scripts/preflight.sh` + `./scripts/smoke-test.sh` — do not hand-edit those numbers.

## Earlier (2026-07-24)

- **Overview view + cockpit intuitiveness pass SHIPPED + LIVE-verified (Playwright).** New default
  landing **Overview** (customer-facing: personas + tool matrix + 7 steps + verdict legend), and Demo
  rewritten (F1–F6): per-call identity **badges** (no more dead persona buttons), human step labels,
  honest per-call verdict labels (classifier untouched, U8). Copy is now sourced from `scenarios.js`
  (SSoT, U11) + `demo-ui/public/content.js`. Decisions U10/U11. Spec+plan dated 2026-07-24. 16/16 unit
  tests; all 7 Demo steps green live. Screenshots `claude/specs/visuals/2026-07-24-demo-ui-verification/verify-overview.png` / `claude/specs/visuals/2026-07-24-demo-ui-verification/verify-demo-step1.png`.
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
