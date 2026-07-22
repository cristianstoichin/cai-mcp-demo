// registry.js — Konnect MCP Registry discovery. PAT stays server-side. Mirrors
// demo.sh:87-96 parsing. US region / Labs tech preview (NOTES.md).

import { config } from "./config.js";

export async function discover() {
  if (!config.registryId || !config.konnectToken) return { configured: false, servers: [] };
  const url = `https://klabs.${config.konnectRegion}.api.konghq.com/v0/mcp-registries/${config.registryId}/v0.1/servers`;
  try {
    const res = await fetch(url, { headers: { Authorization: `Bearer ${config.konnectToken}` } });
    if (!res.ok) return { configured: true, servers: [], error: `registry API ${res.status}` };
    const data = await res.json();
    const raw = data.servers || data.data || [];
    const servers = raw.map(s => {
      const x = s.server || s;
      const remote = (x.remotes && x.remotes[0]) || {};
      return { name: x.name || "?", title: x.title, url: remote.url || "?" };
    });
    return { configured: true, servers };
  } catch (e) {
    return { configured: true, servers: [], error: String(e.message || e) };
  }
}
