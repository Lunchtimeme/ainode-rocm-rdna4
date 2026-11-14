#!/usr/bin/env bash
# ==============================================================================
# build-base.sh - build ainode-base:python313 with the configured host UID/GID
# ==============================================================================
# The base image creates the container user (uid AINODE_USER_UID) that every
# Python-based service runs as. Building it with a bare `docker build` always
# produced uid 1000, so on a machine whose user is not 1000 the bind-mounted
# data directories ended up written by a stranger.
#
# Usage:
#   scripts/build-base.sh            build ./docker/base
#   scripts/build-base.sh --check    print what would be built, build nothing
#
# Requires BuildKit (the docker-buildx package on Arch) because the Dockerfiles
# in this stack use cache mounts.
# ==============================================================================
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
ROOT=$(dirname -- "$SCRIPT_DIR")
. "$SCRIPT_DIR/lib-env.sh"

MODE=build
case ${1:-} in
    --check) MODE=check ;;
    -h|--help) sed -n '2,18p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    "") ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
esac

ainode_load_env "$ROOT/.env"

UID_ARG=${AINODE_USER_UID:-1000}
GID_ARG=${AINODE_USER_GID:-100}
IMAGE=${AINODE_BASE_IMAGE:-ainode-base:python313}

cat <<EOF
base image : $IMAGE
USER_UID   : $UID_ARG   (id -u on this machine: $(id -u))
USER_GID   : $GID_ARG   (container-internal "users" group, not a host group)
context    : $ROOT/docker/base
EOF

if [ "$UID_ARG" != "$(id -u)" ]; then
    echo "note: AINODE_USER_UID differs from your own uid; files in data/ will be" >&2
    echo "      owned by $UID_ARG inside the containers. That is intended if you" >&2
    echo "      set it deliberately." >&2
fi

[ "$MODE" = build ] || exit 0

if ! "$AINODE_DOCKER" buildx version >/dev/null 2>&1; then
    echo "error: docker buildx is not available; the Dockerfiles use cache mounts." >&2
    echo "       install it with: pacman -S docker-buildx  (or apt install docker-buildx-plugin)" >&2
    exit 1
fi

exec "$AINODE_DOCKER" build \
    --build-arg "USER_UID=$UID_ARG" \
    --build-arg "USER_GID=$GID_ARG" \
    -t "$IMAGE" \
    --progress=plain \
    "$ROOT/docker/base"
