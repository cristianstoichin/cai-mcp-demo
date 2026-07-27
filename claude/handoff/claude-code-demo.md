# Claude Code persona demo flows — success & failure by identity

How to demo governed MCP access from Claude Code, showing that **the same client, logged in as
different employees, gets different tool access** — enforced at Kong, not configured in the client.

Companion to README → *Connect Claude Code (MCP client)*. Uses **Option B (browser OAuth)**.

## The auth model (read this first)

- Each persona logs in **once** in the browser; Keycloak SSO then shares that identity across **all 5**
  registered servers. You do **not** log in per-server or per-tool.
- In browser mode every persona's token carries the same scopes (the `claude-code` client's scopes are
  default), so **every denial you see is a governance decision on the token's `groups` claim** (the tool
  ACL) **or the OPA argument policy** — not a scope/audience failure. That's the story: *same token,
  different entitlement.*
- The two passthrough remotes (`cox-market`, `cox-deepwiki`) accept **any** valid cox-auto token, so all
  personas can use them — the "govern a third-party MCP with your own auth" beat.

### Switching persona (do this between flows)

Keycloak SSO will silently re-use the last identity, so a clean switch is:

```bash
scripts/claude-code-teardown.sh --apply                                   # drop cached tokens
open "http://keycloak:8080/realms/cox-auto/protocol/openid-connect/logout" # end the Keycloak SSO session
scripts/claude-code-setup.sh --browser --apply                            # re-register the 5 servers
# then /mcp in Claude Code → log in as the next persona
```

(Or just use a fresh **incognito** window per persona — no shared SSO cookie.) Password for all three:
`Demo1234!`.

## One-time setup

```bash
scripts/hosts-alias.sh --apply                                  # host resolves keycloak (sudo)
docker compose up -d --force-recreate keycloak && docker compose restart kong-dp   # if KC was already running
scripts/claude-code-setup.sh --browser --apply                 # register the 5 servers
```

---

## Flow 1 — `dana.dealer` (group: **dealers**) — a dealer-desk employee

Log in as `dana.dealer`. Then type into Claude Code:

| Ask Claude Code | Tool → server | Result | Why |
|---|---|---|---|
| "list the dealer customers" | `list_dealer_customers` → cox-dealers | ✅ data | dealers ∈ allow[dealers,ops] |
| "list the dealer vehicles" | `list_dealer_vehicles` → cox-dealers | ✅ data | dealers ∈ allow[dealers,ops] |
| "list the finance invoices" | `list_invoices` → cox-finance | ❌ **403** | tool ACL — invoices allow[finance,ops]; dana is [dealers] |
| "show floorplan financing" | `list_floorplans` → cox-finance | ❌ **403** | tool ACL — floorplans allow[finance] only |

**Say:** "A dealer-role token reads every dealer tool and is blocked from every finance tool — Kong
decided that from the `groups` claim; Claude Code sent no per-tool config."

## Flow 2 — `frank.finance` (group: **finance**) — a finance employee

Log in as `frank.finance` (mirror image of dana):

| Ask Claude Code | Tool → server | Result | Why |
|---|---|---|---|
| "list the invoices" | `list_invoices` → cox-finance | ✅ data | finance ∈ allow[finance,ops] |
| "list the floorplans" | `list_floorplans` → cox-finance | ✅ data | finance ∈ allow[finance] |
| "list the dealer vehicles" | `list_dealer_vehicles` → cox-dealers | ❌ **403** | tool ACL — allow[dealers,ops] + explicit deny[finance] |
| "list the dealer customers" | `list_dealer_customers` → cox-dealers | ❌ **403** | tool ACL — allow[dealers,ops]; frank is [finance] |

**Say:** "Swap the employee, invert the access — no redeploy, no client change."

## Flow 3 — `olivia.ops` (group: **ops**) — cross-functional, but still bounded

Log in as `olivia.ops`. This flow shows **two** enforcement layers:

| Ask Claude Code | Tool → server | Result | Why |
|---|---|---|---|
| "list the dealer customers" | `list_dealer_customers` → cox-dealers/ops | ✅ data | ops ∈ allow[dealers,ops] |
| "list the invoices" | `list_invoices` → cox-finance/ops | ✅ data | ops ∈ allow[finance,ops] — spans **both** domains |
| "list the floorplans" | `list_floorplans` → cox-finance | ❌ **403** | tool ACL — allow[finance] only; even ops isn't all-powerful |
| "list the **overdue** invoices" | `list_invoices` `{query_status: overdue}` → cox-ops | ❌ **403 unauthorized** | **OPA** — an argument-level rule the tool ACL can't express |

**Say:** "Ops spans both domains, but is still fenced off from floorplans — there's no blanket admin. And
a *second* policy engine (OPA) blocks a sensitive **argument** the tool ACL never sees. Two layers, one
identity, zero client-side logic."

## Shared beat — governed remotes (any persona)

| Ask Claude Code | Server | Result |
|---|---|---|
| "check the market price for a Ford F-150" | cox-market (passthrough) | ✅ |
| "ask deepwiki about the modelcontextprotocol spec" | cox-deepwiki (third-party passthrough) | ✅ |

**Say:** "Both are MCP servers Kong doesn't own — the DeepWiki one is a public third party — yet the
client still had to present a valid cox-auto token to reach them. Kong governs remotes it didn't build."

---

## Quick reference — who can call what

| Tool (server) | dana (dealers) | frank (finance) | olivia (ops) |
|---|:--:|:--:|:--:|
| `list_dealer_customers` (cox-dealers, cox-ops) | ✅ | ❌ | ✅ |
| `list_dealer_vehicles` (cox-dealers) | ✅ | ❌ | ✅ |
| `list_invoices` (cox-finance, cox-ops) | ❌ | ✅ | ✅ |
| `list_invoices` + `query_status=overdue` | ❌ | ❌ | ❌ **(OPA)** |
| `list_floorplans` (cox-finance) | ❌ | ✅ | ❌ |
| cox-market / cox-deepwiki (remotes) | ✅ | ✅ | ✅ |

**Which layer denies:** group mismatch → **tool ACL** (ai-mcp-proxy, `groups` claim); sensitive argument →
**OPA** (`/mcp/ops` only). In browser mode the inner scope/audience gate never denies (all tokens carry
all scopes) — to also demo scope/audience denial + the RFC 8693 **token exchange**, use the bearer flow
(`scripts/get-token.sh` per persona) or the demo-ui cockpit, which mint per-persona *scoped* tokens.
