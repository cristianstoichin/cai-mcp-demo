// kong.js — thin adapter to Kong :8000. MCP listeners accept a single stateless
// JSON-RPC POST and may answer as SSE (data: {...}) or plain JSON; parse both.

import { config } from "./config.js";

function parseMaybeSse(text) {
  const t = (text || "").trim();
  if (!t) return null;
  // SSE: take the last data: line.
  if (t.startsWith("data:") || t.includes("\ndata:")) {
    const line = t.split("\n").filter(l => l.startsWith("data:")).pop();
    if (line) { try { return JSON.parse(line.slice(5).trim()); } catch { return null; } }
  }
  try { return JSON.parse(t); } catch { return t; } // fall back to raw text (HTML 403)
}

export async function callMcp({ token, path, body }) {
  const headers = {
    "Content-Type": "application/json",
    "Accept": "application/json, text/event-stream",
  };
  if (token) headers["Authorization"] = `Bearer ${token}`;
  const res = await fetch(`${config.kongUrl}${path}`, {
    method: "POST", headers, body: JSON.stringify(body),
  });
  const raw = await res.text();
  return { httpStatus: res.status, body: parseMaybeSse(raw), raw };
}

export async function callRest({ token, path }) {
  const headers = {};
  if (token) headers["Authorization"] = `Bearer ${token}`;
  const res = await fetch(`${config.kongUrl}${path}`, { method: "GET", headers });
  const raw = await res.text();
  let body; try { body = JSON.parse(raw); } catch { body = raw; }
  return { httpStatus: res.status, body, raw };
}
