# Accounted on Podman Quadlet

Rootless Podman Quadlet deployment of Accounted with its own self-hosted Supabase stack.
Plan, reasoning and diagrams: [`docs/plans/podman-quadlet/`](../../docs/plans/podman-quadlet/PRD.md).

| Path | What |
|---|---|
| `instances/<dev\|staging\|prod>.env` | non-secret defaults per instance: user, port block, road, URLs |
| `internal-ports.env` | ports inside `accounted.network`; never published |
| `quadlets/` | unit templates; `${ACCOUNTED_*}` tokens are filled in by `install.sh` |
| `secrets.manifest` | every Podman secret an instance needs and how it is made |
| `bin/prepare-host.sh` | prints the root steps for a new instance user (Craig runs them) |
| `bin/install.sh` | render, install, start, stop, status, remove; run as the instance user |
| `bin/secrets-init.sh` | creates the Podman secrets from the manifest |
| `bin/check.sh` | static gate: paths, ports, blocks, templates |

## Instances

| Instance | Host | User | Port block | Road |
|---|---|---|---|---|
| `dev` | Minisforum | `accounted-dev` | 21230-21237 | none (tailnet opt-in) |
| `staging` | Hostinger | `accounted-staging` | 26219-26226 | tunnel + Cloudflare Access |
| `prod` | Hostinger | `accounted-prod` | 17166-17173 | tunnel + Cloudflare Access |

Block offsets: `+0` edge (the only always-published port, `127.0.0.1`), `+1` Studio and `+2` database
admin (loopback, on demand), `+3..+7` reserved.

## Config precedence

Process environment, then `${XDG_CONFIG_HOME:-~/.config}/accounted/instance.env` on the host, then
`instances/<name>.env`. Only `ACCOUNTED_*` keys are read. Secrets never go in any of these files.

## First install of an instance

```bash
deploy/podman/bin/prepare-host.sh --instance dev      # prints root steps; run them as root
sudo -iu accounted-dev                                 # then, as the instance user:
git clone <repo> ~/accounted && cd ~/accounted
deploy/podman/bin/secrets-init.sh --instance dev
deploy/podman/bin/install.sh --instance dev install
deploy/podman/bin/install.sh --instance dev start
```
