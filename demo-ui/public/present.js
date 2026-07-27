// present.js — Present mode: self-driven tell-show-tell walkthrough (manual Next).
// Renders from the SAME scenarios.js as Demo/Overview; reuses trace.js renderers and
// the api client injected by app.js. Pure phaseSequence() is unit-tested under node.
// renderCallRow below is imported with a RELATIVE path so this module loads under
// both the browser (served from /) and node --test.

import { renderCallRow } from "./trace.js";

// Pure: the ordered phases for a scene. Exported for unit tests.
export function phaseSequence(scene) {
  return ["tell-open", ...scene.calls.map((_, i) => `show:${i}`), "tell-close"];
}

let ctx = null;                     // { view, scenarios, api }
const ps = { sceneIdx: 0, pi: 0 }; // pi = index into phaseSequence(current scene)
let revealed = [];                 // accumulated call-row HTML for the current scene

// Entrypoint: app.js calls this on the #/present route. Enters the current scene at tell-open.
export function renderPresent(context) {
  ctx = context;
  ps.pi = 0;
  revealed = [];
  draw();
}

function scene()  { return ctx.scenarios[ps.sceneIdx]; }
function phases() { return phaseSequence(scene()); }
function phase()  { return phases()[ps.pi]; }

function stepperHTML() {
  return `<div class="stepper">${ctx.scenarios.map((s, i) =>
    `<button class="step ${i < ps.sceneIdx ? "done" : ""} ${i === ps.sceneIdx ? "cur" : ""}" data-i="${i}">
       <span class="n">${s.n}</span><span class="srail">${s.railLabel}</span></button>`).join("")}</div>`;
}

function phaseIndicatorHTML() {
  const seq = phases(), p = phase();
  const showN = seq.filter(x => x.startsWith("show:")).length;
  let label = p === "tell-open" ? "Tell · setup"
            : p === "tell-close" ? "Tell · takeaway"
            : `Show · ${(+p.split(":")[1]) + 1}/${showN}`;
  return `<div class="pphase">${label}</div>`;
}

function draw() {
  const sc = scene(), p = phase();
  let bodyHTML, btnLabel;
  if (p === "tell-open") {
    bodyHTML = `<div class="tellcard"><p class="telltext">${sc.setup}</p>
                <p class="sproves"><b>Proves:</b> ${sc.proves}</p></div>`;
    btnLabel = "Next ▸";
  } else if (p === "tell-close") {
    bodyHTML = `<div class="tellcard takeaway"><p class="telltext">${sc.takeaway}</p></div>`;
    btnLabel = ps.sceneIdx < ctx.scenarios.length - 1 ? "Next scene ▸" : "↺ Restart";
  } else {
    const i = +p.split(":")[1];
    bodyHTML = `<div class="showrows">${revealed.join("")}</div>`;
    btnLabel = i === sc.calls.length - 1 ? "Next ▸ takeaway" : "Next ▸";
  }
  ctx.view.innerHTML = `
    ${stepperHTML()}
    <div class="content2">
      <div class="row">
        <div class="stephead"><strong>Scene ${sc.n}/7 · ${sc.headline}</strong></div>
        ${phaseIndicatorHTML()}
      </div>
      ${bodyHTML}
      <div class="row"><button class="runbtn" id="pnext">${btnLabel}</button></div>
    </div>`;
  ctx.view.querySelectorAll(".step").forEach(b => b.onclick = () => {
    ps.sceneIdx = +b.dataset.i; ps.pi = 0; revealed = []; draw();
  });
  ctx.view.querySelector("#pnext").onclick = onNext;
}

async function onNext() {
  const sc = scene(), seq = phases(), p = phase();
  if (p === "tell-close") {                 // hop to next scene (or restart from 0)
    ps.sceneIdx = ps.sceneIdx < ctx.scenarios.length - 1 ? ps.sceneIdx + 1 : 0;
    ps.pi = 0; revealed = [];
    return draw();
  }
  ps.pi += 1;
  const np = seq[ps.pi];
  if (np && np.startsWith("show:")) {
    await revealCall(sc, sc.calls[+np.split(":")[1]]);
  }
  draw();
}

// Fire one call live and append its row. Same payload + row markup as Demo's runDemoStep.
async function revealCall(sc, call) {
  const sceneAtStart = ps.sceneIdx;             // guard: bail if a stepper jump lands us on a new scene mid-flight
  const btn = ctx.view.querySelector("#pnext");
  if (btn) { btn.disabled = true; btn.textContent = "Running…"; }
  ctx.view.querySelectorAll(".step").forEach(b => b.disabled = true);
  if (call.kind === "registry") {
    const registry = await ctx.api.registry();
    if (ps.sceneIdx !== sceneAtStart) return;   // scene changed while awaiting — discard stale result
    revealed.push(registryRow(registry));
    return;
  }
  const persona = call.persona === undefined ? null : call.persona;
  const payload = { persona, scope: call.scope, path: call.path,
    method: call.method, tool: call.tool, args: call.args };
  const res = await ctx.api.mcp(payload);
  const exchange = (sc.showExchange && persona && call.expect.verdict === "allow")
    ? await ctx.api.exchangePreview(persona) : null;
  if (ps.sceneIdx !== sceneAtStart) return;     // scene changed while awaiting — discard stale result
  revealed.push(renderCallRow(sc, call, res, exchange));   // shared with Demo (Task 3)
}

function registryRow(r) {
  if (r.error) return `<div class="tile" style="margin-top:10px"><div class="callhead"><span class="calltxt">Konnect MCP Registry</span></div><p style="color:var(--warn)">Registry error: ${r.error}</p></div>`;
  if (!r.configured) return `<div class="tile" style="margin-top:10px">Registry not configured — run <code>scripts/registry-setup.sh</code>.</div>`;
  const rows = r.servers.map(s => `<div class="kv"><span class="k">${s.name}</span> → <span class="p">${s.url}</span></div>`).join("");
  return `<div class="tile" style="margin-top:10px"><div class="callhead"><span class="calltxt">Konnect MCP Registry — discoverable servers</span></div>${rows}</div>`;
}
