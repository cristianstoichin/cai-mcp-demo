# Present Mode — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a 5th cockpit tab, **Present** — a self-driven tell-show-tell walkthrough where ▶ Run enters a scene and a single **Next ▸** advances tell-open → each live call (one per click) → tell-close → next scene.

**Architecture:** New `demo-ui/public/present.js` ES module renders from the same `scenarios.js` as Demo/Overview and reuses `trace.js` renderers + the `api` client passed in by `app.js`. A pure `phaseSequence(scene)` is unit-tested under node. `scenarios.js` gains `setup`/`takeaway` per scene (authored via `kong-demo-scenes`). Demo mode is untouched.

**Tech Stack:** Vanilla ESM (no build), Node test runner (`node --test`), Docker Compose (demo-ui image), Playwright for the live drive.

## Global Constraints

- **Node-testable modules use RELATIVE imports** (`import … from "./trace.js"`), not `/trace.js` — this is how `overview.js` loads under both browser (served from `/`) and `node --test`. `present.js` MUST use `./trace.js`.
- **No new backend endpoints** — Present uses existing `/api/mcp`, `/api/exchange-preview`, `/api/registry`.
- **Demo/Explore/Stack/Overview, Kong config, call/verdict logic: unchanged.** `scenarios.js` additions are non-breaking (Demo/Overview ignore new fields).
- **Verdict display rules preserved (U6/U8/U11):** customer sees `verdictLabel`; `got` only drives the live-match trust chip; `verdictKind(expect, showExchange)` sets the color.
- **Rebuild demo-ui with `scripts/rebuild.sh demo-ui` (`--no-cache`, D7)** before any live check — `scenarios.js`/`present.js` are baked into the image (no bind-mount).
- The 7 scenes (fixed order/ids): `oidc`(1), `convert`(2), `acl`(3), `exchange`(4), `opa`(5), `remote`(6), `registry`(7).
- Commit messages: Conventional Commits; footer `Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>`.

---

## File Structure

