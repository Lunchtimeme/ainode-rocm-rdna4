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
# The golden file is generated with tests/compose.test.env, not your .env, and
# with the repository path normalised to <repo>, so the test is reproducible on
# any machine and in CI.
#
# Usage:
#   scripts/check-compose.sh            compare, exit 1 on drift
#   scripts/check-compose.sh --update   rewrite tests/compose.golden.yml
#
# Run it after editing compose.yml, and in CI.
# ==============================================================================
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
ROOT=$(dirname -- "$SCRIPT_DIR")
. "$SCRIPT_DIR/lib-env.sh"
TEST_ENV="$ROOT/tests/compose.test.env"
GOLDEN="$ROOT/tests/compose.golden.yml"

UPDATE=0
case ${1:-} in
    --update) UPDATE=1 ;;
    -h|--help) sed -n '2,24p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    "") ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
esac

ainode_require_cmd docker "compose config is the renderer under test" "pacman -S docker docker-compose" || exit 1

# Render with a fixed environment: no inherited COMPOSE_*, no user .env.
render() {
    env -u COMPOSE_FILE -u COMPOSE_PROJECT_NAME -u COMPOSE_PROFILES \
        -u AINODE_PREFIX -u AINODE_LAN_DOMAIN -u CRAWL4AI_API_TOKEN \
        -u SEARXNG_SECRET -u STRATA_API_KEY \
        docker compose --project-directory "$ROOT" \
            -f "$ROOT/compose.yml" --env-file "$TEST_ENV" config \
    | sed -e "s#$ROOT#<repo>#g" \
          -e 's/\(CRAWL4AI_API_TOKEN: \).*/\1<redacted>/' \
          -e 's/\(SEARXNG_SECRET: \).*/\1<redacted>/' \
          -e 's/\(STRATA_API_KEY: \).*/\1<redacted>/' \
          -e 's/\(API_KEY: \)test-strata-key-not-a-secret/\1<redacted>/'
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

if diff -u "$GOLDEN" "$tmp" > /tmp/ainode-compose-diff.$$ 2>&1; then
    echo "compose.yml matches the golden config" >&2
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
