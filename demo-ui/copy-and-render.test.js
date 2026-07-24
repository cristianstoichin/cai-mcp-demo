// copy-and-render.test.js — data integrity + pure-render checks for the UI copy.
import { test } from "node:test";
import assert from "node:assert/strict";
import { scenarios } from "./scenarios.js";
import { personas, matrix, legend } from "./public/content.js";

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
