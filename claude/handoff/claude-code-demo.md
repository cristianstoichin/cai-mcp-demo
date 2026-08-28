# Claude Code persona demo flows — success & failure by identity

How to demo governed MCP access from Claude Code, showing that **the same client, logged in as
different employees, gets different tool access** — enforced at Kong, not configured in the client.

Companion to README → *Connect Claude Code (MCP client)*. Uses **Option B (browser OAuth)**.

## The auth model (read this first)

- The 6 servers are registered together, but Claude Code authenticates them **individually** in the
  `/mcp` panel — **registering is not authenticating**. Keycloak SSO means that after the **first**
  browser login, authenticating each remaining server is **one click** (no re-entering credentials),
  all as the same persona.
- **Authenticate all 6 servers up-front in `/mcp` before running any demo prompt.** `claude mcp list`
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
scripts/claude-code-setup.sh --browser --apply                            # re-register the 6 servers
# then /mcp in Claude Code → log in as the next persona
```

(Or just use a fresh **incognito** window per persona — no shared SSO cookie.) Password for all three:
`Demo1234!`.

## One-time setup

```bash
scripts/hosts-alias.sh --apply                                  # host resolves keycloak (sudo)
docker compose up -d --force-recreate keycloak && docker compose restart kong-dp   # if KC was already running
scripts/claude-code-setup.sh --browser --apply                 # register the 6 servers
```

Then in Claude Code: run `/mcp` and **authenticate every `cox-*` server** — the first opens a browser
login (pick your persona); the rest are one-click via SSO. Verify before demoing:

```bash
claude mcp list | grep cox-      # every cox-* must say "Connected", not "Needs authentication"
```

---

## How governance surfaces in Claude Code (read before the flows)

Kong filters `tools/list` by the caller's `groups`, so **each employee's Claude Code gets a different
tool catalog** — a tool a persona can't call is **absent**, not shown-then-403'd (a well-behaved client
only calls tools it can see). So the governance shows up two ways:

- **Group governance → tool visibility.** dana's Claude Code simply has **no** finance tools; frank's has
  no dealer tools. Visible directly in `claude mcp list` / the `/mcp` panel — the tool *counts* differ per
  persona. That **is** the enforcement; there's nothing to "try and get 403'd."
- **OPA argument governance → a live 403.** OPA gates a call *argument*, which `tools/list` can't filter
  on, so the tool stays visible and the block lands as a real `403` when the argument is used. This is the
  one hard denial you'll see **inside** Claude Code.

(The tool-ACL's hard `403`-on-call still exists, but only when a tool is called **directly** by name —
that's the **cockpit / bearer** flow, which bypasses the filtered list. See the last section.)

### What each persona's Claude Code sees

Authenticate all servers, then `claude mcp list` — the catalog is filtered to the group:

| Server | dana (dealers) | frank (finance) | olivia (ops) |
|---|---|---|---|
| cox-dealers | customers, vehicles | **—** | customers, vehicles |
| cox-finance | **—** | floorplans, invoices | invoices *(not floorplans)* |
| cox-ops | customers | invoices | customers, invoices |
| cox-market | all (2) | all (2) | all (2) |
| cox-deepwiki | all (3) | all (3) | all (3) |

The differing catalogs **are** the governance — same 5 registrations, per-identity tool set.

## Flow 1 — `dana.dealer` (dealers) — a dealer-desk employee

| Ask Claude Code | What happens | Point |
|---|---|---|
| "list the dealer customers" / "list the dealer vehicles" | ✅ returns data | both dealer tools are in dana's catalog |
| "list the finance invoices" | Claude Code has **no invoices tool** — cox-finance shows *0 tools*, cox-ops exposes only `customers` to her | Kong filtered every finance tool out of her catalog by group |

**Say:** "dana's Claude Code was never handed a finance tool — Kong scoped her catalog to her group.
There's nothing to 'try and be denied'; it simply isn't there."

## Flow 2 — `frank.finance` (finance) — the mirror

| Ask Claude Code | What happens | Point |
|---|---|---|
| "list the invoices" / "list the floorplans" | ✅ data | both finance tools are in frank's catalog |
| "list the dealer vehicles" | **no dealer tool** in frank's catalog (cox-dealers shows *0 tools*) | inverted access, zero client change |

**Say:** "Swap the employee, invert the catalog — no redeploy, no client config."

## Flow 3 — `olivia.ops` (ops) — cross-domain, still bounded, + the live OPA 403

| Ask Claude Code | What happens | Point |
|---|---|---|
| "list the dealer customers" / "list the invoices" | ✅ data | ops catalog spans **both** domains |
| "list the floorplans" | **no floorplans tool** (cox-finance exposes only `invoices` to olivia) | `list_floorplans` is `allow[finance]` — even ops is bounded, so it's filtered out |
| "list the **overdue** invoices" | tool **is** available, but returns **403 unauthorized** | **OPA** blocks the *argument*; `list_invoices` is visible to ops, so this denial surfaces **live** in Claude Code |

**Say:** "Ops spans both domains but is still fenced off from floorplans — filtered right out of the
catalog. And when olivia calls a tool she *does* have with a sensitive argument, a second policy engine
(OPA) blocks it live. Group governance shows as what's in the catalog; OPA shows as a 403 on the call."

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

## Quick reference — who can call what (call-level truth)

This is the **call-level** ACL (what a *direct* `tools/call` returns). In Claude Code, a ❌ here means the
tool is **absent from that persona's catalog** (filtered from `tools/list`), except the OPA row — that
tool is visible and returns a live 403. In the **cockpit/bearer** flow every ❌ is a direct-call 403.

| Tool (server) | dana (dealers) | frank (finance) | olivia (ops) |
|---|:--:|:--:|:--:|
| `list_dealer_customers` (cox-dealers, cox-ops) | ✅ | ❌ | ✅ |
| `list_dealer_vehicles` (cox-dealers) | ✅ | ❌ | ✅ |
| `list_invoices` (cox-finance, cox-ops) | ❌ | ✅ | ✅ |
| `list_invoices` + `query_status=overdue` | ❌ | ❌ | ❌ **(OPA, live 403)** |
| `list_floorplans` (cox-finance) | ❌ | ✅ | ❌ |
| cox-market / cox-deepwiki (remotes) | ✅ | ✅ | ✅ |

**Which layer denies, and how it shows in Claude Code:**
- **group mismatch → tool ACL** (`groups` claim). In Claude Code this is **tool absence** (filtered
  `tools/list`); via a direct call it's a `403`.
- **sensitive argument → OPA** (`/mcp/ops`). The tool stays visible, so this is a **live 403** in Claude Code.
- **inner scope/audience gate** never denies in browser mode (all tokens carry all scopes) — to demo that
  layer + the RFC 8693 **token exchange**, use the bearer flow (`scripts/get-token.sh` per persona) or the
  demo-ui cockpit, which mint per-persona *scoped* tokens and call tools directly.
