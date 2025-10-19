#!/usr/bin/env bash
# i3-project-clear - Clear active project (return to global mode)
#
# Usage: i3-project-clear

# shellcheck source=./i3-project-common.sh
source "${HOME}/.config/i3/scripts/common.sh" || exit 1

usage() {
    cat <<EOF
Usage: i3-project-clear

Clear the active project and return to global mode.

In global mode:
  - All applications are visible
  - No project context is applied
  - Launching apps creates global (non-project-scoped) windows

Examples:
    i3-project-clear
EOF
}

main() {
    if [ "$1" = "--help" ]; then
        usage
        exit 0
    fi

    # Get current project before clearing
    local old_project
    old_project=$(get_active_project 2>/dev/null) || old_project=""

    if [ -z "$old_project" ]; then
        echo "No active project to clear"
        exit 0
    fi

    log_info "Clearing active project: $old_project"

    # Clear active project file
    echo "" > "$ACTIVE_PROJECT_FILE"

    echo -e "${GREEN}✓${NC} Cleared active project (was: $old_project)"
    echo "  Returned to global mode"

    # Phase 5: Show all project-scoped windows from scratchpad
    # Get all unique project marks
    log_info "Showing all project windows from scratchpad"

    # Find all windows with project marks and show them
    local all_marks
    all_marks=$(i3_cmd "-t get_tree" | jq -r '.. | select(.marks?) | .marks[] | select(startswith("project:"))' | sort -u)

    if [ -n "$all_marks" ]; then
        while IFS= read -r mark; do
            if [ -n "$mark" ]; then
                log_debug "Showing windows with mark: $mark"
                i3_show_windows_by_mark "$mark" || log_debug "No windows to show for mark $mark"
            fi
        done <<< "$all_marks"
    fi

    # Phase 6: Send i3 tick event for polybar/UI updates
    log_debug "Sending tick event: project:none"
    i3_send_tick "project:none"
}

main "$@"
