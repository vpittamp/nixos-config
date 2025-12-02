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

    # Build lazygit command
    # Per research.md: lazygit --path <dir> <view>
    local lazygit_cmd="lazygit --path \"$worktree_path\" $view"

    # Launch in new terminal
    # Per contracts/lazygit-context.json: Always spawn new instance
    echo "[Feature 109] Launching lazygit in $worktree_path with view: $view"

    case "$TERMINAL" in
        ghostty)
            exec $TERMINAL -e bash -c "$lazygit_cmd"
            ;;
        alacritty)
            exec $TERMINAL -e bash -c "$lazygit_cmd"
            ;;
        kitty)
            exec $TERMINAL bash -c "$lazygit_cmd"
            ;;
        *)
            # Generic fallback
            exec $TERMINAL -e bash -c "$lazygit_cmd"
            ;;
    esac
}

main "$@"
