# PQ-12: Books seat

**Depends on:** PQ-09 · **Size:** M

## Goal
Accounted takes the books seat from `atlas-vault/docs/41-hosted-topology.md`: reachable by Atlas Desk
and receipt-hunter through its door, reaching nothing directly.

## Scope
- Peers (other Linux users) call the instance edge over host loopback (`host.containers.internal` with
  pasta); document the exact address per host. No shared Podman network (PRD 6, Q7).
- Mint a `gnubok_sk_` key for receipt-hunter, read + stage scopes only, stored in its own secret store.
- Egress: `HTTPS_PROXY`/`NO_PROXY` on app and auth; a forward proxy with a destination allowlist
  (Skatteverket, bank providers, SMTP, Google OAuth, the AI endpoint, listed from code) until Bastion
  has a release.

## Acceptance
- A stand-in MCP client in another user's container stages an entry with the key; gateway, database
  and Studio are unreachable from it.
- With the proxy stopped, outbound calls fail closed and the app says so.
