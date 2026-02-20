#!/usr/bin/env bash
# worktree-lazygit.sh - Launch lazygit with worktree context
#
# Feature 109: Enhanced Worktree User Experience (T002, T025)
#
# Usage: worktree-lazygit.sh <worktree-path> [view]
#
# Arguments:
#   worktree-path: Absolute path to the git worktree directory
#   view: Optional lazygit view to focus (status, branch, log, stash)
#         Default: status
#
# Examples:
#   worktree-lazygit.sh /home/user/repos/project/109-feature
#   worktree-lazygit.sh /home/user/repos/project/109-feature branch
#   worktree-lazygit.sh /home/user/repos/project/109-feature status
#
# Per research.md: Uses lazygit --path <dir> <view> pattern
# Per contracts/lazygit-context.json: Always spawns new terminal instance

set -euo pipefail

# Default terminal emulator (ghostty per plan.md)
TERMINAL="${TERMINAL:-ghostty}"
ACTIVE_WORKTREE_FILE="${HOME}/.config/i3/active-worktree.json"

REMOTE_HOST=""
REMOTE_USER=""
REMOTE_PORT="22"
REMOTE_DIR=""

resolve_path() {
    local input="$1"
    realpath -m "$input" 2>/dev/null || echo "$input"
}

load_remote_context_for_path() {
    local worktree_path="$1"

    if [[ ! -f "$ACTIVE_WORKTREE_FILE" ]]; then
        return 1
    fi
    if ! command -v jq >/dev/null 2>&1; then
        return 1
    fi

    local remote_enabled
    remote_enabled=$(jq -r '.remote.enabled // false' "$ACTIVE_WORKTREE_FILE" 2>/dev/null || echo "false")
    if [[ "$remote_enabled" != "true" ]]; then
        return 1
    fi

    local active_local_dir active_dir
    active_local_dir=$(jq -r '.local_directory // ""' "$ACTIVE_WORKTREE_FILE" 2>/dev/null || echo "")
    active_dir=$(jq -r '.directory // ""' "$ACTIVE_WORKTREE_FILE" 2>/dev/null || echo "")
    if [[ -z "$active_local_dir" ]]; then
        active_local_dir="$active_dir"
    fi
    if [[ -z "$active_local_dir" ]]; then
        return 1
    fi

    local resolved_input resolved_active
    resolved_input=$(resolve_path "$worktree_path")
    resolved_active=$(resolve_path "$active_local_dir")
    if [[ "$resolved_input" != "$resolved_active" ]]; then
        return 1
    fi

    REMOTE_HOST=$(jq -r '.remote.host // "ryzen"' "$ACTIVE_WORKTREE_FILE" 2>/dev/null || echo "ryzen")
    REMOTE_USER=$(jq -r '.remote.user // env.USER // "vpittamp"' "$ACTIVE_WORKTREE_FILE" 2>/dev/null || echo "${USER:-vpittamp}")
    REMOTE_PORT=$(jq -r '.remote.port // 22' "$ACTIVE_WORKTREE_FILE" 2>/dev/null || echo "22")
    REMOTE_DIR=$(jq -r '.remote.remote_dir // .directory // ""' "$ACTIVE_WORKTREE_FILE" 2>/dev/null || echo "")

    if [[ -z "$REMOTE_HOST" || -z "$REMOTE_USER" || -z "$REMOTE_DIR" ]]; then
        return 1
    fi

    if [[ ! "$REMOTE_PORT" =~ ^[0-9]+$ ]]; then
        REMOTE_PORT="22"
    fi

    return 0
}

launch_local_lazygit() {
    local worktree_path="$1"
    local view="$2"

    local lazygit_cmd="lazygit --path \"$worktree_path\" $view"
    echo "[Feature 109] Launching lazygit in $worktree_path with view: $view"

    case "$TERMINAL" in
        ghostty|alacritty)
            exec "$TERMINAL" -e bash -c "$lazygit_cmd"
            ;;
        kitty)
            exec "$TERMINAL" bash -c "$lazygit_cmd"
            ;;
        *)
            exec "$TERMINAL" -e bash -c "$lazygit_cmd"
            ;;
    esac
}

launch_remote_lazygit() {
    local view="$1"

    local remote_lazygit_cmd
    remote_lazygit_cmd="lazygit --path $(printf '%q' "$REMOTE_DIR") $view"
    local remote_cmd
    remote_cmd="cd $(printf '%q' "$REMOTE_DIR") && $remote_lazygit_cmd"

    local ssh_args=(ssh -t)
    if [[ "$REMOTE_PORT" != "22" ]]; then
        ssh_args+=(-p "$REMOTE_PORT")
    fi
    ssh_args+=("$REMOTE_USER@$REMOTE_HOST" "$remote_cmd")

    local ssh_cmd_serialized
    ssh_cmd_serialized=$(printf '%q ' "${ssh_args[@]}")
    ssh_cmd_serialized="${ssh_cmd_serialized% }"

    local runtime_dir remote_launch_script
    runtime_dir="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
    mkdir -p "$runtime_dir"
    remote_launch_script="$(mktemp "$runtime_dir/i3pm-lazygit-remote.XXXXXX.sh")"
    chmod 700 "$remote_launch_script"

    cat > "$remote_launch_script" <<EOF
#!/usr/bin/env bash
set -euo pipefail
if ! $ssh_cmd_serialized; then
  echo
  echo "[i3pm] SSH lazygit launch failed for $REMOTE_USER@$REMOTE_HOST."
  echo "[i3pm] Press Enter to close..."
  read -r
fi
rm -f -- "\$0" >/dev/null 2>&1 || true
EOF

    echo "[Feature 109] Launching remote lazygit on $REMOTE_USER@$REMOTE_HOST:$REMOTE_PORT ($REMOTE_DIR)"
    case "$TERMINAL" in
        kitty)
            exec "$TERMINAL" "$remote_launch_script"
            ;;
        *)
            exec "$TERMINAL" -e "$remote_launch_script"
            ;;
    esac
}

main() {
    local worktree_path="${1:-}"
    local view="${2:-status}"

    if [[ -z "$worktree_path" ]]; then
        echo "Error: worktree-path is required" >&2
        echo "Usage: worktree-lazygit.sh <worktree-path> [view]" >&2
        exit 1
    fi

    # Validate worktree path exists and is a git directory
    if [[ ! -d "$worktree_path" ]]; then
        echo "Error: Directory does not exist: $worktree_path" >&2
        exit 1
    fi

    if [[ ! -e "$worktree_path/.git" ]]; then
        echo "Error: Not a git worktree: $worktree_path" >&2
        exit 1
    fi

    # Validate view is one of the allowed values
    case "$view" in
        status|branch|log|stash)
            ;;
        *)
            echo "Error: Invalid view '$view'. Must be one of: status, branch, log, stash" >&2
            exit 1
            ;;
    esac

    # Feature 087: If the selected worktree is the active SSH worktree, launch
    # lazygit remotely over SSH in a terminal.
    if load_remote_context_for_path "$worktree_path"; then
        launch_remote_lazygit "$view"
    fi

    launch_local_lazygit "$worktree_path" "$view"
}

main "$@"
