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
