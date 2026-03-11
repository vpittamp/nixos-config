#!/usr/bin/env bash
#
# Devenv-aware Terminal Launch Helper
#
# Purpose: Launch terminal sessions with devenv integration
#
# For projects WITH devenv.nix:
#   1. Create tmux session with "shell" window (main working window)
#   2. Create "devenv" window running `devenv up` (services)
#   3. Attach to "shell" window
#
# For projects WITHOUT devenv.nix:
#   - Delegate to the managed project tmux launcher
#
# Usage: devenv-terminal-launch.sh <session_dir> [session_name]
#
# Arguments:
#   session_dir   - Project directory (required)
#   session_name  - Session name (optional, defaults to directory basename)
#
# Environment Variables (inherited from app-launcher-wrapper.sh):
#   I3PM_PROJECT_NAME - Project name for logging
#   DEBUG=1           - Enable verbose logging

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/managed-tmux-session.sh"

# Arguments
SESSION_DIR="${1:-}"
if [[ -z "$SESSION_DIR" ]]; then
    echo "devenv-terminal-launch: Usage: devenv-terminal-launch.sh <session_dir> [session_name]" >&2
    exit 1
fi

# Resolve to absolute path
SESSION_DIR=$(cd "$SESSION_DIR" && pwd)

managed_tmux_require_context

TMUX_SESSION_NAME="$(managed_tmux_session_name "${I3PM_PROJECT_NAME:-project}" "${I3PM_TERMINAL_ANCHOR_ID}")"
managed_tmux_prepare_env "$TMUX_SESSION_NAME"

# Check if devenv.nix exists in project
if [[ -f "$SESSION_DIR/devenv.nix" ]]; then
    if tmux has-session -t "$TMUX_SESSION_NAME" 2>/dev/null; then
        managed_tmux_validate_metadata "$TMUX_SESSION_NAME"
        managed_tmux_export_current_env "$TMUX_SESSION_NAME"
        exec env TMUX= tmux attach-session -t "$TMUX_SESSION_NAME"
    fi

    args=(new-session -d -s "$TMUX_SESSION_NAME" -c "$SESSION_DIR" -n "shell")
    while IFS='=' read -r name value; do
        [[ -n "$name" ]] || continue
        args+=(-e "$name=$value")
    done < <(env | rg '^I3PM_')
    args+=("exec ${SHELL:-/bin/bash} -l")
    tmux "${args[@]}"

    managed_tmux_export_current_env "$TMUX_SESSION_NAME"
    managed_tmux_set_metadata "$TMUX_SESSION_NAME"

    tmux new-window -t "$TMUX_SESSION_NAME" -n "devenv" -c "$SESSION_DIR" "devenv up"
    tmux select-window -t "$TMUX_SESSION_NAME:shell"

    exec env TMUX= tmux attach-session -t "$TMUX_SESSION_NAME"
else
    exec "$SCRIPT_DIR/project-terminal-launch.sh" "$SESSION_DIR" "${2:-}"
fi
