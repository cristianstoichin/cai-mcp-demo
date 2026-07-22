// dealer-svc — Cox Automotive dealer REST service (demo mock).
//
// Two endpoints Kong converts into MCP tools via ai-mcp-proxy (conversion-only):
//   GET /customers  -> list_dealer_customers
//   GET /vehicles   -> list_dealer_vehicles
// Plus GET /health for compose healthchecks.
//
// Every request logs its inbound headers as JSON to stdout so that claims Kong
// forwards (X-User-Id, X-User-Name, etc.) are visible in `docker compose logs`
// during the demo — this is the "governed identity reaches the upstream" beat.

const express = require("express");

const app = express();
const PORT = process.env.PORT || 3000;

// --- Header-logging middleware -------------------------------------------------
// DANGER: logs full inbound headers (incl. forwarded identity) — demo only.
app.use((req, _res, next) => {
  console.log(
    JSON.stringify({
      svc: "dealer-svc",
      method: req.method,
      path: req.path,
      query: req.query,
      headers: req.headers,
      at: new Date().toISOString(),
    })
  );
  next();
});

// --- Data ----------------------------------------------------------------------
const CUSTOMERS = [
  { name: "Marcus Bell", dealership: "Sunrise Ford", region: "southeast", kbb_trade_in_interest: "high" },
  { name: "Priya Nadella", dealership: "Lakeside Toyota", region: "midwest", kbb_trade_in_interest: "medium" },
  { name: "Dwayne Ellis", dealership: "Summit Chevrolet", region: "west", kbb_trade_in_interest: "high" },
  { name: "Carla Jimenez", dealership: "Sunrise Ford", region: "southeast", kbb_trade_in_interest: "low" },
  { name: "Aaron Fitzgerald", dealership: "Metro Honda", region: "northeast", kbb_trade_in_interest: "medium" },
];

const VEHICLES = [
  { vin: "1FTFW1E5XKFA12345", make: "Ford", model: "F-150", days_on_lot: 12, vauto_price_rank: "great" },
  { vin: "5TDZA23C13S012345", make: "Toyota", model: "Sequoia", days_on_lot: 63, vauto_price_rank: "high" },
  { vin: "1GCUYDED5KZ123456", make: "Chevrolet", model: "Silverado", days_on_lot: 8, vauto_price_rank: "great" },
  { vin: "2HGFC2F59KH512345", make: "Honda", model: "Civic", days_on_lot: 41, vauto_price_rank: "fair" },
  { vin: "1C4RJFBG5MC712345", make: "Jeep", model: "Grand Cherokee", days_on_lot: 27, vauto_price_rank: "good" },
];

// --- Routes --------------------------------------------------------------------
app.get("/health", (_req, res) => res.json({ status: "ok", svc: "dealer-svc" }));

// Kong routes forward these paths verbatim (strip_path:false), so the mock owns
// the real dealer API surface. ai-mcp-proxy converts each into an MCP tool.

// GET /api/dealers/customers?region=<southeast|midwest|west|northeast>
app.get("/api/dealers/customers", (req, res) => {
  const { region } = req.query;
  let rows = CUSTOMERS;
  if (region) rows = rows.filter((c) => c.region === String(region).toLowerCase());
  res.json({ count: rows.length, customers: rows });
});

// GET /api/dealers/vehicles?price_rank=<great|good|fair|high>
app.get("/api/dealers/vehicles", (req, res) => {
  const rank = req.query.price_rank;
  let rows = VEHICLES;
  if (rank) rows = rows.filter((v) => v.vauto_price_rank === String(rank).toLowerCase());
  res.json({ count: rows.length, vehicles: rows });
});

app.listen(PORT, () => console.log(`dealer-svc listening on :${PORT}`));
