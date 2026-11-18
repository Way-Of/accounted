#!/usr/bin/env bash
# prepare-host.sh: PRINTS the root steps that create an instance's Linux user.
# It runs nothing as root: a change that can lock the operator out is his (Rule 24).
#
#   deploy/podman/bin/prepare-host.sh --instance dev|staging|prod
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

inst=""
while [ $# -gt 0 ]; do
  case "$1" in
    --instance) inst="${2:-}"; shift ;;
    --instance=*) inst="${1#*=}" ;;
    -h|--help) sed -n '2,6p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) die "unknown argument $1" ;;
  esac
  shift
done
[ -n "$inst" ] || die "--instance is required"
load_instance "$inst"
u="$ACCOUNTED_USER"

# next free 65536-id range after every range already handed out
next_subid() {
  local f="$1" max=100000 start count
  [ -r "$f" ] || { echo 100000; return; }
  while IFS=: read -r _ start count; do
    [ -n "$start" ] && [ $((start + count)) -gt "$max" ] && max=$((start + count))
  done < "$f"
  echo "$max"
}
a=$(next_subid /etc/subuid); b=$(next_subid /etc/subgid)
sub_start=$(( a > b ? a : b )); sub_end=$((sub_start + 65535))

podman_v=$(podman --version 2>/dev/null | awk '{print $3}' || true)
note "host check: podman ${podman_v:-MISSING} (need 5.x for Quadlet), user $u $(id "$u" >/dev/null 2>&1 && echo exists || echo 'does not exist yet')"

cat <<STEPS
# --- run as root on this host -------------------------------------------------
# 1. the instance user (no password login; reach it with: sudo -iu $u)
useradd --create-home --shell /bin/bash $u
passwd --lock $u
# 2. subordinate ids for rootless Podman (skip if 'grep $u /etc/subuid' already shows a range)
usermod --add-subuids $sub_start-$sub_end --add-subgids $sub_start-$sub_end $u
# 3. keep its user systemd running without a login session
loginctl enable-linger $u
# 4. check
loginctl show-user $u -p Linger      # Linger=yes
grep "^$u:" /etc/subuid /etc/subgid
# --- revert -------------------------------------------------------------------
# loginctl disable-linger $u && userdel --remove $u
# (removes the instance's containers, volumes and secrets: back up first)
STEPS
note "subuid range $sub_start-$sub_end is the first range free in both /etc/subuid and /etc/subgid on this host right now."
