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
