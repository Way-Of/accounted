# HANDOFF

**Accounted on Podman Quadlet with self-hosted Supabase** (Way-Of fork: `Way-Of/accounted`)

> **Read this first in a fresh session.** It is the logical state of the Quadlet work, not the session
> cache. The PRD holds the reasoning; this file holds where we are and what is next.

```
handoff{ "branch": "podman-conversion-and-staging-push", "base": "b0b481b9d", "updated": "2026-11-18" }
```

## Where we are

```
phase_status:
  "PRD","revision 2: docs/plans/podman-quadlet/PRD.md (official Supabase self-hosted stack, trimmed, PG 17)"
  "Tasks","15 slices: docs/plans/podman-quadlet/tasks/ (PQ-01..PQ-15); statuses in tasks/README.md"
  "Diagrams","docs/plans/podman-quadlet/ARCHITECTURE.md"
  "Built","PQ-01..03 done; PQ-04 (stack), PQ-06 (migrate), PQ-07 (app, cron), PQ-08 (edge) built and running on Hostinger"
  "Live","qa (accounted-qa, 127.0.0.1:26791) and staging (accounted-staging, 127.0.0.1:26219) on Hostinger, healthy, 1088 migrations; loopback only, no hostname yet"
  "Blocked on Craig","hostnames + Cloudflare Access for qa/staging; Q8; commit/push of the 2026-11-18 deploy work; first real accounts"
  "Remotes","GitHub only; both Forgejos wait on credentials (see Remotes below)"
```

## Facts established (do not re-derive)

- **Data layer:** the official Supabase self-hosted stack (`self-hosted/vX.Y.Z`, pinned in
  `deploy/podman/upstream.lock`), trimmed: keep db, auth, rest, storage, realtime, gateway, meta,
  studio (on demand). Drop analytics, vector (mounts the Docker socket), functions (0 invokes), imgproxy
  (0 transforms), supavisor (no direct pg in `src/`).
- **Postgres 17** on self-hosted; hosted prod and CI stay 15, so PQ-05 adds pg-real on 17.
- **Migrations:** `supabase/bootstrap.sql` once on an empty DB, then `supabase db push` (CLI ledger in
  `supabase_migrations.schema_migrations`). No custom runner.
- **Instances, one Linux user each:** `dev` (Minisforum, `accounted-dev`), `staging` and `prod`
  (Hostinger, `accounted-staging`, `accounted-prod`). Same `install.sh` everywhere.
- **Built so far:** `deploy/podman/` (instances/*.env, internal-ports.env, secrets.manifest, demo-values.txt,
  upstream.lock, quadlets/accounted.network, bin/{lib,check,prepare-host,install,secrets-init}.sh). Services
  register rows in `$YMIR_HOME/config/services.yaml` (created 2026-11-17, check is clean).
- **Upstream v0.8.4 facts:** Envoy is the default gateway; analytics/vector moved to an optional logs overlay;
  new opaque/asymmetric keys are optional (we keep HS256 anon/service_role, which the app reads).
- **Port blocks:** prod 17166-17173, staging 26219-26226, dev 21230-21237. `+0` edge (only published
  port, 127.0.0.1), `+1` Studio and `+2` DB admin (loopback, on demand), `+3..+7` reserved.
  Internal container ports keep image defaults pending Q10.
- **Peers** (Atlas, receipt-hunter, agents) cannot share a rootless Podman network across users: they
  call the edge door over host loopback with their own scoped `gnubok_sk_` key.
- **Single origin:** edge routes `/auth/v1 /rest/v1 /storage/v1 /realtime/v1` to the gateway; Next has no
  routes there (only `/auth/callback`, `/auth/email-change`).
- **Backups:** reuse `scripts/self-host/backup.sh` / `restore.sh`; they already target this stack.
- Hostinger pattern to copy: `atlas-vault/deploy/hostinger/runbook.md`.
- Do NOT copy from WoWx/wayofteams: absolute `/home/...` mounts, `PublishPort=5432:5432`,
  `SecurityLabelDisable=true`, plaintext env files.
- Claude subagents are blocked by a house hook; delegate through Eindri or work inline.

## Running now (2026-11-18)

- Release tree: `/opt/way-of/accounted` (root-owned copy of the working tree, `REVISION` names the commit +
  worktree time). Images built as `craig` (`localhost/accounted:527f026`, `localhost/accounted-cron:527f026`)
  and loaded into each instance user with `podman save | podman load`.
- Run as an instance user from `craig`: `~/bin/asu <qa|staging> '<command>'` (sudo -u with the user's
  systemd bus). Install: `install.sh --instance <i> install|start|status|migrate`.
- Reach a door from the Mac: `ssh -L 26791:127.0.0.1:26791 hostinger` then http://127.0.0.1:26791 (qa);
  26219 for staging. The browser must use that exact origin (it is baked into the bundle at start).
- Proven per instance (throwaway user, removed): admin create, password sign-in, rest as the user (200),
  `/auth/v1/user`, storage, realtime ping, public sign-up refused (`signup_disabled`), owned sockets loopback only.
- Josef's Docker instance (`/srv/accounted`, accounted.veyral.io) left as is except sign-up closed
  (`.env.bak-signup-20261118-223448`); Josef emailed.
- Not built yet: studio/meta units (on demand), backups (PQ-10), egress door, upstream-diff.sh, image digests
  in `upstream.lock` (pulled digests are in `install.sh pull` output), SMTP.

## Next actions

1. Craig: `deploy/podman/bin/prepare-host.sh --instance dev`, run the printed root steps (user, subids, linger).
2. Craig: decide Q8 (secrets source of record; Infisical parked). Recommendation in the session notes: SOPS + age.
3. As `accounted-dev`: `secrets-init.sh --instance dev`, `install.sh --instance dev install`, then finish PQ-04
   (units for db, auth, rest, storage, realtime, gateway (Envoy), meta, studio from the v0.8.4 compose in
   upstream `docker/`; vendored init SQL minus `_supabase.sql`, `logs.sql`, `pooler.sql`).
4. Start the DPA with Reygan (gates `prod`, PQ-11). Finish the Forgejo pushes.

## Remotes

| Remote | URL | State 2026-11-17 |
|---|---|---|
| `origin` | `git@github.com:Way-Of/accounted.git` | pushed |
| `forgejo` | `http://localhost:8889/Way-Of/accounted.git` (Minisforum, rootless under craigema) | **not pushed**: needs the `wayof` password; push-to-create is off, so the repo must exist first |
| `forgejo-hostinger` | `https://git.veyral.io/Way-Of/accounted.git` (Hostinger, user `forgejo`, SSH disabled) | **not pushed**: needs a sign-in or token; repo existence unknown |

## Not live

qa and staging run on Hostinger loopback only: no hostname, no tunnel, no Cloudflare Access, no SMTP,
no backups, no real accounts. dev (Minisforum) and prod are not installed.
