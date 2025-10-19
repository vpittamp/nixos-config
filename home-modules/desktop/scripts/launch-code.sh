#!/usr/bin/env bash
# launch-code - Launch VS Code in project context with automatic marking
#
# Usage: launch-code [DIRECTORY]

# shellcheck source=./i3-project-common.sh
source "${HOME}/.config/i3/scripts/common.sh" || exit 1

main() {
    # Get active project
    local project_name
    project_name=$(get_active_project 2>/dev/null) || project_name=""

    # Determine directory
    local target_dir="$1"

    if [ -n "$project_name" ]; then
        # Project is active - use project directory if no arg provided
        if [ -z "$target_dir" ]; then
            local project_file="${PROJECT_DIR}/${project_name}.json"
            if [ -f "$project_file" ]; then
                target_dir=$(jq -r '.project.directory' "$project_file")
                log_info "Launching Code in project directory: $target_dir"
            fi
        fi
    fi

    # Launch VS Code
    if [ -n "$target_dir" ]; then
        log_debug "Executing: code \"$target_dir\""
        code "$target_dir" &
        local code_pid=$!
    else
        log_debug "Executing: code"
        code &
        local code_pid=$!
    fi

    # If project is active and app is scoped, mark the window
    if [ -n "$project_name" ]; then
        if is_app_scoped "Code"; then
            log_info "Code is project-scoped, will mark window with project:$project_name"

            # Wait for window to appear and get its ID
            local window_id
            window_id=$(get_window_id_by_pid "$code_pid" 10)

            if [ -n "$window_id" ]; then
                mark_window_with_project "$window_id" "$project_name"
                echo -e "${GREEN}✓${NC} Launched Code for project: $project_name (window $window_id)"
            else
                log_warn "Could not find window for Code process $code_pid"
                echo -e "${YELLOW}⚠${NC} Launched Code but could not mark window"
            fi
        else
            log_debug "Code is global - not marking window"
        fi
    fi
}

main "$@"
