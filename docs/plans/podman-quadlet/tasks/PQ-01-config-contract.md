# PQ-01: Config contract, instances, port blocks, register claim

**Depends on:** none · **Size:** S

## Goal
One place declares every tunable, with one documented default per instance (Rule 07), and the three
port blocks are claimed before anything binds (Rule 24 register law).

## Scope
- `deploy/podman/instances/{dev,staging,prod}.env`: `ACCOUNTED_INSTANCE`, `ACCOUNTED_EDGE_PORT`,
  `ACCOUNTED_STUDIO_PORT`, `ACCOUNTED_DB_ADMIN_PORT`, `ACCOUNTED_BIND_HOST=127.0.0.1`,
  `ACCOUNTED_PUBLIC_URL`, `ACCOUNTED_ROAD`, `ACCOUNTED_IMAGE`, `ACCOUNTED_BACKUP_*`, `ACCOUNTED_EGRESS_PROXY`.
  Blocks: prod 17166-17173, staging 26219-26226, dev 21230-21237 (PRD 7.1).
- `deploy/podman/internal-ports.env`: the unpublished container ports, one place (PRD 7.1, Q10).
- `deploy/podman/README.md` pointing at the PRD.
- Rows for all three blocks in `$YMIR_HOME/config/services.yaml` on the Minisforum (create if absent):
  name, class, gate, `road`; `bin/ward/services-register.sh check` exits 0.

## Acceptance
- All 24 ports free on the Minisforum (`ss -ltnH`) before first start.
- `grep -rE '/home/' deploy/podman` finds nothing; no published port outside the blocks.
- Ymir `compliance-check.sh` config gate passes on `deploy/podman/`.
