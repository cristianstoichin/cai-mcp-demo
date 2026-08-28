// copy-and-render.test.js — data integrity + pure-render checks for the UI copy.
import { test } from "node:test";
import assert from "node:assert/strict";
import { scenarios } from "./scenarios.js";
import { personas, matrix, legend } from "./public/content.js";
import { phaseSequence } from "./public/present.js";
import { identityBadge, verdictKind, verdictChip } from "./public/trace.js";
import { overviewHTML } from "./public/overview.js";
import contentDefault from "./public/content.js";

test("every scene has customer-facing copy fields", () => {
  assert.equal(scenarios.length, 8);
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
  assert.deepEqual(byTool.hello_custom_tool.allow, ["finance", "dealers"]);
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

test("verdictKind maps expect+exchange to a color kind", () => {
  assert.equal(verdictKind("allow", false), "ok");
  assert.equal(verdictKind("allow", true), "exch");
  assert.equal(verdictKind("auth-fail", false), "auth");
  assert.equal(verdictKind("acl-deny", false), "deny");
  assert.equal(verdictKind("opa-deny", false), "deny");
  assert.equal(verdictKind("inner-gate-deny", false), "deny");
});

test("identityBadge renders a slugged, human badge", () => {
  const b = identityBadge("no-token");
  assert.match(b, /idb-no-token/);
  assert.match(b, /no token/);
  assert.match(identityBadge("Olivia"), /idb-olivia/);
  assert.match(identityBadge("Olivia"), />Olivia</);
});

test("verdictChip carries the kind class and the label text", () => {
  const c = verdictChip("403 · OPA policy", "deny");
  assert.match(c, /vchip vchip-deny/);
  assert.match(c, /403 · OPA policy/);
});

test("overviewHTML renders all sections and is customer-safe", () => {
  const html = overviewHTML(scenarios, contentDefault);
  for (const n of ["Dana", "Frank", "Olivia"]) assert.match(html, new RegExp(n));
  for (const t of ["list_dealer_customers", "list_invoices", "list_floorplans", "hello_custom_tool"]) assert.match(html, new RegExp(t));
  for (const s of scenarios) assert.ok(html.includes(s.headline), `missing headline: ${s.headline}`);
  assert.match(html, /Passed every gate/);
  assert.ok(!/confusingly wrong|being fixed|gets wrong/i.test(html), "internal callout leaked");
});

test("every scene has Present-mode tell-show-tell copy", () => {
  for (const s of scenarios) {
    assert.equal(typeof s.setup, "string", `${s.id} setup is a string`);
    assert.ok(s.setup.trim().length > 0, `${s.id} setup non-empty`);
    assert.equal(typeof s.takeaway, "string", `${s.id} takeaway is a string`);
    assert.ok(s.takeaway.trim().length > 0, `${s.id} takeaway non-empty`);
  }
});

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
