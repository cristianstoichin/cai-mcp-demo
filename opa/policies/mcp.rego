# =============================================================================
# mcp.rego — external policy for the /mcp/ops MCP endpoint.
#
# Kong's `opa` plugin POSTs an `input` document to /v1/data/mcp/allow and gates
# the request on the boolean result. This policy demonstrates policy-as-code on
# TOP of the token-claim ACL: it can re-express an entitlement in an external
# engine AND enforce dimensions Kong has no native plugin for (argument-level and
# time-of-day rules). Edit this file and OPA hot-reloads it — no Kong sync.
#
# Input wiring (see kong/konnect.yaml, plugin `opa` on /mcp/ops):
#   - include_parsed_json_body_in_opa_input: true -> JSON-RPC body is decoded, so
#     input.request.http.parsed_body carries the MCP method + params.name/arguments.
#   - ai-mcp-oauth2 claim_to_header groups -> X-User-Groups header.
#
# VERIFIED-BY-OBSERVATION (Kong 3.14, OPA decision log — see NOTES.md Phase-5.2):
#   - the body is at input.request.http.parsed_body (NOT input.request.body).
#   - header keys are lower-cased.
#   - a non-scalar claim (the groups ARRAY) is forwarded by claim_to_header as
#     BASE64-encoded JSON: ["ops"] -> "WyJvcHMiXQ==". So it must be base64-decoded
#     then json.unmarshal'd — a plain comma-split is wrong.
# Do not "correct" these paths from memory of other Kong OPA examples.
# =============================================================================
package mcp

import rego.v1

# Default allow — OPA is an ADDITIONAL gate, not the primary authorizer
# (ai-mcp-oauth2 + the token-claim tool ACL already ran). Only the rules below subtract.
default allow := true

# --- request facts (from the decoded JSON-RPC body) ------------------------
body := input.request.http.parsed_body

method := object.get(body, "method", "")

params := object.get(body, "params", {})

tool := object.get(params, "name", "")

args := object.get(params, "arguments", {})

# --- caller groups (base64(JSON) in X-User-Groups) -------------------------
raw_groups := object.get(input.request.http.headers, "x-user-groups", "")

default groups := []

groups := json.unmarshal(base64.decode(raw_groups)) if raw_groups != ""

# --- Rule 1: entitlement as code -------------------------------------------
# Only finance/ops may list invoices. Parallels the tool ACL — the point is that
# the SAME entitlement can be externalized to a policy engine.
allow := false if {
	method == "tools/call"
	tool == "list_invoices"
	not group_allowed
}

group_allowed if groups[_] == "finance"

group_allowed if groups[_] == "ops"

# --- Rule 2: argument-level policy the tool ACL CANNOT express --------------
# Even a permitted caller may not filter invoices to the sensitive `overdue`
# status through the MCP endpoint. The tool ACL is tool-grained; only an external
# policy can see and gate the CALL ARGUMENTS. (Query args are namespaced query_<name>.)
allow := false if {
	method == "tools/call"
	tool == "list_invoices"
	object.get(args, "query_status", "") == "overdue"
}

# --- Rule 3 (commented): business hours — a dimension Kong has no plugin for --
# Deny all tool calls outside 08:00–18:00 UTC. Uncomment to demo a time policy.
# deny_off_hours if {
# 	method == "tools/call"
# 	hour := time.clock(time.now_ns())[0]
# 	hour < 8
# }
# deny_off_hours if {
# 	method == "tools/call"
# 	hour := time.clock(time.now_ns())[0]
# 	hour >= 18
# }
# allow := false if deny_off_hours
