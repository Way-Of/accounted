# PQ-06: `accounted-migrate`

**Depends on:** PQ-04 · **Size:** S

## Goal
Migrations applied the way Supabase Cloud is migrated, with the same ledger, so DoD item 8
reconciliation works on self-hosted instances.

## Scope
- A small migrate image: pinned Supabase CLI release binary + `psql`, with `supabase/` copied in at the
  app image's git sha.
- Step 1, only when `supabase_migrations.schema_migrations` does not exist: `psql -f supabase/bootstrap.sql`.
- Step 2: `supabase db push --db-url <from secrets>`; then `NOTIFY pgrst, 'reload schema'`.
- `accounted-migrate.container`: oneshot, `After=` auth/storage/realtime, `Before=` rest and app.

## Acceptance
- First run on an empty database applies bootstrap and all migrations; a second run applies nothing.
- A new migration file + `install.sh upgrade` applies exactly that file.
- A fake version inserted into the ledger makes the run fail with the orphan named.
