# PQ-11: Hostinger `staging` then `prod`

**Depends on:** PQ-10, PQ-15, a signed DPA with Reygan · **Size:** M

## Scope
- `prepare-host.sh --instance staging` and `--instance prod` printed for Craig; users created, linger on.
- Re-check both blocks free on the server; claim them in that host's register.
- `install.sh --instance staging --road tunnel`, then the same for `prod` after staging passes PQ-09's
  checklist (short form).
- Host Caddy blocks for each public name -> `127.0.0.1:26219` / `127.0.0.1:17166`, Caddyfile backed up,
  `caddy validate` before reload (AtlasAI runbook pattern).
- Cloudflare Access in front of both public names (Q4). List every non-browser caller that comes in
  over the tunnel (external MCP connectors, webhooks, email-hook callbacks) and give each a service
  token or a narrow path bypass, written in the runbook.
- Secrets from Infisical (`secrets-init.sh --source infisical`), not the local generator.
- `prod` go-live for Reygan's books only after: DPA signed, PQ-10 backups running to EU storage with
  Object Lock, restore drill passed on `staging`.
- Measure memory with both stacks up; record it.
- `deploy/podman/runbook-hostinger.md`: start, stop, upgrade, Supabase release bump, restore, rollback, remove.

## Acceptance
- `ss -ltn`: Accounted only on the two loopback edge ports.
- With an app stopped, its public name answers 502, not a vanished host.
- Ward `security-audit.sh`: no HIGH for Accounted.
- One real verifikat posted on `prod` and seen in the general ledger (DoD item 9).