| File | Responsibility |
|------|----------------|
| `demo-ui/public/trace.js` (modify) | Add shared `renderCallRow(sc, call, res, exchange)` (extracted from Demo's inline markup; single source for both Demo + Present) |
| `demo-ui/public/present.js` (create) | Present view + per-scene phase state machine; pure `phaseSequence()`; reuses `trace.js` (incl. `renderCallRow`) + injected `api` |
| `demo-ui/scenarios.js` (modify) | Add `setup` + `takeaway` string to each of the 7 scene objects |
| `demo-ui/public/app.js` (modify) | Refactor `runDemoStep` to use `renderCallRow`; import `renderPresent`; add `#/present` route + `setNav("present")` |
| `demo-ui/public/index.html` (modify) | Add the `Present` navitem between Demo and Explore |
| `demo-ui/public/styles.css` (modify) | `.tellcard`, `.telltext`, `.takeaway`, `.pphase`, `.showrows` |
| `demo-ui/copy-and-render.test.js` (modify) | Assert `setup`/`takeaway` present; assert `phaseSequence` shape |
| `claude/DECISIONS.md`, `claude/handoff/shipped-log.md`, `README.md` (modify) | Record decision + ship + nav mention |

---

## Task 1: `phaseSequence()` pure function + unit test

**Files:**
- Create: `demo-ui/public/present.js` (only the pure function + import for now)
- Modify: `demo-ui/copy-and-render.test.js`

**Interfaces:**
- Produces: `phaseSequence(scene) -> string[]` = `["tell-open", "show:0", …, "show:N-1", "tell-close"]` where `N = scene.calls.length`.

- [ ] **Step 1: Write the failing test**

Add to `demo-ui/copy-and-render.test.js` (after the existing imports, add the import; add the test at the end):

```js
import { phaseSequence } from "./public/present.js";

test("phaseSequence = tell-open + one show per call + tell-close", () => {
  for (const s of scenarios) {
    const seq = phaseSequence(s);
    assert.equal(seq[0], "tell-open", `${s.id} starts tell-open`);
    assert.equal(seq[seq.length - 1], "tell-close", `${s.id} ends tell-close`);
    assert.equal(seq.length, s.calls.length + 2, `${s.id} length`);
    assert.equal(seq.filter(p => p.startsWith("show:")).length, s.calls.length, `${s.id} show count`);
    assert.deepEqual(seq.slice(1, -1), s.calls.map((_, i) => `show:${i}`), `${s.id} show order`);
  }
});
```

- [ ] **Step 2: Run it to verify it fails**

Run: `cd demo-ui && node --test copy-and-render.test.js 2>&1 | tail -5`
Expected: FAIL — `Cannot find module './public/present.js'` (file doesn't exist yet).

- [ ] **Step 3: Create `present.js` with the import + pure function**

Create `demo-ui/public/present.js`:

```js
// present.js — Present mode: self-driven tell-show-tell walkthrough (manual Next).
// Renders from the SAME scenarios.js as Demo/Overview; reuses trace.js renderers and
// the api client injected by app.js. Pure phaseSequence() is unit-tested under node.
// (Task 4 adds `import { renderCallRow } from "./trace.js";` when the view is added —
// relative import so this loads under both the browser (served from /) and node --test.)

// Pure: the ordered phases for a scene. Exported for unit tests.
export function phaseSequence(scene) {
  return ["tell-open", ...scene.calls.map((_, i) => `show:${i}`), "tell-close"];
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `cd demo-ui && node --test copy-and-render.test.js 2>&1 | tail -5`
Expected: all tests pass (the new one + the existing suite).

- [ ] **Step 5: Commit**

```bash
git add demo-ui/public/present.js demo-ui/copy-and-render.test.js
git commit -m "feat(demo-ui): phaseSequence() for Present-mode state machine + test

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 2: Scene `setup`/`takeaway` copy (tell-show-tell) + presence test

**Files:**
- Modify: `demo-ui/scenarios.js` (add `setup` + `takeaway` to each of 7 scenes)
- Modify: `demo-ui/copy-and-render.test.js`

**Interfaces:**
- Produces: every scene object has non-empty `setup` (opening Tell) and `takeaway` (closing Tell + transition) strings. Present (Task 3) consumes them.

- [ ] **Step 1: Write the failing test**

Add to `demo-ui/copy-and-render.test.js`:

```js
test("every scene has Present-mode tell-show-tell copy", () => {
  for (const s of scenarios) {
    assert.equal(typeof s.setup, "string", `${s.id} setup is a string`);
    assert.ok(s.setup.trim().length > 0, `${s.id} setup non-empty`);
    assert.equal(typeof s.takeaway, "string", `${s.id} takeaway is a string`);
    assert.ok(s.takeaway.trim().length > 0, `${s.id} takeaway non-empty`);
  }
});
```

- [ ] **Step 2: Run it to verify it fails**

Run: `cd demo-ui && node --test copy-and-render.test.js 2>&1 | tail -5`
Expected: FAIL — `setup is a string` assertion fails (fields absent).

- [ ] **Step 3: Author the 7 `setup`/`takeaway` pairs with the kong-demo-scenes skill**

Invoke the `kong-demo-scenes` skill to author, in the SE org's tell-show-tell voice, a 1–2 sentence
`setup` (context + why it matters) and a 1–2 sentence `takeaway` (so-what + transition to the next scene)
for each of the 7 scenes: `oidc, convert, acl, exchange, opa, remote, registry`. Insert each pair as
fields on its scene object in `demo-ui/scenarios.js`, immediately after that scene's `proves:` line.

Concrete shape + reference content to insert (refine wording via the skill; these are complete, valid
strings — not placeholders):

```js
// scene oidc (n1) — after its proves: line
    setup: "Before any MCP exists, the raw REST APIs are already locked down. We'll hit the dealer API three ways — no token, the right persona, and the wrong scope — and watch Kong's OIDC gate decide each.",
    takeaway: "Authentication and scope/audience are enforced at the edge, before a single tool is generated. Now let's turn those same APIs into MCP tools.",
// scene convert (n2)
    setup: "Kong converts each governed REST route into an MCP tool and aggregates them by tag. We'll list the tools on three endpoints and see the same APIs show up as callable MCP tools.",
    takeaway: "One REST surface, now discoverable as MCP tools — with listing open but calls still ungoverned until the next scene. Let's see who is actually allowed to call what.",
// scene acl (n3)
    setup: "Every persona gets only the tools their group allows, decided straight from the JWT groups claim — no Kong consumers in the path. Watch each persona call their own tools, and Frank get blocked on a dealer tool.",
    takeaway: "Per-identity tool authorization from a token claim, enforced at the gateway before the upstream. Next: how a tool-only token still reaches the APIs.",
// scene exchange (n4)
    setup: "An agent token carrying only mcp:use has none of the API audiences the inner gate needs. On /mcp/ops Kong performs an RFC 8693 exchange; on /mcp/dealers it doesn't. Same token, two outcomes.",
    takeaway: "Kong bridges the MCP identity to the API identity exactly where policy allows it — no broad-scope tokens handed to agents. Next: a rule the tool ACL can't express.",
// scene opa (n5)
    setup: "Some rules live in an argument, not a tool name. We'll call an allowed tool with a benign argument, then with query_status=overdue, and let external OPA make the call.",
    takeaway: "Argument-level policy as code, hot-reloaded with no Kong sync — governance the ACL alone can't reach. Next: governing MCP servers Kong didn't build.",
// scene remote (n6)
    setup: "Kong can front MCP servers it never converted — one you own and a third-party one you don't. We'll hit a passthrough remote unauthenticated, then authenticated.",
    takeaway: "The same OAuth + governance wraps remote MCP servers, including third-party ones — one control plane over all of it. Finally, how clients discover these servers.",
// scene registry (n7)
    setup: "Every governed server is published to the Konnect MCP Registry so any client can discover it by its canonical URL. We'll list what's discoverable right now.",
    takeaway: "Discovery, governance, and analytics for MCP in one place — the full Cox governed-MCP story, end to end.",
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `cd demo-ui && node --test copy-and-render.test.js 2>&1 | tail -5`
Expected: all pass, including "every scene has Present-mode tell-show-tell copy".

- [ ] **Step 5: Commit**

```bash
git add demo-ui/scenarios.js demo-ui/copy-and-render.test.js
git commit -m "feat(demo-ui): tell-show-tell setup/takeaway copy per scene (Present mode)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 3: Extract `renderCallRow()` into trace.js; refactor Demo to use it

**Files:**
- Modify: `demo-ui/public/trace.js` (add `renderCallRow`)
- Modify: `demo-ui/public/app.js` (import it; use it in `runDemoStep`)

**Interfaces:**
- Produces: `renderCallRow(sc, call, res, exchange) -> string` — the call-row tile markup (identity badge, verdict chip, live-match trust line, optional note, `renderPanel`). Consumed by Demo (Task 3) and Present (Task 4). Behavior-preserving: identical HTML to Demo's current inline block.

- [ ] **Step 1: Add `renderCallRow` to trace.js**

Append to `demo-ui/public/trace.js` (it already exports `identityBadge`, `verdictChip`, `verdictKind`, `renderPanel`):

```js
// Shared call-row tile for Demo + Present. `res` is the /api/mcp response; `exchange`
// is the optional exchange-preview (or null). Customer sees verdictLabel (U8/U11);
// `got` only drives the live-match trust chip.
export function renderCallRow(sc, call, res, exchange) {
  const kind = verdictKind(call.expect.verdict, !!sc.showExchange);
  const got = res.verdict.verdict, match = got === call.expect.verdict;
  return `
    <div class="tile" style="margin-top:10px">
      <div class="callhead">${identityBadge(call.identity)}<span class="calltxt">${call.label}</span>${verdictChip(call.verdictLabel, kind)}</div>
      <div class="trust ${match ? "ok" : "bad"}">${match
        ? "✓ matches expected · live call"
        : `✗ live call returned <code>${got}</code>, expected <code>${call.expect.verdict}</code>`}</div>
      ${call.note ? `<p class="callnote">${call.note}</p>` : ""}
      ${renderPanel({ ...res, exchange, showExchange: sc.showExchange })}
    </div>`;
}
```

- [ ] **Step 2: Import it in app.js**

In `demo-ui/public/app.js` line 2, add `renderCallRow` to the trace import:

```js
import { renderPanel, identityBadge, verdictChip, verdictKind, renderCallRow } from "/trace.js";
```

- [ ] **Step 3: Use it in `runDemoStep` (replace the inline block)**

In `runDemoStep` (app.js ~lines 76–91), replace the inline `kind`/`got`/`match`/`blocks.push(\`…\`)` block with:

```js
    const exchange = (sc.showExchange && persona && call.expect.verdict === "allow")
      ? await api.exchangePreview(persona) : null;
    blocks.push(renderCallRow(sc, call, res, exchange));
```

Remove the now-dead lines that computed `exchange` earlier in the loop and the old `kind`/`got`/`match` locals + the inline `blocks.push` template, so the loop keeps: registry short-circuit → build `payload` → `res = await api.mcp(payload)` → the two lines above.

- [ ] **Step 4: Verify Demo unchanged (tests + node import)**

Run: `cd demo-ui && node --test copy-and-render.test.js 2>&1 | tail -5`
Expected: all pass (trace.js still imports cleanly; no test asserts the inline form).

- [ ] **Step 5: Commit**

```bash
git add demo-ui/public/trace.js demo-ui/public/app.js
git commit -m "refactor(demo-ui): extract renderCallRow() to trace.js (shared Demo/Present)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 4: Present view + phase state machine

**Files:**
- Modify: `demo-ui/public/present.js` (add the view + machine below the pure function)

**Interfaces:**
- Consumes: `phaseSequence` (Task 1), scene `setup`/`takeaway` (Task 2), `trace.js` helpers incl. `renderCallRow` (Task 3), injected `ctx = { view, scenarios, api }`.
- Produces: `renderPresent(ctx)` — entrypoint app.js calls on `#/present`. Module-local state `ps = { sceneIdx, pi }` + `revealed[]`.

- [ ] **Step 1: Append the view + state machine to `present.js`**

First add the trace import at the **top** of `demo-ui/public/present.js` (below the header comment, above `phaseSequence`):

```js
import { renderCallRow } from "./trace.js";
```

Then append the view + state machine:

```js
let ctx = null;                     // { view, scenarios, api }
const ps = { sceneIdx: 0, pi: 0 }; // pi = index into phaseSequence(current scene)
let revealed = [];                 // accumulated call-row HTML for the current scene

// Entrypoint: app.js calls this on the #/present route. Enters the current scene at tell-open.
export function renderPresent(context) {
  ctx = context;
  ps.pi = 0;
  revealed = [];
  draw();
}

function scene()  { return ctx.scenarios[ps.sceneIdx]; }
function phases() { return phaseSequence(scene()); }
function phase()  { return phases()[ps.pi]; }

function stepperHTML() {
  return `<div class="stepper">${ctx.scenarios.map((s, i) =>
    `<button class="step ${i < ps.sceneIdx ? "done" : ""} ${i === ps.sceneIdx ? "cur" : ""}" data-i="${i}">
       <span class="n">${s.n}</span><span class="srail">${s.railLabel}</span></button>`).join("")}</div>`;
}

function phaseIndicatorHTML() {
  const seq = phases(), p = phase();
  const showN = seq.filter(x => x.startsWith("show:")).length;
  let label = p === "tell-open" ? "Tell · setup"
            : p === "tell-close" ? "Tell · takeaway"
            : `Show · ${(+p.split(":")[1]) + 1}/${showN}`;
  return `<div class="pphase">${label}</div>`;
}

function draw() {
  const sc = scene(), p = phase();
  let bodyHTML, btnLabel;
  if (p === "tell-open") {
    bodyHTML = `<div class="tellcard"><p class="telltext">${sc.setup}</p>
                <p class="sproves"><b>Proves:</b> ${sc.proves}</p></div>`;
    btnLabel = "Next ▸";
  } else if (p === "tell-close") {
    bodyHTML = `<div class="tellcard takeaway"><p class="telltext">${sc.takeaway}</p></div>`;
    btnLabel = ps.sceneIdx < ctx.scenarios.length - 1 ? "Next scene ▸" : "↺ Restart";
  } else {
    const i = +p.split(":")[1];
    bodyHTML = `<div class="showrows">${revealed.join("")}</div>`;
    btnLabel = i === sc.calls.length - 1 ? "Next ▸ takeaway" : "Next ▸";
  }
  ctx.view.innerHTML = `
    ${stepperHTML()}
    <div class="content2">
      <div class="row">
        <div class="stephead"><strong>Scene ${sc.n}/7 · ${sc.headline}</strong></div>
        ${phaseIndicatorHTML()}
      </div>
      ${bodyHTML}
      <div class="row"><button class="runbtn" id="pnext">${btnLabel}</button></div>
    </div>`;
  ctx.view.querySelectorAll(".step").forEach(b => b.onclick = () => {
    ps.sceneIdx = +b.dataset.i; ps.pi = 0; revealed = []; draw();
  });
  ctx.view.querySelector("#pnext").onclick = onNext;
}

async function onNext() {
  const sc = scene(), seq = phases(), p = phase();
  if (p === "tell-close") {                 // hop to next scene (or restart from 0)
    ps.sceneIdx = ps.sceneIdx < ctx.scenarios.length - 1 ? ps.sceneIdx + 1 : 0;
    ps.pi = 0; revealed = [];
    return draw();
  }
  ps.pi += 1;
  const np = seq[ps.pi];
  if (np && np.startsWith("show:")) {
    await revealCall(sc, sc.calls[+np.split(":")[1]]);
  }
  draw();
}

// Fire one call live and append its row. Same payload + row markup as Demo's runDemoStep.
async function revealCall(sc, call) {
  const btn = ctx.view.querySelector("#pnext");
  if (btn) { btn.disabled = true; btn.textContent = "Running…"; }
  if (call.kind === "registry") {
    revealed.push(registryRow(await ctx.api.registry()));
    return;
  }
  const persona = call.persona === undefined ? null : call.persona;
  const payload = { persona, scope: call.scope, path: call.path,
    method: call.method, tool: call.tool, args: call.args };
  const res = await ctx.api.mcp(payload);
  const exchange = (sc.showExchange && persona && call.expect.verdict === "allow")
    ? await ctx.api.exchangePreview(persona) : null;
  revealed.push(renderCallRow(sc, call, res, exchange));   // shared with Demo (Task 3)
}

function registryRow(r) {
  if (!r.configured) return `<div class="tile" style="margin-top:10px">Registry not configured — run <code>scripts/registry-setup.sh</code>.</div>`;
  const rows = r.servers.map(s => `<div class="kv"><span class="k">${s.name}</span> → <span class="p">${s.url}</span></div>`).join("");
  return `<div class="tile" style="margin-top:10px"><div class="callhead"><span class="calltxt">Konnect MCP Registry — discoverable servers</span></div>${rows}</div>`;
}
```

- [ ] **Step 2: Verify node still imports the module cleanly (no top-level DOM)**

Run: `cd demo-ui && node --test copy-and-render.test.js 2>&1 | tail -5`
Expected: all pass (import of the enlarged `present.js` still succeeds under node; all logic is inside functions).

- [ ] **Step 3: Commit**

```bash
git add demo-ui/public/present.js
git commit -m "feat(demo-ui): Present view + tell-show-tell phase state machine

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 5: Wire the route, nav item, and styles

**Files:**
- Modify: `demo-ui/public/app.js` (import + route + setNav)
- Modify: `demo-ui/public/index.html` (navitem)
- Modify: `demo-ui/public/styles.css` (Present-specific styles)

**Interfaces:**
- Consumes: `renderPresent` (Task 4). Produces: `#/present` reachable and styled.

- [ ] **Step 1: Import `renderPresent` in app.js**

In `demo-ui/public/app.js`, change the overview import line (line 3) region to also import present:

```js
import { renderOverview } from "/overview.js";
import { renderPresent } from "/present.js";
```

- [ ] **Step 2: Add the `#/present` route**

In `app.js` `route()` (currently lines 189–196), add the present branch after the demo branch:

```js
function route() {
  const h = location.hash || "#/overview";
  if (h.startsWith("#/demo")) return renderDemo();
  if (h.startsWith("#/present")) { setNav("present"); return renderPresent({ view, scenarios: SCENARIOS, api }); }
  if (h.startsWith("#/explore")) return renderExplore();
  if (h.startsWith("#/stack")) return renderStack();
  setNav("overview");                          // #/ and #/overview
  return renderOverview(SCENARIOS, content);
}
```

- [ ] **Step 3: Add the nav item**

In `demo-ui/public/index.html`, add the Present navitem between Demo (line 19) and Explore (line 20):

```html
        <a class="navitem" href="#/demo" data-mode="demo">▷ Demo</a>
        <a class="navitem" href="#/present" data-mode="present">▸ Present</a>
        <a class="navitem" href="#/explore" data-mode="explore">⌕ Explore</a>
```

- [ ] **Step 4: Add Present styles**

Append to `demo-ui/public/styles.css`:

```css
/* Present mode — tell-show-tell walkthrough */
.pphase { font-size: 12px; color: var(--muted); letter-spacing: .04em; text-transform: uppercase; }
.tellcard { background: var(--panel, #12161c); border: 1px solid var(--line, #2a3038);
  border-radius: 10px; padding: 16px 18px; margin: 12px 0; }
.tellcard.takeaway { border-left: 3px solid var(--accent, #22c55e); }
.telltext { font-size: 16px; line-height: 1.5; margin: 0 0 8px; }
.showrows { min-height: 40px; }
```

(If any `var(--…)` token is undefined in the file, substitute the literal value the file already uses for panels/lines/accent — match the existing palette.)

- [ ] **Step 5: Rebuild demo-ui no-cache and smoke the route**

Run:
```bash
scripts/rebuild.sh demo-ui
for i in $(seq 1 12); do docker compose ps demo-ui --format '{{.Status}}' | grep -qi healthy && break; sleep 3; done
curl -s http://127.0.0.1:${UI_PORT:-4000}/present.js | grep -q 'renderPresent' && echo "present.js served OK"
```
Expected: `present.js served OK` (the new module is baked into the image and served).

- [ ] **Step 6: Commit**

```bash
git add demo-ui/public/app.js demo-ui/public/index.html demo-ui/public/styles.css
git commit -m "feat(demo-ui): wire Present tab — route, nav item, styles

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 6: Live drive + docs

**Files:**
- Modify: `claude/DECISIONS.md`, `claude/handoff/shipped-log.md`, `README.md`

**Interfaces:**
- Consumes: Tasks 1–5. Produces: verified feature + recorded history.

- [ ] **Step 1: Drive `#/present` end-to-end with Playwright (one full scene)**

Using the Playwright MCP tools: navigate to `http://127.0.0.1:4000/#/present`, snapshot, click the scene-3 stepper button, then click `#pnext` repeatedly and assert the phase progression:
- tell-open shows `setup` text + `Proves:`.
- each `Next ▸` reveals one more call row (identity badge + verdict chip + trace); after the last call the button reads `Next ▸ takeaway`.
- tell-close shows `takeaway` text; button reads `Next scene ▸`.
Capture a screenshot of tell-open and of a mid-show state.

Expected: the sequence matches `phaseSequence(scene3)` = tell-open, show:0…show:5, tell-close (6 calls after the Task-earlier fixes).

- [ ] **Step 2: Full test + static suites green**

Run:
```bash
cd demo-ui && npm test 2>&1 | tail -6
cd .. && scripts/smoke-test.sh --static 2>&1 | tail -3
```
Expected: demo-ui tests all pass (existing + 2 new); smoke static still passes (tool-coverage guard unaffected).

- [ ] **Step 3: Append a DECISIONS.md row**

Append to the `claude/DECISIONS.md` table (one physical line):

```markdown
| 2026-07-27 | Add a 5th cockpit mode **Present**: self-driven tell-show-tell walkthrough (manual Next; one live call per click), reusing scenarios.js + trace.js; Demo left as the quick run-all. Scenes gain `setup`/`takeaway` copy authored via kong-demo-scenes. | Demo dumps a scene's calls at once with no presenter pacing; SEs/customers wanted a tell→show→tell they can step through. A new mode is additive/non-breaking vs. reworking tested Demo behavior; single-sourcing on scenarios.js avoids a second copy of the story. | demo-ui UX | specs/2026-07-27-present-mode-design.md, plans/2026-07-27-present-mode.md, [[U11]] |
```

- [ ] **Step 4: Append a shipped-log entry**

Append to `claude/handoff/shipped-log.md`:

```markdown
## 2026-07-27 — Present mode (tell-show-tell cockpit walkthrough)
- New 5th cockpit tab **Present**: ▶ Run enters a scene; one **Next ▸** advances tell-open → each
  live call (one per click) → tell-close → next scene. Manual, presenter/self-driven.
- `demo-ui/public/present.js` — phase state machine + pure `phaseSequence()` (unit-tested); reuses
  `trace.js` renderers + injected `api`. Demo mode unchanged; both render from `scenarios.js`.
- `scenarios.js` gained `setup`/`takeaway` per scene (tell-show-tell copy via kong-demo-scenes).
- Tests: phaseSequence shape + setup/takeaway presence. Live-driven via Playwright.
```

- [ ] **Step 5: Note the new tab in README**

In `README.md`, in the demo-ui "Four modes" section, change "Four modes" → "Five modes" and add a bullet:

```markdown
- **Present** — the same 7 scenes as a self-driven **tell-show-tell** walkthrough: ▶ Run enters a
  scene, then one **Next ▸** advances the setup Tell → each live call (one per click) → the takeaway
  Tell → the next scene. Presenter/self-paced; same live calls as Demo.
```

- [ ] **Step 6: Commit**

```bash
git add claude/DECISIONS.md claude/handoff/shipped-log.md README.md
git commit -m "docs: record Present mode (decision, ship log, README)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Final verification (after all tasks)

- [ ] `cd demo-ui && npm test` — all pass (existing 16 + phaseSequence + setup/takeaway).
- [ ] `scripts/smoke-test.sh --static` — 7/7.
- [ ] `scripts/rebuild.sh demo-ui` clean; `#/present` drives end-to-end (Playwright screenshots captured).
- [ ] Demo/Explore/Stack/Overview unchanged (spot-check `#/demo` still runs).
- [ ] Nav shows five tabs in order: Overview · Demo · Present · Explore · Stack.

## Self-review notes (author)

- **Spec coverage:** interaction model → Task 3; setup/takeaway → Task 2; nav/route/styles → Task 4; phaseSequence + tests → Task 1; live+docs → Task 5. ✔
- **Placeholders:** none — `present.js` given in full; 7 real `setup`/`takeaway` strings provided (skill refines wording). ✔
- **Type/name consistency:** `phaseSequence(scene)`, `renderPresent(ctx={view,scenarios,api})`, `ps={sceneIdx,pi}`, phase strings `tell-open|show:i|tell-close` used identically across Tasks 1/3/5. Reused helpers match `trace.js` exports (`renderPanel`, `verdictKind`, `identityBadge`, `verdictChip`). ✔
- **Node-testability:** `present.js` uses relative `./trace.js`; no top-level DOM; `phaseSequence` pure. ✔
```
