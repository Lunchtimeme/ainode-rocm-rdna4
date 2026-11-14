#!/usr/bin/env bash
# ==============================================================================
# set-comfyui-password.sh - write the ComfyUI basic-auth file
# ==============================================================================
# ComfyUI is the only service behind HTTP basic auth. Its credential is an
# apr1 hash of the form $apr1$salt$hash, which CANNOT live in .env: compose
# applies ${} interpolation to unquoted and double-quoted values, and every
# '$' in the hash is read as a (missing) variable, collapsing the value.
# So the hash stays a file: data/reverseproxy/htpasswd/.htpasswd (gitignored).
#
# Usage:
#   scripts/set-comfyui-password.sh                 prompt for user and password
#   scripts/set-comfyui-password.sh --user alice    prompt for password only
#   printf '%s' "$PW" | scripts/set-comfyui-password.sh --user alice --stdin
# ==============================================================================
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
ROOT=$(dirname -- "$SCRIPT_DIR")
HTPASSWD=${AINODE_HTPASSWD:-$ROOT/data/reverseproxy/htpasswd/.htpasswd}

USER_NAME=comfyui
FROM_STDIN=0
while [ $# -gt 0 ]; do
    case $1 in
        --user) USER_NAME=${2:?--user needs a value}; shift 2 ;;
        --stdin) FROM_STDIN=1; shift ;;
        -h|--help) sed -n '2,20p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "unknown argument: $1" >&2; exit 2 ;;
    esac
done

if [ "$FROM_STDIN" = 1 ]; then
    IFS= read -r PW
else
    printf 'Password for %s: ' "$USER_NAME" >&2
    IFS= read -rs PW
    printf '\nRepeat: ' >&2
    IFS= read -rs PW2
    printf '\n' >&2
    [ "$PW" = "$PW2" ] || { echo "passwords do not match" >&2; exit 1; }
fi

[ -n "$PW" ] || { echo "empty password refused" >&2; exit 1; }

mkdir -p "$(dirname "$HTPASSWD")"
umask 077
# apr1 keeps this readable by nginx on Arch (openssl passwd -apr1 == htpasswd -m)
HASH=$(printf '%s\n' "$PW" | openssl passwd -apr1 -stdin)
printf '%s:%s\n' "$USER_NAME" "$HASH" > "$HTPASSWD"
chmod 644 "$HTPASSWD"   # the container's nginx runs as root; the *file* is
                        # only as secret as the directory it lives in
echo "wrote $HTPASSWD for user $USER_NAME" >&2
echo "reload the proxy to apply: scripts/render-config.sh --reload" >&2
