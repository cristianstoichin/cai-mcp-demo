# Overview view + cockpit intuitiveness — design

**Date:** 2026-07-24
**Scope:** `demo-ui` cockpit only. No Kong/Keycloak/OPA config changes.
**Status:** approved (design); pending spec review → implementation plan.

## Problem

Two complaints, both about legibility, not plumbing:

1. **"What the hell is being demoed" is not readable.** The personas (Dana / Frank /
   Olivia) and the 7 steps are described only by terse, jargon-heavy `narration` strings
   in `scenarios.js`, which Demo mode prints raw. A cold reader (a Cox engineer, no SE
   present) can't tell who each persona is, what they can reach, or what each step proves.
2. **The cockpit is not intuitive.** Concrete, code-level UX defects (enumerated in F1–F6)
   mislead a viewer — most visibly a dead persona control that makes a `401` look like a
   named persona being denied.

## Goals

- A **customer-facing** "Overview / Start here" screen, **baked into the cockpit** as the
  **default landing view**, that explains the personas, the tool-permission matrix, and the
  seven steps in plain language. (Reader = Cox, solo. No internal gotchas / SE talking points.)
- Fix the copy **at its source** so Demo mode reads better too — one source of truth, no
  drift between Overview and Demo.
- Repair the six cockpit intuitiveness defects (F1–F6).
- Thorough **Playwright** verification of every view and every scripted step.

## Non-goals

- No changes to Kong config, Keycloak realm, OPA policy, or the verdict **classifier**
  (`verdict.js`). The 5-verdict taxonomy stays coarse per DECISIONS **U8**.
- No new demo capability, no new backend routes beyond what the Overview needs (it needs
  none — it renders from `/api/scenarios` + static content).
- The out-of-band exchange reproduction (U7), Stack host/container split (U9), and the
  three existing modes (U1) are untouched except where F1–F6 name them.

## Decisions honored (do not reverse)

| Decision | What it locks | How this design respects it |
|---|---|---|
| **U1** | Three modes: Demo / Explore / Stack | Overview is **additive** (4th mode), not a replacement. New decision to record: U10. |
| **U2/U3** | Hybrid trace is the governance-viz hero; Demo nav is a top stepper | Both **kept**. F2/F4 enhance the stepper and call rows; they do not remove the trace or the stepper. |
| **U8** | Verdict taxonomy is coarse (5 verdicts); a non-`unauthorized` 403 → `acl-deny`, covering BOTH the tool-ACL deny and the REST OIDC scope/audience 403; per-call `note` carries the precise story | Classifier **untouched**. F6 changes only the *customer-facing display label*, sourced per-call, so the coarse enum is never shown to Cox. |

### New decisions to record in DECISIONS.md

- **U10** — Add a 4th cockpit mode, **Overview**, as the default landing route (`#/` →
  overview). Rationale: a legible front door is the first fix to "not intuitive"; Demo/
  Explore/Stack become the "now go do it" tabs.
- **U11** — `scenarios.js` becomes the single source of the **customer-facing copy** (each
  scene gains `headline`, `proves`, and a per-call `verdictLabel`). Overview and Demo both
  render from it. Rationale: kill drift; fix the terse-narration complaint at the root.

## Ground truth (verified against `kong/konnect.yaml`, 2026-07-24)

Personas (from `config.personas`, mirrors `get-token.sh`):

| Persona | username | group (`groups` claim) | scopes |
|---|---|---|---|
| Dana | `dana.dealer` | `dealers` | `openid dealers:read mcp:use` |
| Frank | `frank.finance` | `finance` | `openid finance:read mcp:use` |
| Olivia | `olivia.ops` | `ops` | `openid dealers:read finance:read mcp:use` |

Tool → allow-list (per-tool `acl.allow` on the conversion-only plugins; enforced at the
listener via `acl_attribute_type: oauth_access_token`, `access_token_claim_field: groups`
— **claim-based, not Kong consumers**):

| Tool | Returns | allow groups | Dana | Frank | Olivia |
|---|---|---|---|---|---|
| `list_dealer_customers` | dealership customers + trade-in interest | `[dealers, ops]` | ✓ | ✕ | ✓ |
| `list_dealer_vehicles` | dealer inventory (VIN, days-on-lot, vAuto rank) | `[dealers, ops]` (`deny: finance`) | ✓ | ✕ | ✓ |
| `list_invoices` | floor-plan invoices (dealer, amount, status) | `[finance, ops]` | ✕ | ✓ | ✓ |
| `list_floorplans` | floor-plan audit status | `[finance]` | ✕ | ✓ | ✕ |

