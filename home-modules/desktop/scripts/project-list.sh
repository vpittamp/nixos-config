#!/usr/bin/env bash
# i3-project-list - List all available projects
#
# Usage: i3-project-list [--format text|json]

# shellcheck source=./i3-project-common.sh
source "${HOME}/.config/i3/scripts/common.sh" || exit 1

usage() {
    cat <<EOF
Usage: i3-project-list [--format FORMAT]

List all available i3 projects.

Arguments:
    --format FORMAT    Output format: text (default) or json

Examples:
    i3-project-list
    i3-project-list --format json
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
    local active_project
    active_project=$(get_active_project 2>/dev/null) || active_project=""

    # Find all project files
    local project_files=()
    while IFS= read -r -d '' file; do
        project_files+=("$file")
    done < <(find "$PROJECT_DIR" -maxdepth 1 -name "*.json" -print0 2>/dev/null | sort -z)

    if [ ${#project_files[@]} -eq 0 ]; then
        if [ "$format" = "json" ]; then
            echo '{"projects": []}'
        else
            echo "No projects found in $PROJECT_DIR"
        fi
        exit 0
    fi

    if [ "$format" = "json" ]; then
        # JSON output
        echo "{"
        echo '  "active": "'$active_project'",'
        echo '  "projects": ['

        local first=true
        for file in "${project_files[@]}"; do
            if [ "$first" = true ]; then
                first=false
            else
                echo ","
            fi

            local proj_json
            proj_json=$(cat "$file")
            local name
            name=$(echo "$proj_json" | jq -r '.project.name')

            echo -n "    {"
            echo -n '"name": "'$name'", '
            echo -n '"active": '$([ "$name" = "$active_project" ] && echo "true" || echo "false")', '
            echo -n '"file": "'$file'", '
            echo -n '"data": '$proj_json
            echo -n "    }"
        done

        echo ""
        echo "  ]"
        echo "}"
    else
        # Text output
        echo "Available projects:"
        echo ""

        for file in "${project_files[@]}"; do
            local name display_name icon dir
            name=$(jq -r '.project.name' "$file")
            display_name=$(jq -r '.project.displayName // .project.name' "$file")
            icon=$(jq -r '.project.icon // ""' "$file")
            dir=$(jq -r '.project.directory' "$file")

            local active_marker=" "
            if [ "$name" = "$active_project" ]; then
                active_marker="*"
            fi

            printf " %s %s %s\n" "$active_marker" "$icon" "$display_name"
            printf "    Name: %s\n" "$name"
            printf "    Directory: %s\n" "$dir"
            echo ""
        done

        if [ -n "$active_project" ]; then
            echo "* = currently active project"
        fi
    fi
}

main "$@"
