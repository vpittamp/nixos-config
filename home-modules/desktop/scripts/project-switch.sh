#!/usr/bin/env bash
# i3-project-switch - Switch to a different project
#
# Usage: i3-project-switch PROJECT_NAME

# shellcheck source=./i3-project-common.sh
source "${HOME}/.config/i3/scripts/common.sh" || exit 1

usage() {
    cat <<EOF
Usage: i3-project-switch PROJECT_NAME

Switch to an i3 project context.

Arguments:
    PROJECT_NAME    Name of the project to activate

Examples:
    i3-project-switch nixos
    i3-project-switch stacks

This will:
  1. Load project configuration
  2. Apply workspace layouts (i3 append_layout)
  3. Execute launch commands
  4. Apply workspace output assignments (multi-monitor)
  5. Update active project state
  6. Hide old project windows / show new project windows (Phase 5)
  7. Send i3 tick event for UI updates (Phase 6)

To see available projects: i3-project-list
EOF
}

main() {
    local project_name="$1"

    if [ -z "$project_name" ] || [ "$project_name" = "--help" ]; then
        usage
        exit $([ "$project_name" = "--help" ] && echo 0 || echo 1)
    fi

    # Check i3 is running
    check_i3_running

    # Get project JSON
    local project_file="${PROJECT_DIR}/${project_name}.json"
    if [ ! -f "$project_file" ]; then
        die "Project '$project_name' does not exist"
    fi

    if ! validate_json "$project_file"; then
        die "Project configuration is invalid JSON"
    fi

    local project_json
    project_json=$(cat "$project_file")

    # Extract project information
    local display_name dir icon
    display_name=$(echo "$project_json" | jq -r '.project.displayName // .project.name')
    dir=$(echo "$project_json" | jq -r '.project.directory')
    icon=$(echo "$project_json" | jq -r '.project.icon // ""')

    log_info "Switching to project: $project_name"

    # Get old project (for Phase 6 - window management)
    local old_project
    old_project=$(get_active_project 2>/dev/null) || old_project=""

    # Update active project file (JSON format for i3blocks project indicator)
    cat > "$ACTIVE_PROJECT_FILE" <<EOF
{
  "name": "$project_name",
  "display_name": "$display_name",
  "icon": "$icon"
}
EOF

    log_info "Active project set to: $project_name"
    echo -e "${GREEN}✓${NC} Switched to project: $icon $display_name"

    # Directory feedback
    if [ -d "$dir" ]; then
        echo "  Project directory: $dir"
    else
        echo -e "${YELLOW}⚠${NC}  Warning: Project directory does not exist: $dir"
    fi

    # Phase 4: Apply workspace output assignments (multi-monitor)
    local workspace_outputs
    workspace_outputs=$(echo "$project_json" | jq -r '.workspaceOutputs // empty')

    if [ -n "$workspace_outputs" ]; then
        log_info "Applying workspace output assignments..."
        local ws_nums
        ws_nums=$(echo "$workspace_outputs" | jq -r 'keys[]' 2>/dev/null)

        while IFS= read -r ws_num; do
            if [ -n "$ws_num" ]; then
                local output
                output=$(echo "$workspace_outputs" | jq -r ".[\"$ws_num\"]")

                if [ -n "$output" ] && [ "$output" != "null" ]; then
                    log_debug "Assigning workspace $ws_num to output $output"
                    i3_cmd "workspace $ws_num output $output" || log_warn "Failed to assign workspace $ws_num to output $output"
                fi
            fi
        done <<< "$ws_nums"
    fi

    # Phase 4: Apply workspace layouts if present
    local workspaces
    workspaces=$(echo "$project_json" | jq -r '.workspaces // empty')

    if [ -n "$workspaces" ]; then
        log_info "Applying workspace layouts..."
        local ws_nums
        ws_nums=$(echo "$workspaces" | jq -r 'keys[]' 2>/dev/null)

        while IFS= read -r ws_num; do
            if [ -n "$ws_num" ]; then
                local ws_data
                ws_data=$(echo "$workspaces" | jq -r ".[\"$ws_num\"]")

                # Check for layout
                local layout
                layout=$(echo "$ws_data" | jq -r '.layout // empty')

                if [ -n "$layout" ]; then
                    log_debug "Applying layout to workspace $ws_num"

                    # Create temporary layout file
                    local layout_file
                    layout_file=$(mktemp)
                    echo "$layout" > "$layout_file"

                    # Switch to workspace and append layout
                    i3_cmd "workspace $ws_num" || log_warn "Failed to switch to workspace $ws_num"
                    i3_cmd "append_layout $layout_file" || log_warn "Failed to apply layout to workspace $ws_num"

                    # Clean up
                    rm -f "$layout_file"
                fi
            fi
        done <<< "$ws_nums"
    fi

    # Phase 4: Execute launch commands if present
    if [ -n "$workspaces" ]; then
        log_info "Executing launch commands..."
        local ws_nums
        ws_nums=$(echo "$workspaces" | jq -r 'keys[]' 2>/dev/null)

        while IFS= read -r ws_num; do
            if [ -n "$ws_num" ]; then
                local ws_data
                ws_data=$(echo "$workspaces" | jq -r ".[\"$ws_num\"]")

                # Check for launchCommands
                local launch_cmds
                launch_cmds=$(echo "$ws_data" | jq -r '.launchCommands // empty')

                if [ -n "$launch_cmds" ]; then
                    local cmd_count
                    cmd_count=$(echo "$launch_cmds" | jq 'length')

                    log_debug "Executing $cmd_count launch command(s) for workspace $ws_num"

                    local idx=0
                    while [ $idx -lt "$cmd_count" ]; do
                        local cmd
                        cmd=$(echo "$launch_cmds" | jq -r ".[$idx]")

                        if [ -n "$cmd" ] && [ "$cmd" != "null" ]; then
                            log_debug "Launching: $cmd"

                            # Execute command in background
                            # Change to project directory first
                            (cd "$dir" && eval "$cmd" &) || log_warn "Failed to execute: $cmd"

                            # Small delay to allow window to appear
                            sleep 0.5
                        fi

                        ((idx++))
                    done
                fi
            fi
        done <<< "$ws_nums"
    fi

    # Phase 5: Hide old project windows, show new project windows
    if [ -n "$old_project" ] && [ "$old_project" != "$project_name" ]; then
        log_info "Switching from project: $old_project → $project_name"

        # Hide windows marked with old project
        local old_mark="project:${old_project}"
        log_debug "Moving windows with mark '$old_mark' to scratchpad"
        i3_hide_windows_by_mark "$old_mark" || log_warn "Failed to hide windows for old project"
    fi

    # Show windows marked with new project
    local new_mark="project:${project_name}"
    log_debug "Showing windows with mark '$new_mark' from scratchpad"
    i3_show_windows_by_mark "$new_mark" || log_debug "No windows to show for project (or failed to show)"

    # Phase 6: Send i3 tick event for polybar/UI updates
    log_debug "Sending tick event: project:$project_name"
    i3_send_tick "project:$project_name"

    # Update i3blocks project indicator (Feature 013)
    log_debug "Signaling i3blocks to update project indicator"
    pkill -RTMIN+10 i3blocks 2>/dev/null || true
}

main "$@"
