#!/usr/bin/env bash
# secrets-init.sh: create an instance's Podman secrets from secrets.manifest.
#
#   deploy/podman/bin/secrets-init.sh --instance <i> [--from FILE] [--rotate NAME] [--list]
#
#   (no flags)      create every generated secret that does not exist yet; idempotent
#   --from FILE     also create "supplied" secrets from FILE (lines: <secret-name>=<value>);
#                   FILE must be mode 0600 and must not be a .env.local (that file is production)
#   --rotate NAME   replace NAME with a new value; rotating accounted-jwt-secret re-signs every jwt
#   --list          show which secrets exist and which are missing; never prints a value
#
# Runs as the instance user: secrets live in that user's rootless Podman store.
# No value is ever printed, logged, or written to disk by this script.
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

MANIFEST="$ACCOUNTED_DEPLOY_DIR/secrets.manifest"
DEMO="$ACCOUNTED_DEPLOY_DIR/demo-values.txt"

inst="" from="" rotate="" list=0
while [ $# -gt 0 ]; do
  case "$1" in
    --instance) inst="${2:-}"; shift ;;
    --instance=*) inst="${1#*=}" ;;
    --from) from="${2:-}"; shift ;;
    --rotate) rotate="${2:-}"; shift ;;
    --list) list=1 ;;
    -h|--help) sed -n '2,16p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) die "unknown argument $1" ;;
  esac
  shift
done
[ -n "$inst" ] || die "--instance is required"
load_instance "$inst"
require_user
command -v openssl >/dev/null || die "openssl is required"
command -v python3 >/dev/null || die "python3 is required (JWT signing reads the secret from stdin)"

manifest_rows() { grep -vE '^\s*(#|$)' "$MANIFEST"; }
exists() { podman secret inspect "$1" >/dev/null 2>&1; }
# podman prints the value followed by a newline; the containers get it without one, so the
# JWTs must be signed over exactly that (command substitution strips the newline)
read_secret() { local v; v="$(podman secret inspect --showsecret --format '{{.SecretData}}' "$1")"; printf '%s' "$v"; }

is_demo() {
  local v="$1"
  grep -vE '^\s*(#|$)' "$DEMO" | grep -qxF -- "$v"
}

store() { # store NAME VALUE (value on stdin of podman, never in argv)
  local name="$1" value="$2"
  is_demo "$value" && die "$name: refusing a known demo value"
  printf '%s' "$value" | podman secret create --label "accounted.instance=$ACCOUNTED_INSTANCE" "$name" - >/dev/null
}

make_jwt() { # make_jwt ROLE: HS256 JWT signed with the secret read from stdin (never argv)
  python3 -c '
import base64, hashlib, hmac, json, sys, time
role, ttl_days = sys.argv[1], int(sys.argv[2])
secret = sys.stdin.read().encode()
b64 = lambda b: base64.urlsafe_b64encode(b).rstrip(b"=").decode()
now = int(time.time())
head = b64(json.dumps({"alg": "HS256", "typ": "JWT"}, separators=(",", ":")).encode())
body = b64(json.dumps({"role": role, "iss": "supabase", "iat": now, "exp": now + ttl_days * 86400}, separators=(",", ":")).encode())
sig = b64(hmac.new(secret, f"{head}.{body}".encode(), hashlib.sha256).digest())
sys.stdout.write(f"{head}.{body}.{sig}")
' "$1" "${ACCOUNTED_JWT_TTL_DAYS:-3650}"
}

generate() { # generate NAME KIND ARG
  local name="$1" kind="$2" arg="${3:-}"
  case "$kind" in
    hex) openssl rand -hex "$arg" ;;
    jwt) exists accounted-jwt-secret || die "$name needs accounted-jwt-secret first"
         read_secret accounted-jwt-secret | make_jwt "$arg" ;;
    *) die "$name: cannot generate kind '$kind'" ;;
  esac
}

if [ "$list" = 1 ]; then
  while read -r name kind _; do
    printf '%-36s %-9s %s\n' "$name" "$kind" "$(exists "$name" && echo present || echo missing)"
  done < <(manifest_rows)
  exit 0
fi

if [ -n "$rotate" ]; then
  row=$(manifest_rows | awk -v n="$rotate" '$1 == n') || true
  [ -n "$row" ] || die "$rotate is not in $MANIFEST"
  read -r name kind arg <<<"$row"
  [ "$kind" != supplied ] || die "$rotate is supplied: rotate it with --from"
  podman secret rm "$name" >/dev/null 2>&1 || true
  store "$name" "$(generate "$name" "$kind" "$arg")"
  rotated="$name"
  if [ "$name" = accounted-jwt-secret ]; then
    while read -r n k a; do
      [ "$k" = jwt ] || continue
      podman secret rm "$n" >/dev/null 2>&1 || true
      store "$n" "$(generate "$n" "$k" "$a")"
      rotated="$rotated $n"
    done < <(manifest_rows)
  fi
  note "rotated: $rotated (values not shown). Restart the units that read them: install.sh --instance $inst stop && start"
  exit 0
fi

created=0
# generated secrets, hex before jwt so the signing secret exists first
for pass in hex jwt; do
  while read -r name kind arg; do
    [ "$kind" = "$pass" ] || continue
    exists "$name" && continue
    store "$name" "$(generate "$name" "$kind" "$arg")"
    created=$((created + 1))
  done < <(manifest_rows)
done

if [ -n "$from" ]; then
  [ -r "$from" ] || die "cannot read $from"
  case "$from" in *.env.local) die "refusing $from: .env.local points at production (CLAUDE.md)" ;; esac
  mode=$(stat -c '%a' "$from" 2>/dev/null || stat -f '%Lp' "$from")
  [ "$mode" = 600 ] || die "$from is mode $mode; secrets at rest are 0600 (Rule 24)"
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in ''|'#'*) continue ;; esac
    key="${line%%=*}" value="${line#*=}"
    kind=$(manifest_rows | awk -v n="$key" '$1 == n {print $2}')
    [ "$kind" = supplied ] || die "$from: '$key' is not a supplied secret in $MANIFEST"
    [ -n "$value" ] || die "$from: '$key' is empty"
    podman secret rm "$key" >/dev/null 2>&1 || true
    store "$key" "$value"
    created=$((created + 1))
  done < "$from"
fi

note "secrets for $inst: $created created; run --list to see what is present (values are never shown)"
