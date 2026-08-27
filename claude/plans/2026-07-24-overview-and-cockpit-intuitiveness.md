# Overview view + cockpit intuitiveness — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a customer-facing "Overview" landing view to the demo-ui cockpit and fix six intuitiveness defects, with copy fixed at its source (`scenarios.js`) and verified live via Playwright.

**Architecture:** Vanilla ESM SPA, no build step. `scenarios.js` gains customer-facing copy fields (single source of truth); a new `content.js` (client ESM, no secrets) holds personas/matrix/legend; a new `overview.js` renders the default landing view from both; `trace.js` gains pure presentation helpers; `app.js` routes to Overview by default and rewrites Demo per F1–F6. Pure string-builders are unit-tested under `node --test`; live behavior is verified with the Playwright MCP browser.

**Tech Stack:** Node 20 (built-in test runner), Express (server, unchanged), vanilla ESM + plain CSS (client), Playwright MCP (verification).

## Global Constraints

- **Spec:** `claude/specs/2026-07-24-overview-and-cockpit-intuitiveness-design.md` — this plan implements it.
- **No changes** to `verdict.js` (classifier), Kong/Keycloak/OPA config, or server routes. Reader = Cox, solo → **customer-facing copy only**, no internal gotchas / SE talking points.
- **Honor decisions:** U1 (Overview is additive to Demo/Explore/Stack), U2 (hybrid trace stays the viz hero), U3 (top stepper stays), U8 (verdict **classifier** taxonomy is coarse — untouched; only *display copy* changes; step-1 call-3 is the REST scope/audience gate, never shown as "acl-deny").
- **Source of truth:** customer-facing copy lives in `scenarios.js`; Overview and Demo both render from it. No duplicated scene prose.
- **Verified ground truth** (against `kong/konnect.yaml`, do not alter): personas Dana=`dana.dealer`/`dealers`, Frank=`frank.finance`/`finance`, Olivia=`olivia.ops`/`ops`; tool allow-lists `list_dealer_customers`+`list_dealer_vehicles`=`[dealers,ops]`, `list_invoices`=`[finance,ops]`, `list_floorplans`=`[finance]`.
- **Tests:** `cd demo-ui && npm test` runs `node --test` (discovers `*.test.js`). New pure/data tests go in `demo-ui/copy-and-render.test.js`.
- **Rebuild before live test:** `scripts/rebuild.sh demo-ui` (`docker compose build --no-cache`) per rule D7; or iterate host-side with `scripts/ui.sh`. Final verification runs against the served cockpit at `http://127.0.0.1:4000`.
- **Commit style:** Conventional Commits, scope `demo-ui`. End messages with `Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>`.

---

## File Structure

| File | Responsibility |
|---|---|
| `demo-ui/scenarios.js` | (modify) + `headline`, `proves`, `why`, `railLabel` per scene; + `identity`, `verdictLabel` per call |
| `demo-ui/public/content.js` | (new) client ESM: `personas`, `matrix`, `legend` — non-sensitive static copy |
| `demo-ui/public/trace.js` | (modify) + pure helpers `identityBadge`, `verdictKind`, `verdictChip` |
| `demo-ui/public/overview.js` | (new) `overviewHTML(scenarios, content)` pure builder + `renderOverview()` DOM attach |
| `demo-ui/public/app.js` | (modify) default route → Overview; Demo rewrite F1–F6 |
| `demo-ui/public/index.html` | (modify) + Overview nav item |
| `demo-ui/public/styles.css` | (modify) persona cards, matrix, legend, identity badge, rail sub-label, trust chip |
| `demo-ui/copy-and-render.test.js` | (new) node --test: scenarios copy integrity, content integrity, pure helpers, overviewHTML sections |
| `claude/DECISIONS.md` | (modify) append U10 (Overview default), U11 (scenarios.js = copy SSoT) |
| `ARCHITECTURE.md`, `README.md`, `NOTES.md`, `claude/handoff/state.md`, `claude/NEXT-SESSION.md` | (modify) sync to the new view + fields |

---

## Task 1: Enrich `scenarios.js` with customer-facing copy

**Files:**
- Modify: `demo-ui/scenarios.js`
- Test: `demo-ui/copy-and-render.test.js`

**Interfaces:**
- Produces: each `scenarios[i]` has string `headline`, `proves`, `why`, `railLabel`; each `calls[j]` has string `identity` and `verdictLabel`. All existing fields preserved.

- [ ] **Step 1: Write the failing test**

Create `demo-ui/copy-and-render.test.js`:

```js
// copy-and-render.test.js — data integrity + pure-render checks for the UI copy.
import { test } from "node:test";
import assert from "node:assert/strict";
import { scenarios } from "./scenarios.js";

test("every scene has customer-facing copy fields", () => {
  assert.equal(scenarios.length, 7);
  for (const s of scenarios) {
    for (const f of ["headline", "proves", "why", "railLabel"]) {
      assert.equal(typeof s[f], "string", `scene ${s.n} missing ${f}`);
      assert.ok(s[f].length > 0, `scene ${s.n} empty ${f}`);
    }
    for (const c of s.calls) {
      assert.equal(typeof c.identity, "string", `scene ${s.n} call missing identity`);
      assert.equal(typeof c.verdictLabel, "string", `scene ${s.n} call missing verdictLabel`);
    }
  }
});

test("step-1 call-1 is the no-token call; call-3 is the REST scope/audience gate (U8)", () => {
  const s1 = scenarios.find(s => s.n === 1);
  assert.equal(s1.calls[0].identity, "no-token");
  assert.equal(s1.calls[0].verdictLabel, "401 · no token");
  assert.equal(s1.calls[2].verdictLabel, "403 · REST scope/audience gate");
  assert.ok(!/acl-deny/i.test(s1.calls[2].verdictLabel), "must not show the raw classifier enum");
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd demo-ui && node --test copy-and-render.test.js`
Expected: FAIL — `scene 1 missing headline` (fields not added yet).

- [ ] **Step 3: Add the copy fields to `scenarios.js`**

Edit each scene object. Add the scene-level fields right after `title`, and `identity`/`verdictLabel` to each call. Full target content of `scenarios.js` `export const scenarios`:

