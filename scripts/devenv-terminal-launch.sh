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
#   - Fallback to standard sesh connect (existing behavior)
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

# Logging function
log() {
    local level="$1"
    shift
    if [[ "${DEBUG:-0}" == "1" ]]; then
        echo "[$level] devenv-terminal-launch: $*" >&2
    fi
}

# Error handling
error() {
    echo "Error: $*" >&2
    exit 1
}

# Arguments
SESSION_DIR="${1:-}"
if [[ -z "$SESSION_DIR" ]]; then
    error "Usage: devenv-terminal-launch.sh <session_dir> [session_name]"
fi

# Resolve to absolute path
SESSION_DIR=$(cd "$SESSION_DIR" && pwd)

# Session name: use provided name, or derive unique name from parent_basename
# e.g., /repos/backstage/main -> backstage_main (avoids conflicts with other repos' "main")
if [[ -n "${2:-}" ]]; then
    SESSION_NAME="$2"
else
    PARENT_DIR=$(basename "$(dirname "$SESSION_DIR")")
    BASE_DIR=$(basename "$SESSION_DIR")
    SESSION_NAME="${PARENT_DIR}_${BASE_DIR}"
fi

# Sanitize session name for tmux (remove special chars, replace with dashes)
SAFE_SESSION_NAME=$(echo "$SESSION_NAME" | tr -c '[:alnum:]-_' '-' | sed 's/--*/-/g; s/^-//; s/-$//')

log "INFO" "Session directory: $SESSION_DIR"
log "INFO" "Session name: $SAFE_SESSION_NAME"

# Check if devenv.nix exists in project
if [[ -f "$SESSION_DIR/devenv.nix" ]]; then
    log "INFO" "Devenv project detected"

    # Check if session already exists
    if tmux has-session -t "$SAFE_SESSION_NAME" 2>/dev/null; then
        log "INFO" "Session '$SAFE_SESSION_NAME' already exists, attaching"
        exec tmux attach-session -t "$SAFE_SESSION_NAME"
    fi

    log "INFO" "Creating new session with devenv window"

    # Create new session with "shell" window (detached)
    tmux new-session -d -s "$SAFE_SESSION_NAME" -c "$SESSION_DIR" -n "shell"

    # Create "devenv" window running devenv up
    # This runs devenv up in the foreground so user can see service output
    tmux new-window -t "$SAFE_SESSION_NAME" -n "devenv" -c "$SESSION_DIR" "devenv up"

    # Switch back to shell window as the active window
    tmux select-window -t "$SAFE_SESSION_NAME:shell"

    log "INFO" "Attaching to session '$SAFE_SESSION_NAME'"

    # Attach to the session
    exec tmux attach-session -t "$SAFE_SESSION_NAME"
else
    log "INFO" "No devenv.nix found, using standard sesh connect"

    # Fallback to standard sesh behavior
    exec sesh connect "$SESSION_DIR"
fi
