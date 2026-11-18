# Tasks: Accounted on Podman Quadlet with self-hosted Supabase

Vertical slices in dependency order. PRD: [`../PRD.md`](../PRD.md) (revision 2).
Every task inherits the CLAUDE.md Definition of Done and the house rules (Rule 07 ports/paths, Rule 24 doors and roads).
Every task is proven on the `dev` instance (Minisforum) before it touches `staging` or `prod` (Hostinger).

| ID | Task | Depends on | Size | Status |
|---|---|---|---|---|
| [PQ-01](PQ-01-config-contract.md) | Config contract, instances, port blocks, register claim | none | S | **done** 2026-11-17 |
| [PQ-02](PQ-02-instance-users-installer.md) | Instance users and installer skeleton | PQ-01 | S | **code done**; waits on Craig creating `accounted-dev` |
| [PQ-03](PQ-03-secrets.md) | Podman secrets, every upstream demo key replaced | PQ-02 | S | **code done**; real-store run waits on `accounted-dev` |
| [PQ-04](PQ-04-supabase-stack.md) | Trimmed upstream Supabase stack as Quadlets, `upstream.lock`, drift check | PQ-03 | L | **started**: release pinned (v0.8.4) |
| [PQ-05](PQ-05-postgres-17.md) | Postgres 17 compatibility: full replay and pg-real on the 17 image | PQ-04 | M | todo |
| [PQ-06](PQ-06-migrate.md) | `accounted-migrate`: `bootstrap.sql` once, then `supabase db push` | PQ-04 | S | todo |
| [PQ-07](PQ-07-app-cron.md) | App and cron units | PQ-06 | M | todo |
| [PQ-08](PQ-08-edge-single-origin.md) | Edge Caddy: one door, single-origin API, collision test | PQ-07 | S | todo |
| [PQ-09](PQ-09-dev-parity.md) | `dev` parity walk-through | PQ-05, PQ-08 | L | todo |
| [PQ-10](PQ-10-backup-restore.md) | Backups via `scripts/self-host/`, restore drill | PQ-09 | M | todo |
| [PQ-11](PQ-11-hostinger.md) | Hostinger `staging` then `prod` behind the tunnel + Cloudflare Access | PQ-10, PQ-15, Reygan DPA | M | todo |
| [PQ-12](PQ-12-books-seat.md) | Books seat: peers through the door, scoped MCP key, egress door | PQ-09 | M | todo |
| [PQ-13](PQ-13-agents-seat.md) | Our agents: per-agent keys over MCP through Bastion | PQ-12, Bastion release | M | blocked |
| [PQ-14](PQ-14-docs-and-gates.md) | `docs/PODMAN.md`, CI quadlet lint, ward and config gates | starts PQ-04, ends PQ-11 | S | todo |
| [PQ-15](PQ-15-infisical.md) | Infisical on Hostinger as the secrets source of record | PQ-03 | M | **parked** (Q8 reopened) |

**Milestones.** M1 `dev` runs the stack and the app: PQ-01..08. M2 `dev` proven: PQ-09, 10 (+ PQ-05).
M3 live on Hostinger: PQ-11 (`prod` carries Reygan's books). M4 Atlas and agents: PQ-12, 13. PQ-14 rides along.