```js
export const scenarios = [
  {
    id: "oidc", n: 1, title: "REST OIDC gates", tag: "OIDC", railLabel: "Protected APIs",
    headline: "The raw APIs are already protected",
    proves: "Authentication + per-scope authorization at the edge — before MCP exists.",
    why: "Dana's token carries dealers:read but not finance:read, so it has no finance-api audience — the finance route rejects it. That is the REST OIDC scope/audience gate, before any MCP tool exists.",
    narration: "The raw APIs are protected before any MCP. No token → 401; dana (dealers:read) → 200; dana on the finance API → 403 (scope+audience).",
    calls: [
      { label: "no-token → /api/dealers/customers", persona: null, identity: "no-token", verdictLabel: "401 · no token", kind: "rest",
        path: "/api/dealers/customers", method: "GET", expect: { verdict: "auth-fail" } },
      { label: "dana → /api/dealers/customers", persona: "dana", identity: "Dana", verdictLabel: "200 · allowed", kind: "rest",
        path: "/api/dealers/customers", method: "GET", expect: { verdict: "allow" } },
      { label: "dana → /api/finance/invoices (wrong scope+aud)", persona: "dana", identity: "Dana", verdictLabel: "403 · REST scope/audience gate", kind: "rest",
        path: "/api/finance/invoices", method: "GET", expect: { verdict: "acl-deny" },
        note: "403 from the inner OIDC gate (scope+audience), shown as a deny." },
    ],
  },
  {
    id: "convert", n: 2, title: "REST → MCP conversion", tag: "CONVERT", railLabel: "REST → MCP",
    headline: "Kong converts those APIs into MCP tools",
    proves: "REST→MCP conversion with zero rewrite of the upstream services.",
    why: "SUPERSEDED 2026-07-28 — tools/list IS ACL-filtered per identity on EE 3.14.0.2. See NOTES.md; the shipped scenarios.js carries the corrected copy.",
    narration: "SUPERSEDED — as olivia /mcp/finance returns 1 tool, not 2 (floorplans is finance-only and filtered out).",
    calls: [
      { label: "/mcp/dealers tools/list", persona: "olivia", identity: "Olivia", verdictLabel: "200 · 2 tools", kind: "mcp", path: "/mcp/dealers",
        tool: null, method: "tools/list", expect: { verdict: "allow" } },
      { label: "/mcp/finance tools/list", persona: "olivia", identity: "Olivia", verdictLabel: "200 · 2 tools", kind: "mcp", path: "/mcp/finance",
        tool: null, method: "tools/list", expect: { verdict: "allow" } },
      { label: "/mcp/ops tools/list", persona: "olivia", identity: "Olivia", verdictLabel: "200 · 2 bundled", kind: "mcp", path: "/mcp/ops",
        tool: null, method: "tools/list", expect: { verdict: "allow" } },
    ],
  },
  {
    id: "acl", n: 3, title: "Persona tool ACL", tag: "ACL", railLabel: "Per-user tools",
    headline: "Each person only gets the tools their group allows",
    proves: "Per-identity tool authorization straight from a JWT groups claim.",
    why: "Frank's groups:[finance] is not in that tool's allow-list [dealers, ops] — blocked at the gateway, never reaches the API.",
    narration: "Filtering by the token's groups claim (no Kong consumers). olivia (ops) may call list_invoices; frank (finance) may NOT call a dealer tool.",
    calls: [
      { label: "olivia → list_invoices @ /mcp/ops", persona: "olivia", identity: "Olivia", verdictLabel: "200 · allowed", kind: "mcp",
        path: "/mcp/ops", tool: "list_invoices", args: {}, expect: { verdict: "allow" } },
      { label: "frank → list_dealer_customers @ /mcp/ops", persona: "frank", identity: "Frank", verdictLabel: "403 · tool ACL — group not allowed", kind: "mcp",
        path: "/mcp/ops", tool: "list_dealer_customers", args: {}, expect: { verdict: "acl-deny" } },
    ],
  },
  {
    id: "exchange", n: 4, title: "RFC 8693 token exchange", tag: "EXCHANGE", railLabel: "Token exchange",
    showExchange: true,
    headline: "Kong exchanges a narrow token so the call can reach the API",
    proves: "RFC 8693 token exchange — the client never holds API credentials; Kong bridges trust.",
    why: "Same token, two routes. On /mcp/ops Kong swaps the audience to [dealer-api, finance-api] so the inner gate passes; on /mcp/dealers there is no exchange, so the inner gate 403s.",
    narration: "A token with ONLY 'mcp:use' lacks the dealer-api/finance-api audiences the inner gates need. On /mcp/ops Kong exchanges it so the call reaches the API; on /mcp/dealers it can't.",
    calls: [
      { label: "mcp:use-only olivia → /mcp/ops list_dealer_customers", persona: "olivia", identity: "Olivia", verdictLabel: "exchanged → 200",
        scope: "openid mcp:use", kind: "mcp", path: "/mcp/ops", tool: "list_dealer_customers",
        args: {}, expect: { verdict: "allow" }, note: "Kong exchanges the token here." },
      { label: "mcp:use-only olivia → /mcp/dealers list_dealer_customers", persona: "olivia", identity: "Olivia", verdictLabel: "403 · no audience (not exchanged)",
        scope: "openid mcp:use", kind: "mcp", path: "/mcp/dealers", tool: "list_dealer_customers",
        args: {}, expect: { verdict: "inner-gate-deny" }, note: "No exchange here → inner-gate 403." },
    ],
  },
  {
    id: "opa", n: 5, title: "External OPA policy", tag: "OPA", railLabel: "OPA policy",
    headline: "An external policy decides on the request's arguments",
    proves: "Externalized, argument-aware policy (OPA) that hot-reloads without touching Kong.",
    why: "Olivia is fully entitled to list_invoices — but the OPA rule denies the overdue filter specifically. Edit mcp.rego and the decision changes live, with no Kong sync.",
    narration: "A rule the tool ACL cannot express: OPA denies list_invoices when the call argument query_status=overdue, even for a permitted caller. opa/policies/mcp.rego hot-reloads with no Kong sync.",
    calls: [
      { label: "olivia → list_invoices (no filter)", persona: "olivia", identity: "Olivia", verdictLabel: "200 · allowed", kind: "mcp",
        path: "/mcp/ops", tool: "list_invoices", args: {}, expect: { verdict: "allow" } },
      { label: "olivia → list_invoices query_status=overdue", persona: "olivia", identity: "Olivia", verdictLabel: "403 · OPA policy", kind: "mcp",
        path: "/mcp/ops", tool: "list_invoices", args: { query_status: "overdue" },
        expect: { verdict: "opa-deny" } },
    ],
  },
  {
    id: "remote", n: 6, title: "Passthrough remotes", tag: "REMOTE", railLabel: "Remote MCP",
    headline: "Kong governs MCP servers it didn't even build",
    proves: "One governed front door for any MCP server, including ones you don't own.",
    why: "The remote MCP servers do their own thing upstream; Kong still requires a valid cox-auto token before anything reaches them.",
    narration: "Govern MCP servers Kong did not convert. /mcp/remote → local market-mcp (Cox tools); /mcp/remote-public → DeepWiki (third-party). Both require a cox-auto token.",
    calls: [
      { label: "/mcp/remote unauth", persona: null, identity: "no-token", verdictLabel: "401 · no token", kind: "mcp", path: "/mcp/remote",
        tool: null, method: "tools/list", expect: { verdict: "auth-fail" } },
      { label: "/mcp/remote-public authed tools/list", persona: "olivia", identity: "Olivia", verdictLabel: "200 · allowed", kind: "mcp",
        path: "/mcp/remote-public", tool: null, method: "tools/list", expect: { verdict: "allow" } },
    ],
  },
  {
    id: "registry", n: 7, title: "MCP Registry discovery", tag: "REGISTRY", railLabel: "Registry",
    headline: "Every server is discoverable in the Konnect MCP Registry",
    proves: "Governed discovery — a sanctioned catalog, not ad-hoc URLs.",
    why: "dealers, finance, ops, remote (market-mcp), remote-public (DeepWiki) — each advertised at its http://localhost:8000/mcp/* address, discoverable by any host client.",
    narration: "The servers are catalogued in Konnect's MCP Registry — discoverable by any host-side client (e.g. Claude Code).",
    calls: [
      { label: "Konnect MCP Registry — discover servers", identity: "Konnect", verdictLabel: "servers listed", kind: "registry",
        expect: { verdict: "allow" } },
    ],
  },
];
```

