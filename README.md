# cai-mcp-demo

**Kong Gateway 3.14 (Konnect hybrid mode) turning Cox Automotive REST APIs into governed MCP servers.**

REST→MCP conversion, tag-aggregated MCP endpoints, OAuth + token-claim tool ACLs, RFC 8693 token
exchange, external OPA policy, and passthrough governance of remote MCP servers — all discoverable via the
Konnect MCP Registry. One `docker compose up` runs everything except the Konnect control plane (SaaS).

## What it demonstrates

| # | Capability | Where |
|---|------------|-------|
| 1 | **OAuth-gated REST APIs** — bearer-only `openid-connect`, scope + audience enforced | `/api/dealers/*`, `/api/finance/*` |
| 2 | **REST → MCP conversion** — `ai-mcp-proxy` `conversion-only` turns each REST route into an MCP tool | 4 REST routes |
| 3 | **Tag-aggregated MCP endpoints** — one listener bundles tools by entity tag | `/mcp/dealers` (2), `/mcp/finance` (2), `/mcp/ops` (2 bundled) |
| 4 | **Token-claim tool ACLs** — allow/deny per tool by the token's `groups` claim (no Kong consumers) | `ai-mcp-proxy` listener |
| 5 | **RFC 8693 token exchange** — an `mcp:use`-only token reaches the APIs via introspection + exchange | `/mcp/ops` |
| 6 | **External OPA policy** — argument-level rule the tool ACL can't express; hot-reloads with no Kong sync | `/mcp/ops` + `opa/policies/mcp.rego` |
| 7 | **Passthrough governance** — front an MCP server you own *and* a third-party one you don't | `/mcp/remote` → market-mcp, `/mcp/remote-public` → DeepWiki |
| 8 | **MCP Registry** — publish + discover the servers in Konnect | `scripts/registry-setup.sh` |
| 9 | **Konnect analytics dashboard** — MCP volume, per-server split, error/denial rate, latency | `scripts/install-dashboard.sh` |

Identity: Keycloak `cox-auto` realm, personas **dana** (dealers), **frank** (finance), **olivia** (ops, both groups).

## Architecture

```mermaid
flowchart TB
  client["MCP client<br/>(curl / Claude Code)"]
  kc["Keycloak 26<br/>realm cox-auto<br/>:8080"]
  konnect["Konnect control plane<br/>(SaaS) + MCP Registry"]

  subgraph dp["Kong DP :8000 (hybrid data plane)"]
    rest["REST routes<br/>openid-connect + ai-mcp-proxy conversion-only"]
    lst["/mcp/dealers · /mcp/finance · /mcp/ops<br/>ai-mcp-oauth2 + ai-mcp-proxy listener<br/>(tag-aggregate + token-claim ACL)"]
    ops["/mcp/ops extras<br/>introspection + RFC 8693 exchange + OPA"]
    pass["/mcp/remote · /mcp/remote-public<br/>ai-mcp-oauth2 + passthrough-listener"]
  end

  dealer["dealer-svc :3000"]
  finance["finance-svc :3000"]
  market["market-mcp :3000<br/>(MCP, owned)"]
  deepwiki["DeepWiki<br/>(MCP, third-party)"]
  opa["OPA :8181<br/>mcp.rego"]

  client -- "Bearer (Keycloak JWT)" --> dp
  kc -. "JWKS / introspection / token exchange" .-> dp
  konnect -. "config push (decK sync)" .-> dp
  rest --> dealer & finance
  lst --> rest
  ops -. "policy query" .-> opa
  pass --> market & deepwiki
```

See [ARCHITECTURE.md](./ARCHITECTURE.md) for the module + Kong-topology tables, and
[TECHSTACK.md](./TECHSTACK.md) for pinned versions.

## Prerequisites

