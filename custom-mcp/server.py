# custom-mcp — a hand-written PYTHON MCP server, governed by Kong at /mcp/custom.
#
# Why this exists: dealer-svc/finance-svc are REST APIs that Kong CONVERTS into MCP
# tools (ai-mcp-proxy conversion-only). This service is the other shape — a real MCP
# server someone built by hand, in a language other than the rest of the stack — fronted
# by ai-mcp-proxy `passthrough-listener`. It proves the registry/gateway story is
# language- and transport-agnostic: Kong governs a custom Python tool it did not generate.
#
# Access model: authentication is mandatory (ai-mcp-oauth2 401s an unauthenticated call) AND
# Kong enforces a PER-TOOL ACL matched by name on the passthrough listener:
# allow: [finance, dealers]. So dana + frank may call hello_custom_tool; olivia (ops) is
# denied and does not even see it in tools/list. The ACL lives in kong/konnect.yaml — this
# server has no notion of it, which is the point: governance is external to the tool.
#
# Transport: Streamable HTTP, mounted at /mcp (SDK default), STATELESS so a single POST
# tools/list or tools/call works without session negotiation — that keeps it usable from
# curl, scripts/demo.sh and the cockpit. (market-mcp is session-based; the passthrough
# handles both, but stateless is friendlier to demo one-liners.)
#
# VERIFIED against mcp 2.0.0 (2026-08-12): the high-level class is
# `mcp.server.mcpserver.MCPServer`. `mcp.server.fastmcp` does NOT exist in 2.x — the
# FastMCP import every pre-2.0 example uses raises ModuleNotFoundError. See NOTES.md.

import os

from mcp.server.mcpserver import MCPServer
from mcp.server.transport_security import TransportSecuritySettings
from starlette.requests import Request
from starlette.responses import JSONResponse

PORT = int(os.environ.get("PORT", "3000"))

mcp = MCPServer(
    "custom-mcp",
    title="Cox Custom MCP (Python)",
    version="1.0.0",
    instructions="A hand-written Python MCP server governed by Kong AI Gateway.",
)


@mcp.tool()
def hello_custom_tool() -> str:
    # The docstring IS the agent-facing tool description (the SDK forwards it verbatim
    # in tools/list), so keep it one tight line — no indented continuation lines.
    """Return a greeting confirming this custom Python MCP tool is reachable through Kong."""
    return "Hello from custom tool"


@mcp.custom_route("/health", methods=["GET"])
async def health(_request: Request) -> JSONResponse:
    # Mirrors the Node services' /health so the compose healthcheck is uniform.
    return JSONResponse({"status": "ok", "svc": "custom-mcp"})


if __name__ == "__main__":
    mcp.run(
        transport="streamable-http",
        host="0.0.0.0",  # noqa: S104 — container-internal; Kong is the only ingress.
        port=PORT,
        streamable_http_path="/mcp",
        stateless_http=True,
        # The SDK enables DNS-rebinding protection by default, which validates the
        # inbound Host header against an allow-list. Kong proxies to this service as
        # `custom-mcp:3000`, so the default would reject every gateway-borne request.
        # The trust boundary here is Kong + ai-mcp-oauth2 (this port is never exposed
        # publicly), so we turn the Host check off rather than enumerate hostnames.
        transport_security=TransportSecuritySettings(
            enable_dns_rebinding_protection=False,
        ),
    )
