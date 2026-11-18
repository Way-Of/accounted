# PQ-11: Hostinger `staging` then `prod`

**Depends on:** PQ-10, Q4, Q6, Q9 · **Size:** M

## Scope
- `prepare-host.sh --instance staging` and `--instance prod` printed for Craig; users created, linger on.
- Re-check both blocks free on the server; claim them in that host's register.
- `install.sh --instance staging --road tunnel`, then the same for `prod` after staging passes PQ-09's
  checklist (short form).
- Host Caddy blocks for each public name -> `127.0.0.1:26219` / `127.0.0.1:17166`, Caddyfile backed up,
  `caddy validate` before reload (AtlasAI runbook pattern); Cloudflare Access if Q4 says so.
- Measure memory with both stacks up; record it.
- `deploy/podman/runbook-hostinger.md`: start, stop, upgrade, Supabase release bump, restore, rollback, remove.

## Acceptance
- `ss -ltn`: Accounted only on the two loopback edge ports.
- With an app stopped, its public name answers 502, not a vanished host.
- Ward `security-audit.sh`: no HIGH for Accounted.
- One real verifikat posted on `prod` and seen in the general ledger (DoD item 9).
