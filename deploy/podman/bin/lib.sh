#!/usr/bin/env bash
# Shared helpers for the Accounted Podman Quadlet scripts. Sourced, never run.
#
# Config precedence (Rule 07): a variable already set in the process environment
# wins, then the host override file, then the instance defaults in the repo.

ACCOUNTED_DEPLOY_DIR="${ACCOUNTED_DEPLOY_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
ACCOUNTED_HOST_CONFIG="${ACCOUNTED_HOST_CONFIG:-${XDG_CONFIG_HOME:-$HOME/.config}/accounted/instance.env}"
ACCOUNTED_INSTANCES="dev staging prod"

die() { printf 'error: %s\n' "$*" >&2; exit 1; }
note() { printf '%s\n' "$*" >&2; }

# load_env_file FILE: export KEY=VALUE lines whose KEY is not already set.
# Only ACCOUNTED_* keys are accepted, so an env file cannot redefine PATH or HOME.
load_env_file() {
  local file="$1" line key value
  [ -r "$file" ] || return 0
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in ''|'#'*) continue ;; esac
    key="${line%%=*}"
    value="${line#*=}"
    [[ "$key" =~ ^ACCOUNTED_[A-Z0-9_]+$ ]] || die "$file: refusing key '$key' (only ACCOUNTED_* keys)"
    if [ -z "${!key+x}" ]; then
      export "$key=$value"
    fi
  done < "$file"
}

# load_instance NAME: resolve the full config for one instance.
load_instance() {
  local name="$1"
  case " $ACCOUNTED_INSTANCES " in *" $name "*) ;; *) die "unknown instance '$name' (one of: $ACCOUNTED_INSTANCES)" ;; esac
  local defaults="$ACCOUNTED_DEPLOY_DIR/instances/$name.env"
  [ -r "$defaults" ] || die "missing $defaults"
  load_env_file "$ACCOUNTED_HOST_CONFIG"
  load_env_file "$ACCOUNTED_DEPLOY_DIR/internal-ports.env"
  load_env_file "$defaults"
  [ "${ACCOUNTED_INSTANCE:-}" = "$name" ] || die "instance mismatch: ACCOUNTED_INSTANCE=${ACCOUNTED_INSTANCE:-} but asked for $name (check $ACCOUNTED_HOST_CONFIG)"
  validate_ports
}

# validate_ports: every published port is five digits inside 10000-32767 and inside
# this instance's block of eight (Rule 07 C).
validate_ports() {
  local base="${ACCOUNTED_PORT_BASE:?ACCOUNTED_PORT_BASE is not set}" var port
  for var in ACCOUNTED_EDGE_PORT ACCOUNTED_STUDIO_PORT ACCOUNTED_DB_ADMIN_PORT; do
    port="${!var:?$var is not set}"
    [[ "$port" =~ ^[0-9]{5}$ ]] || die "$var=$port is not a five-digit port"
    [ "$port" -ge 10000 ] && [ "$port" -le 32767 ] || die "$var=$port is outside 10000-32767"
    [ "$port" -ge "$base" ] && [ "$port" -le $((base + 7)) ] || die "$var=$port is outside the instance block $base-$((base + 7))"
  done
  case "${ACCOUNTED_BIND_HOST:-}" in
    127.0.0.1|::1) ;;
    *) die "ACCOUNTED_BIND_HOST=${ACCOUNTED_BIND_HOST:-} is not loopback; a wide bind needs a named door (Rule 24), not a config value" ;;
  esac
}

# render_template SRC DST: substitute ${ACCOUNTED_*} tokens; refuse leftovers.
render_template() {
  local src="$1" dst="$2" content var
  content="$(cat "$src")"
  for var in $(compgen -v ACCOUNTED_); do
    content="${content//\$\{$var\}/${!var}}"
  done
  if grep -qE '\$\{ACCOUNTED_[A-Z0-9_]+\}' <<<"$content"; then
    die "$src: unresolved $(grep -oE '\$\{ACCOUNTED_[A-Z0-9_]+\}' <<<"$content" | sort -u | tr '\n' ' ')"
  fi
  printf '%s\n' "$content" > "$dst"
}

# require_user: the command runs as the instance's own Linux user, or not at all.
require_user() {
  local me; me="$(id -un)"
  [ "$me" = "${ACCOUNTED_USER:?}" ] || die "run as $ACCOUNTED_USER (you are $me): one instance per user keeps staging out of prod"
}
