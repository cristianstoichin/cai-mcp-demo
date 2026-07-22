// finance-svc — Cox Automotive finance REST service (demo mock).
//
// Two endpoints Kong converts into MCP tools via ai-mcp-proxy (conversion-only):
//   GET /invoices    -> list_invoices
//   GET /floorplans  -> list_floorplans
// Plus GET /health for compose healthchecks.
//
// Same header-logging as dealer-svc so forwarded identity claims are visible in
// `docker compose logs` during the demo.

const express = require("express");

const app = express();
const PORT = process.env.PORT || 3000;

// DANGER: logs full inbound headers (incl. forwarded identity) — demo only.
app.use((req, _res, next) => {
  console.log(
    JSON.stringify({
      svc: "finance-svc",
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
const INVOICES = [
  { invoice_id: "INV-2026-0412", dealer: "Sunrise Ford", amount: 184200.0, status: "paid" },
  { invoice_id: "INV-2026-0417", dealer: "Lakeside Toyota", amount: 92750.5, status: "overdue" },
  { invoice_id: "INV-2026-0421", dealer: "Summit Chevrolet", amount: 210500.0, status: "pending" },
  { invoice_id: "INV-2026-0425", dealer: "Metro Honda", amount: 46300.75, status: "paid" },
  { invoice_id: "INV-2026-0429", dealer: "Sunrise Ford", amount: 133900.0, status: "pending" },
];

const FLOORPLANS = [
  { floorplan_line: "FPL-SUNRISE-01", utilization: 0.82, next_audit_date: "2026-08-14" },
  { floorplan_line: "FPL-LAKESIDE-03", utilization: 0.67, next_audit_date: "2026-08-02" },
  { floorplan_line: "FPL-SUMMIT-02", utilization: 0.94, next_audit_date: "2026-07-29" },
  { floorplan_line: "FPL-METRO-01", utilization: 0.55, next_audit_date: "2026-09-05" },
];

// --- Routes --------------------------------------------------------------------
app.get("/health", (_req, res) => res.json({ status: "ok", svc: "finance-svc" }));

// GET /invoices?status=<paid|overdue|pending>
app.get("/invoices", (req, res) => {
  const { status } = req.query;
  let rows = INVOICES;
  if (status) rows = rows.filter((i) => i.status === String(status).toLowerCase());
  res.json({ count: rows.length, invoices: rows });
});

// GET /floorplans?status=<due-soon|ok>  (derived: due-soon = audit within 21 days of 2026-07-22)
app.get("/floorplans", (req, res) => {
  const { status } = req.query;
  let rows = FLOORPLANS;
  if (status === "due-soon") {
    rows = rows.filter((f) => new Date(f.next_audit_date) <= new Date("2026-08-12"));
  } else if (status === "ok") {
    rows = rows.filter((f) => new Date(f.next_audit_date) > new Date("2026-08-12"));
  }
  res.json({ count: rows.length, floorplans: rows });
});

app.listen(PORT, () => console.log(`finance-svc listening on :${PORT}`));
