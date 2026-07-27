# demo-ui live verification screenshots (2026-07-24)

Playwright captures from the live verification pass recorded in commit `789749e`
(*test(demo-ui): live Playwright verification — Overview + F1–F6, 7 steps green*).
Relocated here from the repo root on 2026-07-27 to keep root clean; cited by
`NOTES.md`, `claude/NEXT-SESSION.md`, and `claude/handoff/state.md`.

| File | What it evidences |
|------|-------------------|
| `verify-overview.png` | Overview is the default route: personas, the 4-tool permission matrix (✓/✕ matching `kong/konnect.yaml` allow-lists), 7 steps, and legend — customer-safe, no internal callouts. |
| `verify-demo-step1.png` | Demo mode Step 1 rendering: per-call identity badge, expected/got trust chip ("✓ matches expected · live call"), plugin-chain trace. |

These are verification evidence, not brainstorm mockups — no DECISIONS entry is locked by
them; they back the "verified LIVE" claims in NOTES.md's demo-ui build findings.
