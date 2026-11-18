# PQ-03: Podman secrets, demo keys replaced

**Depends on:** PQ-02 · **Size:** S

## Scope
- `deploy/podman/bin/secrets-init.sh [--from <0600 file>] [--rotate <name>]`, run as the instance user.
- Generated: JWT secret (>= 32 bytes), `anon` and `service_role` JWTs signed with it, Postgres password,
  `CRON_SECRET`, Realtime `SECRET_KEY_BASE`, Studio/dashboard credentials, any other secret the pinned
  upstream `.env.example` lists.
- Supplied once from a 0600 file: SMTP, Google OAuth, AI endpoint key. Refuses non-0600 files and any
  path ending in `.env.local`.
- Units consume with `Secret=<name>,type=env,target=<VAR>`.
- `install.sh start` refuses if any secret equals a value from upstream's `.env.example` (demo keys).

## Acceptance
- `podman secret ls` shows the set; `podman inspect` of any unit shows no secret in `Env`.
- `git grep -nE 'eyJ|sk_live|BEGIN (RSA|OPENSSH)' deploy/` finds nothing.
- `--rotate accounted-cron-secret` + restart keeps cron working.
