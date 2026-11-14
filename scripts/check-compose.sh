#!/usr/bin/env bash
# ==============================================================================
# check-compose.sh - regression test for compose.yml
# ==============================================================================
# `docker compose config` renders the file exactly as compose will see it: every
# ${VAR} resolved, profiles applied, defaults filled in. Diffing that against a
# checked-in golden file catches the mistakes that are otherwise invisible until
# a container refuses to start: a renamed variable, a lost default, a service
# that quietly moved behind a profile, a port that changed.
#
# The comparison is done on a canonicalised form (scripts/canonicalize-compose.py):
# sorted keys, version-specific cosmetic fields removed, paths normalised to
# <repo>, secrets redacted. Without that, the test fails whenever the compose
# version differs between machines - which is exactly what happened when it was
# first run in GitHub Actions.
#
# The golden file is generated with tests/compose.test.env, not your .env, so the
# result does not depend on this machine's configuration.
#
# Usage:
#   scripts/check-compose.sh            compare, exit 1 on drift
#   scripts/check-compose.sh --update   rewrite tests/compose.golden.json
#
# Run it after editing compose.yml, and in CI.
# ==============================================================================
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
ROOT=$(dirname -- "$SCRIPT_DIR")
. "$SCRIPT_DIR/lib-env.sh"
TEST_ENV="$ROOT/tests/compose.test.env"
GOLDEN="$ROOT/tests/compose.golden.json"

UPDATE=0
case ${1:-} in
    --update) UPDATE=1 ;;
    -h|--help) sed -n '2,26p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    "") ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
esac

ainode_require_cmd docker "compose config is the renderer under test" "pacman -S docker docker-compose" || exit 1
ainode_require_cmd python3 "the rendered config is canonicalised before the diff" "pacman -S python" || exit 1

# Render with a clean environment. `env -i` matters: any AINODE_* or COMPOSE_*
# exported in the user's shell outranks --env-file, so a leftover variable would
# make this test pass or fail for reasons that have nothing to do with the file
# under test. compose config needs no daemon, only the CLI.
render() {
    env -i PATH="$PATH" HOME="${HOME:-/tmp}" \
        docker compose --project-directory "$ROOT" \
            -f "$ROOT/compose.yml" --env-file "$TEST_ENV" config --format json \
    | python3 "$SCRIPT_DIR/canonicalize-compose.py" "$ROOT"
}

tmp=$(mktemp)
trap 'rm -f "$tmp"' EXIT
render > "$tmp"

if [ "$UPDATE" = 1 ]; then
    cp "$tmp" "$GOLDEN"
    echo "golden updated: $GOLDEN" >&2
    exit 0
fi

[ -f "$GOLDEN" ] || { echo "no $GOLDEN; run with --update once" >&2; exit 1; }

# --- revision pins ---------------------------------------------------------
# The same default lives in compose.yml (so .env can override it) and in the
# Dockerfile ARG (so a bare `docker build` still works). Guard against the two
# drifting apart, which would silently build a different revision than the one
# the repository documents.
pin_drift=0
# check_pin <build-arg key> <env variable> <Dockerfile>
check_pin() {
    local key=$1 var=$2 file=$3 c d
    c=$(grep -F "${key}: \${${var}:-" "$ROOT/compose.yml" | head -1 || true)
    [ -n "$c" ] || return 0
    c=${c#*:-}; c=${c%%\}*}
    d=$(grep -oE "^ARG ${key}=[^ ]+" "$file" | head -1 || true)
    [ -n "$d" ] || return 0
    d=${d#*=}
    if [ "$c" != "$d" ]; then
        echo "pin drift: ${var} resolves to '$c' in compose.yml but the image default is '$d' (${file#"$ROOT"/})" >&2
        pin_drift=1
    fi
}
check_pin AINODE_OWUI_REF   AINODE_OWUI_REF   "$ROOT/docker/openwebui/Dockerfile"
check_pin AINODE_KOKORO_REF AINODE_KOKORO_REF "$ROOT/docker/kokoro-fastapi/Dockerfile"
check_pin COMFYUI_REF       AINODE_COMFYUI_REF "$ROOT/docker/comfyui/Dockerfile"
[ "$pin_drift" = 0 ] || exit 1

if diff -u "$GOLDEN" "$tmp" > /tmp/ainode-compose-diff.$$ 2>&1; then
    echo "compose.yml matches the golden config (pins consistent)" >&2
    rm -f /tmp/ainode-compose-diff.$$
    exit 0
fi

cat >&2 <<EOF
compose.yml has drifted from $GOLDEN

Every line below is a resolved difference, so it is what compose would actually
run. If the change is intentional, review it and run:
  scripts/check-compose.sh --update

EOF
sed 's/^/  /' /tmp/ainode-compose-diff.$$ >&2
rm -f /tmp/ainode-compose-diff.$$
exit 1
