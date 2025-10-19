#!/usr/bin/env bash
# i3-project-mark-window - Mark a window with the current project
#
# Usage: i3-project-mark-window [--window-id WINDOW_ID]

# shellcheck source=./i3-project-common.sh
source "${HOME}/.config/i3/scripts/common.sh" || exit 1

usage() {
    cat <<EOF
Usage: i3-project-mark-window [--window-id WINDOW_ID]

Mark a window with the active project mark.

If no window ID is provided, marks the currently focused window.

Arguments:
    --window-id WINDOW_ID    Specific window ID to mark (optional)

Examples:
    i3-project-mark-window              # Mark focused window
    i3-project-mark-window --window-id 12345  # Mark specific window

This command:
  1. Checks for an active project
  2. Applies i3 mark "project:PROJECT_NAME" to the window
  3. Logs the operation
EOF
}

main() {
    local window_id=""

    if [ "$1" = "--help" ]; then
        usage
        exit 0
    fi

    if [ "$1" = "--window-id" ]; then
        window_id="$2"
    fi

    # Check i3 is running
    check_i3_running

    # Get active project
    local project_name
    project_name=$(get_active_project 2>/dev/null) || project_name=""

    if [ -z "$project_name" ]; then
        echo -e "${YELLOW}⚠${NC} No active project - cannot mark window"
        log_warn "Attempted to mark window with no active project"
        exit 1
    fi

    local mark="project:${project_name}"

    # Mark the window
    if [ -n "$window_id" ]; then
        # Mark specific window
        log_info "Marking window $window_id with $mark"
        i3_cmd "[id=\"$window_id\"] mark --add \"$mark\"" || die "Failed to mark window $window_id"
        echo -e "${GREEN}✓${NC} Marked window $window_id with project: $project_name"
    else
        # Mark focused window
        log_info "Marking focused window with $mark"
        i3_cmd "mark --add \"$mark\"" || die "Failed to mark focused window"
        echo -e "${GREEN}✓${NC} Marked focused window with project: $project_name"
    fi
}

main "$@"
