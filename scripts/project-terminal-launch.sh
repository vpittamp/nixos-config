#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/managed-tmux-session.sh"

PROJECT_DIR="${1:-}"
shift || true

if [[ -z "$PROJECT_DIR" ]]; then
    echo "project-terminal-launch: Usage: project-terminal-launch.sh <project_dir> [command ...]" >&2
    exit 1
fi

PROJECT_DIR="$(cd "$PROJECT_DIR" && pwd)"
managed_tmux_require_context

TMUX_SESSION_NAME="${I3PM_TMUX_SESSION_NAME:-}"
if [[ -z "$TMUX_SESSION_NAME" ]]; then
    TMUX_SESSION_NAME="$(managed_tmux_session_name "${I3PM_PROJECT_NAME:-project}" "${I3PM_CONTEXT_KEY:-${I3PM_TERMINAL_ANCHOR_ID:-}}")"
fi
managed_tmux_prepare_env "$TMUX_SESSION_NAME"
managed_tmux_ensure_socket_parent

existing_session_state="missing"

project_terminal_handle_existing_session() {
    if ! managed_tmux has-session -t "$TMUX_SESSION_NAME" 2>/dev/null; then
        existing_session_state="missing"
        return 1
    fi

    if recreate_reason="$(managed_tmux_recreate_reason "$TMUX_SESSION_NAME" 2>/dev/null)"; then
        quarantine_name="$(managed_tmux_quarantine_session "$TMUX_SESSION_NAME" "$recreate_reason" 2>/dev/null || true)"
        if [[ -z "$quarantine_name" ]]; then
            echo "project-terminal-launch: failed to quarantine stale managed session '$TMUX_SESSION_NAME' ($recreate_reason)" >&2
            exit 1
        fi
        echo "project-terminal-launch: quarantined stale managed session '$TMUX_SESSION_NAME' as '$quarantine_name' ($recreate_reason)" >&2
        existing_session_state="recreate"
        return 1
    fi

    existing_session_state="attach"
    managed_tmux_export_current_env "$TMUX_SESSION_NAME"
    managed_tmux_set_metadata "$TMUX_SESSION_NAME"
    if [[ $# -gt 0 ]]; then
        window_name="$(basename -- "$1")"
        command_string="$(printf '%q ' "$@")"
        command_string="${command_string% }"
        managed_tmux new-window -t "$TMUX_SESSION_NAME" -c "$PROJECT_DIR" -n "${window_name:0:24}" "exec $command_string"
    fi
    exec env TMUX= I3PM_TMUX_SOCKET="$I3PM_TMUX_SOCKET" tmux -S "$I3PM_TMUX_SOCKET" attach-session -t "$TMUX_SESSION_NAME"
}

project_terminal_handle_existing_session "$@" || true

args=(new-session -d -s "$TMUX_SESSION_NAME" -c "$PROJECT_DIR" -n main)
while IFS='=' read -r name value; do
    [[ -n "$name" ]] || continue
    args+=(-e "$name=$value")
done < <(env | rg '^I3PM_')
args+=("exec ${SHELL:-/bin/bash} -l")
if ! managed_tmux "${args[@]}"; then
    project_terminal_handle_existing_session "$@" || true
    if [[ "$existing_session_state" == "recreate" ]]; then
        managed_tmux "${args[@]}"
    else
        echo "project-terminal-launch: failed to create managed session '$TMUX_SESSION_NAME'" >&2
        exit 1
    fi
fi

managed_tmux_export_current_env "$TMUX_SESSION_NAME"
managed_tmux_set_metadata "$TMUX_SESSION_NAME"

if [[ $# -gt 0 ]]; then
    window_name="$(basename -- "$1")"
    command_string="$(printf '%q ' "$@")"
    command_string="${command_string% }"
    managed_tmux new-window -t "$TMUX_SESSION_NAME" -c "$PROJECT_DIR" -n "${window_name:0:24}" "exec $command_string"
fi

exec env TMUX= I3PM_TMUX_SOCKET="$I3PM_TMUX_SOCKET" tmux -S "$I3PM_TMUX_SOCKET" attach-session -t "$TMUX_SESSION_NAME"
