# RUNBOOK — Running cai-mcp-demo for the first time

This is the **start-here** guide. For deep reference (per-step demo expectations,
plugin-schema notes, full troubleshooting) see [README.md](./README.md) and [NOTES.md](./NOTES.md).

> **What you get:** Kong Gateway (Konnect hybrid) turning REST APIs into governed MCP servers —
> OAuth-gated, token-claim tool ACLs, RFC 8693 exchange, OPA policy, remote-MCP passthrough,
> discoverable in the Konnect MCP Registry, with a Konnect analytics dashboard.

## 1. Before you begin (human-only — cannot be scripted)

You need a **Konnect organization** with:

| Requirement | Why | Where |
|-------------|-----|-------|
| **AI Gateway Enterprise** entitlement (tech preview) | `ai-mcp-oauth2` / `ai-mcp-proxy` plugins require it | Konnect org tier |
| A **Personal Access Token (PAT)** with control-plane admin rights | Bootstrap + config sync + dashboard | Konnect → *your avatar* → Personal Access Tokens |
| *(only for `--with-registry`)* **Labs → "Catalog - MCP Registry"** = ON | Publish/discover MCP servers | Konnect → Organization → Labs (US region only) |

Local tools: **Docker + Docker Compose v2**, `curl`, `jq`, `python3`, `openssl`.
(`setup.sh` checks these and tells you what's missing.)

## 2. Set up (one command)

```bash
git clone <this-repo> && cd cai-mcp-demo
./scripts/setup.sh
```

On first run with no `.env`, setup copies `.env.example → .env` and **prompts** for your
`KONNECT_TOKEN` + region, then runs the whole flow. For the full experience (analytics + registry):

```bash
./scripts/setup.sh --with-dashboard --with-registry
```

Prefer to fill `.env` yourself first? Edit `KONNECT_TOKEN` and `KONNECT_REGION` in `.env`, then
`./scripts/setup.sh --yes` (non-interactive).

## 3. What `setup.sh` does

| Stage | Action |
|-------|--------|
| 1 Preflight | Verify docker/compose/curl/jq/python3/openssl |
| 2 Ensure `.env` | Create from example; prompt for PAT + region if missing |
| 3 Bootstrap | Create the Konnect control plane, generate + pin the data-plane cert, **write CP/TP endpoints into `.env`** |
| 4 Up | `docker compose up -d` (Kong DP, Keycloak, OPA, mock APIs, market-mcp, demo-ui) |
| 5 Wait-health | Poll Keycloak, OPA, Kong until ready |
| 6 Sync | `deck gateway sync` — push the declarative config |
| 7 Wait-routes | Poll until the data plane serves the MCP routes |
| 8 Add-ons | *(opt-in)* install dashboard / publish registry — best-effort |
| 9 Smoke | `smoke-test.sh` static + live checks |

Idempotent — safe to re-run. It writes a `.env.bak` before touching `.env`.

## 4. Verify & run the demo

```bash
./scripts/preflight.sh     # tools, container health, port reachability
./scripts/demo.sh          # guided 7-step CLI walkthrough (pauses between steps)
./scripts/ui.sh            # OR the visual cockpit at http://127.0.0.1:4000
```

Mint a token and call a governed endpoint directly:

```bash
TOKEN=$(./scripts/get-token.sh olivia --raw)
curl -s http://localhost:8000/mcp/ops -H "Authorization: Bearer $TOKEN" \
  -H 'Content-Type: application/json' -H 'Accept: application/json, text/event-stream' \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/list"}'
```

## 5. Tear down / reset

```bash
docker compose down -v     # stop + remove volumes (Keycloak is ephemeral H2 anyway)
./scripts/setup.sh         # re-run to rebuild
```

The Konnect control plane persists across teardowns (it's SaaS). `setup.sh`/bootstrap are
idempotent and will reuse it.

## 6. When something fails

| Symptom | First move |
|---------|-----------|
| Missing tool at Stage 1 | Install it (setup prints the hint), re-run |
| Stage 3 bootstrap 401/403 | `KONNECT_TOKEN` invalid/expired or wrong `KONNECT_REGION` — fix in `.env`, re-run |
| Stage 5 Keycloak/Kong timeout | `docker compose logs keycloak` / `kong-dp`; re-run once Docker settles |
| Stage 6 deck sync error | `docker compose --profile tools run --rm deck gateway validate /config/konnect.yaml` |
| Every token 401s at Kong | Keep the `iss` pin — see README → Troubleshooting |
| `--with-registry` 404/permission | Enable Labs "Catalog - MCP Registry" (US only) |

Full troubleshooting and per-step demo expectations: **[README.md](./README.md)**.
Doc-vs-reality plugin facts: **[NOTES.md](./NOTES.md)**.
