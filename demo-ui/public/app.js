// app.js — hash router + the three views. Vanilla ESM, no framework/build.
import { renderPanel, identityBadge, verdictChip, verdictKind, renderCallRow } from "/trace.js";
import { renderOverview } from "/overview.js";
import content from "/content.js";

const view = document.getElementById("view");
const api = {
  scenarios: () => fetch("/api/scenarios").then(r => r.json()),
  mcp: (payload) => fetch("/api/mcp", { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify(payload) }).then(r => r.json()),
  exchangePreview: (persona) => fetch("/api/exchange-preview", { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ persona }) }).then(r => r.json()),
  registry: () => fetch("/api/registry").then(r => r.json()),
  status: () => fetch("/api/status").then(r => r.json()),
  meta: () => fetch("/api/meta").then(r => r.json()).catch(() => ({})),
};

let SCENARIOS = [];
const state = { stepIdx: 0, persona: "olivia" };
const PERSONAS = ["dana", "frank", "olivia"];

function setNav(mode) {
  document.querySelectorAll(".navitem").forEach(a =>
    a.classList.toggle("on", a.dataset.mode === mode));
}

// ---------- DEMO ----------
// F1: no global persona buttons — each scripted call carries a fixed `identity`,
// shown as a per-row badge. F2: stepper uses human `railLabel`. F3: header shows
// `headline` + `proves`. F5: an always-visible verdict legend bar.
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

// F4: rows lead with identity + outcome (verdictLabel), with the expected/got match
// kept as a small de-emphasized trust chip (proves it's a live call, not canned).
// F6: the customer sees `verdictLabel` (honest per-call), never the raw classifier
// enum; `got` is used only for the live-match check (U8: classifier untouched).
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
    const exchange = (sc.showExchange && persona && call.expect.verdict === "allow")
      ? await api.exchangePreview(persona) : null;
    blocks.push(renderCallRow(sc, call, res, exchange));
  }
  out.innerHTML = blocks.join("");
  if (whyEl) whyEl.hidden = false;   // reveal the plain-language "why" after the run
}

function renderRegistryBlock(r) {
  if (!r.configured) return `<div class="tile" style="margin-top:10px">Registry not configured — run <code>scripts/registry-setup.sh</code>.</div>`;
  const rows = r.servers.map(s => `<div class="kv"><span class="k">${s.name}</span> → <span class="p">${s.url}</span></div>`).join("");
  return `<div class="tile" style="margin-top:10px"><div class="label">${r.servers.length} server(s) in the Konnect MCP Registry</div>${rows || "(none)"}${r.error ? `<p style="color:var(--warn)">${r.error}</p>` : ""}</div>`;
}

// ---------- EXPLORE ----------
const ENDPOINTS = ["/mcp/dealers", "/mcp/finance", "/mcp/ops", "/mcp/remote", "/mcp/remote-public"];
function renderExplore() {
  setNav("explore");
  const personas = PERSONAS.map(p => `<option value="${p}">${p}</option>`).join("");
  const eps = ENDPOINTS.map(e => `<option value="${e}">${e}</option>`).join("");
  view.innerHTML = `
    <div class="content2">
      <div class="label">Explore — free sandbox</div>
      <div class="row" style="justify-content:flex-start;gap:10px;flex-wrap:wrap;margin:8px 0">
        <label>persona <select id="ex-persona">${personas}</select></label>
        <label>scope override <input type="text" id="ex-scope" placeholder="(default)" size="26"></label>
        <label>endpoint <select id="ex-path">${eps}</select></label>
        <label>tool <input type="text" id="ex-tool" placeholder="(tools/list)" size="22"></label>
        <label>args JSON <input type="text" id="ex-args" placeholder="{}" size="18"></label>
        <button class="runbtn" id="ex-run">▶ Run</button>
      </div>
      <div id="ex-result"></div>
    </div>`;
  view.querySelector("#ex-persona").value = state.persona;
  view.querySelector("#ex-run").onclick = async () => {
    const out = view.querySelector("#ex-result");
    out.innerHTML = `<p style="color:var(--muted)">Running…</p>`;
    let args = {}; const at = view.querySelector("#ex-args").value.trim();
    if (at) { try { args = JSON.parse(at); } catch { out.innerHTML = `<p style="color:var(--deny)">args must be JSON</p>`; return; } }
    const tool = view.querySelector("#ex-tool").value.trim() || null;
    const res = await api.mcp({
      persona: view.querySelector("#ex-persona").value,
      scope: view.querySelector("#ex-scope").value.trim() || undefined,
      path: view.querySelector("#ex-path").value,
      method: tool ? "tools/call" : "tools/list", tool, args,
    });
    out.innerHTML = `<div class="tile">${renderPanel({ ...res, showExchange: false })}</div>`;
  };
}

