# HANDOFF

**Accounted on Podman Quadlet with self-hosted Supabase** (Way-Of fork: `Way-Of/accounted`)

> **Read this first in a fresh session.** It is the logical state of the Quadlet work, not the session
> cache. The PRD holds the reasoning; this file holds where we are and what is next.

```
handoff{ "branch": "podman-conversion-and-staging-push", "base": "b0b481b9d", "updated": "2026-11-17" }
```

## Where we are

```
phase_status:
  "PRD","revision 2: docs/plans/podman-quadlet/PRD.md (official Supabase self-hosted stack, trimmed, PG 17)"
  "Tasks","15 slices: docs/plans/podman-quadlet/tasks/ (PQ-01..PQ-15)"
  "Diagrams","docs/plans/podman-quadlet/ARCHITECTURE.md (estate, hosts, instance, boot, request, delivery)"
  "Remotes","pushed to GitHub only; both Forgejos wait on credentials (see Remotes below)"
  "Answered","all Q1-Q10 (PRD section 12): fork only · Access on staging/prod · shared VPS for now · Infisical · Reygan's books first on prod (EU VPS) · internal ports keep image defaults"
  "Tasks added","PQ-15 Infisical on Hostinger (user infisical, block 24095-24098, tailnet only)"
  "Code","none yet; nothing installed, no units on any host, no ports bound"
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

## Next actions

1. Get a personuppgiftsbiträdesavtal (DPA) with Reygan started; it gates `prod` go-live (PQ-11).
2. Finish the Forgejo pushes (needs Craig's credentials; see Remotes).
3. PQ-01 (config contract + register rows), PQ-02 (users, installer), PQ-03 (secrets), then PQ-04 (the stack).

## Remotes

| Remote | URL | State 2026-11-17 |
|---|---|---|
| `origin` | `git@github.com:Way-Of/accounted.git` | pushed |
| `forgejo` | `http://localhost:8889/Way-Of/accounted.git` (Minisforum, rootless under craigema) | **not pushed**: needs the `wayof` password; push-to-create is off, so the repo must exist first |
| `forgejo-hostinger` | `https://git.veyral.io/Way-Of/accounted.git` (Hostinger, user `forgejo`, SSH disabled) | **not pushed**: needs a sign-in or token; repo existence unknown |

## Not live

Nothing is live. No instance user exists, no unit is installed, no secret created, no port claimed in
`$YMIR_HOME/config/services.yaml` (that file does not exist yet on the Minisforum).
