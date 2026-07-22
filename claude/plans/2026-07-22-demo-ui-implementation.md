# demo-ui Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a local, Cox-branded web cockpit (`demo-ui/`) that drives the real governed-MCP stack and makes each Kong governance decision legible — plugin-chain trace + token before/after + verdict — across three modes: Demo (scripted 7-step story), Explore (free sandbox), Stack (ops control).

**Architecture:** Host-run Node/Express backend (NOT in Compose) serving a no-build vanilla-JS SPA. The backend owns all secrets and CORS: it mints persona tokens against Keycloak (ROPC), proxies JSON-RPC calls to Kong `:8000`, reproduces the RFC 8693 exchange out-of-band, classifies the response into a governance verdict, discovers the Konnect MCP Registry, reports `docker compose` status, and runs a fixed whitelist of stack actions over SSE. The SPA renders a shared hybrid panel (trace hero → why → token → response) in all three views.

**Tech Stack:** Node 20 (host prereq, verified present), Express 4, native `fetch` (Node 20 global), vanilla ES-module JS in the browser, CSS variables for the Cox palette. No bundler, no framework, no TypeScript. One unit test via `node --test`.

## Global Constraints

_Every task's requirements implicitly include this section. Values copied verbatim from the spec, CLAUDE.md hard rules, and NOTES.md (live-verified)._

- **Zero hardcoded** org IDs / CP names / region hosts / PATs / secrets / client secrets anywhere in `demo-ui/`. Everything org-specific comes from `.env` (loaded by the launcher). Only non-sensitive realm artifacts already defaulted by existing scripts may be defaulted in code (see Env Contract below).
- **Canonical external base URL** `http://localhost:8000` (Kong). Keycloak `http://localhost:8080`. Realm `cox-auto`. These match the existing `scripts/*.sh` defaults exactly.
- **Local-only tool, no UI auth.** The server binds `127.0.0.1`. Secrets (PAT, client secrets) never reach the browser — only the backend holds them.
- **Stack actions are a fixed whitelist** (`up`, `down`, `sync`, `preflight`, `smoke`, `registry-setup`) mapped to existing scripts/compose commands. Reject anything not in the map — no arbitrary command execution.
- **No new host prereq beyond Node 20** (already present) and the tools the existing scripts need (`docker`, `deck`, `curl`, `jq`, `python3`) which are already required by the 6-phase demo.
- **No build step.** Browser JS is served as-is. `package.json` has `"type": "module"`, `express` as the only runtime dependency, and `node --test` for the unit test.
- **Verdict signatures are LIVE-VERIFIED, not guessed.** The classifier MUST inspect the JSON-RPC body, not only the HTTP status (inner-gate deny arrives as HTTP 200 with `isError` in the body). Re-verify every signature against the running stack before trusting it (Task 2 + Task 12).
- **Scenarios are DATA** (`scenarios.js`) — the single source of truth, mirroring `scripts/demo.sh`'s seven steps. No scenario logic hardcoded in the frontend.
- **Cox palette is approximate** (blue/navy) via CSS variables — flagged as approximate; exact hex is a one-line swap.
- Commit per task (Conventional Commits, scope `demo-ui`). Branch: `feat/cai-mcp-demo-build` (current).

### Env Contract (what the server reads, with the SAME defaults the existing scripts use)

| Var | Default (mirrors) | Sensitive? | Used for |
|-----|-------------------|------------|----------|
| `KONG_URL` | `http://localhost:8000` (demo.sh:16) | no | proxy target |
| `KEYCLOAK_BASE` | `http://localhost:8080` (get-token.sh:25) | no | token mint / exchange |
| `KEYCLOAK_REALM` | `cox-auto` (get-token.sh:26) | no | realm path |
| `DEMO_CLI_CLIENT_ID` | `demo-cli` (get-token.sh:27) | no | ROPC client |
| `DEMO_CLI_SECRET` | `demo-cli-secret-change-me` (get-token.sh:28) | **yes** | ROPC client secret |
| `DEMO_PASSWORD` | `Demo1234!` (get-token.sh:29) | **yes** | persona password |
| `KONG_EXCHANGE_CLIENT_ID` | `kong-exchange` (.env.example) | no | exchange client |
| `KONG_EXCHANGE_SECRET` | `kong-exchange-secret-change-me` | **yes** | exchange client secret |
| `KONNECT_TOKEN` | (required, no default) | **yes** | registry discovery |
| `KONNECT_REGION` | `us` | no | registry host |
| `KONNECT_MCP_REGISTRY_ID` | (from .env; may be empty) | no | registry discovery |
| `UI_PORT` | `4000` | no | server bind port |

The launcher `scripts/ui.sh` sources `.env` (like every other script), so `process.env` is populated. The server reads these via a small `config.js` with the defaults above. **Sensitive values are never sent to the browser** — only used server-side.

### Persona Contract (mirrors get-token.sh:46-50)

| Persona | Keycloak username | group | default scope |
|---------|-------------------|-------|---------------|
| `dana` | `dana.dealer` | dealers | `openid dealers:read mcp:use` |
| `frank` | `frank.finance` | finance | `openid finance:read mcp:use` |
| `olivia` | `olivia.ops` | ops | `openid dealers:read finance:read mcp:use` |

---

## File Structure

```
demo-ui/
├── package.json          # type:module; express; node --test; start script
├── config.js             # reads process.env → typed config object w/ the Env Contract defaults
├── keycloak.js           # mintToken(persona, scope?) + exchangeToken(subjectToken) + decodeJwt(jwt)
├── kong.js               # callMcp({token, path, body}) + callRest({token, path}) → {httpStatus, body, raw}
├── verdict.js            # classify({httpStatus, body}) → {verdict, node, why}  ← the one testable unit
├── verdict.test.js       # node --test: known signatures → expected verdict
├── registry.js           # discover() → {servers:[{name,url}]} via Konnect Labs API (PAT server-side)
├── scenarios.js          # the 7 Demo scenarios as DATA (mirrors demo.sh); shared by server + client
├── stack.js              # ACTIONS whitelist map + runAction(action) → child_process stream
├── server.js             # Express: static + /api/* endpoints wiring the modules above
└── public/
    ├── index.html        # SPA shell (Cox chrome, left nav, mode containers)
    ├── app.js            # hash router + Demo/Explore/Stack views + shared hybrid-panel renderer
    ├── trace.js          # renderTrace(nodes) — the plugin-chain hero (persona→oauth2→[exchange]→ACL→[OPA]→upstream)
    └── styles.css        # Cox palette via CSS variables; dark app chrome from the visuals
scripts/ui.sh             # launcher: source .env → node demo-ui/server.js → print the URL
```

Responsibility split: `keycloak.js`/`kong.js`/`registry.js`/`stack.js` are thin I/O adapters (each one job, easy to reason about); `verdict.js` + `scenarios.js` are pure data/logic (unit-testable, no I/O); `server.js` only wires HTTP routes to those modules. Frontend `app.js` routes + orchestrates; `trace.js` is the one reusable visual primitive shared by all three views.

---

## Task 1: Project scaffold + launcher + config

**Files:**
- Create: `demo-ui/package.json`
- Create: `demo-ui/config.js`
- Create: `scripts/ui.sh`
- Create: `demo-ui/.gitignore` (node_modules)

**Interfaces:**
- Produces: `config.js` default export `config` — object with keys `kongUrl, keycloakBase, realm, demoCliId, demoCliSecret, demoPassword, exchangeClientId, exchangeSecret, konnectToken, konnectRegion, registryId, uiPort` (all strings; `registryId`/`konnectToken` may be empty).
- Produces: `demo-ui/personas` (named export from `config.js`) — the Persona Contract map `{dana:{username,group,scope}, frank:{...}, olivia:{...}}`.

- [ ] **Step 1: Create `demo-ui/package.json`**

```json
{
  "name": "cai-mcp-demo-ui",
  "version": "1.0.0",
  "description": "Cox-branded local cockpit for the governed-MCP demo",
  "type": "module",
  "private": true,
  "scripts": {
    "start": "node server.js",
    "test": "node --test"
  },
  "dependencies": {
    "express": "^4.19.2"
  }
}
```

