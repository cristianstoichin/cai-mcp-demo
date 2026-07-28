# Claude Code persona demo flows — success & failure by identity

How to demo governed MCP access from Claude Code, showing that **the same client, logged in as
different employees, gets different tool access** — enforced at Kong, not configured in the client.

Companion to README → *Connect Claude Code (MCP client)*. Uses **Option B (browser OAuth)**.

## The auth model (read this first)

- The 5 servers are registered together, but Claude Code authenticates them **individually** in the
  `/mcp` panel — **registering is not authenticating**. Keycloak SSO means that after the **first**
  browser login, authenticating each remaining server is **one click** (no re-entering credentials),
  all as the same persona.
- **Authenticate all 5 servers up-front in `/mcp` before running any demo prompt.** `claude mcp list`
  should show every `cox-*` as connected, not *"Needs authentication."* If you skip this, a tool call to
  an un-authenticated server triggers a messy mid-conversation auth — and the model may **improvise a
  bogus "paste the callback URL here" step, which is NOT how MCP OAuth completes** (the `/mcp` harness
  captures the callback itself; the model plays no part in the code exchange). A `403` only means "Kong
  blocked it" when the server is already **connected** — otherwise it's just unauthenticated.
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

Then in Claude Code: run `/mcp` and **authenticate every `cox-*` server** — the first opens a browser
login (pick your persona); the rest are one-click via SSO. Verify before demoing:

```bash
claude mcp list | grep cox-      # every cox-* must say "Connected", not "Needs authentication"
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

## Why the denials are identity-based here — and how it differs from the bearer / UI flow

### Two independent things live in the token

Kong checks two separate fields, and they answer different questions:

| In the token | Example | Who checks it | Question |
|---|---|---|---|
| **`scope` + `aud`** | `dealers:read`, `finance:read` + audience `dealer-api` | inner `openid-connect` gate on the REST route | "Is this token *cleared for* the dealer/finance API at all?" |
| **`groups`** | `[dealers]` / `[finance]` / `[ops]` | tool ACL (`ai-mcp-proxy`) | "Which team is this *person* on?" |

Scopes describe what the **token** is provisioned for; `groups` describes **who the person is**.

### Every browser token carries the same scopes

The `claude-code` client's `dealers:read` / `finance:read` / `mcp:use` are **default** scopes — Keycloak
always issues them, for every login, regardless of who logs in. So dana, frank, and olivia get
**structurally identical tokens** (same scopes, same audiences); the only field that differs is `groups`.

Consequence: the inner scope/audience gate **passes for everyone**, so it can never be what denies. Every
browser-mode denial therefore lands one layer deeper — the **tool ACL** (group mismatch) or **OPA** (call
argument). When dana is blocked from a finance tool it is *not* because her token lacks finance access
(it doesn't) — it's because her `groups` is `[dealers]`.

→ **Same token, different entitlement.** You don't hand people different capabilities by minting them
different scopes; everyone gets the same token and the gateway enforces per-identity policy.

### Same gateway, two OAuth clients (the "why")

The browser flow and the bearer/UI-cockpit flow are the **same governance implementation** — identical
Kong routes, `ai-mcp-oauth2` + `ai-mcp-proxy`, tool ACLs, OPA policy, and token-exchange config. Kong
can't tell how a token was obtained; it validates and governs the same either way. What differs is only
**how the token is minted** — two clients in the same Keycloak realm:

| | Browser flow (Claude Code) | Bearer / UI cockpit |
|---|---|---|
| OAuth client | `claude-code` (public, auth-code + PKCE) | `demo-cli` (confidential, ROPC/password) |
| Scopes | **default** — every persona gets all | **per-persona** — dana only `dealers:read`, etc. |
| Interactive? | yes (browser login) | no (scripted) |
| Denials demonstrate | tool ACL (`groups`) + OPA | scope/audience gate + RFC 8693 **token exchange** |

**Why default scopes for the browser client:** in the auth-code flow the *harness* decides which scopes
to request, and Claude Code requests a generic set — it has no notion of `dealers:read` vs `finance:read`.
If those were *optional* and unrequested, the token would lack them and every tool call would 403 at the
inner gate (the exact bug hit on 2026-07-27). Making them **default** guarantees an unmodified harness
gets a usable token. Per-persona scoping isn't practically available in an interactive login anyway
(there's no "log in with only `dealers:read`" knob), so the browser flow leans on **group**-based
governance instead — an equally honest story, just enforced at a different layer.

The two flows are **complementary, not redundant**: together they exercise every governance layer —
browser covers group ACL + OPA; bearer covers scope/audience + the token exchange.

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
