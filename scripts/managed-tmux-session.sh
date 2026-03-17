#!/usr/bin/env bash

set -euo pipefail

managed_tmux_schema_version() {
    printf '1'
}

managed_tmux_prepare_terminal_term() {
    local current_term="${TERM:-}"
    case "$current_term" in
        ""|dumb|linux|unknown)
            export TERM="${I3PM_TERM_OVERRIDE:-xterm-256color}"
            ;;
    esac
}

managed_tmux_expected_server_key() {
    printf '%s' "${I3PM_TMUX_SERVER_KEY:-$(managed_tmux_current_socket)}"
}

managed_tmux_session_option() {
    local session_name="$1"
    local option_name="$2"
    managed_tmux show-options -t "$session_name" -qv "$option_name" 2>/dev/null || true
}

managed_tmux_session_exists() {
    local session_name="$1"
    managed_tmux has-session -t "$session_name" 2>/dev/null
}

managed_tmux_quarantine_name() {
    local session_name="$1"
    local reason="${2:-stale}"
    local timestamp sanitized_reason
    timestamp="$(date +%s)"
    sanitized_reason="$(printf '%s' "$reason" | tr ':/' '--' | sed 's/[^a-zA-Z0-9_.-]/-/g; s/-\{2,\}/-/g; s/^-//; s/-$//')"
    if [[ -z "$sanitized_reason" ]]; then
        sanitized_reason="stale"
    fi
    printf 'orphan-%s-%s-%s' "${session_name:0:20}" "${sanitized_reason:0:24}" "$timestamp"
}

managed_tmux_quarantine_session() {
    local session_name="$1"
    local reason="${2:-stale}"
    local quarantine_name
    quarantine_name="$(managed_tmux_quarantine_name "$session_name" "$reason")"
    managed_tmux rename-session -t "$session_name" "$quarantine_name" >/dev/null
    printf '%s' "$quarantine_name"
}

managed_tmux_is_managed_session() {
    local session_name="$1"
    [[ "$(managed_tmux_session_option "$session_name" "@i3pm_managed")" == "1" ]]
}

managed_tmux_validate_metadata() {
    local session_name="$1"
    local existing_managed existing_context existing_role existing_server_key existing_schema
    existing_managed="$(managed_tmux_session_option "$session_name" "@i3pm_managed")"
    existing_context="$(managed_tmux_session_option "$session_name" "@i3pm_context_key")"
    existing_role="$(managed_tmux_session_option "$session_name" "@i3pm_terminal_role")"
    existing_server_key="$(managed_tmux_session_option "$session_name" "@i3pm_tmux_server_key")"
    existing_schema="$(managed_tmux_session_option "$session_name" "@i3pm_schema_version")"

    if [[ "$existing_managed" != "1" ]]; then
        echo "managed-tmux: refusing to attach unmanaged tmux session '$session_name'" >&2
        exit 1
    fi

    if [[ "$existing_context" != "${I3PM_CONTEXT_KEY}" ]]; then
        echo "managed-tmux: refusing to attach stale tmux session '$session_name' (context='$existing_context'; expected context='${I3PM_CONTEXT_KEY}')" >&2
        exit 1
    fi

    if [[ -n "${I3PM_TERMINAL_ROLE:-}" && -n "$existing_role" && "$existing_role" != "${I3PM_TERMINAL_ROLE}" ]]; then
        echo "managed-tmux: refusing to attach mismatched terminal role for '$session_name' (role='$existing_role'; expected='${I3PM_TERMINAL_ROLE}')" >&2
        exit 1
    fi

    if [[ -n "$existing_server_key" && "$existing_server_key" != "$(managed_tmux_expected_server_key)" ]]; then
        echo "managed-tmux: refusing to attach mismatched tmux server for '$session_name' (server='$existing_server_key'; expected='$(managed_tmux_expected_server_key)')" >&2
        exit 1
    fi

    if [[ -n "$existing_schema" && "$existing_schema" != "$(managed_tmux_schema_version)" ]]; then
        echo "managed-tmux: refusing to attach incompatible managed session '$session_name' (schema='$existing_schema'; expected='$(managed_tmux_schema_version)')" >&2
        exit 1
    fi
}

managed_tmux_require_context() {
    if ! command -v tmux >/dev/null 2>&1; then
        echo "managed-tmux: tmux is required but not installed" >&2
        exit 1
    fi

    if [[ -z "${I3PM_CONTEXT_KEY:-}" || -z "${I3PM_TERMINAL_ANCHOR_ID:-}" ]]; then
        echo "managed-tmux: missing I3PM terminal context; refusing unmanaged tmux launch" >&2
        exit 1
    fi
}

managed_tmux_session_name() {
    local project_name="${1:-project}"
    local anchor_id="${2:-}"
    local slug digest
    slug="$(printf '%s' "$project_name" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9_-]/-/g; s/-\\{2,\\}/-/g; s/^-//; s/-$//')"
    if [[ -z "$slug" ]]; then
        slug="project"
    fi
    digest="$(printf '%s' "$anchor_id" | sha1sum | awk '{print $1}' | cut -c1-8)"
    printf 'i3pm-%s-%s' "${slug:0:24}" "$digest"
}

