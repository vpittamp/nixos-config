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

    # If project is active and app is scoped, detect the new window using i3 native queries
    local window_id=""
    if [ -n "$project_name" ] && is_app_scoped "Code"; then
        log_info "Code is project-scoped, will mark window with project:$project_name"

        # Get current Code windows from i3 tree (native i3 query)
        local windows_before
        windows_before=$(i3-msg -t get_tree | jq -r '[.. | select(.window_properties?.class? == "Code") | .window] | .[]' 2>/dev/null || true)
        log_debug "Code windows in i3 before launch: $(echo "$windows_before" | grep -c . || echo 0)"
    fi

    # Launch VS Code
    if [ -n "$target_dir" ]; then
        log_debug "Executing: code \"$target_dir\""
        code "$target_dir" &
    else
        log_debug "Executing: code"
        code &
    fi

    # If project is active and app is scoped, mark the new window
    if [ -n "$project_name" ]; then
        if is_app_scoped "Code"; then
            # Poll i3 tree for new window (more reliable than xdotool)
            local max_attempts=20
            local attempt=0

            while [ $attempt -lt $max_attempts ]; do
                sleep 0.5

                # Get current windows from i3 tree
                local windows_after
                windows_after=$(i3-msg -t get_tree | jq -r '[.. | select(.window_properties?.class? == "Code") | .window] | .[]' 2>/dev/null || true)

                # Find new window by comparing lists
                local new_window
                new_window=$(comm -13 <(echo "$windows_before" | sort) <(echo "$windows_after" | sort) | head -1)

                if [ -n "$new_window" ]; then
                    window_id="$new_window"
                    log_debug "Found new Code window in i3 tree: $window_id (attempt $attempt)"

                    # Wait briefly for window to stabilize
                    sleep 0.3

                    # Verify window still exists in i3 tree (not just X11)
                    if i3-msg -t get_tree | jq -e ".. | select(.window? == $window_id)" >/dev/null 2>&1; then
                        log_debug "Verified window $window_id exists in i3 tree"
                        break
                    else
                        log_debug "Window $window_id not in i3 tree, continuing search..."
                        window_id=""
                    fi
                fi

                ((attempt++))
            done

            if [ -n "$window_id" ]; then
                mark_window_with_project "$window_id" "$project_name"
                echo -e "${GREEN}✓${NC} Launched Code for project: $project_name (window $window_id)"
            else
                log_warn "Could not detect new Code window in i3 tree after ${max_attempts} attempts"
                echo -e "${YELLOW}⚠${NC} Launched Code but could not mark window"
            fi
        else
            log_debug "Code is global - not marking window"
        fi
    fi
}

main "$@"