Keep the trailing `export default scenarios;` and the file header comment.

- [ ] **Step 4: Run test to verify it passes**

Run: `cd demo-ui && node --test copy-and-render.test.js`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add demo-ui/scenarios.js demo-ui/copy-and-render.test.js
git commit -m "feat(demo-ui): add customer-facing copy fields to scenarios (SSoT, U11)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 2: `content.js` — personas, matrix, legend

**Files:**
- Create: `demo-ui/public/content.js`
- Test: `demo-ui/copy-and-render.test.js` (append)

**Interfaces:**
- Produces: `export const personas` (array of 3 `{key,name,username,role,group,scopes[],can[],cant[]}`), `export const matrix` (array of 4 `{tool,returns,allow[],dana,frank,olivia}`), `export const legend` (array of 6 `{label,kind,title,desc}`). Default export `{personas, matrix, legend}`.

- [ ] **Step 1: Write the failing test**

Append to `demo-ui/copy-and-render.test.js`:

```js
import { personas, matrix, legend } from "./public/content.js";

test("content.personas match the verified realm", () => {
  assert.equal(personas.length, 3);
  const byKey = Object.fromEntries(personas.map(p => [p.key, p]));
  assert.equal(byKey.dana.group, "dealers");
  assert.equal(byKey.frank.group, "finance");
  assert.equal(byKey.olivia.group, "ops");
  assert.deepEqual(byKey.olivia.scopes, ["dealers:read", "finance:read", "mcp:use"]);
});

test("content.matrix matches konnect.yaml allow-lists", () => {
  const byTool = Object.fromEntries(matrix.map(m => [m.tool, m]));
  assert.deepEqual(byTool.list_dealer_customers.allow, ["dealers", "ops"]);
  assert.deepEqual(byTool.list_invoices.allow, ["finance", "ops"]);
  assert.deepEqual(byTool.list_floorplans.allow, ["finance"]);
  // ✓/✕ flags must agree with the allow-lists
  for (const m of matrix) {
    assert.equal(m.dana, m.allow.includes("dealers"));
    assert.equal(m.frank, m.allow.includes("finance"));
    assert.equal(m.olivia, m.allow.includes("ops"));
  }
});

test("content.legend covers the six verdict kinds", () => {
  assert.equal(legend.length, 6);
  assert.deepEqual(legend.map(l => l.label).sort(),
    ["acl-deny", "auth-fail", "allow", "exchanged", "inner-gate", "opa-deny"].sort());
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd demo-ui && node --test copy-and-render.test.js`
Expected: FAIL — cannot find module `./public/content.js`.

- [ ] **Step 3: Create `demo-ui/public/content.js`**

```js
// content.js — customer-facing static copy for the Overview + Demo legend.
// Client ESM, NO secrets. Persona values mirror config.personas / get-token.sh;
// matrix allow-lists are verified against kong/konnect.yaml (2026-07-24).

export const personas = [
  { key: "dana", name: "Dana", username: "dana.dealer",
    role: "Dealership operations — works with customers and inventory.",
    group: "dealers", scopes: ["dealers:read", "mcp:use"],
    can: ["Dealer tools — customers, inventory"],
    cant: ["Finance tools — invoices, floor-plans"] },
  { key: "frank", name: "Frank", username: "frank.finance",
    role: "Floor-plan financing — works with dealer invoices and audits.",
    group: "finance", scopes: ["finance:read", "mcp:use"],
    can: ["Finance tools — invoices, floor-plans"],
    cant: ["Dealer tools — customers, inventory"] },
  { key: "olivia", name: "Olivia", username: "olivia.ops",
    role: "Cross-functional operations — spans dealer and finance.",
    group: "ops", scopes: ["dealers:read", "finance:read", "mcp:use"],
    can: ["Dealer + finance — customers, inventory, invoices"],
    cant: ["Floor-plans (finance-only, by design)"] },
];

export const matrix = [
  { tool: "list_dealer_customers", returns: "Dealership customers + trade-in interest",
    allow: ["dealers", "ops"], dana: true,  frank: false, olivia: true },
  { tool: "list_dealer_vehicles",  returns: "Dealer inventory — VIN, days-on-lot, vAuto rank",
    allow: ["dealers", "ops"], dana: true,  frank: false, olivia: true },
  { tool: "list_invoices",         returns: "Floor-plan invoices — dealer, amount, status",
    allow: ["finance", "ops"], dana: false, frank: true,  olivia: true },
  { tool: "list_floorplans",       returns: "Floor-plan audit status",
    allow: ["finance"],        dana: false, frank: true,  olivia: false },
];

export const legend = [
  { label: "allow",      kind: "ok",   title: "Passed every gate",   desc: "The call reached the upstream and returned data." },
  { label: "auth-fail",  kind: "auth", title: "No / invalid token",  desc: "Rejected at the door — 401, before any tool runs." },
  { label: "acl-deny",   kind: "deny", title: "Not allowed",         desc: "The token's group (or REST scope) isn't permitted here — 403." },
  { label: "opa-deny",   kind: "deny", title: "Policy said no",      desc: "OPA rejected this specific request's arguments — 403." },
  { label: "exchanged",  kind: "exch", title: "Token upgraded",      desc: "Kong swapped the token for one the API accepts, then allowed it." },
  { label: "inner-gate", kind: "deny", title: "Missing audience",    desc: "The token lacked the API audience and wasn't exchanged here — 403." },
];

export default { personas, matrix, legend };
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd demo-ui && node --test copy-and-render.test.js`
Expected: PASS (5 tests).

