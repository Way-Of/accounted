# Vendored from upstream Supabase self-hosted

Copied verbatim from `supabase/supabase` at `self-hosted/v0.8.4` (commit
`189adda99d1b56da55fc5a6ee3f849354aaea92a`), path `docker/volumes/`. Do not edit these files:
an upgrade replaces them whole, and `upstream.lock` records the release they belong to.

| File | Upstream path | Mounted by |
|---|---|---|
| `db/realtime.sql` | `volumes/db/realtime.sql` | `accounted-db` (init, `99-realtime.sql`) |
| `db/webhooks.sql` | `volumes/db/webhooks.sql` | `accounted-db` (init, `98-webhooks.sql`) |
| `db/roles.sql` | `volumes/db/roles.sql` | `accounted-db` (init, `99-roles.sql`) |
| `db/jwt.sql` | `volumes/db/jwt.sql` | `accounted-db` (init, `99-jwt.sql`) |
| `envoy/*` | `volumes/api/envoy/*` | `accounted-gateway` |

Left out on purpose (PRD 5.2): `_supabase.sql` and `logs.sql` (the analytics database, dropped with
Logflare and vector) and `pooler.sql` (Supavisor, dropped: nothing in `src/` speaks Postgres directly).
