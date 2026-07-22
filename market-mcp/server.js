// =============================================================================
// market-mcp — a local Cox Automotive-themed MCP server (Streamable HTTP).
//
// This is the "remote MCP server you own" behind Kong's /mcp/remote passthrough
// route: Kong governs access (ai-mcp-oauth2) and proxies the raw MCP protocol to
// this server without converting anything. Contrast /mcp/remote-public → DeepWiki
// (a third-party MCP server you do NOT own).
//
// Streamable-HTTP transport at POST/GET/DELETE /mcp; plain /health for the
// container healthcheck. Listens on :3000 (compose maps ${MARKET_MCP_PORT}->3000).
// =============================================================================
import { randomUUID } from "node:crypto";
import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StreamableHTTPServerTransport } from "@modelcontextprotocol/sdk/server/streamableHttp.js";
import { isInitializeRequest } from "@modelcontextprotocol/sdk/types.js";
import express from "express";
import { z } from "zod";

// --- Cox-themed market dummy data -------------------------------------------
// vAuto/KBB-style market bands keyed by "make model" (lowercased).
const MARKET = {
  "ford f-150": { segment: "full-size pickup", avg_market_price: 48250, price_band: [44100, 53200], days_supply: 41, demand: "high" },
  "toyota rav4": { segment: "compact suv", avg_market_price: 33110, price_band: [30800, 36400], days_supply: 28, demand: "very high" },
  "honda civic": { segment: "compact car", avg_market_price: 26480, price_band: [24100, 29200], days_supply: 33, demand: "high" },
  "chevrolet silverado": { segment: "full-size pickup", avg_market_price: 46900, price_band: [42500, 51800], days_supply: 58, demand: "moderate" },
  "tesla model 3": { segment: "electric sedan", avg_market_price: 39990, price_band: [36500, 43900], days_supply: 22, demand: "very high" },
};

// Days-supply by segment (inventory velocity; <30 tight, >60 soft).
const SEGMENT_SUPPLY = {
  "full-size pickup": { days_supply: 49, trend: "rising", note: "softening as incentives return" },
  "compact suv": { days_supply: 27, trend: "flat", note: "chronically tight; fast turns" },
  "compact car": { days_supply: 31, trend: "falling", note: "affordability demand firming" },
  "electric sedan": { days_supply: 24, trend: "falling", note: "tight on popular trims" },
};

const buildServer = () => {
  const server = new McpServer({ name: "market-mcp", version: "1.0.0" });

  server.tool(
    "market_price_check",
    "Check the current retail market price band for a vehicle (vAuto/KBB-style). Returns average market price, low/high band, days-supply, and demand.",
    { make: z.string(), model: z.string() },
    async ({ make, model }) => {
      const key = `${make} ${model}`.toLowerCase().trim();
      const row = MARKET[key];
      if (!row) {
        return { content: [{ type: "text", text: `No market data for "${make} ${model}". Known: ${Object.keys(MARKET).join(", ")}` }] };
      }
      return { content: [{ type: "text", text: JSON.stringify({ make, model, ...row }, null, 2) }] };
    },
  );

  server.tool(
    "days_supply_lookup",
    "Look up inventory days-supply (velocity) for a vehicle segment, e.g. 'compact suv' or 'full-size pickup'. Lower is tighter/faster-turning.",
    { segment: z.string() },
    async ({ segment }) => {
      const row = SEGMENT_SUPPLY[segment.toLowerCase().trim()];
      if (!row) {
        return { content: [{ type: "text", text: `No supply data for segment "${segment}". Known: ${Object.keys(SEGMENT_SUPPLY).join(", ")}` }] };
      }
      return { content: [{ type: "text", text: JSON.stringify({ segment, ...row }, null, 2) }] };
    },
  );

  return server;
};

const app = express();
app.use(express.json());

// One transport per MCP session id (Streamable HTTP session model).
const transports = {};

app.all("/mcp", async (req, res) => {
  try {
    const sessionId = req.headers["mcp-session-id"];
    let transport;

    if (sessionId && transports[sessionId]) {
      transport = transports[sessionId];
    } else if (!sessionId && req.method === "POST" && isInitializeRequest(req.body)) {
      transport = new StreamableHTTPServerTransport({
        sessionIdGenerator: () => randomUUID(),
        onsessioninitialized: (sid) => { transports[sid] = transport; },
      });
      transport.onclose = () => {
        const sid = transport.sessionId;
        if (sid && transports[sid]) delete transports[sid];
      };
      await buildServer().connect(transport);
    } else {
      res.status(400).json({ jsonrpc: "2.0", error: { code: -32000, message: "Bad Request: No valid session ID" }, id: null });
      return;
    }

    await transport.handleRequest(req, res, req.body);
  } catch (err) {
    console.error(JSON.stringify({ level: "error", msg: "mcp request failed", err: String(err) }));
    if (!res.headersSent) {
      res.status(500).json({ jsonrpc: "2.0", error: { code: -32603, message: "Internal server error" }, id: null });
    }
  }
});

app.get("/health", (_req, res) => res.json({ status: "ok", service: "market-mcp" }));

app.listen(3000, () => {
  console.log(JSON.stringify({ level: "info", msg: "market-mcp listening on :3000 (Streamable HTTP at /mcp)" }));
});
