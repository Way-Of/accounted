# PQ-10: Backups and restore drill

**Depends on:** PQ-09 · **Size:** M

## Goal
Reuse the existing self-host tooling (`scripts/self-host/backup.sh`, `restore.sh`, `acl-manifest.sql`),
which already targets this stack, instead of writing new backup code.

## Scope
- `accounted-backup.container` (oneshot) + `accounted-backup.timer` running `backup.sh` with the
  instance's env: dump, ACL manifest, documents, db-config archive, to S3-compatible storage
  (Object Lock where the target supports it). Off-host target per instance in the instance env.
- Load `swedish-accounting-compliance` before fixing the retention, so nothing linked to a posted entry
  goes before BFL allows.
- Restore drill with `restore.sh` into a fresh instance user (a throwaway `accounted-drill`).

## Acceptance
- Timer observed firing; backup set present with checksums.
- Restore reproduces the company, entries, voucher sequence and openable documents.