- [ ] **Step 5: Commit**

```bash
git add demo-ui/public/content.js demo-ui/copy-and-render.test.js
git commit -m "feat(demo-ui): add content.js (personas, matrix, legend) verified vs konnect.yaml

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 3: Pure presentation helpers in `trace.js`

**Files:**
- Modify: `demo-ui/public/trace.js`
- Test: `demo-ui/copy-and-render.test.js` (append)

**Interfaces:**
- Consumes: nothing new.
- Produces: `export function identityBadge(identity)` → HTML string; `export function verdictKind(expectVerdict, showExchange)` → one of `"ok"|"auth"|"deny"|"exch"`; `export function verdictChip(label, kind)` → HTML string. Used by `app.js` (Demo) and `overview.js`.

- [ ] **Step 1: Write the failing test**

Append to `demo-ui/copy-and-render.test.js`:

```js
import { identityBadge, verdictKind, verdictChip } from "./public/trace.js";

test("verdictKind maps expect+exchange to a color kind", () => {
  assert.equal(verdictKind("allow", false), "ok");
  assert.equal(verdictKind("allow", true), "exch");     // step 4 exchanged
  assert.equal(verdictKind("auth-fail", false), "auth");
  assert.equal(verdictKind("acl-deny", false), "deny");
  assert.equal(verdictKind("opa-deny", false), "deny");
  assert.equal(verdictKind("inner-gate-deny", false), "deny");
});

test("identityBadge renders a slugged, human badge", () => {
  const b = identityBadge("no-token");
  assert.match(b, /idb-no-token/);
  assert.match(b, /no token/);            // 'no-token' shown as 'no token'
  assert.match(identityBadge("Olivia"), /idb-olivia/);
  assert.match(identityBadge("Olivia"), />Olivia</);
});