// ---------- STACK ----------
const STACK_ACTIONS = [
  ["up", "Start stack"], ["down", "Stop stack"], ["sync", "deck sync"],
  ["preflight", "Preflight"], ["smoke", "Smoke test"], ["registry-setup", "Publish registry"],
];
async function renderStack() {
  setNav("stack");
  const meta = await api.meta();
  // In-container: a container must not tear down its own compose project, so the
  // execute buttons are host-only. Show a note pointing at scripts/ui.sh instead.
  const actionsBlock = meta.inContainer
    ? `<div class="tile" style="margin-top:6px">Stack execute actions (up / down / sync / preflight / smoke /
         registry-setup) run <strong>host-side</strong> — launch the cockpit with
         <code>scripts/ui.sh</code> to drive them. (A container shouldn't tear down its own compose project.)</div>`
    : `<div class="row" style="justify-content:flex-start;gap:6px;flex-wrap:wrap">
         ${STACK_ACTIONS.map(([a, d]) => `<button class="persbtn" data-a="${a}" title="${d}">${a}</button>`).join("")}
       </div>
       <div class="label" style="margin-top:12px">Output</div>
       <div class="term" id="st-term">(select an action)</div>`;
  view.innerHTML = `
    <div class="content2">
      <div class="label">Stack — status</div>
      <div id="st-status" class="grid2" style="grid-template-columns:repeat(3,1fr)">Loading…</div>
      <div class="label" style="margin-top:14px">Actions (whitelisted)</div>
      ${actionsBlock}
      <div class="label" style="margin-top:12px">Konnect analytics</div>
      <a class="link" id="dash-link" href="#" target="_blank" rel="noopener">Open the “Cox Automotive: Governed MCP” dashboard in Konnect ↗</a>
    </div>`;
  const region = meta.region || "us";
  const dash = document.getElementById("dash-link");
  dash.href = meta.dashboardId
    ? `https://cloud.konghq.com/${region}/analytics/dashboards/${meta.dashboardId}`
    : `https://cloud.konghq.com/${region}/analytics/dashboards`;
  const status = await api.status();
  document.getElementById("st-status").innerHTML = (status.services || []).map(s =>
    `<div class="tile"><div>${s.service}</div><span class="chip ${s.healthy ? "ok" : "deny"}">${s.status || "?"}</span></div>`).join("") || "(docker not reachable)";
  view.querySelectorAll("[data-a]").forEach(b => b.onclick = () => streamAction(b.dataset.a));
}

function streamAction(action) {
  const term = document.getElementById("st-term");
  term.textContent = "";
  const es = new EventSource(`/api/stack/${action}`);
  es.addEventListener("start", (e) => term.textContent += `$ ${JSON.parse(e.data).desc}\n`);
  es.addEventListener("line", (e) => { term.textContent += JSON.parse(e.data).line + "\n"; term.scrollTop = term.scrollHeight; });
  es.addEventListener("end", (e) => { term.textContent += `\n[exit ${JSON.parse(e.data).code}]\n`; es.close(); });
  es.onerror = () => { term.textContent += "\n[stream closed]\n"; es.close(); };
}

// ---------- ROUTER ----------
function route() {
  const h = location.hash || "#/overview";
  if (h.startsWith("#/demo")) return renderDemo();
  if (h.startsWith("#/explore")) return renderExplore();
  if (h.startsWith("#/stack")) return renderStack();
  setNav("overview");                          // #/ and #/overview
  return renderOverview(SCENARIOS, content);
}
window.addEventListener("hashchange", route);
(async function init() {
  const data = await api.scenarios();
  SCENARIOS = data.scenarios;
  route();
})();
