# PQ-15: Infisical as the secrets manager

> **Parked 2026-11-17 (Q8 reopened by Craig).** Concern: weight on every client deployment target
> (multi-cloud, several VPSs, local servers) and the debt is not worth the security gain at our
> size. Kept for the record; not to be built unless Q8 lands back here.

**Depends on:** PQ-03 · **Blocks:** PQ-11 (no client secret on `prod` lives only in a local generator) · **Size:** M

## Goal
A hardened, shared Infisical on Hostinger is the source of record for every Accounted instance's
secrets (PRD 7.5, Q8). Accounted never depends on it at container start.

## Scope
- `prepare-host.sh`-style printed root steps for user `infisical` + linger (Craig runs them).
- Quadlets (in this repo under `deploy/podman/infisical/` until a shared infra repo exists):
  `infisical.network` (`Internal=true`), `infisical-db` + volume, `infisical-redis`, `infisical`
  (image pinned by digest, starting from the house's `v0.159.25`; check the current release and its
  self-host notes before pinning), `PublishPort=127.0.0.1:24095:<internal>`.
- Claim 24095-24098 in the Hostinger services register; road `tailnet`; never routed on the tunnel.
- Generate `ENCRYPTION_KEY` and `AUTH_SECRET` as Podman secrets; write the offline copy procedure and
  have Craig confirm it is done before any real secret goes in.
- Project `accounted`, environments `dev` / `staging` / `prod`; one read-only machine identity per
  instance user, scoped to its environment; its credential stored as that user's Podman secret.
- `secrets-init.sh --source infisical`: pull into Podman secrets at install and upgrade; first install
  generates and pushes. Rotation = change in Infisical, then `install.sh upgrade`.
- Backup of `infisical-db` (encrypted, off-host) and a restore drill into a scratch user.
- Check which features the pinned version licenses for self-hosting (audit log retention, SSO,
  approvals) and record what we rely on.

## Acceptance
- `ss -ltn` on Hostinger: Infisical only on `127.0.0.1:24095`; reachable from the Minisforum over the tailnet.
- `accounted-staging` cannot read the `prod` environment with its identity (refused, logged).
- With Infisical stopped, `systemctl --user restart accounted-app` still succeeds.
- Restore drill brings back every secret with the offline root keys.
