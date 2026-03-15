#!/usr/bin/env bash

set -euo pipefail

managed_tmux_prepare_terminal_term() {
    local current_term="${TERM:-}"
    if [[ -z "$current_term" || "$current_term" == "dumb" ]]; then
        export TERM="${I3PM_TERM_OVERRIDE:-xterm-256color}"
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

managed_tmux_current_socket() {
    if [[ -n "${I3PM_TMUX_SOCKET:-}" ]]; then
        printf '%s' "${I3PM_TMUX_SOCKET}"
        return 0
    fi
    if [[ -n "${TMUX:-}" ]]; then
        printf '%s' "${TMUX%%,*}"
        return 0
    fi
    tmux display-message -p '#{socket_path}' 2>/dev/null || true
}

managed_tmux_refresh_server_metadata() {
    local session_name="$1"
    local tmux_socket tmux_server_key
    tmux_socket="$(managed_tmux_current_socket)"
    tmux_server_key="$tmux_socket"
    if [[ -n "$tmux_socket" ]]; then
        export I3PM_TMUX_SOCKET="$tmux_socket"
        export I3PM_TMUX_SERVER_KEY="$tmux_server_key"
        tmux set-environment -t "$session_name" I3PM_TMUX_SOCKET "$tmux_socket"
        tmux set-environment -t "$session_name" I3PM_TMUX_SERVER_KEY "$tmux_server_key"
    fi
}

managed_tmux_export_current_env() {
    local session_name="$1"
    managed_tmux_refresh_server_metadata "$session_name"
    while IFS='=' read -r name _; do
        [[ -n "$name" ]] && tmux set-environment -t "$session_name" -u "$name" 2>/dev/null || true
    done < <(tmux show-environment -t "$session_name" 2>/dev/null | sed -n 's/^\([A-Z0-9_]*\)=.*/\1/p' | rg '^I3PM_' || true)

    while IFS='=' read -r name value; do
        [[ -n "$name" ]] || continue
        tmux set-environment -t "$session_name" "$name" "$value"
    done < <(env | rg '^I3PM_')
}

managed_tmux_set_metadata() {
    local session_name="$1"
    managed_tmux_refresh_server_metadata "$session_name"
    tmux set-option -t "$session_name" -q @i3pm_managed "1"
    tmux set-option -t "$session_name" -q @i3pm_terminal_anchor "${I3PM_TERMINAL_ANCHOR_ID}"
    tmux set-option -t "$session_name" -q @i3pm_context_key "${I3PM_CONTEXT_KEY}"
    tmux set-option -t "$session_name" -q @i3pm_project_name "${I3PM_PROJECT_NAME:-}"
    tmux set-option -t "$session_name" -q @i3pm_terminal_role "${I3PM_TERMINAL_ROLE:-}"
    tmux set-option -t "$session_name" -q @i3pm_tmux_session_name "${I3PM_TMUX_SESSION_NAME:-$session_name}"
    tmux set-option -t "$session_name" -q @i3pm_tmux_socket "${I3PM_TMUX_SOCKET:-}"
    tmux set-option -t "$session_name" -q @i3pm_tmux_server_key "${I3PM_TMUX_SERVER_KEY:-}"
}

managed_tmux_validate_metadata() {
    local session_name="$1"
    local existing_managed existing_context existing_role
    existing_managed="$(tmux show-options -t "$session_name" -qv @i3pm_managed || true)"
    existing_context="$(tmux show-options -t "$session_name" -qv @i3pm_context_key || true)"
    existing_role="$(tmux show-options -t "$session_name" -qv @i3pm_terminal_role || true)"

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
}

managed_tmux_recreate_reason() {
    local session_name="$1"
    local existing_managed existing_context existing_role

    existing_managed="$(tmux show-options -t "$session_name" -qv @i3pm_managed || true)"
    existing_context="$(tmux show-options -t "$session_name" -qv @i3pm_context_key || true)"
    existing_role="$(tmux show-options -t "$session_name" -qv @i3pm_terminal_role || true)"

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

    return 1
}

managed_tmux_prepare_env() {
    managed_tmux_prepare_terminal_term
    export I3PM_TMUX_SESSION_NAME="$1"
    local tmux_socket
    tmux_socket="$(managed_tmux_current_socket)"
    if [[ -n "$tmux_socket" ]]; then
        export I3PM_TMUX_SOCKET="$tmux_socket"
        export I3PM_TMUX_SERVER_KEY="$tmux_socket"
    fi
}