test("verdictChip carries the kind class and the label text", () => {
  const c = verdictChip("403 · OPA policy", "deny");
  assert.match(c, /vchip vchip-deny/);
  assert.match(c, /403 · OPA policy/);
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd demo-ui && node --test copy-and-render.test.js`
Expected: FAIL — `identityBadge is not a function` (not exported yet).

- [ ] **Step 3: Add the helpers to `trace.js`**

Append these exports to `demo-ui/public/trace.js` (the file already has `esc`; reuse it):

```js
// ---- customer-facing presentation helpers (used by Demo + Overview) ----

// Map a call's expected verdict (+ whether the scene shows an exchange) to a color kind.
export function verdictKind(expectVerdict, showExchange) {
  if (expectVerdict === "allow") return showExchange ? "exch" : "ok";
  if (expectVerdict === "auth-fail") return "auth";
  return "deny"; // acl-deny, opa-deny, inner-gate-deny
}

// A small identity pill. "no-token" renders as "no token".
export function identityBadge(identity) {
  const slug = String(identity).toLowerCase().replace(/[^a-z0-9]+/g, "-");
  const text = identity === "no-token" ? "no token" : identity;
  return `<span class="idb idb-${esc(slug)}">${esc(text)}</span>`;
}

// A color-coded verdict pill showing the customer-facing label.
export function verdictChip(label, kind) {
  return `<span class="vchip vchip-${esc(kind)}">${esc(label)}</span>`;
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd demo-ui && node --test copy-and-render.test.js`
Expected: PASS (8 tests).

- [ ] **Step 5: Commit**

```bash
git add demo-ui/public/trace.js demo-ui/copy-and-render.test.js
git commit -m "feat(demo-ui): pure identity/verdict presentation helpers in trace.js

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 4: `overview.js` view + nav + default route

**Files:**
- Create: `demo-ui/public/overview.js`
- Modify: `demo-ui/public/index.html`, `demo-ui/public/app.js`
- Test: `demo-ui/copy-and-render.test.js` (append)

**Interfaces:**
- Consumes: `scenarios` (via `/api/scenarios`), `content.js` (`personas/matrix/legend`).
- Produces: `export function overviewHTML(scenarios, content)` → full HTML string; `export function renderOverview(scenarios, content)` → sets `#view` innerHTML + calls `setNav("overview")`.

- [ ] **Step 1: Write the failing test**

Append to `demo-ui/copy-and-render.test.js`:

```js
import { overviewHTML } from "./public/overview.js";
import contentDefault from "./public/content.js";

test("overviewHTML renders all sections and is customer-safe", () => {
  const html = overviewHTML(scenarios, contentDefault);
  // personas
  for (const n of ["Dana", "Frank", "Olivia"]) assert.match(html, new RegExp(n));
  // matrix tools
  for (const t of ["list_dealer_customers", "list_invoices", "list_floorplans"]) assert.match(html, new RegExp(t));
  // all 7 headlines
  for (const s of scenarios) assert.ok(html.includes(s.headline), `missing headline: ${s.headline}`);
  // legend labels
  assert.match(html, /Passed every gate/);
  // customer-safe: no internal "gets wrong" callout, no SE gotchas
  assert.ok(!/confusingly wrong|being fixed|gets wrong/i.test(html), "internal callout leaked");
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd demo-ui && node --test copy-and-render.test.js`
Expected: FAIL — cannot find module `./public/overview.js`.

- [ ] **Step 3: Create `demo-ui/public/overview.js`**

```js
// overview.js — the customer-facing "Overview / Start here" landing view.
// Pure builder (overviewHTML) + DOM attach (renderOverview). Renders from
// scenarios.js (copy SSoT) + content.js (personas/matrix/legend).
import { identityBadge, verdictChip, verdictKind } from "/trace.js";

const esc = (s) => String(s).replace(/[&<>"]/g, c => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" }[c]));
const yn = (b) => b ? `<span class="cell y">✓</span>` : `<span class="cell n">✕</span>`;

function personaCard(p) {
  return `<div class="persona persona-${esc(p.key)}">
    <div class="who"><span class="pname">${esc(p.name)}</span><span class="puid">${esc(p.username)}</span></div>
    <div class="prole">${esc(p.role)}</div>
    <div class="klabel">group / scopes</div>
    <div class="chips"><span class="chip grp">groups: ${esc(p.group)}</span>${p.scopes.map(s => `<span class="chip">${esc(s)}</span>`).join("")}</div>
    <div class="klabel">reach</div>
    <ul class="can">${p.can.map(c => `<li class="y">${esc(c)}</li>`).join("")}${p.cant.map(c => `<li class="n">${esc(c)}</li>`).join("")}</ul>
  </div>`;
}

function matrixRow(m) {
  return `<tr><td class="mtool">${esc(m.tool)}</td><td class="mdesc">${esc(m.returns)}</td>
    <td class="c">${yn(m.dana)}</td><td class="c">${yn(m.frank)}</td><td class="c">${yn(m.olivia)}</td></tr>`;
}

function sceneBlock(s) {
  const calls = s.calls.map(c =>
    `<div class="ocall"><span class="ocwho">${identityBadge(c.identity)}</span>
       <span class="octxt">${esc(c.label)}</span>
       ${verdictChip(c.verdictLabel, verdictKind(c.expect.verdict, !!s.showExchange))}</div>`).join("");
  return `<div class="scene"><div class="snum">${s.n}</div><div class="sbody">
    <div class="stitle">${esc(s.headline)}</div>
    <div class="sproves"><b>Proves:</b> ${esc(s.proves)}</div>
    <div class="ocalls">${calls}</div>
    <div class="swhy">${esc(s.why)}</div>
  </div></div>`;
}

function legendRow(l) {
  return `<div class="leg"><span class="vchip vchip-${esc(l.kind)}">${esc(l.label)}</span>
    <span class="legt"><b>${esc(l.title)}</b>${esc(l.desc)}</span></div>`;
}

export function overviewHTML(scenarios, content) {
  const { personas, matrix, legend } = content;
  return `<div class="ov">
    <p class="ov-eyebrow">Cox Automotive · Kong AI Gateway</p>
    <h1 class="ov-h1">Governed MCP — what this demo shows</h1>
    <p class="ov-lede">Kong turns Cox Automotive's REST APIs into <b>MCP servers</b> and governs every
      call — who the caller is, which tools they may use, and what policy says about the specific
      request. Three people, one gateway, seven things it proves.</p>

    <div class="ov-h2">The three people</div>
    <div class="cast">${personas.map(personaCard).join("")}</div>

    <div class="ov-h2">Who can call which tool</div>
    <div class="mscroll"><table class="mtable"><thead><tr>
      <th>MCP tool</th><th>Returns</th><th class="c">Dana</th><th class="c">Frank</th><th class="c">Olivia</th>
    </tr></thead><tbody>${matrix.map(matrixRow).join("")}</tbody></table></div>
    <p class="mnote">Enforced against the token's <code>groups</code> claim at call time —
      <b>no Kong consumers, no API keys</b>. Endpoints: <code>/mcp/dealers</code>,
      <code>/mcp/finance</code>, <code>/mcp/ops</code> (bundle; token-exchange + OPA also run here).</p>

    <div class="ov-h2">The seven steps</div>
    <div class="scenes">${scenarios.map(sceneBlock).join("")}</div>

    <div class="ov-h2">How to read a result</div>
    <div class="legend">${legend.map(legendRow).join("")}</div>
  </div>`;
}

export function renderOverview(scenarios, content) {
  const view = document.getElementById("view");
  view.innerHTML = overviewHTML(scenarios, content);
}
```

- [ ] **Step 4: Add the nav item to `index.html`**

In `demo-ui/public/index.html`, change the `<nav>` block to put Overview first:

```html
      <nav class="nav">
        <a class="navitem" href="#/overview" data-mode="overview">◉ Overview</a>
        <a class="navitem" href="#/demo" data-mode="demo">▷ Demo</a>
        <a class="navitem" href="#/explore" data-mode="explore">⌕ Explore</a>
        <a class="navitem" href="#/stack" data-mode="stack">⚙ Stack</a>
      </nav>
```

- [ ] **Step 5: Wire the router + default in `app.js`**

At the top of `demo-ui/public/app.js`, add imports (next to the existing `renderPanel` import):

```js
import { renderOverview } from "/overview.js";
import content from "/content.js";
```

Replace the `route()` function so Overview is the default landing:

```js
function route() {
  const h = location.hash || "#/overview";
  if (h.startsWith("#/demo")) return renderDemo();
  if (h.startsWith("#/explore")) return renderExplore();
  if (h.startsWith("#/stack")) return renderStack();
  return renderOverview(SCENARIOS, content);   // #/ and #/overview
}
```

- [ ] **Step 6: Run tests + smoke the route locally**

Run: `cd demo-ui && node --test copy-and-render.test.js`
Expected: PASS (9 tests).

Run (host-side quick check): `cd demo-ui && node server.js &` then
`curl -s localhost:4000/overview.js | head -1` → prints the module comment line;
`curl -s localhost:4000/ | grep -c 'data-mode="overview"'` → `1`. Kill the server.

- [ ] **Step 7: Commit**

```bash
git add demo-ui/public/overview.js demo-ui/public/index.html demo-ui/public/app.js demo-ui/copy-and-render.test.js
git commit -m "feat(demo-ui): Overview landing view, default route (U10)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 5: Demo-mode intuitiveness rewrite (F1–F6) + styles

**Files:**
- Modify: `demo-ui/public/app.js` (`renderDemo`, `runDemoStep`, remove persona state from Demo)
- Modify: `demo-ui/public/styles.css`

**Interfaces:**
- Consumes: `identityBadge`, `verdictChip`, `verdictKind` from `/trace.js`; `content.legend`; scene fields `headline/proves/railLabel/why`, call fields `identity/verdictLabel`.
- Produces: no exports; DOM behavior only (Playwright-verified in Task 7).

- [ ] **Step 1: Update imports in `app.js`**

Extend the trace import to include the new helpers:

```js
import { renderPanel, identityBadge, verdictChip, verdictKind } from "/trace.js";
```

- [ ] **Step 2: Replace `renderDemo()` (F1, F2, F3, F5)**

Replace the whole `renderDemo` function in `demo-ui/public/app.js` with:

```js
// ---------- DEMO ----------
function renderDemo() {
  setNav("demo");
  const sc = SCENARIOS[state.stepIdx];
  const steps = SCENARIOS.map((s, i) =>
    `<button class="step ${i < state.stepIdx ? "done" : ""} ${i === state.stepIdx ? "cur" : ""}" data-i="${i}">
       <span class="n">${s.n}</span><span class="srail">${s.railLabel}</span></button>`).join("");
  const legendBar = content.legend.map(l =>
    `<span class="lchip vchip vchip-${l.kind}" title="${l.title} — ${l.desc}">${l.label}</span>`).join("");
  view.innerHTML = `
    <div class="stepper">${steps}</div>
    <div class="content2">
      <div class="row">
        <div class="stephead"><strong>Step ${sc.n}/7 · ${sc.headline}</strong></div>
        <button class="runbtn" id="run">▶ Run step</button>
      </div>
      <p class="sproves"><b>Proves:</b> ${sc.proves}</p>
      <div class="legendbar">${legendBar}</div>
      <div id="result"></div>
      <p class="swhy" id="swhy" hidden>${sc.why}</p>
    </div>`;
  view.querySelectorAll(".step").forEach(b => b.onclick = () => { state.stepIdx = +b.dataset.i; renderDemo(); });
  view.querySelector("#run").onclick = () => runDemoStep(sc);
}
```

Note: the global persona buttons are **gone** from Demo (F1). `state.persona` still exists (Explore uses it) but is no longer read in Demo — every Demo call has a fixed `identity`.

- [ ] **Step 3: Replace `runDemoStep()` (F4, F6)**

Replace the whole `runDemoStep` function with:

```js
async function runDemoStep(sc) {
  const out = view.querySelector("#result");
  const whyEl = view.querySelector("#swhy");
  out.innerHTML = `<p style="color:var(--muted)">Running ${sc.calls.length} call(s)…</p>`;
  const blocks = [];
  for (const call of sc.calls) {
    if (call.kind === "registry") {
      const r = await api.registry();
      blocks.push(renderRegistryBlock(r));
      continue;
    }
    const persona = call.persona === undefined ? null : call.persona;
    const payload = { persona, scope: call.scope, path: call.path,
      method: call.method, tool: call.tool, args: call.args };
    const res = await api.mcp(payload);
    let exchange = null;
    if (sc.showExchange && persona && call.expect.verdict === "allow") {
      exchange = await api.exchangePreview(persona);
    }
    const kind = verdictKind(call.expect.verdict, !!sc.showExchange);
    const got = res.verdict.verdict;
    const match = got === call.expect.verdict;
    blocks.push(`
      <div class="tile" style="margin-top:10px">
        <div class="callhead">
          ${identityBadge(call.identity)}
          <span class="calltxt">${call.label}</span>
          ${verdictChip(call.verdictLabel, kind)}
        </div>
        <div class="trust ${match ? "ok" : "bad"}">${match
          ? "✓ matches expected · live call"
          : `✗ live call returned <code>${got}</code>, expected <code>${call.expect.verdict}</code>`}</div>
        ${call.note ? `<p class="callnote">${call.note}</p>` : ""}
        ${renderPanel({ ...res, exchange, showExchange: sc.showExchange })}
      </div>`);
  }
  out.innerHTML = blocks.join("");
  if (whyEl) whyEl.hidden = false;   // reveal the plain-language "why" after the run
}
```

- [ ] **Step 4: Add styles to `styles.css`**

Append to `demo-ui/public/styles.css`:

```css
/* ---- Demo: rail sub-label, legend bar, call outcome rows (F2/F4/F5/F6) ---- */
.srail { display:block; font-size:9.5px; line-height:1.15; margin-top:2px; }
.stephead strong { font-size:14px; }
.sproves { color: var(--muted); margin: 6px 0; }
.sproves b { color: var(--text); }
.legendbar { display:flex; gap:6px; flex-wrap:wrap; margin:8px 0 4px; }
.lchip { cursor: help; }
.callhead { display:flex; align-items:center; gap:9px; flex-wrap:wrap; }
.calltxt { font-family: var(--mono); font-size:12px; color: var(--text); flex:1; min-width:180px; }
.callnote { color: var(--muted); font-size:12px; margin:6px 0; }
.trust { font-size:11px; margin:6px 0 2px; color: var(--pass); }
.trust.bad { color: var(--deny); }
.swhy { border-left:3px solid var(--cox-blue); padding:7px 10px; margin-top:10px;
  background: color-mix(in srgb, var(--cox-blue) 10%, transparent); border-radius:4px; color: var(--text); }

/* identity badge */
.idb { display:inline-block; padding:2px 8px; border-radius:20px; font-size:11px; font-weight:700;
  border:1px solid var(--border); background: var(--panel); color: var(--text); }
.idb-no-token { color:#c9d1d9; border-style:dashed; }
.idb-dana { color:#7fb0ff; border-color:#2b4d80; }
.idb-frank { color:#3fb950; border-color:#1f5e34; }
.idb-olivia { color:#c58bff; border-color:#5a3a86; }
.idb-konnect { color:#e6a44a; border-color:#7a5a1f; }

/* verdict chip (customer-facing label) */
.vchip { display:inline-block; padding:2px 9px; border-radius:6px; font-size:11px; font-weight:700;
  font-family: var(--mono); white-space:nowrap; }
.vchip-ok   { background: color-mix(in srgb, var(--pass) 20%, transparent); color:#3fb950; }
.vchip-auth { background: color-mix(in srgb, var(--warn) 22%, transparent); color:#e0a044; }
.vchip-deny { background: color-mix(in srgb, var(--deny) 20%, transparent); color:#ff6f66; }
.vchip-exch { background: color-mix(in srgb, var(--exch) 22%, transparent); color:#c58bff; }

/* ---- Overview view ---- */
.ov { padding: 20px 22px 40px; max-width: 900px; }
.ov-eyebrow { font-family: var(--mono); font-size:11px; letter-spacing:.14em; text-transform:uppercase;
  color: var(--cox-blue); font-weight:700; margin:0 0 10px; }
.ov-h1 { font-size:28px; line-height:1.1; margin:0 0 12px; letter-spacing:-.01em; }
.ov-lede { color: var(--muted); font-size:15px; max-width:64ch; margin:0 0 8px; }
.ov-lede b, .mnote b { color: var(--text); }
.ov-h2 { font-family: var(--mono); font-size:11px; letter-spacing:.12em; text-transform:uppercase;
  color: var(--muted); font-weight:700; margin:30px 0 14px; display:flex; align-items:center; gap:10px; }
.ov-h2::after { content:""; flex:1; height:1px; background: var(--border); }
.cast { display:grid; grid-template-columns:repeat(auto-fit,minmax(240px,1fr)); gap:12px; }
.persona { background: var(--panel); border:1px solid var(--border); border-radius:10px; padding:14px; }
.persona .who { display:flex; align-items:baseline; justify-content:space-between; gap:8px; }
.pname { font-size:17px; font-weight:800; }
.puid { font-family: var(--mono); font-size:11px; color: var(--muted); }
.prole { color: var(--muted); font-size:13px; margin:6px 0 12px; }
.klabel { font-size:9px; letter-spacing:.08em; text-transform:uppercase; color: var(--muted); margin:0 0 5px; }
.chips { display:flex; flex-wrap:wrap; gap:5px; margin-bottom:12px; }
.chips .chip { font-family: var(--mono); font-size:11px; padding:2px 8px; border-radius:20px;
  background: var(--bg); border:1px solid var(--border); color: var(--muted); }
.chips .chip.grp { color:#7fb0ff; border-color:#2b4d80; font-weight:700; }
.can { list-style:none; padding:0; margin:0; font-size:13px; }
.can li { padding-left:18px; position:relative; margin:3px 0; color: var(--muted); }
.can li.y::before { content:"✓"; position:absolute; left:0; color: var(--pass); font-weight:700; }
.can li.n::before { content:"✕"; position:absolute; left:0; color: var(--deny); font-weight:700; }
.mscroll { overflow-x:auto; border:1px solid var(--border); border-radius:10px; }
.mtable { border-collapse:collapse; width:100%; min-width:560px; font-size:13px; }
.mtable th, .mtable td { text-align:left; padding:10px 12px; border-bottom:1px solid var(--border); }
.mtable thead th { font-family: var(--mono); font-size:10px; letter-spacing:.06em; text-transform:uppercase;
  color: var(--muted); background: var(--panel); }
.mtable th.c, .mtable td.c { text-align:center; }
.mtable tbody tr:last-child td { border-bottom:0; }
.mtool { font-family: var(--mono); font-size:12px; white-space:nowrap; }
.mdesc { color: var(--muted); }
.cell { display:inline-flex; align-items:center; justify-content:center; width:22px; height:22px; border-radius:6px; font-weight:700; }
.cell.y { background: color-mix(in srgb, var(--pass) 18%, transparent); color:#3fb950; }
.cell.n { background: color-mix(in srgb, var(--deny) 16%, transparent); color:#ff6f66; }
.mnote { font-size:12.5px; color: var(--muted); margin:10px 2px 0; }
.scenes { display:flex; flex-direction:column; }
.scene { display:grid; grid-template-columns:40px 1fr; gap:14px; padding:16px 0; border-top:1px solid var(--border); }
.scene:first-child { border-top:0; }
.snum { font-family: var(--mono); font-size:22px; font-weight:700; color: var(--cox-blue); }
.stitle { font-size:17px; font-weight:800; margin-bottom:3px; }
.ocalls { display:flex; flex-direction:column; gap:6px; margin:10px 0; }
.ocall { display:flex; align-items:center; gap:9px; flex-wrap:wrap; background: var(--panel);
  border:1px solid var(--border); border-radius:8px; padding:7px 10px; }
.octxt { font-family: var(--mono); font-size:12px; color: var(--muted); flex:1; min-width:180px; }
.swhy { }
.legend { display:grid; grid-template-columns:repeat(auto-fit,minmax(220px,1fr)); gap:8px; }
.leg { display:flex; gap:9px; align-items:flex-start; background: var(--panel);
  border:1px solid var(--border); border-radius:8px; padding:10px 12px; }
.legt { font-size:12.5px; color: var(--muted); }
.legt b { display:block; color: var(--text); margin-bottom:1px; }
```

- [ ] **Step 5: Run the unit tests (regression guard)**

Run: `cd demo-ui && npm test`
Expected: PASS — all `copy-and-render.test.js` and existing `verdict.test.js` tests green (no test touches DOM).

- [ ] **Step 6: Commit**

```bash
git add demo-ui/public/app.js demo-ui/public/styles.css
git commit -m "feat(demo-ui): Demo intuitiveness rewrite — identity badges, outcome rows, legend (F1–F6)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 6: Documentation sync (DECISIONS + project docs)

**Files:**
- Modify: `claude/DECISIONS.md`, `ARCHITECTURE.md`, `README.md`, `NOTES.md`, `claude/handoff/state.md`, `claude/NEXT-SESSION.md`

- [ ] **Step 1: Append U10 + U11 to `claude/DECISIONS.md`**

Add two rows to the decisions table (match the existing `| date (id) | decision | rationale | scope | links |` format):

```markdown
| 2026-07-24 (U10) | demo-ui gains a 4th mode, **Overview** ("Start here"), as the **default landing route** (`#/` → overview). | A legible front door is the first fix to "not intuitive"; Demo/Explore/Stack become the "now go do it" tabs. Additive to U1 — the three modes are unchanged. | demo-ui UX | [[U1]] overview.js, app.js, spec 2026-07-24 |
| 2026-07-24 (U11) | `scenarios.js` is the **single source of the customer-facing copy** (`headline`, `proves`, `why`, `railLabel` per scene; `identity`, `verdictLabel` per call). Overview and Demo both render from it. | Root-causes the "terse/awful descriptions" complaint; no drift between the Overview page and Demo mode. Verdict **classifier** stays coarse per U8 — only the *display label* is sourced here (step-1 call-3 shows "REST scope/audience gate", never "acl-deny"). | demo-ui copy | [[U8]] scenarios.js, content.js, spec 2026-07-24 |
```

- [ ] **Step 2: Sync `ARCHITECTURE.md`**

In the demo-ui module/file table, add rows for `public/content.js` (personas/matrix/legend — customer-facing static copy) and `public/overview.js` (Overview landing view; pure `overviewHTML` builder + DOM attach), and note that `scenarios.js` now carries customer-facing copy fields and Overview is the default route.

- [ ] **Step 3: Sync `README.md`**

Under the demo-ui / cockpit section, document the four modes (Overview default, then Demo/Explore/Stack) and that Overview explains personas + the tool matrix + the seven steps. Update the **Known Issues** section: remove any entry describing the old dead persona-button confusion (now fixed by F1); if none exists, leave the section accurate.

- [ ] **Step 4: Sync `NOTES.md`**

Add a doc-vs-reality note: the verdict **display label** is now per-call (`verdictLabel`) and customer-facing, while the **classifier** remains the coarse 5-verdict taxonomy (U8) — the two are intentionally separate; the live `got` verdict still equals `expect` for every scripted step (that's the Playwright assertion).

- [ ] **Step 5: Sync handoff (`claude/handoff/state.md` + `claude/NEXT-SESSION.md`)**

In `state.md`, update the "what's working" snapshot: Overview view live + default, Demo rewritten (F1–F6). In `NEXT-SESSION.md`, refresh the "Since Last Session" bullets to mention the Overview + intuitiveness pass.

- [ ] **Step 6: Commit**

```bash
git add claude/DECISIONS.md ARCHITECTURE.md README.md NOTES.md claude/handoff/state.md claude/NEXT-SESSION.md
git commit -m "docs(demo-ui): record U10/U11 + sync ARCHITECTURE/README/NOTES/handoff

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 7: Live end-to-end verification with Playwright

**Files:** none (verification only). Uses the Playwright MCP browser tools.

**Preconditions:** stack up and synced. Bring the cockpit up with the changed image:

```bash
scripts/rebuild.sh demo-ui        # docker compose build --no-cache demo-ui (rule D7)
docker compose up -d
docker compose --profile tools run --rm deck gateway sync /config/konnect.yaml   # if not already synced
```

Cockpit URL: `http://127.0.0.1:4000`. If Stack execute actions are needed, run host-side via `scripts/ui.sh` instead (U9).

- [ ] **Step 1: Overview renders by default (spec §A)**

`browser_navigate` → `http://127.0.0.1:4000/`. `browser_snapshot`. Assert:
- Nav item "Overview" is active; `#view` contains the `<h1>` "Governed MCP — what this demo shows".
- 3 persona cards (Dana/Frank/Olivia) with group chips `dealers/finance/ops`.
- Matrix has 4 tool rows; the ✓/✕ pattern matches the ground-truth table (Dana ✓✓✕✕, Frank ✕✕✓✓, Olivia ✓✓✓✕ across the four tools).
- Legend shows all six entries.
- No text matching `/confusingly wrong|being fixed|gets wrong/i` (customer-safe).

- [ ] **Step 2: Demo — no persona buttons; run all 7 steps live (spec §B)**

`browser_navigate` → `#/demo`. Assert **no** `.persbtn` elements exist in Demo (F1).
For each step i in 1..7: click the stepper button, click `#run` (`browser_click`), `browser_wait_for` the results, then assert per call:
- The identity badge text matches the scene's `identity` (Step 1 call 1 = "no token", **not** a persona name).
- The customer-facing verdict chip text matches `verdictLabel` (Step 1 call 3 shows "403 · REST scope/audience gate", never "acl-deny").
- The `.trust` line reads "✓ matches expected · live call" — i.e. the live `got` == scripted `expect` (the real end-to-end assertion). Any `.trust.bad` is a failure to investigate.
- The hybrid trace (`.trace`) is present (U2 intact). On Step 4, the token BEFORE/AFTER panels render (exchange).
`browser_take_screenshot` per step → save for the handoff.

- [ ] **Step 3: Explore still works (spec §C)**

`#/explore`: persona switcher present. Run olivia → `/mcp/ops` `list_invoices` → verdict allow; run frank → `/mcp/ops` `list_dealer_customers` (tool) → verdict deny. Assert both.

- [ ] **Step 4: Stack renders (spec §D)**

`#/stack`: status tiles render; dashboard link `href` resolves to a Konnect analytics URL. If in-container, assert the host-only execute note is shown (U9).

- [ ] **Step 5: Console hygiene (spec §E)**

`browser_console_messages` on each route (`#/overview`, `#/demo`, `#/explore`, `#/stack`) → assert no `error`-level messages.

- [ ] **Step 6: Record results**

If all of §A–E are green (all 7 Demo steps `got` == `expect`, screenshots captured), the pass bar is met. Append a dated verification note to `NOTES.md` (demo-ui block) summarizing what was driven and that live verdicts matched, and reference the screenshots. Commit:

```bash
git add NOTES.md walk-*.png 2>/dev/null; git commit -m "test(demo-ui): live Playwright verification — Overview + F1–F6, 7 steps green

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

If any check is red: stop, treat it as a real defect (invoke systematic-debugging), fix at the source, rebuild, and re-run Task 7 from Step 1. Do not claim done on unit tests alone.

---

## Self-Review

**Spec coverage:**
- Overview view (default, customer-facing, personas/matrix/7 steps/legend) → Tasks 2, 4. ✓
- Copy fixed at source (scenarios.js SSoT, U11) → Task 1. ✓
- F1 dead persona control → Task 5 (renderDemo removes `.persbtn`; identity badges). ✓
- F2 human step labels → Task 5 (`railLabel` in stepper) + Task 1 (data). ✓
- F3 de-jargoned narration → Task 5 (`headline`+`proves` header). ✓
- F4 outcome-not-assert rows → Task 5 (`runDemoStep` callhead + de-emphasized `.trust`). ✓
- F5 inline legend → Task 5 (`legendbar`). ✓
- F6 honest verdict labels respecting U8 → Task 1 (`verdictLabel`) + Task 3 (`verdictKind`/`verdictChip`) + Task 5 (render). Classifier untouched. ✓
- U10/U11 recorded; docs synced → Task 6. ✓
- Playwright thorough verification (A–E) → Task 7. ✓

**Placeholder scan:** No TBD/TODO; every code step shows complete code. ✓

**Type consistency:** `identityBadge(identity)`, `verdictKind(expectVerdict, showExchange)`, `verdictChip(label, kind)` — defined in Task 3, consumed with matching signatures in Tasks 4 and 5. `overviewHTML(scenarios, content)` / `renderOverview(scenarios, content)` — defined Task 4, called in `app.js` `route()` with `(SCENARIOS, content)`. Scene/call field names (`headline/proves/why/railLabel/identity/verdictLabel`) consistent across Tasks 1, 4, 5, and the tests. ✓

**Note on refinement vs spec:** the spec floated a per-call `why`; this plan locks `why` at the **scene** level (matches the proven guide layout, YAGNI) — recorded here so the deviation is intentional, not a gap.