- [ ] **Step 2: Create `demo-ui/config.js`**

```js
// config.js — single source for env-derived config. Defaults MIRROR the existing
// scripts (get-token.sh, demo.sh) so the UI and the CLI behave identically.
// Sensitive values are used server-side only; never serialized to the browser.

const env = process.env;

export const config = {
  kongUrl:         env.KONG_URL              || "http://localhost:8000",
  keycloakBase:    env.KEYCLOAK_BASE         || "http://localhost:8080",
  realm:           env.KEYCLOAK_REALM        || "cox-auto",
  demoCliId:       env.DEMO_CLI_CLIENT_ID    || "demo-cli",
  demoCliSecret:   env.DEMO_CLI_SECRET       || "demo-cli-secret-change-me",
  demoPassword:    env.DEMO_PASSWORD         || "Demo1234!",
  exchangeClientId: env.KONG_EXCHANGE_CLIENT_ID || "kong-exchange",
  exchangeSecret:  env.KONG_EXCHANGE_SECRET  || "kong-exchange-secret-change-me",
  konnectToken:    env.KONNECT_TOKEN         || "",
  konnectRegion:   env.KONNECT_REGION        || "us",
  registryId:      env.KONNECT_MCP_REGISTRY_ID || "",
  uiPort:          Number(env.UI_PORT) || 4000,
};

// Persona Contract — mirrors get-token.sh:46-50.
export const personas = {
  dana:   { username: "dana.dealer",   group: "dealers", scope: "openid dealers:read mcp:use" },
  frank:  { username: "frank.finance", group: "finance", scope: "openid finance:read mcp:use" },
  olivia: { username: "olivia.ops",    group: "ops",     scope: "openid dealers:read finance:read mcp:use" },
};

// tokenUrl helper (used by keycloak.js).
export const tokenUrl = () =>
  `${config.keycloakBase}/realms/${config.realm}/protocol/openid-connect/token`;
```

- [ ] **Step 3: Create `scripts/ui.sh`**

```bash
#!/usr/bin/env bash
set -euo pipefail

# ui.sh — launch the demo-ui cockpit. Sources .env (like every other script),
# installs deps on first run, then runs the host-side Node server. Prints the URL.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
UI_DIR="${REPO_DIR}/demo-ui"

[[ -f "${REPO_DIR}/.env" ]] && { set -a; source "${REPO_DIR}/.env"; set +a; }

command -v node >/dev/null 2>&1 || { echo "[ERROR] Node 20+ is required (host prereq)." >&2; exit 1; }

if [[ ! -d "${UI_DIR}/node_modules" ]]; then
  echo "[INFO] Installing demo-ui dependencies (first run)…"
  ( cd "${UI_DIR}" && npm install --no-audit --no-fund )
fi

PORT="${UI_PORT:-4000}"
echo "[INFO] demo-ui → http://127.0.0.1:${PORT}"
exec node "${UI_DIR}/server.js"
```

- [ ] **Step 4: Create `demo-ui/.gitignore`**

```
node_modules/
```

- [ ] **Step 5: Make the launcher executable and verify config loads**

Run: `chmod +x scripts/ui.sh && cd demo-ui && node -e "import('./config.js').then(m=>console.log(m.config.kongUrl, m.personas.olivia.group))"`
Expected: `http://localhost:8000 ops`

- [ ] **Step 6: Commit**

```bash
git add demo-ui/package.json demo-ui/config.js demo-ui/.gitignore scripts/ui.sh
git commit -m "feat(demo-ui): scaffold — package.json, config, launcher"
```

---

## Task 2: Verdict classifier (the tricky unit — TDD) + LIVE signature re-verification

**Files:**
- Create: `demo-ui/verdict.js`
- Test: `demo-ui/verdict.test.js`

**Interfaces:**
- Produces: `classify({ httpStatus, body })` (default export + named) → `{ verdict, node, why }` where `verdict ∈ {"auth-fail","acl-deny","opa-deny","inner-gate-deny","allow","unknown"}`, `node` is the trace node id that lit red (`"oauth2"|"acl"|"opa"|"exchange"|"upstream"|null`), `why` is a plain-language string. `body` may be a string (raw) or a parsed object; the classifier must handle both.

> Signatures are from NOTES.md + spec §"verdict classifier", ALL live-verified in the 6-phase build. Task 12 re-verifies against the running stack before trusting them.

- [ ] **Step 1: Write the failing test**

```js
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd demo-ui && node --test verdict.test.js`
Expected: FAIL — `Cannot find module './verdict.js'` (or classify undefined).

- [ ] **Step 3: Write minimal implementation**

```js
// verdict.js — map a Kong MCP response signature to a governance verdict.
// Signatures live-verified in the 6-phase build (see NOTES.md). CRITICAL: the
// inner-gate deny arrives as HTTP 200 with isError in the JSON-RPC body, so we
// MUST inspect the body text, not only the status.

function asObject(body) {
  if (body && typeof body === "object") return body;
  if (typeof body === "string") { try { return JSON.parse(body); } catch { return null; } }
  return null;
}
function asText(body) {
  if (typeof body === "string") return body;
  try { return JSON.stringify(body); } catch { return String(body); }
}

export function classify({ httpStatus, body }) {
  const obj = asObject(body);
  const text = asText(body);

  if (httpStatus === 401) {
    return { verdict: "auth-fail", node: "oauth2",
      why: "No valid token — ai-mcp-oauth2 rejected the request before any tool ran." };
  }

  if (httpStatus === 403) {
    if (obj && obj.message === "unauthorized") {
      return { verdict: "opa-deny", node: "opa",
        why: "External OPA policy denied this call (a rule the tool ACL can't express)." };
    }
    // ACL deny surfaces as Kong's HTML 403.
    return { verdict: "acl-deny", node: "acl",
      why: "Tool ACL deny — the token's groups claim isn't in this tool's allow list. Blocked at the gateway." };
  }

  if (httpStatus === 200) {
    // Inner-gate deny: JSON-RPC success envelope but isError + "status 403" text.
    if (/HTTP call failed with status 4\d\d/.test(text) || (obj && deepIsError(obj))) {
      const m = text.match(/status (\d{3})/);
      return { verdict: "inner-gate-deny", node: "exchange",
        why: `Inner OIDC gate returned ${m ? m[1] : "40x"} — the token lacks the API audience/scope. This is the case token-exchange fixes on /mcp/ops.` };
    }
    return { verdict: "allow", node: "upstream",
      why: "All gates passed — the call reached the upstream and returned data." };
  }

  return { verdict: "unknown", node: null, why: `Unexpected HTTP ${httpStatus}.` };
}

function deepIsError(obj) {
  return !!(obj.result && obj.result.isError === true);
}

export default classify;
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd demo-ui && node --test verdict.test.js`
Expected: PASS — all 7 tests.

- [ ] **Step 5: Commit**

```bash
git add demo-ui/verdict.js demo-ui/verdict.test.js
git commit -m "feat(demo-ui): verdict classifier + unit tests (live-verified signatures)"
```

---

## Task 3: Keycloak adapter — mint, exchange, decode

**Files:**
- Create: `demo-ui/keycloak.js`

**Interfaces:**
- Consumes: `config`, `personas`, `tokenUrl` from `config.js`.
- Produces:
  - `mintToken(persona, scopeOverride?)` → `Promise<{ accessToken, claims }>` (ROPC; mirrors get-token.sh).
  - `exchangeToken(subjectToken, scopes = "dealers:read finance:read")` → `Promise<{ accessToken, claims }>` (RFC 8693 standard token exchange against Keycloak using the `kong-exchange` client; scopes only, NO audience param — per NOTES.md the audience param must name a client).
  - `decodeJwt(jwt)` → `claims` object (base64url payload decode, NO signature verify; display only).

- [ ] **Step 1: Create `demo-ui/keycloak.js`**

