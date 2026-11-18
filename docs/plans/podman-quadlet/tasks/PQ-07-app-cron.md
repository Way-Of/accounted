# PQ-07: App and cron units

**Depends on:** PQ-06 · **Size:** M

## Scope
- `podman build -f docker/Dockerfile -t localhost/accounted:<git-sha> .` (no Dockerfile edits).
- `accounted-app.container`: `NEXT_PUBLIC_SUPABASE_URL` = `ACCOUNTED_PUBLIC_URL` (single origin, PQ-08),
  `SUPABASE_URL` for server calls = the gateway's internal address, `NEXT_PUBLIC_SELF_HOSTED=true`,
  secrets from PQ-03; `ReadOnly=true` with tmpfs `/tmp`, `/app/public` and the `accounted-app-runtime`
  volume for `/app/.next` (same reason as `next_runtime` in `docker-compose.yml`); `HealthCmd` on
  `/api/health`; `HTTPS_PROXY` from `ACCOUNTED_EGRESS_PROXY` when set.
- Check how server-side code builds its Supabase URL; if it only reads `NEXT_PUBLIC_SUPABASE_URL`,
  route server calls through the edge instead of adding a new variable.
- `accounted-cron.container` from `docker/cron.Dockerfile`, mounting `docker/crontab.self-hosted`.

## Acceptance
- App healthy; login page renders; a cron route observed firing in `journalctl --user -u accounted-cron`.
- `validate-podman` passes on both units.
