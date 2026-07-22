// stack.js — the ONLY commands the UI may run (fixed whitelist → no arbitrary
// exec). Each streams stdout/stderr to the browser over SSE. Repo-root cwd.

import { spawn } from "node:child_process";
import { fileURLToPath } from "node:url";
import { dirname, resolve } from "node:path";

const REPO = resolve(dirname(fileURLToPath(import.meta.url)), "..");

export const ACTIONS = Object.freeze({
  "up":             { cmd: "docker", args: ["compose", "up", "-d"], desc: "Start the stack (detached)" },
  "down":           { cmd: "docker", args: ["compose", "down"], desc: "Stop the stack" },
  "sync":           { cmd: "docker", args: ["compose", "--profile", "tools", "run", "--rm", "deck", "gateway", "sync", "/config/konnect.yaml"], desc: "deck gateway sync" },
  "preflight":      { cmd: "bash", args: ["scripts/preflight.sh"], desc: "Preflight checks" },
  "smoke":          { cmd: "bash", args: ["scripts/smoke-test.sh"], desc: "Smoke test" },
  "registry-setup": { cmd: "bash", args: ["scripts/registry-setup.sh"], desc: "Publish to the MCP Registry" },
});

// Strip ANSI color/escape codes so the browser terminal shows clean text.
// eslint-disable-next-line no-control-regex
const ANSI = new RegExp("\\x1b\\[[0-9;]*m", "g");

export function runAction(action, onData, onEnd) {
  const spec = ACTIONS[action];
  if (!spec) throw new Error(`action not allowed: ${action}`);
  const child = spawn(spec.cmd, spec.args, { cwd: REPO, env: process.env });
  const pump = (buf) => String(buf).replace(ANSI, "").split("\n").forEach(l => l && onData(l));
  child.stdout.on("data", pump);
  child.stderr.on("data", pump);
  child.on("close", (code) => onEnd(code ?? -1));
  child.on("error", (e) => { onData(`[spawn error] ${e.message}`); onEnd(-1); });
  return child;
}
