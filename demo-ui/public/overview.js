// overview.js — the customer-facing "Overview / Start here" landing view.
// Pure builder (overviewHTML) + DOM attach (renderOverview). Renders from
// scenarios.js (copy SSoT, U11) + content.js (personas/matrix/legend).
// Relative import so this module loads under both the browser (served from /) and
// node --test (which imports it from disk). "./trace.js" resolves correctly in both.
import { identityBadge, verdictChip, verdictKind } from "./trace.js";

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
    <p class="mnote"><b>Authorization</b> is the token's <code>groups</code> claim — no consumer
      or API-key check gates access. Kong consumer records exist <b>only</b> as identity labels so
      Konnect analytics attributes each tool call to a person; they play no part in the access decision.
      Endpoints: <code>/mcp/dealers</code>, <code>/mcp/finance</code>, <code>/mcp/ops</code>
      (bundle; token-exchange + OPA also run here).</p>

    <div class="ov-h2">The demo, step by step</div>
    <div class="scenes">${scenarios.map(sceneBlock).join("")}</div>

    <div class="ov-h2">How to read a result</div>
    <div class="legend">${legend.map(legendRow).join("")}</div>
  </div>`;
}

export function renderOverview(scenarios, content) {
  const view = document.getElementById("view");
  view.innerHTML = overviewHTML(scenarios, content);
}
