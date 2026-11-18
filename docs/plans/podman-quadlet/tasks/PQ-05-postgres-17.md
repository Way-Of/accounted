# PQ-05: Postgres 17 compatibility

**Depends on:** PQ-04 · **Size:** M

## Goal
Prove all migrations and the pg-real suite on the `supabase/postgres` 17 image, while hosted prod and
CI stay on 15 (PRD 5.2, Q3).

## Scope
- Replay `supabase/bootstrap.sql` + every migration on the pinned 17 image (`scripts/tool-pg/reset.sh`
  pattern, image swapped through an env var).
- `npm run test:pg` against it.
- Add a pg-real job (or matrix leg) on the 17 image in `.github/workflows/test-pg-real.yml`, so a new
  migration that breaks 17 fails CI.

## Acceptance
- Replay and pg-real green on 17, or each failure fixed in a **new** migration that works on 15 and 17.
- Zero edits to existing migrations or to migration 017.
- One line in `DECISIONS.md` with the result.
