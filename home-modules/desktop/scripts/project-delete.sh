#!/usr/bin/env bash
# i3-project-delete - Delete project configuration
#
# Usage: i3-project-delete PROJECT_NAME [--force]

# shellcheck source=./i3-project-common.sh
source "${HOME}/.config/i3/scripts/common.sh" || exit 1

usage() {
    cat <<EOF
Usage: i3-project-delete PROJECT_NAME [--force]

Delete an i3 project configuration file.

Arguments:
    PROJECT_NAME    Name of the project to delete
    --force         Skip confirmation prompt

Examples:
    i3-project-delete test-project
    i3-project-delete old-project --force
EOF
}

main() {
    local project_name="$1"
    local force=false

    if [ "$2" = "--force" ]; then
        force=true
    fi

    if [ -z "$project_name" ] || [ "$project_name" = "--help" ]; then
        usage
        exit $([ "$project_name" = "--help" ] && echo 0 || echo 1)
    fi

    local project_file="${PROJECT_DIR}/${project_name}.json"

    if [ ! -f "$project_file" ]; then
        die "Project '$project_name' does not exist"
    fi

    # Check if project is currently active
    local active_project
    if active_project=$(get_active_project 2>/dev/null); then
        if [ "$active_project" = "$project_name" ]; then
            log_warn "Clearing active project before deletion"
            echo "Project '$project_name' is currently active. Clearing..." >&2
            echo "" > "$ACTIVE_PROJECT_FILE"
        fi
    fi

    # Confirm deletion
    if [ "$force" != true ]; then
        echo "Are you sure you want to delete project '$project_name'? (y/N) " >&2
        read -r response
        if [[ ! "$response" =~ ^[Yy]$ ]]; then
            echo "Deletion cancelled." >&2
            exit 0
        fi
    fi

    # Delete project file
    rm "$project_file"
    log_info "Deleted project: $project_name"
    echo -e "${GREEN}✓${NC} Deleted project '$project_name'"
}

main "$@"