managed_tmux_runtime_dir() {
    local uid
    uid="$(id -u)"
    printf '%s' "${XDG_RUNTIME_DIR:-/run/user/$uid}"
}

managed_tmux_canonical_socket() {
    local uid runtime_dir
    uid="$(id -u)"
    runtime_dir="$(managed_tmux_runtime_dir)"
    printf '%s/tmux-%s/default' "$runtime_dir" "$uid"
}

managed_tmux_current_socket() {
    managed_tmux_canonical_socket
}

managed_tmux_ensure_socket_parent() {
    mkdir -p "$(dirname "$(managed_tmux_current_socket)")"
}

managed_tmux() {
    command tmux -S "$(managed_tmux_current_socket)" "$@"
}

managed_tmux_refresh_server_metadata() {
    local session_name="$1"
    local tmux_socket tmux_server_key
    tmux_socket="$(managed_tmux_current_socket)"
    tmux_server_key="$tmux_socket"
    if [[ -n "$tmux_socket" ]]; then
        export I3PM_TMUX_SOCKET="$tmux_socket"
        export I3PM_TMUX_SERVER_KEY="$tmux_server_key"
        managed_tmux set-environment -t "$session_name" I3PM_TMUX_SOCKET "$tmux_socket"
        managed_tmux set-environment -t "$session_name" I3PM_TMUX_SERVER_KEY "$tmux_server_key"
    fi
}

managed_tmux_export_current_env() {
    local session_name="$1"
    managed_tmux_refresh_server_metadata "$session_name"
    while IFS='=' read -r name _; do
        [[ -n "$name" ]] && managed_tmux set-environment -t "$session_name" -u "$name" 2>/dev/null || true
    done < <(managed_tmux show-environment -t "$session_name" 2>/dev/null | sed -n 's/^\([A-Z0-9_]*\)=.*/\1/p' | rg '^I3PM_' || true)

    while IFS='=' read -r name value; do
        [[ -n "$name" ]] || continue
        managed_tmux set-environment -t "$session_name" "$name" "$value"
    done < <(env | rg '^I3PM_')
}

managed_tmux_set_metadata() {
    local session_name="$1"
    managed_tmux_refresh_server_metadata "$session_name"
    managed_tmux set-option -t "$session_name" -q @i3pm_managed "1"
    managed_tmux set-option -t "$session_name" -q @i3pm_schema_version "$(managed_tmux_schema_version)"
    managed_tmux set-option -t "$session_name" -q @i3pm_terminal_anchor "${I3PM_TERMINAL_ANCHOR_ID}"
    managed_tmux set-option -t "$session_name" -q @i3pm_context_key "${I3PM_CONTEXT_KEY}"
    managed_tmux set-option -t "$session_name" -q @i3pm_project_name "${I3PM_PROJECT_NAME:-}"
    managed_tmux set-option -t "$session_name" -q @i3pm_terminal_role "${I3PM_TERMINAL_ROLE:-}"
    managed_tmux set-option -t "$session_name" -q @i3pm_tmux_session_name "${I3PM_TMUX_SESSION_NAME:-$session_name}"
    managed_tmux set-option -t "$session_name" -q @i3pm_tmux_socket "${I3PM_TMUX_SOCKET:-}"
    managed_tmux set-option -t "$session_name" -q @i3pm_tmux_server_key "${I3PM_TMUX_SERVER_KEY:-}"
}

managed_tmux_recreate_reason() {
    local session_name="$1"
    local existing_managed existing_context existing_role existing_server_key existing_schema

    existing_managed="$(managed_tmux_session_option "$session_name" "@i3pm_managed")"
    existing_context="$(managed_tmux_session_option "$session_name" "@i3pm_context_key")"
    existing_role="$(managed_tmux_session_option "$session_name" "@i3pm_terminal_role")"
    existing_server_key="$(managed_tmux_session_option "$session_name" "@i3pm_tmux_server_key")"
    existing_schema="$(managed_tmux_session_option "$session_name" "@i3pm_schema_version")"

    if [[ "$existing_managed" != "1" ]]; then
        printf 'unmanaged'
        return 0
    fi

    if [[ "$existing_context" != "${I3PM_CONTEXT_KEY}" ]]; then
        printf 'context_mismatch:%s' "$existing_context"
        return 0
    fi

    if [[ -n "${I3PM_TERMINAL_ROLE:-}" && -n "$existing_role" && "$existing_role" != "${I3PM_TERMINAL_ROLE}" ]]; then
        printf 'role_mismatch:%s' "$existing_role"
        return 0
    fi

    if [[ -n "$existing_server_key" && "$existing_server_key" != "$(managed_tmux_expected_server_key)" ]]; then
        printf 'server_key_mismatch:%s' "$existing_server_key"
        return 0
    fi

    if [[ -n "$existing_schema" && "$existing_schema" != "$(managed_tmux_schema_version)" ]]; then
        printf 'schema_mismatch:%s' "$existing_schema"
        return 0
    fi

    return 1
}

managed_tmux_prepare_env() {
    managed_tmux_prepare_terminal_term
    export I3PM_TMUX_SESSION_NAME="$1"
    export I3PM_TMUX_SOCKET
    I3PM_TMUX_SOCKET="$(managed_tmux_current_socket)"
    export I3PM_TMUX_SERVER_KEY="$I3PM_TMUX_SOCKET"
}
