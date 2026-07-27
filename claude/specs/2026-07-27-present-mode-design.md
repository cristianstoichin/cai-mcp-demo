# Design — "Present" mode: self-driven tell-show-tell walkthrough

**Date:** 2026-07-27
**Status:** Approved (brainstorm)
**Surface:** demo-ui cockpit

## Problem

The cockpit's **Demo** mode runs a scene's calls all at once and reveals the "why" after — good
for a quick run, but not a presenter/self-driven walkthrough. There's no paced **tell → show →
tell** experience an SE (or a customer clicking solo) can step through scene by scene.

## Goal

A new **Present** cockpit tab: click ▶ Run on a scene and advance, one **Next ▸** click at a time,
through an opening Tell → the live calls (one per click) → a closing Tell, then hop to the next scene.
Presenter-driven pacing, real calls, honest verdicts — the same live engine as Demo, narrated.

## Decisions (from brainstorm)

| Decision | Choice |
|----------|--------|
| Pacing | **Manual Next** (presenter-driven) — no auto-play/timers |
| Show reveal | **One call per Next** (land each verdict individually) |
| Placement | **New 5th mode** `Present`; Demo stays unchanged (quick run-all) |
| Tell copy | **Authored via the `kong-demo-scenes` skill** (SE-canonical tell-show-tell), stored in `scenarios.js` |

Nav becomes: `Overview · Demo · Present · Explore · Stack`.

## Architecture

- **`demo-ui/public/present.js` (new, ES module)** — owns the Present view + a per-scene phase state
  machine. Imports the existing render helpers from `trace.js`
  (`renderPanel`, `verdictKind`, `identityBadge`, `verdictChip`) and the API client from `app.js`
  (or a shared module) — **no duplication** of call-execution or verdict logic.
- **`demo-ui/public/app.js`** — adds the `#/present` route (in `route()`), a `setNav("present")`
  case, and imports `renderPresent` from `present.js`. The API client (`api.mcp`,
  `api.exchangePreview`, `api.registry`) and `SCENARIOS`/`content` globals are shared.
- **`demo-ui/scenarios.js`** — each of the 7 scene objects gains two string fields, `setup` and
  `takeaway`. Additive and non-breaking: Demo and Overview never read them.
- **`demo-ui/public/index.html`** — add the `Present` navitem between Demo and Explore.
- **`demo-ui/public/styles.css`** — Tell card, Show-rows container, Next button, phase indicator.

The story stays single-sourced in `scenarios.js`; Present is a second *renderer* of the same data,
exactly as Overview and Demo already are.

## Interaction model — the phase state machine

Present state (module-local): `{ sceneIdx, phase }` where `phase` walks:

```
"tell-open"  ──Next──▸  "show:0"  ──Next──▸  "show:1"  ──Next──▸ … ──Next──▸  "show:N-1"
             ──Next──▸  "tell-close"  ──Next scene──▸  (sceneIdx+1, "tell-open")
```

- `▶ Run` on a scene enters `tell-open`.
- **tell-open** — renders the scene's `setup` Tell as a card, with `Proves: {proves}` as a sub-line.
  Button: **Next ▸**.
- **show:i** — fires call `i` live (`api.mcp(payload)`, plus `api.exchangePreview` when
  `sc.showExchange && expect==="allow"`, and `api.registry()` for `kind==="registry"` calls —
  identical to Demo's `runDemoStep`). Renders that one call's row via the shared helpers
  (`identityBadge` → `verdictChip` → trust line → `renderPanel`). Prior calls in the scene stay
  visible above it (cumulative reveal). Button: **Next ▸** (label **Next ▸ takeaway** on the last call).
- **tell-close** — renders the `takeaway` Tell + transition. Button: **Next scene ▸**
  (on the final scene: **Restart ▸** back to scene 0 / tell-open).
- The top **stepper** (7-scene rail, reused from Demo markup) marks done/current and lets you jump to
  any scene (resets that scene to `tell-open`). A small **phase indicator** shows `tell · show i/N · tell`.

### Call payload (unchanged from Demo)

```js
const payload = { persona: call.persona ?? null, scope: call.scope,
  path: call.path, method: call.method, tool: call.tool, args: call.args };
const res = await api.mcp(payload);   // same endpoint, same verdict classifier
```

Verdict display uses `verdictKind(call.expect.verdict, !!sc.showExchange)` + `call.verdictLabel`
(U6/U8/U11 rules preserved: customer sees `verdictLabel`, `got` only drives the live-match trust chip).

## Data model — new per-scene fields

```js
// scenarios.js — added to each of the 7 scene objects (authored via kong-demo-scenes):
setup:    "Opening Tell — the context and why it matters (1–2 sentences).",
takeaway: "Closing Tell — the so-what plus a one-line transition to the next scene.",
// unchanged: id, n, title, tag, railLabel, headline, proves, why, narration, showExchange?, calls[]
```

## Content authoring

The 7 `setup` + `takeaway` strings are authored with the **`kong-demo-scenes`** skill in the SE org's
tell-show-tell voice, then written into `scenarios.js`. Existing `headline`/`proves`/`why` are retained
for Demo + Overview. Scene titles/order are fixed (the current 7 scenes).

## Testing

`demo-ui/copy-and-render.test.js` (Node test runner, already present) gains:
- Every scene has non-empty `setup` and `takeaway` strings.
- Present's computed phase sequence for each scene equals `["tell-open", ...N×"show", "tell-close"]`
  where `N === scene.calls.length` (a pure function `phaseSequence(scene)` in `present.js`, exported
  for the test — keeps the state machine unit-testable without a browser).
- No regression: existing verdict + copy/render tests still pass (16/16 today).

Live check: rebuild demo-ui **no-cache** (`scripts/rebuild.sh demo-ui`), open `#/present`, step one
scene end-to-end (Playwright or manual) — Tell → each call reveals on Next → takeaway → next scene.

## Non-goals

- Demo, Explore, Stack, Overview, Kong config, call/verdict logic — **unchanged**.
- No auto-play, timers, or narration audio (manual Next was chosen).
- No new backend endpoints — Present uses the existing `/api/mcp`, `/api/exchange-preview`,
  `/api/registry`.

## Verification

- `cd demo-ui && npm test` green (new coverage + existing 16).
- `scripts/smoke-test.sh --static` still green (tool-coverage guard unaffected).
- `scripts/rebuild.sh demo-ui` (no-cache per D7), then drive `#/present` live.