```js
// keycloak.js — mint persona tokens (ROPC), reproduce the RFC 8693 exchange,
// decode JWTs for display. Mirrors get-token.sh + the Phase-5 exchange (NOTES.md):
// exchange requests SCOPES only (Keycloak's audience param must name a client),
// and the subject token must carry kong-exchange in aud (mcp:use provides it).

import { config, personas, tokenUrl } from "./config.js";

export function decodeJwt(jwt) {
  const part = String(jwt).split(".")[1];
  if (!part) throw new Error("not a JWT");
  const b64 = part.replace(/-/g, "+").replace(/_/g, "/");
  const json = Buffer.from(b64, "base64").toString("utf8");
  return JSON.parse(json);
}

async function postForm(body, errCtx) {
  const res = await fetch(tokenUrl(), {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams(body),
  });
  const data = await res.json().catch(() => ({}));
  if (!res.ok || !data.access_token) {
    throw new Error(`${errCtx}: ${data.error_description || data.error || res.status}`);
  }
  return data.access_token;
}

export async function mintToken(persona, scopeOverride) {
  const p = personas[persona];
  if (!p) throw new Error(`unknown persona: ${persona}`);
  const scope = scopeOverride || p.scope;
  const accessToken = await postForm({
    grant_type: "password",
    client_id: config.demoCliId,
    client_secret: config.demoCliSecret,
    username: p.username,
    password: config.demoPassword,
    scope,
  }, "token request failed");
  return { accessToken, claims: decodeJwt(accessToken) };
}

export async function exchangeToken(subjectToken, scopes = "dealers:read finance:read") {
  // RFC 8693 standard exchange (Keycloak V2). NOTE: request scopes only — the
  // scope mappers add aud:[dealer-api,finance-api]; passing audience= would fail
  // (that param must name a registered client). See NOTES.md Phase-5 RESOLVED.
  const accessToken = await postForm({
    grant_type: "urn:ietf:params:oauth:grant-type:token-exchange",
    client_id: config.exchangeClientId,
    client_secret: config.exchangeSecret,
    subject_token: subjectToken,
    subject_token_type: "urn:ietf:params:oauth:token-type:access_token",
    scope: scopes,
  }, "token exchange failed");
  return { accessToken, claims: decodeJwt(accessToken) };
}
```

- [ ] **Step 2: Verify mint works against the LIVE stack**

Run: `cd demo-ui && node -e "import('./keycloak.js').then(async m=>{const t=await m.mintToken('olivia'); console.log('groups', t.claims.groups, 'scope', t.claims.scope); })"`
Expected: `groups [ 'ops' ] scope openid dealers:read finance:read mcp:use` (or similar — groups includes `ops`).

- [ ] **Step 3: Verify exchange works against the LIVE stack**

Run: `cd demo-ui && node -e "import('./keycloak.js').then(async m=>{const s=await m.mintToken('olivia','openid mcp:use'); const x=await m.exchangeToken(s.accessToken); console.log('before aud', s.claims.aud, '/ after aud', x.claims.aud); })"`
Expected: before aud lacks `dealer-api`; after aud includes `dealer-api` and `finance-api`. (If it errors, capture the message in NOTES.md and stop — do not guess.)

- [ ] **Step 4: Commit**

```bash
git add demo-ui/keycloak.js
git commit -m "feat(demo-ui): keycloak adapter — mint, RFC 8693 exchange, decode (live-verified)"
```

---

## Task 4: Kong adapter — MCP + REST calls

**Files:**
- Create: `demo-ui/kong.js`

**Interfaces:**
- Consumes: `config` from `config.js`.
- Produces:
  - `callMcp({ token, path, body })` → `Promise<{ httpStatus, body, raw }>` — POSTs a JSON-RPC body to `${kongUrl}${path}` with the Accept header Kong's listeners need (`application/json, text/event-stream`); parses an SSE `data:` line or plain JSON into `body`, keeps `raw` text.
  - `callRest({ token, path })` → `Promise<{ httpStatus, body, raw }>` — GET a REST route (for Step 1 OIDC gates).

> The MCP listeners answer a single stateless POST for `tools/list`/`tools/call` (demo.sh:28). Responses may be SSE (`data: {...}`) or JSON — handle both (demo.sh:30 strips `data: `).

- [ ] **Step 1: Create `demo-ui/kong.js`**

```js
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
```

- [ ] **Step 2: Verify a real MCP call end-to-end (mint → call → shape)**

Run: `cd demo-ui && node -e "import('./keycloak.js').then(async k=>{const {callMcp}=await import('./kong.js'); const t=await k.mintToken('olivia'); const r=await callMcp({token:t.accessToken,path:'/mcp/ops',body:{jsonrpc:'2.0',id:1,method:'tools/list'}}); console.log('status',r.httpStatus,'tools',(r.body.result?.tools||[]).map(x=>x.name)); })"`
Expected: `status 200 tools [ 'list_dealer_customers', 'list_invoices' ]`.

- [ ] **Step 3: Commit**

```bash
git add demo-ui/kong.js
git commit -m "feat(demo-ui): kong adapter — MCP + REST calls (SSE-aware, live-verified)"
```

---

## Task 5: Registry adapter

**Files:**
- Create: `demo-ui/registry.js`

**Interfaces:**
- Consumes: `config` (`konnectToken`, `konnectRegion`, `registryId`).
- Produces: `discover()` → `Promise<{ configured, servers, error? }>` where `servers` is `[{ name, title?, url }]`. Returns `{ configured:false }` when `registryId`/`konnectToken` absent (UI shows a "run registry-setup.sh" hint), never throws to the caller.

> API: `GET https://klabs.${region}.api.konghq.com/v0/mcp-registries/${id}/v0.1/servers` (NOTES.md + demo.sh:88). Servers under `.servers` or `.data`; each entry's payload under `.server` or itself; URL at `.remotes[0].url`.

- [ ] **Step 1: Create `demo-ui/registry.js`**

```js
// registry.js — Konnect MCP Registry discovery. PAT stays server-side. Mirrors
// demo.sh:87-96 parsing. US region / Labs tech preview (NOTES.md).

import { config } from "./config.js";

export async function discover() {
  if (!config.registryId || !config.konnectToken) return { configured: false, servers: [] };
  const url = `https://klabs.${config.konnectRegion}.api.konghq.com/v0/mcp-registries/${config.registryId}/v0.1/servers`;
  try {
    const res = await fetch(url, { headers: { Authorization: `Bearer ${config.konnectToken}` } });
    if (!res.ok) return { configured: true, servers: [], error: `registry API ${res.status}` };
    const data = await res.json();
    const raw = data.servers || data.data || [];
    const servers = raw.map(s => {
      const x = s.server || s;
      const remote = (x.remotes && x.remotes[0]) || {};
      return { name: x.name || "?", title: x.title, url: remote.url || "?" };
    });
    return { configured: true, servers };
  } catch (e) {
    return { configured: true, servers: [], error: String(e.message || e) };
  }
}
```

- [ ] **Step 2: Verify discovery against the LIVE registry**

Run: `cd demo-ui && node -e "import('./registry.js').then(async m=>{const r=await m.discover(); console.log('configured',r.configured,'count',r.servers.length); r.servers.forEach(s=>console.log(' ',s.name,'->',s.url)); if(r.error)console.log('ERR',r.error)})"`
Expected: `configured true count 5` and 5 servers advertising `http://localhost:8000/mcp/*`. (If the Labs API is unavailable, `error` is set and count 0 — record in NOTES.md; the UI degrades gracefully.)

- [ ] **Step 3: Commit**

```bash
git add demo-ui/registry.js
git commit -m "feat(demo-ui): registry discovery adapter (server-side PAT, live-verified)"
```

---

## Task 6: Scenarios data (the 7 Demo steps, mirroring demo.sh)

**Files:**
- Create: `demo-ui/scenarios.js`

**Interfaces:**
- Produces: `scenarios` (default export + named) — an array of 7 step objects. Each step:
  ```
  { id, n, title, tag, narration,
    calls: [ { label, persona, scope?, kind:"rest"|"mcp"|"registry",
               path, method?, tool?, args?, expect:{verdict}, note? } ],
    showExchange?: boolean }   // step 4 sets true → token BEFORE/AFTER panel
  ```
  Every field derives from `scripts/demo.sh` (the single source of truth) so on-screen expectations match the live HTTP outcomes.

