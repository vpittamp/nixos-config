#!/usr/bin/env bash
# i3-project-current - Display currently active project
#
# Usage: i3-project-current [--format text|json]

# shellcheck source=./i3-project-common.sh
source "${HOME}/.config/i3/scripts/common.sh" || exit 1

usage() {
    cat <<EOF
Usage: i3-project-current [--format FORMAT]

Display the currently active project.

Arguments:
    --format FORMAT    Output format: text (default) or json

Examples:
    i3-project-current
    i3-project-current --format json
EOF
}

main() {
    local format="text"

    if [ "$1" = "--format" ]; then
        format="$2"
    elif [ "$1" = "--help" ]; then
        usage
        exit 0
    fi

    # Get active project
    local project_name
    project_name=$(get_active_project 2>/dev/null) || project_name=""

    if [ -z "$project_name" ]; then
        if [ "$format" = "json" ]; then
            echo '{"active": false, "name": null}'
        else
            echo "No active project (global mode)"
        fi
        exit 0
    fi

    # Get project details
    local project_file="${PROJECT_DIR}/${project_name}.json"
    if [ ! -f "$project_file" ]; then
        log_error "Active project file not found: $project_name"
        if [ "$format" = "json" ]; then
            echo '{"active": false, "name": null, "error": "project file not found"}'
        else
            echo "Error: Active project '$project_name' configuration not found"
        fi
        exit 1
    fi

    local project_json
    project_json=$(cat "$project_file")

    if [ "$format" = "json" ]; then
        # JSON output
        echo "$project_json" | jq -c '{
            active: true,
            name: .project.name,
            displayName: .project.displayName,
            icon: .project.icon,
            directory: .project.directory
        }'
    else
        # Text output
        local display_name icon dir
        display_name=$(echo "$project_json" | jq -r '.project.displayName // .project.name')
        icon=$(echo "$project_json" | jq -r '.project.icon // ""')
        dir=$(echo "$project_json" | jq -r '.project.directory')

        echo "Active project: $icon $display_name"
        echo "  Name: $project_name"
        echo "  Directory: $dir"
    fi
}

main "$@"
