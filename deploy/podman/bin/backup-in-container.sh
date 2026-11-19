#!/usr/bin/env bash
# accounted-backup (PQ-10): runs inside the supabase/postgres image (pg_dump matches the server's
# major version). One backup set per run via scripts/self-host/backup.sh in its local-directory
# mode, then rolling local sets older than ACCOUNTED_BACKUP_KEEP_DAYS are pruned.
#
# The local sets are the restore point on this host, not the BFL seven-year archive: that is the
# yearly post-bokslut set on off-host, Object Lock storage (PQ-10 follow-up). Every document stays
# in the live storage volume and in every newer set, so pruning an old nightly set deletes nothing
# the law requires us to keep.
set -euo pipefail
umask 077

out=/backup/out
keep="${ACCOUNTED_BACKUP_KEEP_DAYS:?}"
case "$keep" in ''|*[!0-9]*) echo "backup: ACCOUNTED_BACKUP_KEEP_DAYS must be a whole number" >&2; exit 2 ;; esac

until pg_isready -q -h "$PGHOST" -U "$PGUSER"; do sleep 2; done

export BACKUP_DATABASE_URL="postgresql://${PGUSER}@${PGHOST}:5432/${PGDATABASE}"
export BACKUP_LOCAL_DIR="$out"
export BACKUP_S3_PREFIX="$ACCOUNTED_INSTANCE"
export BACKUP_STORAGE_DIR=/backup/storage
export BACKUP_DB_CONFIG_DIR=/backup/db-config
export BACKUP_WORKDIR="$out/.work"
rm -rf "$BACKUP_WORKDIR"
trap 'rm -rf "$BACKUP_WORKDIR"' EXIT

bash /backup/bin/backup.sh

# a set is complete only once its manifest exists; check the newest one against its files
latest="$(ls -1d "$out/$ACCOUNTED_INSTANCE"/*/ 2>/dev/null | sort | tail -1)"
name="$(basename "$latest")"
( cd "$latest" && sha256sum -c "$name.sha256" >/dev/null )
echo "backup: verified $name"

find "$out/$ACCOUNTED_INSTANCE" -mindepth 1 -maxdepth 1 -type d -mtime "+$keep" -print -exec rm -rf {} + \
  | sed 's/^/backup: pruned /'
echo "backup: $(ls -1 "$out/$ACCOUNTED_INSTANCE" | wc -l) set(s) kept, $(du -sh "$out/$ACCOUNTED_INSTANCE" | cut -f1)"
