#!/usr/bin/env bash
# check.sh: the static gate for deploy/podman (Rule 07, Rule 24). Changes nothing.
#
#   deploy/podman/bin/check.sh
#
# Fails on: a user-named absolute path; SecurityLabelDisable; a PublishPort that is
# not ${ACCOUNTED_BIND_HOST}:${ACCOUNTED_*_PORT}:...; an instance whose ports fall
# outside its five-digit block; two instances whose blocks overlap; a unit template
# that does not render for every instance.
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

fail=0
bad() { printf 'FAIL %s\n' "$*"; fail=1; }

files=$(find "$ACCOUNTED_DEPLOY_DIR" -type f \( -name '*.sh' -o -name '*.env' -o -name '*.container' \
  -o -name '*.network' -o -name '*.volume' -o -name '*.timer' -o -name '*.service' -o -name 'Caddyfile*' \
  -o -name '*.manifest' \) | sort)

for f in $files; do
  if sed -E 's/(^|[[:space:]])#.*$//' "$f" | grep -qE '/home/[a-z][a-z0-9_-]+/|/Users/[A-Za-z][A-Za-z0-9_-]+/'; then
    bad "$f: absolute path naming a user (Rule 07 B)"
  fi
done

for f in $(find "$ACCOUNTED_DEPLOY_DIR/quadlets" -type f 2>/dev/null | sort); do
  grep -q '^SecurityLabelDisable' "$f" && bad "$f: SecurityLabelDisable (keep SELinux on, use :Z)"
  while IFS= read -r line; do
    [[ "$line" =~ ^PublishPort=\$\{ACCOUNTED_BIND_HOST\}:\$\{ACCOUNTED_[A-Z_]+_PORT\}:[^:]+$ ]] \
      || bad "$f: '$line' must be PublishPort=\${ACCOUNTED_BIND_HOST}:\${ACCOUNTED_*_PORT}:<internal>"
  done < <(grep '^PublishPort=' "$f" || true)
done

blocks=""
for inst in $ACCOUNTED_INSTANCES; do
  out=$(env -i PATH="$PATH" HOME="${HOME:-/nonexistent}" ACCOUNTED_HOST_CONFIG=/nonexistent bash -c '
    set -euo pipefail
    . "$1/bin/lib.sh"
    load_instance "$2"
    tmp=$(mktemp -d); trap "rm -rf $tmp" EXIT
    for t in $(find "$1/quadlets" -type f 2>/dev/null); do render_template "$t" "$tmp/$(basename "$t")"; done
    q=/usr/libexec/podman/quadlet
    if [ -x "$q" ]; then
      QUADLET_UNIT_DIRS="$tmp" "$q" -dryrun -user >/dev/null 2>"$tmp/.q" || { cat "$tmp/.q"; exit 1; }
      ! grep -qiE "^.*(error|unsupported key)" "$tmp/.q" || { grep -iE "error|unsupported" "$tmp/.q"; exit 1; }
    fi
    echo "$ACCOUNTED_PORT_BASE"' _ "$ACCOUNTED_DEPLOY_DIR" "$inst" 2>&1) || { bad "instance $inst: $out"; continue; }
  base=$(tail -1 <<<"$out")
  for other in $blocks; do
    [ $((base > other ? base - other : other - base)) -ge 8 ] || bad "instance $inst block $base overlaps block $other"
  done
  blocks="$blocks $base"
done

[ $fail = 0 ] && printf 'PASS deploy/podman: paths, ports, blocks and templates clean (%s)\n' "$ACCOUNTED_INSTANCES"
exit $fail
