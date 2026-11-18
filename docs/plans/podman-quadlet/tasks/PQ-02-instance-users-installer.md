# PQ-02: Instance users and installer skeleton

**Depends on:** PQ-01 · **Size:** S

## Goal
The same command installs an instance on either host, as that instance's own Linux user.

## Scope
- `deploy/podman/bin/prepare-host.sh --instance <i>`: prints (does not run) the root steps with revert
  lines: `useradd accounted-<i>`, `loginctl enable-linger`, subuid/subgid check, Podman version check.
  Craig runs them (Rule 24).
- `deploy/podman/bin/install.sh --instance <i> [--road ...]`: refuses to run as any user but
  `accounted-<i>`; renders units from `deploy/podman/quadlets/` with the instance env into
  `~/.config/containers/systemd/`; `daemon-reload`; subcommands `start`, `stop`, `status`, `upgrade`,
  `remove [--purge]` (volumes and backups kept unless `--purge`).
- After start: fail if any socket owned by the user listens on a non-loopback address.

## Acceptance
- On the Minisforum, `accounted-dev` exists with linger; `install.sh --instance dev status` runs clean
  with zero units.
- Running `install.sh --instance prod` as `accounted-dev` is refused.
