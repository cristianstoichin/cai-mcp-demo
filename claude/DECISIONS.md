# DECISIONS.md — cai-mcp-demo

Append-only log of architectural/design decisions. Reversed decisions get a NEW entry
linking back — never edit/delete the original.

| Date | Decision | Rationale (why this, not the alternative) | Scope | Links |
|------|----------|--------------------------------------------|-------|-------|
| 2026-07-22 | Avoid `conversion-listener` entirely: `conversion-only` on REST routes + `listener` on `/mcp/*` + `passthrough-listener` on remotes. | GW 3.13+ breaks when `ai-mcp-oauth2` shares a `conversion-listener` route (all traffic treated as MCP). Splitting modes sidesteps the footgun. | Kong topology | spec §2, §4.2 |
| 2026-07-22 (D1) | Verification = build full repo + local static checks; user runs live phased verification against their org. | No Konnect PAT this session; matches how the aegis reference was built. | Process | plan Global Constraints |
| 2026-07-22 (D2) | Two passthrough routes: `/mcp/remote` → local Cox `market-mcp`; `/mcp/remote-public` → DeepWiki. | Local = offline/on-theme/demo-reliable; DeepWiki = genuine "govern a third-party MCP you don't own". Both stories, no single demo-day failure point. URLs are `.env` vars. | Kong topology | spec §4.2 |
| 2026-07-22 (D3) | Keycloak in-compose, realm fully pre-baked. | Spec requires zero manual clicks + self-contained; aegis used cloud Okta which isn't portable. | Identity | keycloak/realm-export.json |
| 2026-07-22 (D4) | Consumer-group ACLs (`include_consumer_groups`, `consumer_groups_claim:[groups]`), not scope-claim ACLs. | Spec explicit; shows persona/group entitlement filtering. | Kong ACL | spec §4.3 |
| 2026-07-22 (D5) | Single `.env` (+ `.env.example`), not aegis's 3-file split. | Spec requires it. | Config | .env.example |
| 2026-07-22 (D6) | Inline-sequential build; domain agents only for self-contained chunks. | Kong/Keycloak/OPA config is tightly interdependent; phased-verify thread must stay coherent. | Process | plan |
| 2026-07-22 (D7) | Rebuilds always `docker compose build --no-cache` before up/test. | A cached layer masking a code change = demo-day failure + false "verified". Tied to run/test step, not a per-edit hook (would rebuild on doc edits; slow). | Build hygiene | scripts/rebuild.sh |
| 2026-07-22 | MCP Registry API base is `https://klabs.${REGION}.api.konghq.com/v0/mcp-registries`. | Verified from aegis `setup-mcp-registry.sh`; the aegis README's `us.api.konghq.com/v2` path is stale. | Registry | NOTES.md |
| 2026-07-22 | Self-owned Keycloak `identity` client scope for `sub`+`preferred_username`. | Explicit `defaultClientScopes` detaches built-in `basic`/`profile`; ai-mcp-oauth2 consumer mapping needs both claims. Self-owned scope is import-behavior-independent. | Identity | NOTES.md Phase-1 findings |
| 2026-07-22 | Host debug ports `.env`-overridable (`DEALER_SVC_PORT` etc.). | Local dev-server squatters can win over Docker's `0.0.0.0` bind for localhost; keep the demo portable. | Compose | docker-compose.yaml |
| 2026-07-22 | **Reverses D4.** Switch MCP tool filtering to the **aegis scope/claim-based ACL**: `ai-mcp-proxy` listener uses `acl_attribute_type: oauth_access_token` + `access_token_claim_field: groups`; tool `acl.allow/deny` match values in the token's `groups` claim. Drop Kong `consumers`/`consumer_groups` + `include_consumer_groups` + `consumer_groups_claim`. Keep `claim_to_header` for X-User-* identity. | Paul asked for the aegis implementation style directly (overrides the spec's consumer-group prescription). Trade-off: loses per-consumer Konnect analytics + real consumer entities; gains the simpler, token-claim-driven filtering aegis uses. Same allow/deny outcomes, different mechanism. | Kong ACL | [[D4]] NOTES.md |
