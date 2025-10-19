#!/usr/bin/env bash
# reassign-workspaces - Re-apply workspace output assignments for active project
#
# Usage: reassign-workspaces

# shellcheck source=./i3-project-common.sh
source "${HOME}/.config/i3/scripts/common.sh" || exit 1

usage() {
    cat <<EOF
Usage: reassign-workspaces

Re-apply workspace output assignments for the currently active project.

This is useful after:
  - Connecting/disconnecting external monitors
  - Changing display configuration
  - Monitor detection changes

Examples:
    reassign-workspaces
    i3-msg exec ~/.config/i3/scripts/reassign-workspaces.sh

Keybinding: Win+Shift+M
EOF
}

main() {
    if [ "$1" = "--help" ]; then
        usage
        exit 0
    fi

    # Check i3 is running
    check_i3_running

    # Get active project
    local project_name
    project_name=$(get_active_project 2>/dev/null) || project_name=""

    if [ -z "$project_name" ]; then
        echo -e "${YELLOW}⚠${NC} No active project - cannot reassign workspaces"
        log_warn "Attempted to reassign workspaces with no active project"
        exit 1
    fi

    log_info "Re-assigning workspaces for project: $project_name"

    # Get project JSON
    local project_file="${PROJECT_DIR}/${project_name}.json"
    if [ ! -f "$project_file" ]; then
        die "Project file not found: $project_file"
    fi

    local project_json
    project_json=$(cat "$project_file")

    # Apply workspace output assignments
    local workspace_outputs
    workspace_outputs=$(echo "$project_json" | jq -r '.workspaceOutputs // empty')

    if [ -z "$workspace_outputs" ] || [ "$workspace_outputs" = "null" ]; then
        echo -e "${YELLOW}⚠${NC} No workspace output assignments defined for project: $project_name"
        log_info "No workspace outputs to reassign"
        exit 0
    fi

    # Get list of currently connected outputs
    local connected_outputs
    connected_outputs=$(i3_cmd "-t get_outputs" | jq -r '.[] | select(.active == true) | .name')

    log_debug "Connected outputs: $connected_outputs"

    # Apply each workspace output assignment
    local ws_nums
    ws_nums=$(echo "$workspace_outputs" | jq -r 'keys[]' 2>/dev/null)

    local assigned_count=0
    local skipped_count=0

    while IFS= read -r ws_num; do
        if [ -n "$ws_num" ]; then
            local output
            output=$(echo "$workspace_outputs" | jq -r ".[\"$ws_num\"]")

            if [ -n "$output" ] && [ "$output" != "null" ]; then
                # Check if output is connected
                if echo "$connected_outputs" | grep -q "^${output}$"; then
                    log_debug "Assigning workspace $ws_num to output $output"
                    if i3_cmd "workspace $ws_num output $output"; then
                        ((assigned_count++))
                    else
                        log_warn "Failed to assign workspace $ws_num to output $output"
                    fi
                else
                    log_warn "Output $output not connected, skipping workspace $ws_num"
                    ((skipped_count++))
                fi
            fi
        fi
    done <<< "$ws_nums"

    echo -e "${GREEN}✓${NC} Reassigned $assigned_count workspace(s) for project: $project_name"

    if [ $skipped_count -gt 0 ]; then
        echo -e "${YELLOW}⚠${NC} Skipped $skipped_count workspace(s) (output not connected)"
    fi

    log_info "Workspace reassignment complete: assigned=$assigned_count skipped=$skipped_count"
}

main "$@"