- Docker + Docker Compose v2, `curl`, `jq`, `python3`. decK runs via the bundled `deck` compose service.
- A **Konnect organization** with:
  - A Personal Access Token (PAT) with control-plane admin rights (`KONNECT_TOKEN` in `.env`).
  - **AI Gateway Enterprise** entitlement — `ai-mcp-oauth2` / `ai-mcp-proxy` require it (tech preview).
  - **Organization → Labs → "Catalog - MCP Registry"** enabled (US region only; tech preview) for
    `scripts/registry-setup.sh`. Everything else works without it.

## Quickstart

```bash
cp .env.example .env                 # set KONNECT_TOKEN and KONNECT_REGION (=us)
./scripts/konnect-bootstrap.sh       # create the control plane, generate + upload the DP cert,
                                     # and print CP/TP endpoints to append to .env
docker compose up -d                 # kong-dp + keycloak + opa + mock services + market-mcp
docker compose --profile tools run --rm deck gateway sync /config/konnect.yaml
```

Verify the stack, then run the guided demo:

```bash
./scripts/preflight.sh               # tools, container health, port reachability
./scripts/demo.sh                    # numbered, pause-between-steps walkthrough
```

Mint a token and call a governed MCP endpoint directly:

```bash
TOKEN=$(./scripts/get-token.sh olivia --raw)
curl -s http://localhost:8000/mcp/ops -H "Authorization: Bearer $TOKEN" \
  -H 'Content-Type: application/json' -H 'Accept: application/json, text/event-stream' \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/list"}'
```

## Demo walkthrough (`scripts/demo.sh`)

Each step runs live against the stack. Expected results:

1. **REST OIDC gates** — no token → `401`; dana on the dealer API → `200`; dana on the finance API → `403`
   (missing `finance:read` scope + `finance-api` audience).
2. **REST → MCP conversion** — `tools/list`: `/mcp/dealers` = `list_dealer_customers, list_dealer_vehicles`;
   `/mcp/finance` = `list_invoices, list_floorplans`; `/mcp/ops` = `list_dealer_customers, list_invoices` (bundled by tag).
3. **Token-claim tool ACL** — olivia (ops) → `list_invoices` returns data; frank (finance) → `list_dealer_customers`
   → `403` (his `groups:[finance]` isn't in the tool's `allow:[dealers,ops]`). No Kong consumers involved.
4. **RFC 8693 token exchange** — an `mcp:use`-only token (no API audiences) → `/mcp/ops list_dealer_customers`
   **succeeds** (Kong introspects + exchanges it for a token carrying `dealer-api`/`finance-api`), but the same
   token → `/mcp/dealers` (no exchange) → inner-gate `403`. Watch it: `docker compose logs kong-dp | grep 'exchanging access token'`.