- [ ] **Step 1: Create `demo-ui/scenarios.js`** (each call mirrors a line in demo.sh)

```js
// scenarios.js — the 7 Demo steps AS DATA. Single source of truth for Demo mode,
// mirroring scripts/demo.sh exactly (persona, scope, path, tool, args, expected
// verdict, narration). Shared by server (/api/scenarios) and client.

export const scenarios = [
  {
    id: "oidc", n: 1, title: "REST OIDC gates", tag: "OIDC",
    narration: "The raw APIs are protected before any MCP. No token → 401; dana (dealers:read) → 200; dana on the finance API → 403 (scope+audience).",
    calls: [
      { label: "no-token → /api/dealers/customers", persona: null, kind: "rest",
        path: "/api/dealers/customers", method: "GET", expect: { verdict: "auth-fail" } },
      { label: "dana → /api/dealers/customers", persona: "dana", kind: "rest",
        path: "/api/dealers/customers", method: "GET", expect: { verdict: "allow" } },
      { label: "dana → /api/finance/invoices (wrong scope+aud)", persona: "dana", kind: "rest",
        path: "/api/finance/invoices", method: "GET", expect: { verdict: "acl-deny" },
        note: "403 from the inner OIDC gate (scope+audience), shown as a deny." },
    ],
  },
  {
    id: "convert", n: 2, title: "REST → MCP conversion", tag: "CONVERT",
    narration: "Same APIs, now MCP tools, tag-aggregated: /mcp/dealers = 2 tools, /mcp/finance = 2, /mcp/ops = 2 bundled (dealer+finance).",
    calls: [
      { label: "/mcp/dealers tools/list", persona: "olivia", kind: "mcp", path: "/mcp/dealers",
        tool: null, method: "tools/list", expect: { verdict: "allow" } },
      { label: "/mcp/finance tools/list", persona: "olivia", kind: "mcp", path: "/mcp/finance",
        tool: null, method: "tools/list", expect: { verdict: "allow" } },
      { label: "/mcp/ops tools/list", persona: "olivia", kind: "mcp", path: "/mcp/ops",
        tool: null, method: "tools/list", expect: { verdict: "allow" } },
    ],
  },
  {
    id: "acl", n: 3, title: "Persona tool ACL", tag: "ACL",
    narration: "Filtering by the token's groups claim (no Kong consumers). olivia (ops) may call list_invoices; frank (finance) may NOT call a dealer tool.",
    calls: [
      { label: "olivia → list_invoices @ /mcp/ops", persona: "olivia", kind: "mcp",
        path: "/mcp/ops", tool: "list_invoices", args: {}, expect: { verdict: "allow" } },
      { label: "frank → list_dealer_customers @ /mcp/ops", persona: "frank", kind: "mcp",
        path: "/mcp/ops", tool: "list_dealer_customers", args: {}, expect: { verdict: "acl-deny" } },
    ],
  },
  {
    id: "exchange", n: 4, title: "RFC 8693 token exchange", tag: "EXCHANGE",
    showExchange: true,
    narration: "A token with ONLY 'mcp:use' lacks the dealer-api/finance-api audiences the inner gates need. On /mcp/ops Kong exchanges it so the call reaches the API; on /mcp/dealers it can't.",
    calls: [
      { label: "mcp:use-only olivia → /mcp/ops list_dealer_customers", persona: "olivia",
        scope: "openid mcp:use", kind: "mcp", path: "/mcp/ops", tool: "list_dealer_customers",
        args: {}, expect: { verdict: "allow" }, note: "Kong exchanges the token here." },
      { label: "mcp:use-only olivia → /mcp/dealers list_dealer_customers", persona: "olivia",
        scope: "openid mcp:use", kind: "mcp", path: "/mcp/dealers", tool: "list_dealer_customers",
        args: {}, expect: { verdict: "inner-gate-deny" }, note: "No exchange here → inner-gate 403." },
    ],
  },
  {
    id: "opa", n: 5, title: "External OPA policy", tag: "OPA",
    narration: "A rule the tool ACL cannot express: OPA denies list_invoices when the call argument query_status=overdue, even for a permitted caller. opa/policies/mcp.rego hot-reloads with no Kong sync.",
    calls: [
      { label: "olivia → list_invoices (no filter)", persona: "olivia", kind: "mcp",
        path: "/mcp/ops", tool: "list_invoices", args: {}, expect: { verdict: "allow" } },
      { label: "olivia → list_invoices query_status=overdue", persona: "olivia", kind: "mcp",
        path: "/mcp/ops", tool: "list_invoices", args: { query_status: "overdue" },
        expect: { verdict: "opa-deny" } },
    ],
  },
  {
    id: "remote", n: 6, title: "Passthrough remotes", tag: "REMOTE",
    narration: "Govern MCP servers Kong did not convert. /mcp/remote → local market-mcp (Cox tools); /mcp/remote-public → DeepWiki (third-party). Both require a cox-auto token.",
    calls: [
      { label: "/mcp/remote unauth", persona: null, kind: "mcp", path: "/mcp/remote",
        tool: null, method: "tools/list", expect: { verdict: "auth-fail" } },
      { label: "/mcp/remote-public authed tools/list", persona: "olivia", kind: "mcp",
        path: "/mcp/remote-public", tool: null, method: "tools/list", expect: { verdict: "allow" } },
    ],
  },
  {
    id: "registry", n: 7, title: "MCP Registry discovery", tag: "REGISTRY",
    narration: "The servers are catalogued in Konnect's MCP Registry — discoverable by any host-side client (e.g. Claude Code).",
    calls: [
      { label: "Konnect MCP Registry — discover servers", kind: "registry",
        expect: { verdict: "allow" } },
    ],
  },
];

export default scenarios;
```

- [ ] **Step 2: Sanity-check the data shape**

Run: `cd demo-ui && node -e "import('./scenarios.js').then(m=>{console.log('steps',m.scenarios.length); console.log('step4 exchange?',m.scenarios[3].showExchange); console.log('calls total',m.scenarios.reduce((a,s)=>a+s.calls.length,0)); })"`
Expected: `steps 7`, `step4 exchange? true`, `calls total 14`.

- [ ] **Step 3: Commit**

```bash
git add demo-ui/scenarios.js
git commit -m "feat(demo-ui): 7 Demo scenarios as data (mirrors demo.sh)"
```

---

## Task 7: Stack action whitelist (SSE runner)

**Files:**
- Create: `demo-ui/stack.js`

**Interfaces:**
- Consumes: nothing from other modules (uses `node:child_process`, `config` only for repo root).
- Produces:
  - `ACTIONS` — frozen map `{ up, down, sync, preflight, smoke, registry-setup }` → `{ cmd, args, desc }`.
  - `runAction(action, onData, onEnd)` → spawns the mapped command from the repo root, streams stdout+stderr lines to `onData(line)`, calls `onEnd(code)` on exit. Throws synchronously if `action` not in `ACTIONS`.

> Commands map to existing scripts/compose. `sync` mirrors the compose deck sync (NEXT-SESSION.md:12). Repo root is `demo-ui/..`.

- [ ] **Step 1: Create `demo-ui/stack.js`**

