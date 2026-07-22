// trace.js — the reusable plugin-chain trace + hybrid panel. Pure string builders
// (no framework). Colors come from styles.css classes; node lit from the verdict.

export const NODE_ORDER = ["persona", "oauth2", "exchange", "acl", "opa", "upstream"];
const NODE_LABEL = { persona: "persona", oauth2: "ai-mcp-oauth2", exchange: "exchange",
  acl: "tool ACL", opa: "OPA", upstream: "upstream" };

const esc = (s) => String(s).replace(/[&<>"]/g, c => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" }[c]));

export function renderTrace(verdict, { showExchange } = {}) {
  const chain = NODE_ORDER.filter(n => n !== "exchange" || showExchange);
  const failNode = verdict.verdict === "allow" ? null : verdict.node; // node id that denied
  let reached = true;
  const nodes = chain.map(n => {
    let cls = "node", chip = '<span class="chip muted">—</span>';
    if (n === "persona") { chip = '<span class="chip muted">token</span>'; }
    if (!reached) { cls += " idle"; }
    else if (failNode && n === failNode) { cls += (n === "exchange") ? " exch" : " fail";
      chip = `<span class="chip ${n === "exchange" ? "new" : "deny"}">${n === "exchange" ? "no aud" : "DENY"}</span>`; reached = false; }
    else if (n === "persona") { /* keep the muted token chip */ }
    else { cls += (n === "exchange") ? " exch" : " pass";
      chip = `<span class="chip ${n === "exchange" ? "new" : "ok"}">${n === "exchange" ? "＋token" : "✓"}</span>`; }
    return `<div class="${cls}"><div>${esc(NODE_LABEL[n])}</div>${chip}</div>`;
  });
  return `<div class="trace">${nodes.join('<span class="arrow">→</span>')}</div>`;
}

export function fmtClaims(claims, highlightKeys = []) {
  if (!claims) return '<div class="kv muted">(no token)</div>';
  const keys = ["aud", "scope", "groups", "sub", "azp"];
  const hi = new Set(highlightKeys);
  const rows = keys.filter(k => claims[k] !== undefined).map(k => {
    const cls = hi.has(k) ? "add" : "k";
    const val = Array.isArray(claims[k]) ? `[${claims[k].join(", ")}]` : String(claims[k]);
    return `<span class="${cls}">${esc(k)}</span>: <span class="${hi.has(k) ? "add" : "p"}">${esc(val)}</span>`;
  });
  return `<div class="kv">${rows.join("<br>")}</div>`;
}

export function renderPanel({ verdict, httpStatus, body, tokenClaims, exchange, showExchange }) {
  const whyClass = verdict.verdict === "allow" ? "ok" : (verdict.node === "exchange" ? "exch" : "");
  let tokenBlock;
  if (exchange) {
    // Which AFTER keys changed → highlight.
    const changed = ["aud", "scope"].filter(k =>
      JSON.stringify(exchange.after?.[k]) !== JSON.stringify(exchange.before?.[k]));
    tokenBlock = `
      <div class="grid2" style="margin-top:10px">
        <div><div class="label">Token BEFORE</div><div class="panel">${fmtClaims(exchange.before)}</div></div>
        <div><div class="label">Token AFTER exchange</div><div class="panel">${fmtClaims(exchange.after, changed)}</div></div>
      </div>`;
  } else {
    tokenBlock = `<div style="margin-top:10px"><div class="label">Token claims</div><div class="panel">${fmtClaims(tokenClaims)}</div></div>`;
  }
  const respText = typeof body === "string" ? body : JSON.stringify(body, null, 2);
  return `
    <div class="label">Request flow through Kong</div>
    ${renderTrace(verdict, { showExchange })}
    <div class="why ${whyClass}"><strong>${esc(verdictHeadline(verdict))}</strong> ${esc(verdict.why)}</div>
    ${tokenBlock}
    <div style="margin-top:10px"><div class="label">Response · HTTP ${esc(httpStatus)}</div>
      <div class="panel kv">${esc(truncate(respText, 1200))}</div></div>`;
}

function verdictHeadline(v) {
  return { "allow": "Allowed.", "auth-fail": "401 Unauthorized.", "acl-deny": "403 Forbidden — ACL.",
    "opa-deny": "403 — OPA policy.", "inner-gate-deny": "Inner-gate 403.", "unknown": "Unexpected." }[v.verdict] || "";
}
function truncate(s, n) { s = s || ""; return s.length > n ? s.slice(0, n) + "\n… (truncated)" : s; }