5. **External OPA policy** — olivia `list_invoices` → `200`; olivia `list_invoices` with `query_status=overdue`
   → `403` (an argument-level rule the tool ACL can't express). Edit `opa/policies/mcp.rego` and OPA hot-reloads — no Kong sync.
6. **Passthrough remotes** — `/mcp/remote` unauth → `401`; authed → market-mcp tools;
   `/mcp/remote-public` authed → DeepWiki tools (`ask_question`, `read_wiki_contents`, `read_wiki_structure`). A valid cox-auto token is required for the third-party server.
7. **MCP Registry** — `scripts/registry-setup.sh` publishes and discovers all 5 servers in Konnect.

Hook Claude Code up to the governed servers:

```bash
./scripts/claude-code-setup.sh          # prints `claude mcp add` lines (per-persona tokens)
./scripts/claude-code-setup.sh --apply  # or run them
```

## Repo layout

- `dealer-svc/`, `finance-svc/` — Node/Express mock REST APIs (converted to MCP tools).
- `market-mcp/` — local Cox-themed MCP server (Streamable HTTP), the `/mcp/remote` passthrough target.
- `keycloak/realm-export.json` — pre-baked `cox-auto` realm (zero manual clicks).
- `kong/konnect.yaml` — the entire declarative decK config.
- `opa/policies/mcp.rego` — external policy for `/mcp/ops`.
- `konnect/mcp-registry/*.json` — registry create + publish bodies.
- `konnect/dashboards/cai-mcp-analytics.json` — the Konnect "Governed MCP" analytics dashboard.
- `scripts/` — `konnect-bootstrap`, `get-token`, `rebuild`, `registry-setup`, `install-dashboard`,
  `claude-code-setup`, `demo`, `preflight`, `smoke-test`.
- `NOTES.md` — doc-vs-reality findings + verified plugin-schema facts (trust this over memory).

## Troubleshooting

- **DP won't connect to Konnect.** Re-run `scripts/konnect-bootstrap.sh` (idempotent) and confirm
  `certs/tls.crt` + `certs/tls.key` exist and `KONNECT_CP_ENDPOINT`/`KONNECT_TP_ENDPOINT` in `.env` match
  your org. Check `docker compose logs kong-dp` for TLS/cert errors.
- **Every token 401s at Kong.** Keycloak's issuer is pinned to `http://keycloak:8080` so host-minted and
  DP-validated tokens share one `iss`. If you changed `KC_HOSTNAME`, tokens minted via `localhost:8080`
  will mismatch — keep the pin. Re-import realm edits with `docker compose up -d --force-recreate keycloak`
  (dev mode uses ephemeral H2).
- **`audience`/RFC-8707 401 on an MCP listener.** The listeners set `insecure_relaxed_audience_validation:
  true` on `ai-mcp-oauth2` because our Keycloak audiences (`mcp-*`) differ from the resource URL;
  authorization is enforced by the inner OIDC gate + the token-claim ACL instead.
- **Token exchange fails `invalid_client / Audience not found`.** Keycloak's exchange `audience` parameter
  must name a registered *client* — request the API *scopes* instead (their mappers add the audiences).
  The subject token must also carry `kong-exchange` in `aud` (the `mcp:use` scope provides it).
- **OPA denies everyone / allows everyone.** The `groups` header is base64-encoded JSON
  (`["ops"]` → `WyJvcHMiXQ==`); the rego `json.unmarshal(base64.decode(...))`s it. Enable
  `include_parsed_json_body_in_opa_input` so the body reaches `input.request.http.parsed_body`.
- **Registry script 400/404.** `description` must be ≤100 chars (400 otherwise). A 404/permission error
  means **Catalog - MCP Registry** isn't enabled in Konnect Labs for your region (US-only tech preview).
- **Host `curl localhost:3001` misses the container.** A local dev server can squat the debug port. Real
  traffic uses Kong `:8000`; override `DEALER_SVC_PORT`/`FINANCE_SVC_PORT`/`MARKET_MCP_PORT` in `.env`, or
  test in-network: `docker compose exec finance-svc node -e "..."`.

## Known Issues

- **Rule 1 of the OPA policy (finance/ops-only for `list_invoices`) is shadowed by the tool ACL** on
  `/mcp/ops`, so it never independently decides live. It stays as an "entitlement-as-code" illustration;
  the argument-level rule (Rule 2, `query_status=overdue`) is the one that visibly makes OPA the decider.
- **Keycloak secrets are baked into `realm-export.json`** (a static import) **and** mirrored in `.env` /
  `.env.example`. If you change a client secret or the demo password, change it in **both** places.
- **`ai-mcp-oauth2` + the MCP Registry are tech preview** (AI Gateway Enterprise / Konnect Labs).
  Availability varies by org tier and region (Registry is US-only). Scripts fail with a helpful message
  when a capability isn't enabled.
- **DeepWiki is a live third-party service.** `/mcp/remote-public` depends on `mcp.deepwiki.com` being
  reachable and on its protocol staying ≥ `2025-06-18`. Swap `REMOTE_PUBLIC_MCP_URL` in `.env` for any
  other remote MCP server if needed.
