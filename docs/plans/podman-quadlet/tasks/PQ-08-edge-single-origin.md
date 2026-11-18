# PQ-08: Edge Caddy, one door, single origin

**Depends on:** PQ-07 · **Size:** S

## Scope
- `deploy/podman/edge/Caddyfile` with env placeholders only: `/auth/v1/*`, `/rest/v1/*`, `/storage/v1/*`,
  `/realtime/v1/*` (websocket) to the gateway; everything else to the app; `X-Forwarded-Proto` for the tunnel.
- `accounted-edge.container`: `PublishPort=${ACCOUNTED_BIND_HOST}:${ACCOUNTED_EDGE_PORT}:<internal>`.
- Unit test in `scripts/__tests__/` that fails if `src/app` gains a route under `auth/v1`, `rest`,
  `storage` or `realtime`.

## Acceptance
- `ss -ltnH` shows `127.0.0.1:21230` and no other Accounted socket for `dev`.
- In a browser on the Minisforum: register, log in, upload a file, see a realtime update.
- Collision test passes on main, fails with a dummy `src/app/rest/page.tsx`.
