# PQ-04: Trimmed upstream Supabase stack as Quadlets

**Depends on:** PQ-03 · **Size:** L

## Goal
The official self-hosted Supabase stack, minus what Accounted does not use, runs rootless on
`accounted.network` (`Internal=true`) for the `dev` instance.

## Scope
- Pick the current `self-hosted/vX.Y.Z` release; record it and every image digest in
  `deploy/podman/upstream.lock`. Postgres image: the release's 17.x `supabase/postgres`.
- Units: `accounted.network`, `accounted-db` (+ volume, + vendored init SQL from the release),
  `accounted-auth`, `accounted-rest`, `accounted-storage` (+ volume, file backend), `accounted-realtime`,
  `accounted-gateway` (Kong or Envoy, whichever the release defaults to, with its config vendored),
  `accounted-meta`, `accounted-studio` (not enabled at boot; published on `ACCOUNTED_STUDIO_PORT`,
  loopback only, when started).
- Dropped: `analytics`, `vector`, `functions`, `imgproxy`, `supavisor`, and the init SQL that only
  they need (`_supabase` analytics DB, pooler schema). Grep the kept services' env and init SQL for
  references to dropped ones; anything needed comes back with a reason in the PRD.
- `Requires=`/`After=`: db -> auth, storage, realtime -> (migrate, PQ-06) -> rest -> gateway.
- Per-unit rootless fixes (`UserNS`, added capabilities) found by booting, never `SecurityLabelDisable`.
- `deploy/podman/bin/upstream-diff.sh <tag>`: fetch upstream `docker/` at a tag, report image, env-key
  and init-SQL differences against the units and the lock.

## Acceptance
- Cold `install.sh --instance dev start` on an empty user reaches all-healthy with no manual steps.
- `curl` with the anon key through the gateway (from inside the network) answers on `/rest/v1/` and
  `/auth/v1/health`.
- `podman ps` shows no published port except Studio when started; nothing reaches the internet from
  the network (`podman exec accounted-db curl -m3 https://example.org` fails).
- `upstream-diff.sh` on the pinned tag reports no differences.
