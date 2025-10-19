#!/usr/bin/env bash
# launch-ghostty - Launch Ghostty terminal in project context with automatic marking
#
# Usage: launch-ghostty

# shellcheck source=./i3-project-common.sh
source "${HOME}/.config/i3/scripts/common.sh" || exit 1

main() {
    # Get active project
    local project_name
    project_name=$(get_active_project 2>/dev/null) || project_name=""

    local target_dir=""
    local session_name=""

    if [ -n "$project_name" ]; then
        # Project is active - get project directory
        local project_file="${PROJECT_DIR}/${project_name}.json"
        if [ -f "$project_file" ]; then
            target_dir=$(jq -r '.project.directory' "$project_file")
            session_name="$project_name"
            log_info "Launching Ghostty in project directory: $target_dir (session: $session_name)"
        fi
    fi

    # Launch Ghostty with sesh if project is active, otherwise just ghostty
    local ghostty_pid

    if [ -n "$session_name" ] && command -v sesh >/dev/null 2>&1; then
        # Launch with sesh session
        log_debug "Executing: ghostty -e sesh connect \"$session_name\""
        ghostty -e sesh connect "$session_name" &
        ghostty_pid=$!
    elif [ -n "$target_dir" ]; then
        # Launch in project directory without sesh
        log_debug "Executing: ghostty --working-directory=\"$target_dir\""
        ghostty --working-directory="$target_dir" &
        ghostty_pid=$!
    else
        # Launch ghostty normally
        log_debug "Executing: ghostty"
        ghostty &
        ghostty_pid=$!
    fi

    # If project is active and app is scoped, mark the window
    if [ -n "$project_name" ]; then
        if is_app_scoped "Ghostty" || is_app_scoped "com.mitchellh.ghostty"; then
            log_info "Ghostty is project-scoped, will mark window with project:$project_name"

            # Wait for window to appear and get its ID
            local window_id
            window_id=$(get_window_id_by_pid "$ghostty_pid" 10)

            if [ -n "$window_id" ]; then
                mark_window_with_project "$window_id" "$project_name"
                echo -e "${GREEN}✓${NC} Launched Ghostty for project: $project_name (window $window_id)"
            else
                log_warn "Could not find window for Ghostty process $ghostty_pid"
                echo -e "${YELLOW}⚠${NC} Launched Ghostty but could not mark window"
            fi
        else
            log_debug "Ghostty is global - not marking window"
        fi
    fi
}

main "$@"
