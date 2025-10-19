#!/usr/bin/env bash
# i3-project-validate - Validate project JSON configuration
#
# Usage: i3-project-validate PROJECT_NAME

# shellcheck source=./i3-project-common.sh
source "${HOME}/.config/i3/scripts/common.sh" || exit 1

usage() {
    cat <<EOF
Usage: i3-project-validate PROJECT_NAME

Validate project JSON configuration file.

Checks performed:
  - JSON syntax validity
  - Required fields present (version, project.name, project.directory)
  - Valid i3 layout syntax if workspaces defined
  - Valid workspace output assignments
  - Valid application class references

Arguments:
    PROJECT_NAME    Name of the project to validate

Examples:
    i3-project-validate nixos
    i3-project-validate stacks
EOF
}

validate_workspace_layout() {
    local workspace_data="$1"
    local workspace_num="$2"

    # Check if layout field exists and is an object or array
    local layout
    layout=$(echo "$workspace_data" | jq -r '.layout // empty')

    if [ -n "$layout" ]; then
        # Basic i3 layout validation - should be valid JSON
        if ! echo "$layout" | jq empty 2>/dev/null; then
            log_error "Workspace $workspace_num: Invalid i3 layout JSON"
            return 1
        fi

        # Check for required i3 layout fields
        local has_nodes
        has_nodes=$(echo "$layout" | jq 'has("nodes")' 2>/dev/null)
        if [ "$has_nodes" != "true" ]; then
            log_warn "Workspace $workspace_num: Layout missing 'nodes' array (may not restore correctly)"
        fi
    fi

    return 0
}

validate_project_json() {
    local project_file="$1"
    local project_name="$2"
    local errors=0

    log_info "Validating project: $project_name"

    # Read project JSON
    local project_json
    project_json=$(cat "$project_file")

    # Validate JSON syntax
    if ! echo "$project_json" | jq empty 2>/dev/null; then
        log_error "Invalid JSON syntax in $project_file"
        return 1
    fi

    # Check required fields
    local version project_name_field project_dir
    version=$(echo "$project_json" | jq -r '.version // empty')
    project_name_field=$(echo "$project_json" | jq -r '.project.name // empty')
    project_dir=$(echo "$project_json" | jq -r '.project.directory // empty')

    if [ -z "$version" ]; then
        log_error "Missing required field: version"
        ((errors++))
    fi

    if [ -z "$project_name_field" ]; then
        log_error "Missing required field: project.name"
        ((errors++))
    elif [ "$project_name_field" != "$project_name" ]; then
        log_error "Project name mismatch: filename=$project_name, json=$project_name_field"
        ((errors++))
    fi

    if [ -z "$project_dir" ]; then
        log_error "Missing required field: project.directory"
        ((errors++))
    elif [ ! -d "$project_dir" ]; then
        log_warn "Project directory does not exist: $project_dir"
    fi

    # Validate workspaces if present
    local workspace_count
    workspace_count=$(echo "$project_json" | jq '.workspaces | length' 2>/dev/null || echo "0")

    if [ "$workspace_count" -gt 0 ]; then
        log_info "Validating $workspace_count workspace(s)..."

        # Iterate over workspace keys
        local workspace_nums
        workspace_nums=$(echo "$project_json" | jq -r '.workspaces | keys[]' 2>/dev/null)

        while IFS= read -r ws_num; do
            local ws_data
            ws_data=$(echo "$project_json" | jq ".workspaces[\"$ws_num\"]")

            # Validate workspace layout if present
            if ! validate_workspace_layout "$ws_data" "$ws_num"; then
                ((errors++))
            fi

            # Validate launchCommands if present
            local launch_cmds
            launch_cmds=$(echo "$ws_data" | jq '.launchCommands // empty')
            if [ -n "$launch_cmds" ]; then
                if ! echo "$launch_cmds" | jq -e 'type == "array"' >/dev/null 2>&1; then
                    log_error "Workspace $ws_num: launchCommands must be an array"
                    ((errors++))
                fi
            fi
        done <<< "$workspace_nums"
    fi

    # Validate workspaceOutputs if present
    local output_count
    output_count=$(echo "$project_json" | jq '.workspaceOutputs | length' 2>/dev/null || echo "0")

    if [ "$output_count" -gt 0 ]; then
        log_info "Validating $output_count workspace output assignment(s)..."

        # Check that workspace numbers are valid
        local output_keys
        output_keys=$(echo "$project_json" | jq -r '.workspaceOutputs | keys[]' 2>/dev/null)

        while IFS= read -r ws_num; do
            if ! [[ "$ws_num" =~ ^[0-9]+$ ]]; then
                log_error "Invalid workspace number in workspaceOutputs: $ws_num"
                ((errors++))
            fi

            local output_name
            output_name=$(echo "$project_json" | jq -r ".workspaceOutputs[\"$ws_num\"]")
            if [ -z "$output_name" ]; then
                log_error "Empty output name for workspace $ws_num"
                ((errors++))
            fi
        done <<< "$output_keys"
    fi

    # Validate appClasses if present
    local app_class_count
    app_class_count=$(echo "$project_json" | jq '.appClasses | length' 2>/dev/null || echo "0")

    if [ "$app_class_count" -gt 0 ]; then
        log_info "Validating $app_class_count application class override(s)..."

        # Check that appClasses is an array of objects
        if ! echo "$project_json" | jq -e '.appClasses | type == "array"' >/dev/null 2>&1; then
            log_error "appClasses must be an array"
            ((errors++))
        else
            # Validate each app class entry
            local idx=0
            while true; do
                local app_class
                app_class=$(echo "$project_json" | jq -r ".appClasses[$idx] // empty")
                [ -z "$app_class" ] && break

                # Check for required 'class' field
                local class_name
                class_name=$(echo "$app_class" | jq -r '.class // empty')
                if [ -z "$class_name" ]; then
                    log_error "appClasses[$idx]: Missing 'class' field"
                    ((errors++))
                fi

                # Check for 'scoped' field
                local scoped
                scoped=$(echo "$app_class" | jq -r '.scoped // empty')
                if [ -z "$scoped" ]; then
                    log_warn "appClasses[$idx]: Missing 'scoped' field (will use default)"
                elif [ "$scoped" != "true" ] && [ "$scoped" != "false" ]; then
                    log_error "appClasses[$idx]: 'scoped' must be true or false"
                    ((errors++))
                fi

                ((idx++))
            done
        fi
    fi

    # Summary
    if [ "$errors" -eq 0 ]; then
        echo -e "${GREEN}✓${NC} Validation passed: $project_name"
        log_info "Validation passed for project: $project_name"
        return 0
    else
        echo -e "${RED}✗${NC} Validation failed: $errors error(s) found"
        log_error "Validation failed for project $project_name: $errors error(s)"
        return 1
    fi
}

main() {
    if [ "$1" = "--help" ] || [ -z "$1" ]; then
        usage
        exit 0
    fi

    local project_name="$1"

    # Validate project name
    if ! [[ "$project_name" =~ ^[a-zA-Z0-9_-]+$ ]]; then
        die "Invalid project name: must contain only alphanumeric characters, dash, or underscore"
    fi

    # Check if project exists
    local project_file="${PROJECT_DIR}/${project_name}.json"
    if [ ! -f "$project_file" ]; then
        die "Project not found: $project_name (expected file: $project_file)"
    fi

    # Validate the project
    validate_project_json "$project_file" "$project_name"
}

main "$@"