Endpoints: `/mcp/dealers` (dealer tools), `/mcp/finance` (finance tools), `/mcp/ops`
(bundle of `list_dealer_customers` + `list_invoices`; token-exchange + OPA also run here),
`/mcp/remote` (local market-mcp), `/mcp/remote-public` (DeepWiki, 3rd-party).

## Design

### 1. Content model (source of truth)

**`scenarios.js`** — each scene gains customer-facing fields; existing fields
(`id/n/title/tag/calls/expect/...`) are preserved so nothing else breaks:

```js
{
  id: "oidc", n: 1, tag: "OIDC",
  title: "REST OIDC gates",                 // kept (internal/short)
  headline: "The raw APIs are already protected",   // NEW — plain title
  proves: "Authentication + per-scope authorization at the edge, before MCP exists.", // NEW
  narration: "...",                          // kept for now; Demo stops rendering it raw
  calls: [
    { label: "...", persona: null, identity: "no-token", // NEW identity display key
      verdictLabel: "401 · no token",        // NEW — honest, customer-facing
      why: "No credential presented — rejected at the door.", // NEW per-call plain 'why'
      ... existing fields (path/method/tool/args/expect/note) ... },
  ],
}
```

- `identity` is a display key resolved to a badge (`no-token` / `Dana` / `Frank` / `Olivia`).
- `verdictLabel` is what the customer sees. It is **not** the classifier enum. Step-1 call-3
  gets `"403 · REST scope/audience gate"` (per U8's note), never `"acl-deny"`.
- `why` is the one-line plain explanation shown under the row / scene.

**`demo-ui/public/content.js`** (new) — the static, customer-facing content that does *not*
belong in `scenarios.js`:
- `personas[]` — Dana/Frank/Olivia with `role` and `reach` (can/can't) prose, derived from
  `config.personas` values (username/group/scope) + hand-written role text.
- `matrix` — the tool→group table above (verified constant; one-line to re-verify against
  `konnect.yaml` if tools change).
- `legend[]` — the verdict key (allow / auth-fail / acl-deny / opa-deny / exchanged /
  inner-gate), shared by Overview (full) and Demo (compact).

`config.js` already exposes `personas` server-side; the browser gets persona display data
via the existing `/api/scenarios` payload extended with `content` (server reads `content.js`
values it can share — or `content.js` is a pure client module imported directly, since it's
non-sensitive). **Decision:** `content.js` is a **client ESM module** (no secrets in it),
imported by `overview.js` and `app.js` directly — no new API route.

### 2. Overview view (`demo-ui/public/overview.js`, new)

A 4th mode rendered in the cockpit's **own** CSS (not the standalone guide's separate
palette). Sections, top to bottom:

1. **Lede** — one paragraph: "Kong turns Cox's REST APIs into governed MCP servers and
   governs every call — who the caller is, which tools they may use, and what policy says
   about the specific request. Three people, one gateway, seven things it proves."
2. **The three people** — persona cards (name, username, role, group chip, scope chips,
   ✓/✕ reach list). Sourced from `content.personas`.
3. **Who can call which tool** — the permission matrix (`content.matrix`), with the "claim-
   based, no Kong consumers" note and the endpoint legend.
4. **The seven steps** — one block per scene from `scenarios.js`: number, `headline`,
   "**Proves:** `proves`", the calls (each: identity badge, plain action text, color-coded
   `verdictLabel`), and the scene `why`.
5. **How to read a result** — the full verdict `legend`.

Customer-safe: the standalone guide's internal "two things the cockpit gets wrong" callout
is **omitted**.

### 3. Routing / default landing

- Add nav item **"① Overview"** (or "Start here") as the first nav entry.
- Router: `#/` and `#/overview` → `renderOverview()`. `location.hash || "#/overview"`.
  Demo/Explore/Stack unchanged at their hashes.

### 4. Cockpit intuitiveness fixes

| # | Fix | File(s) |
|---|---|---|
| **F1** | Remove the global persona buttons from **Demo**. Show caller identity as a **badge per call row** (`identity` field). Persona switcher stays in Explore. Removes the "401 next to highlighted Olivia" confusion. | `app.js` (renderDemo/runDemoStep) |
| **F2** | Stepper shows plain `headline` + number; `tag` becomes a small sub-caption. Stepper pattern (U3) kept. | `app.js`, `styles.css` |
| **F3** | Demo step header renders `headline` + `proves`, not the raw `narration`. | `app.js` |
| **F4** | Call rows lead with **outcome + why** (`verdictLabel` + `why`); the "expected/got" match is kept but **de-emphasized** as a small "✓ matches expected · live call" trust chip. | `app.js`, `styles.css` |
| **F5** | Compact, always-visible **verdict legend** in Demo (shared `content.legend`). | `app.js`, `styles.css` |
| **F6** | Customer-facing verdict label sourced from `scenarios.js` `verdictLabel` per call; classifier enum (`res.verdict.verdict`) used only for the live-match check, never shown as the headline. Respects U8. | `app.js`, `scenarios.js` |

`trace.js` `renderPanel` still renders the hybrid trace (U2) and the internal
`verdictHeadline`; F4/F6 add the customer-facing framing *around* it — the trace stays as
the "under the hood" detail.

## Files touched

| File | Change |
|---|---|
| `demo-ui/scenarios.js` | + `headline`, `proves` per scene; + `identity`, `verdictLabel`, `why` per call |
| `demo-ui/public/content.js` | **new** — personas, matrix, legend (client ESM) |
| `demo-ui/public/overview.js` | **new** — Overview view renderer |
| `demo-ui/public/app.js` | route + default to Overview; F1–F6 in Demo |
| `demo-ui/public/index.html` | + Overview nav item |
| `demo-ui/public/styles.css` | persona cards, matrix, legend, badge, sub-caption, trust chip |
| `demo-ui/verdict.test.js` | unchanged (classifier untouched); add a small unit check that every scene/call has the new copy fields |
| `claude/DECISIONS.md` | append U10 (Overview default), U11 (scenarios.js = copy SSoT) |
| `ARCHITECTURE.md`, `README.md`, `NOTES.md`, handoff | sync to the new view + fields |

## Verification — Playwright (thorough)

Live stack required (`docker compose up` + `deck ... sync`). Cockpit at
`http://127.0.0.1:4000`. Driven with the Playwright MCP browser tools.

**A. Static / render checks**
1. Load `#/` → **Overview renders by default**; nav "Overview" is `.on`.
2. Overview shows 3 persona cards, the 4-row matrix, 7 step blocks, and the legend.
   Assert persona group chips = `dealers/finance/ops`; matrix ✓/✕ pattern matches the
   ground-truth table above (snapshot the table, compare cells).
3. No internal "things the cockpit gets wrong" text present (customer-safe).

**B. Demo mode — every step, live**
For each of the 7 steps: click the step, click **Run step**, wait for results, and assert:
- The **identity badge** on each call row matches `identity` (esp. Step 1 call 1 = `no-token`,
  not a persona).
- The customer-facing **verdictLabel** shown matches the scene data (Step 1 call 3 shows
  "403 · REST scope/audience gate", **not** "acl-deny").
- The live **classifier verdict** (`got`) equals `call.expect.verdict` (the trust chip is
  present → live call matched the script). This is the real end-to-end assertion.
- The **hybrid trace** still renders (U2 intact); Step 4 shows token BEFORE/AFTER (exchange).
- **No persona buttons** exist in Demo (F1).
Capture a screenshot per step for the handoff.

**C. Explore mode**
- Persona switcher present and functional; run one call (olivia → `/mcp/ops`
  `list_invoices`) → allow; run frank → `list_dealer_customers` → deny. Assert verdicts.

**D. Stack mode**
- Status tiles render; dashboard link resolves. (Execute actions host-only per U9 — assert
  the in-container note if applicable.)

**E. Console hygiene**
- `browser_console_messages` shows no errors on any route.

**Pass bar:** all of A–E green, all 7 Demo steps' live `got` == `expect`, screenshots
captured. Any red is a real defect — fix and re-run, no claiming done on assertion alone.

## Rollout

Rebuild the changed service with `--no-cache` before test (project rule D7 / `scripts/rebuild.sh`),
or run host-side via `scripts/ui.sh` for faster iteration during dev; final verification runs
against the containerized service.
