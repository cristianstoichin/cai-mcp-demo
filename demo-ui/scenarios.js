// scenarios.js — the 7 Demo steps AS DATA. Single source of truth for Demo mode
// AND the Overview view (U11), mirroring scripts/demo.sh exactly (persona, scope,
// path, tool, args, expected verdict). Customer-facing copy fields: headline,
// proves, why, railLabel (per scene); identity, verdictLabel (per call). The
// verdictLabel is the honest per-call display label — NEVER the raw classifier
// enum (U8: step-1 call-3 is the REST scope/audience gate, not "acl-deny").
// Shared by server (/api/scenarios) and client.

export const scenarios = [
  {
    id: "oidc", n: 1, title: "REST OIDC gates", tag: "OIDC", railLabel: "Protected APIs",
    headline: "The raw APIs are already protected",
    proves: "Authentication + per-scope authorization at the edge — before MCP exists.",
    why: "Dana's token carries dealers:read but not finance:read, so it has no finance-api audience — the finance route rejects it. That is the REST OIDC scope/audience gate, before any MCP tool exists.",
    narration: "The raw APIs are protected before any MCP. No token → 401; dana (dealers:read) → 200; dana on the finance API → 403 (scope+audience).",
    calls: [
      { label: "no-token → /api/dealers/customers", persona: null, identity: "no-token", verdictLabel: "401 · no token", kind: "rest",
        path: "/api/dealers/customers", method: "GET", expect: { verdict: "auth-fail" } },
      { label: "dana → /api/dealers/customers", persona: "dana", identity: "Dana", verdictLabel: "200 · allowed", kind: "rest",
        path: "/api/dealers/customers", method: "GET", expect: { verdict: "allow" } },
      { label: "dana → /api/finance/invoices (wrong scope+aud)", persona: "dana", identity: "Dana", verdictLabel: "403 · REST scope/audience gate", kind: "rest",
        path: "/api/finance/invoices", method: "GET", expect: { verdict: "acl-deny" },
        note: "403 from the inner OIDC gate (scope+audience), shown as a deny." },
    ],
  },
  {
    id: "convert", n: 2, title: "REST → MCP conversion", tag: "CONVERT", railLabel: "REST → MCP",
    headline: "Kong converts those APIs into MCP tools",
    proves: "REST→MCP conversion with zero rewrite of the upstream services.",
    why: "tools/list is never filtered — listing is open; enforcement happens when a tool is actually called (step 3).",
    narration: "Same APIs, now MCP tools, tag-aggregated: /mcp/dealers = 2 tools, /mcp/finance = 2, /mcp/ops = 2 bundled (dealer+finance).",
    calls: [
      { label: "/mcp/dealers tools/list", persona: "olivia", identity: "Olivia", verdictLabel: "200 · 2 tools", kind: "mcp", path: "/mcp/dealers",
        tool: null, method: "tools/list", expect: { verdict: "allow" } },
      { label: "/mcp/finance tools/list", persona: "olivia", identity: "Olivia", verdictLabel: "200 · 2 tools", kind: "mcp", path: "/mcp/finance",
        tool: null, method: "tools/list", expect: { verdict: "allow" } },
      { label: "/mcp/ops tools/list", persona: "olivia", identity: "Olivia", verdictLabel: "200 · 2 bundled", kind: "mcp", path: "/mcp/ops",
        tool: null, method: "tools/list", expect: { verdict: "allow" } },
    ],
  },
  {
    id: "acl", n: 3, title: "Persona tool ACL", tag: "ACL", railLabel: "Per-user tools",
    headline: "Each person only gets the tools their group allows",
    proves: "Per-identity tool authorization straight from a JWT groups claim.",
    why: "Frank's groups:[finance] is not in that tool's allow-list [dealers, ops] — blocked at the gateway, never reaches the API.",
    narration: "Filtering by the token's groups claim (no Kong consumers). olivia (ops) may call list_invoices; frank (finance) may NOT call a dealer tool.",
    calls: [
      { label: "olivia → list_invoices @ /mcp/ops", persona: "olivia", identity: "Olivia", verdictLabel: "200 · allowed", kind: "mcp",
        path: "/mcp/ops", tool: "list_invoices", args: {}, expect: { verdict: "allow" } },
      { label: "frank → list_dealer_customers @ /mcp/ops", persona: "frank", identity: "Frank", verdictLabel: "403 · tool ACL — group not allowed", kind: "mcp",
        path: "/mcp/ops", tool: "list_dealer_customers", args: {}, expect: { verdict: "acl-deny" } },
    ],
  },
  {
    id: "exchange", n: 4, title: "RFC 8693 token exchange", tag: "EXCHANGE", railLabel: "Token exchange",
    showExchange: true,
    headline: "Kong exchanges a narrow token so the call can reach the API",
    proves: "RFC 8693 token exchange — the client never holds API credentials; Kong bridges trust.",
    why: "Same token, two routes. On /mcp/ops Kong swaps the audience to [dealer-api, finance-api] so the inner gate passes; on /mcp/dealers there is no exchange, so the inner gate 403s.",
    narration: "A token with ONLY 'mcp:use' lacks the dealer-api/finance-api audiences the inner gates need. On /mcp/ops Kong exchanges it so the call reaches the API; on /mcp/dealers it can't.",
    calls: [
      { label: "mcp:use-only olivia → /mcp/ops list_dealer_customers", persona: "olivia", identity: "Olivia", verdictLabel: "exchanged → 200",
        scope: "openid mcp:use", kind: "mcp", path: "/mcp/ops", tool: "list_dealer_customers",
        args: {}, expect: { verdict: "allow" }, note: "Kong exchanges the token here." },
      { label: "mcp:use-only olivia → /mcp/dealers list_dealer_customers", persona: "olivia", identity: "Olivia", verdictLabel: "403 · no audience (not exchanged)",
        scope: "openid mcp:use", kind: "mcp", path: "/mcp/dealers", tool: "list_dealer_customers",
        args: {}, expect: { verdict: "inner-gate-deny" }, note: "No exchange here → inner-gate 403." },
    ],
  },
  {
    id: "opa", n: 5, title: "External OPA policy", tag: "OPA", railLabel: "OPA policy",
    headline: "An external policy decides on the request's arguments",
    proves: "Externalized, argument-aware policy (OPA) that hot-reloads without touching Kong.",
    why: "Olivia is fully entitled to list_invoices — but the OPA rule denies the overdue filter specifically. Edit mcp.rego and the decision changes live, with no Kong sync.",
    narration: "A rule the tool ACL cannot express: OPA denies list_invoices when the call argument query_status=overdue, even for a permitted caller. opa/policies/mcp.rego hot-reloads with no Kong sync.",
    calls: [
      { label: "olivia → list_invoices (no filter)", persona: "olivia", identity: "Olivia", verdictLabel: "200 · allowed", kind: "mcp",
        path: "/mcp/ops", tool: "list_invoices", args: {}, expect: { verdict: "allow" } },
      { label: "olivia → list_invoices query_status=overdue", persona: "olivia", identity: "Olivia", verdictLabel: "403 · OPA policy", kind: "mcp",
        path: "/mcp/ops", tool: "list_invoices", args: { query_status: "overdue" },
        expect: { verdict: "opa-deny" } },
    ],
  },
  {
    id: "remote", n: 6, title: "Passthrough remotes", tag: "REMOTE", railLabel: "Remote MCP",
    headline: "Kong governs MCP servers it didn't even build",
    proves: "One governed front door for any MCP server, including ones you don't own.",
    why: "The remote MCP servers do their own thing upstream; Kong still requires a valid cox-auto token before anything reaches them.",
    narration: "Govern MCP servers Kong did not convert. /mcp/remote → local market-mcp (Cox tools); /mcp/remote-public → DeepWiki (third-party). Both require a cox-auto token.",
    calls: [
      { label: "/mcp/remote unauth", persona: null, identity: "no-token", verdictLabel: "401 · no token", kind: "mcp", path: "/mcp/remote",
        tool: null, method: "tools/list", expect: { verdict: "auth-fail" } },
      { label: "/mcp/remote-public authed tools/list", persona: "olivia", identity: "Olivia", verdictLabel: "200 · allowed", kind: "mcp",
        path: "/mcp/remote-public", tool: null, method: "tools/list", expect: { verdict: "allow" } },
    ],
  },
  {
    id: "registry", n: 7, title: "MCP Registry discovery", tag: "REGISTRY", railLabel: "Registry",
    headline: "Every server is discoverable in the Konnect MCP Registry",
    proves: "Governed discovery — a sanctioned catalog, not ad-hoc URLs.",
    why: "dealers, finance, ops, remote (market-mcp), remote-public (DeepWiki) — each advertised at its http://localhost:8000/mcp/* address, discoverable by any host client.",
    narration: "The servers are catalogued in Konnect's MCP Registry — discoverable by any host-side client (e.g. Claude Code).",
    calls: [
      { label: "Konnect MCP Registry — discover servers", identity: "Konnect", verdictLabel: "servers listed", kind: "registry",
        expect: { verdict: "allow" } },
    ],
  },
];

export default scenarios;
