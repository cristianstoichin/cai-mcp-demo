// content.js — customer-facing static copy for the Overview + Demo legend.
// Client ESM, NO secrets. Persona values mirror config.personas / get-token.sh;
// matrix allow-lists are verified against kong/konnect.yaml (2026-08-28).

export const personas = [
  { key: "dana", name: "Dana", username: "dana.dealer",
    role: "Dealership operations — works with customers and inventory.",
    group: "dealers", scopes: ["dealers:read", "mcp:use"],
    can: ["Dealer tools — customers, inventory", "Custom tool — the Python MCP server"],
    cant: ["Finance tools — invoices, floor-plans"] },
  { key: "frank", name: "Frank", username: "frank.finance",
    role: "Floor-plan financing — works with dealer invoices and audits.",
    group: "finance", scopes: ["finance:read", "mcp:use"],
    can: ["Finance tools — invoices, floor-plans", "Custom tool — the Python MCP server"],
    cant: ["Dealer tools — customers, inventory"] },
  { key: "olivia", name: "Olivia", username: "olivia.ops",
    role: "Cross-functional operations — spans dealer and finance.",
    group: "ops", scopes: ["dealers:read", "finance:read", "mcp:use"],
    can: ["Dealer + finance — customers, inventory, invoices"],
    cant: ["Floor-plans (finance-only, by design)", "Custom tool (dealers + finance only)"] },
];

export const matrix = [
  { tool: "list_dealer_customers", returns: "Dealership customers + trade-in interest",
    allow: ["dealers", "ops"], dana: true,  frank: false, olivia: true },
  { tool: "list_dealer_vehicles",  returns: "Dealer inventory — VIN, days-on-lot, vAuto rank",
    allow: ["dealers", "ops"], dana: true,  frank: false, olivia: true },
  { tool: "list_invoices",         returns: "Floor-plan invoices — dealer, amount, status",
    allow: ["finance", "ops"], dana: false, frank: true,  olivia: true },
  { tool: "list_floorplans",       returns: "Floor-plan audit status",
    allow: ["finance"],        dana: false, frank: true,  olivia: false },
  { tool: "hello_custom_tool",     returns: "Greeting from the hand-written Python MCP server",
    allow: ["finance", "dealers"], dana: true, frank: true, olivia: false },
];

export const legend = [
  { label: "allow",      kind: "ok",   title: "Passed every gate",   desc: "The call reached the upstream and returned data." },
  { label: "auth-fail",  kind: "auth", title: "No / invalid token",  desc: "Rejected at the door — 401, before any tool runs." },
  { label: "acl-deny",   kind: "deny", title: "Not allowed",         desc: "The token's group (or REST scope) isn't permitted here — 403." },
  { label: "opa-deny",   kind: "deny", title: "Policy said no",      desc: "OPA rejected this specific request's arguments — 403." },
  { label: "exchanged",  kind: "exch", title: "Token upgraded",      desc: "Kong swapped the token for one the API accepts, then allowed it." },
  { label: "inner-gate", kind: "deny", title: "Missing audience",    desc: "The token lacked the API audience and wasn't exchanged here — 403." },
];

export default { personas, matrix, legend };