```js
// stack.js — the ONLY commands the UI may run (fixed whitelist → no arbitrary
// exec). Each streams stdout/stderr to the browser over SSE. Repo-root cwd.

import { spawn } from "node:child_process";
import { fileURLToPath } from "node:url";
import { dirname, resolve } from "node:path";

const REPO = resolve(dirname(fileURLToPath(import.meta.url)), "..");

export const ACTIONS = Object.freeze({
  "up":             { cmd: "docker", args: ["compose", "up", "-d"], desc: "Start the stack (detached)" },
  "down":           { cmd: "docker", args: ["compose", "down"], desc: "Stop the stack" },
  "sync":           { cmd: "docker", args: ["compose", "--profile", "tools", "run", "--rm", "deck", "gateway", "sync", "/config/konnect.yaml"], desc: "deck gateway sync" },
  "preflight":      { cmd: "bash", args: ["scripts/preflight.sh"], desc: "Preflight checks" },
  "smoke":          { cmd: "bash", args: ["scripts/smoke-test.sh"], desc: "Smoke test" },
  "registry-setup": { cmd: "bash", args: ["scripts/registry-setup.sh"], desc: "Publish to the MCP Registry" },
});

export function runAction(action, onData, onEnd) {
  const spec = ACTIONS[action];
  if (!spec) throw new Error(`action not allowed: ${action}`);
  const child = spawn(spec.cmd, spec.args, { cwd: REPO, env: process.env });
  const pump = (buf) => String(buf).split("\n").forEach(l => l && onData(l));
  child.stdout.on("data", pump);
  child.stderr.on("data", pump);
  child.on("close", (code) => onEnd(code ?? -1));
  child.on("error", (e) => { onData(`[spawn error] ${e.message}`); onEnd(-1); });
  return child;
}
```

- [ ] **Step 2: Verify the whitelist rejects unknown actions and lists known ones**

Run: `cd demo-ui && node -e "import('./stack.js').then(m=>{console.log('actions',Object.keys(m.ACTIONS).join(',')); try{m.runAction('rm -rf /',()=>{},()=>{})}catch(e){console.log('rejected:',e.message)} })"`
Expected: `actions up,down,sync,preflight,smoke,registry-setup` and `rejected: action not allowed: rm -rf /`.

- [ ] **Step 3: Commit**

```bash
git add demo-ui/stack.js
git commit -m "feat(demo-ui): whitelisted stack-action SSE runner"
```

---

## Task 8: Express server wiring all endpoints

**Files:**
- Create: `demo-ui/server.js`

**Interfaces:**
- Consumes: `config`, all adapters, `scenarios`, `classify`.
- Produces: an Express app listening on `127.0.0.1:${uiPort}` with these routes (spec §"Backend endpoints"):
  - `GET /api/scenarios` → the 7 scenarios (data for the stepper).
  - `POST /api/mcp` `{persona, scope?, path, method?, tool?, args?}` → mints token, fires call (REST if path starts `/api/`, else MCP), returns `{ httpStatus, body, verdict, tokenClaims }`.
  - `POST /api/token` `{persona, scope?}` → `{ accessToken, claims }`.
  - `POST /api/token/decode` `{jwt}` → `{ claims }`.
  - `POST /api/exchange-preview` `{persona, scope?}` → mints an mcp:use-only token, exchanges it, returns `{ before, after }` claim sets (spec U7 out-of-band reproduction).
  - `GET /api/registry` → `discover()`.
  - `GET /api/status` → `docker compose ps` parsed to `[{service,status,healthy}]`.
  - `GET /api/stack/:action` (SSE) → streams `runAction` output; rejects non-whitelisted with 400.
  - static: serves `public/`.

- [ ] **Step 1: Create `demo-ui/server.js`**

```js
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
```

- [ ] **Step 2: Boot the server and hit the plumbing endpoints (server already testable headless)**

Run:
```bash
cd demo-ui && (node server.js &) && sleep 1
curl -s localhost:4000/api/scenarios | node -e "process.stdin.on('data',d=>console.log('scenarios',JSON.parse(d).scenarios.length))"
curl -s -X POST localhost:4000/api/mcp -H 'Content-Type: application/json' -d '{"persona":"olivia","path":"/mcp/ops","tool":"list_invoices","args":{}}' | node -e "process.stdin.on('data',d=>{const j=JSON.parse(d);console.log('verdict',j.verdict.verdict,'http',j.httpStatus)})"
curl -s -X POST localhost:4000/api/exchange-preview -H 'Content-Type: application/json' -d '{"persona":"olivia"}' | node -e "process.stdin.on('data',d=>{const j=JSON.parse(d);console.log('before aud',j.before.aud,'after aud',j.after.aud)})"
pkill -f "node server.js"
```
Expected: `scenarios 7`; `verdict allow http 200`; before aud without `dealer-api`, after aud with `dealer-api`+`finance-api`.

- [ ] **Step 3: Commit**

```bash
git add demo-ui/server.js
git commit -m "feat(demo-ui): express server wiring all /api endpoints"
```

---

## Task 9: SPA shell + Cox palette (index.html + styles.css)

**Files:**
- Create: `demo-ui/public/index.html`
- Create: `demo-ui/public/styles.css`

**Interfaces:**
- Produces: the app chrome from the visuals — top app-bar (three dots + "Cox Automotive · Governed MCP on Kong AI Gateway"), left nav (Demo / Explore / Stack), and a `#view` container `app.js` renders into. CSS variables define the Cox palette (`--cox-blue`, `--cox-navy`, node/chip colors from the visuals).

> Visual contract: `claude/specs/visuals/2026-07-22-demo-ui/demo-layout.html` (dark chrome `#0d1117`/`#161b22`, nav highlight `#1f6feb`, node borders `#30363d`, pass `#238636`, deny `#da3633`, exchange `#8957e5`). Cox blue overrides the generic `#1f6feb` accent.

- [ ] **Step 1: Create `demo-ui/public/index.html`**

```html
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>Cox Automotive · Governed MCP</title>
  <link rel="stylesheet" href="/styles.css" />
</head>
<body>
  <div class="appwin">
    <header class="appbar">
      <span class="dot red"></span><span class="dot amber"></span><span class="dot green"></span>
      <span class="appbar-title">Cox Automotive · Governed MCP on Kong AI Gateway</span>
      <span class="appbar-approx" title="Approximate Cox palette — exact hex is a one-line CSS-variable swap">palette ≈ Cox</span>
    </header>
    <div class="appbody">
      <nav class="nav">
        <a class="navitem" href="#/demo" data-mode="demo">▷ Demo</a>
        <a class="navitem" href="#/explore" data-mode="explore">⌕ Explore</a>
        <a class="navitem" href="#/stack" data-mode="stack">⚙ Stack</a>
      </nav>
      <main id="view" class="main"><!-- rendered by app.js --></main>
    </div>
  </div>
  <script type="module" src="/app.js"></script>
</body>
</html>
```

- [ ] **Step 2: Create `demo-ui/public/styles.css`**

