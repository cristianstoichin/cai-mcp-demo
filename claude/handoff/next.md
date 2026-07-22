# next.md — suggested priorities

1. **Phase 2** — `scripts/konnect-bootstrap.sh` (doc-verify CP-create + DP-cert API first),
   kong-dp DP env in compose, `kong/konnect.yaml` services+routes+OIDC, `deck gateway validate`.
   Live gate (user): DP connects; curl matrix 401/200/403.
2. Then Phase 3 (conversion-only + listener), verify `tools/list` 2/2/2-bundled pre-auth.
3. Continue per `claude/plans/2026-07-22-cai-mcp-demo-implementation.md`.
