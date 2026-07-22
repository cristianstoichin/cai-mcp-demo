// verdict.js — map a Kong MCP response signature to a governance verdict.
// Signatures live-verified in the 6-phase build (see NOTES.md). CRITICAL: the
// inner-gate deny arrives as HTTP 200 with isError in the JSON-RPC body, so we
// MUST inspect the body text, not only the status.

function asObject(body) {
  if (body && typeof body === "object") return body;
  if (typeof body === "string") { try { return JSON.parse(body); } catch { return null; } }
  return null;
}
function asText(body) {
  if (typeof body === "string") return body;
  try { return JSON.stringify(body); } catch { return String(body); }
}

export function classify({ httpStatus, body }) {
  const obj = asObject(body);
  const text = asText(body);

  if (httpStatus === 401) {
    return { verdict: "auth-fail", node: "oauth2",
      why: "No valid token — ai-mcp-oauth2 rejected the request before any tool ran." };
  }

  if (httpStatus === 403) {
    if (obj && obj.message === "unauthorized") {
      return { verdict: "opa-deny", node: "opa",
        why: "External OPA policy denied this call (a rule the tool ACL can't express)." };
    }
    // ACL deny surfaces as Kong's HTML 403.
    return { verdict: "acl-deny", node: "acl",
      why: "Tool ACL deny — the token's groups claim isn't in this tool's allow list. Blocked at the gateway." };
  }

  if (httpStatus === 200) {
    // Inner-gate deny: JSON-RPC success envelope but isError + "status 403" text.
    if (/HTTP call failed with status 4\d\d/.test(text) || (obj && deepIsError(obj))) {
      const m = text.match(/status (\d{3})/);
      return { verdict: "inner-gate-deny", node: "exchange",
        why: `Inner OIDC gate returned ${m ? m[1] : "40x"} — the token lacks the API audience/scope. This is the case token-exchange fixes on /mcp/ops.` };
    }
    return { verdict: "allow", node: "upstream",
      why: "All gates passed — the call reached the upstream and returned data." };
  }

  return { verdict: "unknown", node: null, why: `Unexpected HTTP ${httpStatus}.` };
}

function deepIsError(obj) {
  return !!(obj.result && obj.result.isError === true);
}

export default classify;