```css
/* Cox palette (APPROXIMATE — blue/navy). Exact hex = one-line swap here. */
:root {
  --cox-blue: #0b5fff;      /* accent / current */
  --cox-navy: #0a2540;      /* deep brand */
  --bg: #0d1117; --panel: #161b22; --border: #30363d; --muted: #8b949e;
  --text: #e6edf3; --pass: #238636; --deny: #da3633; --warn: #9e6a03; --exch: #8957e5;
  --mono: ui-monospace, SFMono-Regular, Menlo, monospace;
}
* { box-sizing: border-box; }
body { margin: 0; background: #05070a; color: var(--text);
  font: 14px/1.5 -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; }
.appwin { max-width: 1100px; margin: 18px auto; border: 1px solid var(--border);
  border-radius: 12px; overflow: hidden; background: var(--bg); }
.appbar { display: flex; gap: 7px; align-items: center; padding: 9px 14px;
  background: var(--panel); border-bottom: 1px solid var(--border); font-weight: 600; }
.appbar-title { margin-left: 6px; }
.appbar-approx { margin-left: auto; font-size: 10px; color: var(--muted);
  border: 1px solid var(--border); border-radius: 20px; padding: 2px 8px; }
.dot { width: 10px; height: 10px; border-radius: 50%; }
.dot.red{background:#da3633}.dot.amber{background:#f0b429}.dot.green{background:#238636}
.appbody { display: flex; min-height: 520px; }
.nav { width: 130px; background: var(--bg); border-right: 1px solid var(--border);
  padding: 10px; display: flex; flex-direction: column; gap: 5px; }
.navitem { padding: 7px 9px; border-radius: 7px; color: var(--muted);
  text-decoration: none; font-weight: 500; }
.navitem.on { background: color-mix(in srgb, var(--cox-blue) 18%, transparent);
  color: #7fb0ff; font-weight: 700; }
.main { flex: 1; padding: 0; overflow: auto; display: flex; flex-direction: column; }

/* stepper */
.stepper { display: flex; border-bottom: 1px solid var(--border); }
.step { flex: 1; text-align: center; padding: 8px 2px; font-size: 10px; color: #6e7681;
  border-right: 1px solid #21262d; cursor: pointer; background: none; border-top: none;
  border-left: none; font-family: inherit; }
.step:last-child { border-right: none; }
.step .n { display: block; font-size: 14px; font-weight: 700; }
.step.done { color: #3fb950; }
.step.cur { color: #fff; background: color-mix(in srgb, var(--cox-blue) 18%, transparent);
  font-weight: 700; box-shadow: inset 0 -2px 0 var(--cox-blue); }

.content2 { padding: 12px 14px; flex: 1; }
.label { font-size: 9px; letter-spacing: .08em; color: var(--muted);
  text-transform: uppercase; margin-bottom: 4px; }

/* trace nodes */
.trace { display: flex; gap: 6px; flex-wrap: wrap; align-items: center; margin: 8px 0; }
.node { border: 1px solid var(--border); border-radius: 8px; padding: 6px 9px;
  background: var(--panel); text-align: center; min-width: 62px; font-size: 11px; }
.node.pass { border-color: var(--pass); }
.node.fail { border-color: var(--deny); box-shadow: 0 0 0 2px color-mix(in srgb, var(--deny) 30%, transparent); }
.node.exch { border-color: var(--exch); box-shadow: 0 0 0 2px color-mix(in srgb, var(--exch) 30%, transparent); }
.node.idle { opacity: .4; }
.arrow { color: #6e7681; }

.chip { display: inline-block; padding: 2px 7px; border-radius: 20px; font-size: 10px; font-weight: 600; }
.chip.ok{background:var(--pass);color:#fff}.chip.deny{background:var(--deny);color:#fff}
.chip.warn{background:var(--warn);color:#fff}.chip.muted{background:var(--border);color:#c9d1d9}
.chip.new{background:var(--exch);color:#fff}

.persbtn { padding: 4px 10px; border-radius: 7px; border: 1px solid var(--border);
  margin-right: 5px; background: none; color: var(--text); cursor: pointer; font: inherit; font-size: 12px; }
.persbtn.sel { background: var(--cox-blue); border-color: var(--cox-blue); color: #fff; }
.runbtn { background: var(--pass); color: #fff; border: none; padding: 7px 16px;
  border-radius: 7px; font-weight: 700; cursor: pointer; }
.runbtn:disabled { opacity: .5; cursor: default; }

.panel { border: 1px solid var(--border); border-radius: 8px; padding: 9px; background: var(--panel); }
.why { border-left: 3px solid var(--deny); padding: 7px 10px;
  background: color-mix(in srgb, var(--deny) 12%, transparent); border-radius: 4px; margin-top: 8px; }
.why.ok { border-left-color: var(--pass); background: color-mix(in srgb, var(--pass) 12%, transparent); }
.why.exch { border-left-color: var(--exch); background: color-mix(in srgb, var(--exch) 12%, transparent); }
.kv { font-family: var(--mono); font-size: 11.5px; line-height: 1.65; white-space: pre-wrap; word-break: break-word; }
.kv .k{color:#7ee787}.kv .p{color:#79c0ff}.kv .add{color:var(--exch);font-weight:700}
.grid2 { display: grid; grid-template-columns: 1fr 1fr; gap: 8px; }
.row { display: flex; justify-content: space-between; align-items: center; gap: 8px; }
select, input[type=text] { background: var(--panel); color: var(--text);
  border: 1px solid var(--border); border-radius: 6px; padding: 5px 8px; font: inherit; }
.term { font-family: var(--mono); font-size: 11.5px; background: #05070a;
  border: 1px solid var(--border); border-radius: 8px; padding: 9px; height: 300px;
  overflow: auto; white-space: pre-wrap; }
.tile { border: 1px solid var(--border); border-radius: 8px; padding: 9px 11px; background: var(--panel); }
a.link { color: #7fb0ff; }
```

- [ ] **Step 3: Verify the shell serves (visual placeholder OK until app.js exists)**

Run: `cd demo-ui && (node server.js &) && sleep 1 && curl -s localhost:4000/ | grep -o "Governed MCP on Kong AI Gateway" && pkill -f "node server.js"`
Expected: prints `Governed MCP on Kong AI Gateway`.

- [ ] **Step 4: Commit**

```bash
git add demo-ui/public/index.html demo-ui/public/styles.css
git commit -m "feat(demo-ui): SPA shell + Cox palette (approx) from approved visuals"
```

---

## Task 10: Trace renderer + shared hybrid panel (trace.js)

**Files:**
- Create: `demo-ui/public/trace.js`

**Interfaces:**
- Produces (ES-module exports used by `app.js`):
  - `NODE_ORDER` = `["persona","oauth2","exchange","acl","opa","upstream"]`.
  - `renderTrace(verdict, { showExchange })` → HTML string of the plugin-chain hero. The node named by `verdict.node` (mapped from classifier `node` ids: `oauth2→oauth2`, `acl→acl`, `opa→opa`, `exchange→exchange`, `upstream→upstream`) lights red on a deny; all nodes before it are `pass`; nodes after are `idle`; on `allow` all are `pass`. The exchange node is only shown when `showExchange` is true (else omitted from the chain).
  - `renderPanel({ verdict, httpStatus, body, tokenClaims, exchange, showExchange })` → HTML string for the full hybrid panel: trace hero → why line → (token BEFORE/AFTER grid if `exchange`) or token claims → response. Reused by Demo and Explore.
  - `fmtClaims(claims, highlightKeys?)` → HTML of a compact claim view (`aud`, `scope`, `groups`, `sub`, `azp`, `exp`), optionally marking `highlightKeys` with the `.add` class (for AFTER-exchange deltas).

- [ ] **Step 1: Create `demo-ui/public/trace.js`**

```js
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
    if (n === "persona") { cls += ""; chip = '<span class="chip muted">token</span>'; }
    if (!reached) { cls += " idle"; }
    else if (failNode && n === failNode) { cls += (n === "exchange") ? " exch" : " fail";
      chip = `<span class="chip ${n === "exchange" ? "new" : "deny"}">${n === "exchange" ? "no aud" : "DENY"}</span>`; reached = false; }
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
```

- [ ] **Step 2: Verify the module parses in Node (browser ESM is the same syntax)**

Run: `cd demo-ui && node -e "import('./public/trace.js').then(m=>{const html=m.renderTrace({verdict:'acl-deny',node:'acl'},{showExchange:false}); console.log('has fail node?', html.includes('node fail')); console.log('nodes', (html.match(/class=\"node/g)||[]).length); })"`
Expected: `has fail node? true`, `nodes 5` (persona, oauth2, acl, opa, upstream — no exchange when showExchange false).

- [ ] **Step 3: Commit**

```bash
git add demo-ui/public/trace.js
git commit -m "feat(demo-ui): trace renderer + shared hybrid panel"
```

---

## Task 11: App router + Demo / Explore / Stack views (app.js)

**Files:**
- Create: `demo-ui/public/app.js`

**Interfaces:**
- Consumes: `renderPanel`, `renderTrace`, `fmtClaims` from `/trace.js`; the `/api/*` endpoints.
- Produces: a hash-router SPA. On load, fetches `/api/scenarios`. Routes: `#/demo` (default), `#/explore`, `#/stack`. Each renders into `#view`. Nav item gets `.on` for the active mode.

- [ ] **Step 1: Create `demo-ui/public/app.js`**

