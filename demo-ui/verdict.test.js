// verdict.test.js
import { test } from "node:test";
import assert from "node:assert/strict";
import { classify } from "./verdict.js";

test("401 → auth-fail at oauth2", () => {
  const v = classify({ httpStatus: 401, body: "Unauthorized" });
  assert.equal(v.verdict, "auth-fail");
  assert.equal(v.node, "oauth2");
});

test("403 + HTML Forbidden → acl-deny", () => {
  const v = classify({ httpStatus: 403, body: "<html>...403 Forbidden...</html>" });
  assert.equal(v.verdict, "acl-deny");
  assert.equal(v.node, "acl");
});

test("403 + JSON unauthorized → opa-deny", () => {
  const v = classify({ httpStatus: 403, body: { message: "unauthorized" } });
  assert.equal(v.verdict, "opa-deny");
  assert.equal(v.node, "opa");
});

test("200 + JSON-RPC isError HTTP 403 → inner-gate-deny", () => {
  const body = { jsonrpc: "2.0", id: 1, result: { isError: true,
    content: [{ type: "text", text: "HTTP call failed with status 403" }] } };
  const v = classify({ httpStatus: 200, body });
  assert.equal(v.verdict, "inner-gate-deny");
  assert.equal(v.node, "exchange");
});

test("200 + result.content data → allow", () => {
  const body = { jsonrpc: "2.0", id: 1, result: { content: [{ type: "text",
    text: '{"count":5,"customers":[]}' }] } };
  const v = classify({ httpStatus: 200, body });
  assert.equal(v.verdict, "allow");
  assert.equal(v.node, "upstream");
});

test("tools/list 200 with tools array → allow", () => {
  const body = { jsonrpc: "2.0", id: 1, result: { tools: [{ name: "list_invoices" }] } };
  const v = classify({ httpStatus: 200, body });
  assert.equal(v.verdict, "allow");
});

test("handles raw string JSON body", () => {
  const v = classify({ httpStatus: 403, body: '{"message":"unauthorized"}' });
  assert.equal(v.verdict, "opa-deny");
});
