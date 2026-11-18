#!/usr/bin/env bash
# install.sh: install and run one Accounted instance as rootless Quadlet units.
#
#   deploy/podman/bin/install.sh --instance <dev|staging|prod> <command>
#
# Commands:
#   render --out DIR   render the unit templates into DIR (any user; used by CI and tests)
#   install            render into the user's Quadlet dir and daemon-reload
#   start | stop       start or stop the instance's long-running units
#   status             unit states and the sockets this user listens on
#   remove [--purge --yes]
#                      uninstall the units; --purge also deletes volumes and secrets
#
# Every command but render must run as the instance user (ACCOUNTED_USER), so one
# instance's install can never write into another's.
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

QUADLET_DIR="${ACCOUNTED_QUADLET_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/containers/systemd}"
MANIFEST_NAME=".accounted-installed"

inst="" cmd="" out="" purge=0 yes=0
while [ $# -gt 0 ]; do
  case "$1" in
    --instance) inst="${2:-}"; shift ;;
    --instance=*) inst="${1#*=}" ;;
    --out) out="${2:-}"; shift ;;
    --purge) purge=1 ;;
    --yes) yes=1 ;;
    -h|--help) sed -n '2,17p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    render|install|start|stop|status|remove) cmd="$1" ;;
    *) die "unknown argument $1" ;;
  esac
  shift
done
[ -n "$inst" ] || die "--instance is required"
[ -n "$cmd" ] || die "a command is required (render, install, start, stop, status, remove)"
load_instance "$inst"

templates() { find "$ACCOUNTED_DEPLOY_DIR/quadlets" -maxdepth 1 -type f | sort; }

# service name systemd gives a Quadlet file
service_of() {
  local f; f="$(basename "$1")"
  case "$f" in
    *.container) echo "${f%.container}.service" ;;
    *.network) echo "${f%.network}-network.service" ;;
    *.volume) echo "${f%.volume}-volume.service" ;;
    *.timer|*.service) echo "$f" ;;
    *) echo "" ;;
  esac
}

# long-running units, in file order; a template marked "# accounted:on-demand" is skipped
long_running() {
  local t
  for t in $(templates); do
    case "$t" in *.container) ;; *) continue ;; esac
    grep -q '^# accounted:on-demand' "$t" && continue
    grep -q '^Type=oneshot' "$t" && continue
    service_of "$t"
  done
}

render_all() {
  local dir="$1" t
  mkdir -p "$dir"
  for t in $(templates); do render_template "$t" "$dir/$(basename "$t")"; done
}

# every socket this user owns must be on loopback (Rule 24: a door is named, or it is closed)
check_loopback() {
  local wide
  wide=$(ss -ltnpH 2>/dev/null | grep 'users:' | awk '{print $4}' \
    | grep -vE '^(127\.[0-9.]+|\[::1\]|::1):[0-9]+$' || true)
  if [ -n "$wide" ]; then
    printf 'FAIL non-loopback socket(s) owned by %s:\n%s\n' "$(id -un)" "$wide" >&2
    return 1
  fi
}

case "$cmd" in
  render)
    [ -n "$out" ] || die "render needs --out DIR"
    render_all "$out"
    note "rendered $(templates | wc -l) unit(s) for $inst into $out"
    ;;
  install)
    require_user
    mkdir -p "$QUADLET_DIR"
    stage="$(mktemp -d)"; trap 'rm -rf "$stage"' EXIT
    render_all "$stage"
    manifest="$QUADLET_DIR/$MANIFEST_NAME"
    if [ -r "$manifest" ]; then
      while IFS= read -r old; do
        [ -e "$stage/$old" ] || { rm -f "$QUADLET_DIR/$old"; note "removed stale unit $old"; }
      done < "$manifest"
    fi
    : > "$manifest.new"
    for f in "$stage"/*; do
      [ -e "$f" ] || continue
      install -m 0644 "$f" "$QUADLET_DIR/$(basename "$f")"
      basename "$f" >> "$manifest.new"
    done
    mv "$manifest.new" "$manifest"
    systemctl --user daemon-reload
    note "installed $(wc -l < "$manifest") unit(s) for $inst into $QUADLET_DIR"
    ;;
  start)
    require_user
    units=$(long_running)
    [ -n "$units" ] || { note "no long-running units yet for $inst"; check_loopback; exit 0; }
    # shellcheck disable=SC2086
    systemctl --user start $units
    check_loopback
    note "started: $(echo $units)"
    ;;
  stop)
    require_user
    units=$(long_running | tac)
    # shellcheck disable=SC2086
    [ -z "$units" ] || systemctl --user stop $units
    ;;
  status)
    require_user
    for t in $(templates); do
      s=$(service_of "$t"); [ -n "$s" ] || continue
      printf '%-36s %s\n' "$s" "$(systemctl --user is-active "$s" 2>/dev/null || true)"
    done
    printf '\nsockets owned by %s:\n' "$(id -un)"
    ss -ltnpH 2>/dev/null | grep 'users:' | awk '{print "  " $4}' || true
    check_loopback && printf 'loopback only: yes\n'
    ;;
  remove)
    require_user
    manifest="$QUADLET_DIR/$MANIFEST_NAME"
    "$0" --instance "$inst" stop || true
    if [ -r "$manifest" ]; then
      while IFS= read -r f; do rm -f "$QUADLET_DIR/$f"; done < "$manifest"
      rm -f "$manifest"
    fi
    systemctl --user daemon-reload
    if [ "$purge" = 1 ]; then
      [ "$yes" = 1 ] || die "--purge deletes the books' database and documents; add --yes after taking a backup"
      podman volume ls -q --filter label=accounted.instance="$inst" | xargs -r podman volume rm
      podman secret ls --format '{{.Name}}' | grep '^accounted-' | xargs -r podman secret rm
      note "purged volumes and secrets for $inst"
    fi
    note "removed $inst units (volumes and secrets kept unless --purge)"
    ;;
esac
