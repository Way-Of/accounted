# PQ-14: Docs and gates

**Depends on:** starts with PQ-04, finishes with PQ-11 · **Size:** S

## Scope
- `docs/PODMAN.md` next to `docs/DOCKER.md`: instances, users, install, ports, roads, secrets,
  Supabase release bumps, backup; link from `docs/SELF-HOSTING.md` "Fully Self-Hosted".
- CI job: render units for all three instances and run `quadlet -dryrun`; fail on `/home/`, a published
  port outside the blocks, a `PublishPort` not bound to `ACCOUNTED_BIND_HOST`, or `SecurityLabelDisable`.
- `DECISIONS.md` lines as decisions land (PG 17 result, gateway choice, Q10).
- Update `/HANDOFF.md` at the end of every working session.

## Acceptance
- CI job green on the branch, red on a deliberately broken unit.