```js
// app.js — hash router + the three views. Vanilla ESM, no framework/build.
import { renderPanel } from "/trace.js";

const view = document.getElementById("view");
const api = {
  scenarios: () => fetch("/api/scenarios").then(r => r.json()),
  mcp: (payload) => fetch("/api/mcp", { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify(payload) }).then(r => r.json()),
  exchangePreview: (persona) => fetch("/api/exchange-preview", { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ persona }) }).then(r => r.json()),
  registry: () => fetch("/api/registry").then(r => r.json()),
  status: () => fetch("/api/status").then(r => r.json()),
};

let SCENARIOS = [];
const state = { stepIdx: 0, persona: "olivia" };
const PERSONAS = ["dana", "frank", "olivia"];

function setNav(mode) {
  document.querySelectorAll(".navitem").forEach(a =>
    a.classList.toggle("on", a.dataset.mode === mode));
}

// ---------- DEMO ----------
async function renderDemo() {
  setNav("demo");
  const sc = SCENARIOS[state.stepIdx];
  const steps = SCENARIOS.map((s, i) =>
    `<button class="step ${i < state.stepIdx ? "done" : ""} ${i === state.stepIdx ? "cur" : ""}" data-i="${i}">
       <span class="n">${s.n}</span>${s.tag}</button>`).join("");
  const personas = PERSONAS.map(p =>
    `<button class="persbtn ${p === state.persona ? "sel" : ""}" data-p="${p}">${p}</button>`).join("");
  view.innerHTML = `
    <div class="stepper">${steps}</div>
    <div class="content2">
      <div class="row">
        <div><strong>Step ${sc.n}/7 · ${sc.title}</strong></div>
        <div>${personas} <button class="runbtn" id="run">▶ Run step</button></div>
      </div>
      <p style="color:var(--muted);margin:8px 0">${sc.narration}</p>
      <div id="result"></div>
    </div>`;
  view.querySelectorAll(".step").forEach(b => b.onclick = () => { state.stepIdx = +b.dataset.i; renderDemo(); });
  view.querySelectorAll(".persbtn").forEach(b => b.onclick = () => { state.persona = b.dataset.p; });
  view.querySelector("#run").onclick = () => runDemoStep(sc);
}

async function runDemoStep(sc) {
  const out = view.querySelector("#result");
  out.innerHTML = `<p style="color:var(--muted)">Running ${sc.calls.length} call(s)…</p>`;
  const blocks = [];
  for (const call of sc.calls) {
    if (call.kind === "registry") {
      const r = await api.registry();
      blocks.push(renderRegistryBlock(r));
      continue;
    }
    const persona = call.persona === undefined ? state.persona : call.persona;
    const payload = { persona, scope: call.scope, path: call.path,
      method: call.method, tool: call.tool, args: call.args };
    const res = await api.mcp(payload);
    let exchange = null;
    if (sc.showExchange && persona && call.expect.verdict === "allow") {
      exchange = await api.exchangePreview(persona);
    }
    const match = res.verdict.verdict === call.expect.verdict;
    blocks.push(`
      <div class="tile" style="margin-top:10px">
        <div class="row"><div class="label">${call.label}</div>
          <div>expected <span class="chip muted">${call.expect.verdict}</span>
               got <span class="chip ${match ? "ok" : "deny"}">${res.verdict.verdict}</span></div></div>
        ${call.note ? `<p style="color:var(--muted);font-size:12px;margin:6px 0">${call.note}</p>` : ""}
        ${renderPanel({ ...res, exchange, showExchange: sc.showExchange })}
      </div>`);
  }
  out.innerHTML = blocks.join("");
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
  view.innerHTML = `
    <div class="content2">
      <div class="label">Stack — status</div>
      <div id="st-status" class="grid2" style="grid-template-columns:repeat(3,1fr)">Loading…</div>
      <div class="label" style="margin-top:14px">Actions (whitelisted)</div>
      <div class="row" style="justify-content:flex-start;gap:6px;flex-wrap:wrap">
        ${STACK_ACTIONS.map(([a, d]) => `<button class="persbtn" data-a="${a}" title="${d}">${a}</button>`).join("")}
      </div>
      <div class="label" style="margin-top:12px">Output</div>
      <div class="term" id="st-term">(select an action)</div>
      <div class="label" style="margin-top:12px">Konnect analytics</div>
      <a class="link" id="dash-link" href="#" target="_blank" rel="noopener">Open the “Cox Automotive: Governed MCP” dashboard in Konnect ↗</a>
    </div>`;
  // dashboard deep-link (id from a data attribute the server can template later; hardcode-free: read from registry region)
  const dash = document.getElementById("dash-link");
  dash.href = "https://cloud.konghq.com/us/analytics/dashboards"; // region-generic entry; exact dashboard id shown in Stack note
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
  const h = location.hash || "#/demo";
  if (h.startsWith("#/explore")) return renderExplore();
  if (h.startsWith("#/stack")) return renderStack();
  return renderDemo();
}
window.addEventListener("hashchange", route);
(async function init() {
  const data = await api.scenarios();
  SCENARIOS = data.scenarios;
  route();
})();
```

- [ ] **Step 2: Note the dashboard deep-link** — the exact dashboard id (`388e3b28-…`) is org-specific and not in `.env`; the Stack view links to the region analytics area and shows the dashboard name so the SE clicks through. (Task 13 optionally adds `KONNECT_DASHBOARD_ID` to `.env`/config for a precise deep-link.)

- [ ] **Step 3: Manual live verification (browser)** — start the server, open the UI, walk all three modes.

Run: `scripts/ui.sh` then open `http://127.0.0.1:4000`. Verify:
- Demo: click steps 1–7; for each, ▶ Run → the on-screen verdict chip matches `expected` (green). Step 4 shows the BEFORE/AFTER token grid with `dealer-api`/`finance-api` highlighted in AFTER.
- Explore: olivia + `/mcp/ops` + `list_invoices` + `{"query_status":"overdue"}` → OPA deny.
- Stack: status tiles show 6 services; click `preflight` → streamed output ends with `[exit 0]`.

Expected: all verdicts match; no console errors.

- [ ] **Step 4: Commit**

```bash
git add demo-ui/public/app.js
git commit -m "feat(demo-ui): router + Demo/Explore/Stack views wired to live stack"
```

---

## Task 12: LIVE re-verification of every verdict signature (doc-vs-reality gate)

**Files:**
- Modify: `NOTES.md` (append a demo-ui verification block)
- Modify: `demo-ui/verdict.js` (only if a signature drifted)

**Interfaces:** none (verification task).

> Per the project's doc-vs-reality discipline + the spec's open item: confirm each classifier signature against the running stack before trusting it. The inner-gate case (HTTP 200 + isError) is the one most likely to surprise.

- [ ] **Step 1: Capture each real signature via the running server**

Run (server up on :4000):
```bash
cd demo-ui
echo "--- 401 auth-fail ---";      curl -s -X POST localhost:4000/api/mcp -H 'Content-Type: application/json' -d '{"path":"/mcp/remote","method":"tools/list"}' | node -e "process.stdin.on('data',d=>{const j=JSON.parse(d);console.log(j.httpStatus,j.verdict.verdict)})"
echo "--- acl-deny ---";           curl -s -X POST localhost:4000/api/mcp -H 'Content-Type: application/json' -d '{"persona":"frank","path":"/mcp/ops","tool":"list_dealer_customers","args":{}}' | node -e "process.stdin.on('data',d=>{const j=JSON.parse(d);console.log(j.httpStatus,j.verdict.verdict)})"
echo "--- opa-deny ---";           curl -s -X POST localhost:4000/api/mcp -H 'Content-Type: application/json' -d '{"persona":"olivia","path":"/mcp/ops","tool":"list_invoices","args":{"query_status":"overdue"}}' | node -e "process.stdin.on('data',d=>{const j=JSON.parse(d);console.log(j.httpStatus,j.verdict.verdict)})"
echo "--- inner-gate-deny ---";    curl -s -X POST localhost:4000/api/mcp -H 'Content-Type: application/json' -d '{"persona":"olivia","scope":"openid mcp:use","path":"/mcp/dealers","tool":"list_dealer_customers","args":{}}' | node -e "process.stdin.on('data',d=>{const j=JSON.parse(d);console.log(j.httpStatus,j.verdict.verdict)})"
echo "--- allow (exchange) ---";   curl -s -X POST localhost:4000/api/mcp -H 'Content-Type: application/json' -d '{"persona":"olivia","scope":"openid mcp:use","path":"/mcp/ops","tool":"list_dealer_customers","args":{}}' | node -e "process.stdin.on('data',d=>{const j=JSON.parse(d);console.log(j.httpStatus,j.verdict.verdict)})"
```
Expected:
```
--- 401 auth-fail ---      401 auth-fail
--- acl-deny ---           403 acl-deny
--- opa-deny ---           403 opa-deny
--- inner-gate-deny ---    200 inner-gate-deny
--- allow (exchange) ---   200 allow
```

