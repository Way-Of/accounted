#!/usr/bin/env bash
# migrate-in-container.sh: the accounted-migrate unit's body. Runs INSIDE the supabase/postgres
# image (it has psql), never on the host. Reads the release's supabase/ directory from /accounted.
#
#   1. supabase/bootstrap.sql once, on a database that has no migration applied yet
#   2. every supabase/migrations/*.sql not yet in supabase_migrations.schema_migrations, in
#      LC_ALL=C order, each through psql with ON_ERROR_STOP, recorded in that ledger as it lands
#
# The ledger is the table the Supabase CLI writes (version, statements, name), so DoD item 8's
# reconciliation reads it unchanged and a later switch to `supabase db push` sees the same history.
# The path is the one docs/SELF-HOSTING.md documents and CI's pg-real job runs. A file that fails
# halfway is not recorded and may leave partial work (some use CREATE INDEX CONCURRENTLY, so none
# run in one transaction): the unit stops, names the file, and the next start retries from it.
set -euo pipefail
export LC_ALL=C
src=/accounted/supabase
: "${PGHOST:?}" "${PGUSER:?}" "${PGDATABASE:?}" "${PGPASSWORD:?}"
q() { psql -X -q -v ON_ERROR_STOP=1 "$@"; }

for _ in $(seq 90); do pg_isready -q && break; sleep 2; done
pg_isready -q || { echo "migrate: database not ready" >&2; exit 1; }

q <<'SQL'
create schema if not exists supabase_migrations;
create table if not exists supabase_migrations.schema_migrations (
  version text primary key, statements text[], name text);
SQL

applied="$(q -At -c 'select version from supabase_migrations.schema_migrations order by 1')"
if [ -z "$applied" ]; then
  echo "migrate: empty ledger, running supabase/bootstrap.sql"
  q -f "$src/bootstrap.sql"
fi

# an applied version with no file is an orphan (CLAUDE.md): refuse to run on top of it
files="$(cd "$src/migrations" && ls -1 -- *.sql | sort)"
orphans="$(comm -23 <(printf '%s\n' "$applied" | sed '/^$/d' | sort) <(printf '%s\n' "$files" | sed 's/_.*//' | sort))"
[ -z "$orphans" ] || { echo "migrate: ledger versions with no file in this release: $orphans" >&2; exit 1; }

n=0
while IFS= read -r f; do
  v="${f%%_*}"; name="${f#*_}"; name="${name%.sql}"
  grep -qxF -- "$v" <<<"$applied" && continue
  echo "migrate: applying $f"
  q -f "$src/migrations/$f" \
    -c "insert into supabase_migrations.schema_migrations (version, name) values ('$v', '$name')" \
    || { echo "migrate: FAILED at $f" >&2; exit 1; }
  n=$((n + 1))
done <<<"$files"

q -c "notify pgrst, 'reload schema'"
echo "migrate: $n applied, $(q -At -c 'select count(*) from supabase_migrations.schema_migrations') in the ledger"
