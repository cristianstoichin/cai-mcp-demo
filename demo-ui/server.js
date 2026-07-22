// server.js — Express wiring only. Binds 127.0.0.1 (local-only, no UI auth).
// Secrets live here, never sent to the browser.

import express from "express";
import { exec } from "node:child_process";
import { fileURLToPath } from "node:url";
import { dirname, join, resolve } from "node:path";
import { config } from "./config.js";
import { mintToken, exchangeToken, decodeJwt } from "./keycloak.js";
import { callMcp, callRest } from "./kong.js";
import { discover } from "./registry.js";
import { classify } from "./verdict.js";
import { scenarios } from "./scenarios.js";
import { ACTIONS, runAction } from "./stack.js";

const __dir = dirname(fileURLToPath(import.meta.url));
const REPO = resolve(__dir, "..");
const app = express();
app.use(express.json());
app.use(express.static(join(__dir, "public")));

const fail = (res, e) => res.status(500).json({ error: String(e.message || e) });

app.get("/api/scenarios", (_req, res) => res.json({ scenarios }));

app.get("/api/meta", (_req, res) =>
  res.json({ dashboardId: config.dashboardId, region: config.konnectRegion }));

app.post("/api/mcp", async (req, res) => {
  try {
    const { persona, scope, path, method = "tools/call", tool, args = {} } = req.body || {};
    let token = null, claims = null;
    if (persona) { const t = await mintToken(persona, scope); token = t.accessToken; claims = t.claims; }

    let result;
    if (path.startsWith("/api/")) {
      result = await callRest({ token, path });
    } else {
      const body = tool
        ? { jsonrpc: "2.0", id: 1, method: "tools/call", params: { name: tool, arguments: args } }
        : { jsonrpc: "2.0", id: 1, method };
      result = await callMcp({ token, path, body });
    }
    const verdict = classify({ httpStatus: result.httpStatus, body: result.body });
    res.json({ httpStatus: result.httpStatus, body: result.body, raw: result.raw, verdict, tokenClaims: claims });
  } catch (e) { fail(res, e); }
});

app.post("/api/token", async (req, res) => {
  try { const { persona, scope } = req.body || {}; res.json(await mintToken(persona, scope)); }
  catch (e) { fail(res, e); }
});

app.post("/api/token/decode", (req, res) => {
  try { res.json({ claims: decodeJwt((req.body || {}).jwt) }); }
  catch (e) { fail(res, e); }
});

app.post("/api/exchange-preview", async (req, res) => {
  try {
    const { persona = "olivia" } = req.body || {};
    const before = await mintToken(persona, "openid mcp:use");
    const after = await exchangeToken(before.accessToken);
    res.json({ before: before.claims, after: after.claims });
  } catch (e) { fail(res, e); }
});

app.get("/api/registry", async (_req, res) => {
  try { res.json(await discover()); } catch (e) { fail(res, e); }
});

app.get("/api/status", (_req, res) => {
  exec("docker compose ps --format '{{.Service}}|{{.Status}}'", { cwd: REPO }, (err, stdout) => {
    if (err) return res.json({ services: [], error: String(err.message) });
    const services = stdout.trim().split("\n").filter(Boolean).map(line => {
      const [service, status = ""] = line.split("|");
      return { service, status, healthy: /healthy|Up/.test(status) };
    });
    res.json({ services });
  });
});

app.get("/api/stack/:action", (req, res) => {
  const { action } = req.params;
  if (!ACTIONS[action]) return res.status(400).json({ error: `action not allowed: ${action}` });
  res.set({ "Content-Type": "text/event-stream", "Cache-Control": "no-cache", "Connection": "keep-alive" });
  res.flushHeaders();
  const send = (event, data) => res.write(`event: ${event}\ndata: ${JSON.stringify(data)}\n\n`);
  send("start", { action, desc: ACTIONS[action].desc });
  const keep = setInterval(() => res.write(": keep-alive\n\n"), 15000);
  const child = runAction(action, (line) => send("line", { line }), (code) => {
    clearInterval(keep); send("end", { code }); res.end();
  });
  req.on("close", () => { clearInterval(keep); child.kill(); });
});

app.listen(config.uiPort, "127.0.0.1", () => {
  console.log(`demo-ui → http://127.0.0.1:${config.uiPort}`);
});