- [ ] **Step 2: If any line mismatches** — inspect the raw body (`curl … | node -e "…console.log(j.raw)"`), correct `verdict.js` to match the observed signature, re-run Task 2's unit test, and record the discrepancy in `NOTES.md`. Do NOT adjust the expected value to hide a mismatch.

- [ ] **Step 3: Append the verification block to `NOTES.md`**

```markdown
## Build findings (demo-ui) — verdict signatures re-verified LIVE
- ✅ All 5 verdict signatures reproduced through the demo-ui server against the running stack
  (401 auth-fail; 403 HTML acl-deny; 403 {"message":"unauthorized"} opa-deny; HTTP 200 + JSON-RPC
  isError "status 403" inner-gate-deny; HTTP 200 result.content allow). classify() matches all five.
- [record any drift + fix here if Step 2 fired]
```

- [ ] **Step 4: Commit**

```bash
git add NOTES.md demo-ui/verdict.js
git commit -m "test(demo-ui): re-verify all verdict signatures live; NOTES.md doc-vs-reality"
```

---

## Task 13: Docs + handoff updates (README, ARCHITECTURE, handoff, dashboard link)

**Files:**
- Modify: `README.md` (add a "demo-ui cockpit" section + Known Issues if any)
- Modify: `ARCHITECTURE.md` (add the demo-ui module row(s))
- Modify: `.env.example` (document optional `UI_PORT` + `KONNECT_DASHBOARD_ID`)
- Modify: `demo-ui/config.js` (add `dashboardId` from `KONNECT_DASHBOARD_ID`) and `public/app.js` (precise deep-link when set)
- Modify: `claude/handoff/state.md`, `claude/handoff/shipped-log.md`, `claude/NEXT-SESSION.md`

**Interfaces:** none (docs).

- [ ] **Step 1: Add `dashboardId` to config + precise deep-link**

In `demo-ui/config.js` add to the `config` object: `dashboardId: env.KONNECT_DASHBOARD_ID || "",`. Add a `GET /api/meta` route to `server.js` returning `{ dashboardId: config.dashboardId, region: config.konnectRegion }`, and in `app.js` `renderStack()`, if `meta.dashboardId` is set, point `dash.href` at `https://cloud.konghq.com/${region}/analytics/dashboards/${dashboardId}`.

```js
// server.js — add near the other GET routes:
app.get("/api/meta", (_req, res) => res.json({ dashboardId: config.dashboardId, region: config.konnectRegion }));
```

```js
// app.js renderStack() — replace the static dash.href line with:
const meta = await fetch("/api/meta").then(r => r.json()).catch(() => ({}));
dash.href = meta.dashboardId
  ? `https://cloud.konghq.com/${meta.region}/analytics/dashboards/${meta.dashboardId}`
  : `https://cloud.konghq.com/${meta.region || "us"}/analytics/dashboards`;
```

- [ ] **Step 2: Document `UI_PORT` + `KONNECT_DASHBOARD_ID` in `.env.example`**

Append under a new section:
```bash
# -----------------------------------------------------------------------------
# demo-ui cockpit (host-run; scripts/ui.sh). Optional.
#   UI_PORT               -> port for the local cockpit (default 4000)
#   KONNECT_DASHBOARD_ID  -> deep-link the Stack view to the Konnect analytics dashboard
# -----------------------------------------------------------------------------
UI_PORT=4000
KONNECT_DASHBOARD_ID=
```

- [ ] **Step 3: Add a README section**

Add after the demo walkthrough:
```markdown
## demo-ui — the visual cockpit (optional)

A local, Cox-branded web cockpit that drives the same live stack as `scripts/demo.sh`, but
visualizes each governance decision (plugin-chain trace + token before/after + verdict).

```bash
scripts/ui.sh            # installs deps on first run, serves http://127.0.0.1:4000
```

Three modes: **Demo** (the scripted 7-step story with a top stepper), **Explore** (free
persona/endpoint/tool sandbox), **Stack** (status + whitelisted actions: up/down/sync/preflight/
smoke/registry-setup, streamed live; plus a deep-link to the Konnect analytics dashboard).

Host prereq: Node 20+. Local-only (binds 127.0.0.1); all secrets stay server-side.
```

- [ ] **Step 4: Add ARCHITECTURE.md rows** for the `demo-ui/` module (server.js, adapters, verdict.js, scenarios.js, public/ SPA) per that file's existing table format.

- [ ] **Step 5: Update handoff fragments**

- `claude/handoff/state.md`: add a "demo-ui — COMPLETE + live-verified" bullet.
- `claude/handoff/shipped-log.md`: append a dated entry (append-only) for the demo-ui build.
- `claude/NEXT-SESSION.md`: refresh the "Since last session" block to note demo-ui shipped + how to launch it.

- [ ] **Step 6: Full unit-test + static sanity pass**

Run: `cd demo-ui && node --test && node -e "['config.js','keycloak.js','kong.js','verdict.js','registry.js','scenarios.js','stack.js','server.js','public/app.js','public/trace.js'].forEach(f=>import('./'+f).catch(e=>{console.error('PARSE FAIL',f,e.message);process.exit(1)}))" && echo "all modules parse"`
Expected: unit tests pass; `all modules parse` (server.js import will start listening — acceptable, or guard with a `if (import.meta.url===...)` main check; kill after).

- [ ] **Step 7: Commit**

```bash
git add README.md ARCHITECTURE.md .env.example demo-ui/config.js demo-ui/server.js demo-ui/public/app.js claude/handoff/state.md claude/handoff/shipped-log.md claude/NEXT-SESSION.md
git commit -m "docs(demo-ui): README + ARCHITECTURE + handoff + dashboard deep-link"
```

---

## Self-Review

**Spec coverage:**
- U1 three modes → Tasks 11 (Demo/Explore/Stack). ✅
- U2 hybrid viz (trace → why → token → response) → Task 10 `renderPanel`. ✅
- U3 top stepper → Task 11 `renderDemo`. ✅
- U4 whitelisted execute buttons + streamed output → Tasks 7 + 8 (SSE) + 11 (Stack). ✅
- U5 Cox palette via CSS variables (approximate, flagged) → Task 9. ✅
- U6 host-run Node/Express + vanilla SPA, no build → Tasks 1, 8–11. ✅
- U7 out-of-band exchange reproduction → Tasks 3 + 8 (`/api/exchange-preview`) + 10/11 (BEFORE/AFTER). ✅
- All 7 backend endpoints → Task 8. ✅
- verdict classifier w/ unit test → Task 2; live re-verify → Task 12. ✅
- scenarios as data mirroring demo.sh → Task 6. ✅
- registry deep-link / dashboard tile → Tasks 5 + 13. ✅
- config from .env, no new hardcoded values → Task 1 (Env Contract). ✅
- local-only, secrets server-side → Tasks 1, 8 (bind 127.0.0.1). ✅
- testing: unit + live smoke reuse → Tasks 2, 12 (+ existing smoke-test.sh via Stack). ✅

**Placeholder scan:** No TBD/TODO; every code step shows full code; every verify step shows the command + expected output. ✅

**Type consistency:** `classify({httpStatus, body}) → {verdict, node, why}` used identically in verdict.test.js, server.js, trace.js. `mintToken`/`exchangeToken` return `{accessToken, claims}` used consistently in server.js. `renderPanel({verdict, httpStatus, body, tokenClaims, exchange, showExchange})` matches app.js call sites. `scenarios[].calls[]` shape defined in Task 6 consumed in Task 11. ✅

**Open items carried into build (from spec):** exact Cox hex (approx, CSS-var swap — flagged); SSE keep-alive for long actions (Task 8 sends `: keep-alive` every 15s); dashboard id precise deep-link (Task 13, optional env). ✅
