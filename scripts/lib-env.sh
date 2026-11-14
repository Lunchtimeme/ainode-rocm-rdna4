#!/usr/bin/env bash
# ==============================================================================
# lib-env.sh - shared helpers for the scripts in this directory
# ==============================================================================
# Sourced, not executed. Keeps .env parsing and preflight checks in one place so
# the scripts agree on what "the configuration" is.
# ==============================================================================

ainode_repo_root() {
    local here
    here=$(cd -- "$(dirname -- "${BASH_SOURCE[1]:-${BASH_SOURCE[0]}}")" && pwd)
    if [ -f "$here/../compose.yml" ]; then dirname -- "$here"; else pwd; fi
}

# Load .env without eval: KEY=VALUE, optional surrounding quotes. Values already
# present in the environment win, matching `docker compose` precedence.
ainode_load_env() {
    local file=${1:-.env} key val
    [ -f "$file" ] || return 0
    set -a
    while IFS='=' read -r key val || [ -n "$key" ]; do
        case $key in ''|'#'*) continue ;; esac
        key=${key//[[:space:]]/}
        [ -n "${!key+x}" ] && continue
        case $val in
            \"*\") val=${val#\"}; val=${val%\"} ;;
            \'*\') val=${val#\'}; val=${val%\'} ;;
        esac
        export "$key=$val"
    done < "$file"
    set +a
}

# ainode_require_cmd <command> <why> [package hint]
ainode_require_cmd() {
    local cmd=$1 why=$2 hint=${3:-}
    if ! command -v "$cmd" >/dev/null 2>&1; then
        {
            echo "error: '$cmd' is required but not installed."
            echo "       $why"
            [ -n "$hint" ] && echo "       install it with: $hint"
        } >&2
        return 1
    fi
}

# Profiles enabled in the current configuration, as a ",a,b," string for matching.
ainode_profiles() { printf ',%s,' "${COMPOSE_PROFILES:-}"; }

ainode_has_profile() {
    case $(ainode_profiles) in *",$1,"*) return 0 ;; esac
    return 1
}

# Container engine: docker by default, override with AINODE_DOCKER=podman.
AINODE_DOCKER=${AINODE_DOCKER:-docker}
