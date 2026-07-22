# cai-mcp-demo

**Kong Gateway 3.14 (Konnect hybrid mode) turning Cox Automotive REST APIs into governed MCP servers.**

REST→MCP conversion, tag-aggregated MCP endpoints, OAuth + consumer-group tool ACLs, RFC 8693 token
exchange, OPA policy, and passthrough of external MCP servers — all discoverable via the Konnect MCP
Registry. One `docker compose up` runs everything except the Konnect control plane.

> **Status:** under construction. Phase 1 (mock services + Keycloak realm) complete. See
> `claude/plans/2026-07-22-cai-mcp-demo-implementation.md` for the build plan and `NOTES.md` for
> plugin-schema notes.

## Prerequisites

- Docker + Docker Compose v2, `curl`, `jq`, and [decK](https://developer.konghq.com/deck/) (or use the bundled `deck` compose service).
- A **Konnect organization** with:
  - A Personal Access Token (PAT) with control-plane admin rights.
  - **Organization → Labs → "Catalog - MCP Registry"** enabled (US region only; tech preview) for `scripts/registry-setup.sh`.
  - **AI Gateway Enterprise** entitlement — the `ai-mcp-oauth2` plugin requires it (tech preview).

## Quickstart (three commands)

```bash
cp .env.example .env                 # set KONNECT_TOKEN and KONNECT_REGION
./scripts/konnect-bootstrap.sh       # create the control plane, generate + upload the DP cert,
                                     # and print CP/TP endpoints to append to .env
docker compose up -d                 # kong-dp + keycloak + opa + mock services + market-mcp
docker compose --profile tools run --rm deck gateway sync /config/konnect.yaml
```

Then mint a token and call a governed MCP endpoint:

```bash
eval "$(./scripts/get-token.sh olivia --raw >/tmp/t && echo TOKEN=$(cat /tmp/t))"
curl -s http://localhost:8000/mcp/ops -H "Authorization: Bearer $TOKEN" \
  -H 'Content-Type: application/json' \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/list"}' | jq
```

## Demo walkthrough

`./scripts/demo.sh` runs a numbered, pause-between-steps walkthrough (401/200/403 proofs, `tools/list`
across the three listeners, registry discovery, audience-mismatch, token-exchange proof, ACL diff, OPA
deny→allow). Full expected outputs will be documented here in Phase 6.

## Architecture

See [ARCHITECTURE.md](./ARCHITECTURE.md) for the module + Kong-topology tables and a request-path
diagram, and [TECHSTACK.md](./TECHSTACK.md) for pinned versions. A mermaid diagram is added in Phase 6.

## Troubleshooting

Fleshed out in Phase 6. Will cover: DP not connecting to Konnect (cert issues), Keycloak realm-import
failures, audience-validation 401s from localhost/hostname mismatch, and the tech-preview status of
`ai-mcp-oauth2` + the MCP Registry.

## Known Issues

- **Host port collisions on the debug ports.** A local dev server squatting `127.0.0.1:3001/3002/3003`
  can shadow the container's published port for `localhost` connections. Real traffic goes through Kong
  (`:8000`) regardless; override the debug ports via `DEALER_SVC_PORT` / `FINANCE_SVC_PORT` /
  `MARKET_MCP_PORT` in `.env` if needed.
- **Keycloak secrets are baked into `realm-export.json`** (a static import) **and** mirrored in
  `.env.example`. If you change a client secret or the demo password, change it in **both** places.
- **MCP Registry + `ai-mcp-oauth2` are tech preview** (Konnect Labs / AI Gateway Enterprise). Availability
  varies by org tier and region (Registry is US-only). Scripts fail with a helpful message if unavailable.
- Phases 2–6 are still under construction; the gateway config, OPA policy, registry, and demo scripts
  are being added incrementally.
