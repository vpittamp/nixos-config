#!/usr/bin/env bash
# i3-project-edit - Edit project JSON configuration
#
# Usage: i3-project-edit PROJECT_NAME

# shellcheck source=./i3-project-common.sh
source "${HOME}/.config/i3/scripts/common.sh" || exit 1

usage() {
    cat <<EOF
Usage: i3-project-edit PROJECT_NAME

Open the project JSON configuration file in your default editor.

Environment Variables:
    EDITOR    Editor to use (default: vim)

Arguments:
    PROJECT_NAME    Name of the project to edit

Examples:
    i3-project-edit nixos
    EDITOR=code i3-project-edit stacks
    EDITOR=nano i3-project-edit personal
EOF
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

    # Determine editor
    local editor="${EDITOR:-vim}"

    log_info "Opening project configuration in $editor: $project_name"

    # Save original modification time
    local orig_mtime
    orig_mtime=$(stat -c %Y "$project_file" 2>/dev/null || stat -f %m "$project_file" 2>/dev/null)

    # Open editor
    "$editor" "$project_file"

    # Check if file was modified
    local new_mtime
    new_mtime=$(stat -c %Y "$project_file" 2>/dev/null || stat -f %m "$project_file" 2>/dev/null)

    if [ "$orig_mtime" != "$new_mtime" ]; then
        log_info "Project configuration modified: $project_name"

        # Validate the edited JSON
        if command -v jq >/dev/null 2>&1; then
            if jq empty "$project_file" 2>/dev/null; then
                echo -e "${GREEN}✓${NC} JSON syntax valid"
            else
                echo -e "${YELLOW}⚠${NC} Warning: JSON syntax errors detected"
                log_warn "Invalid JSON syntax in edited file: $project_file"
            fi
        fi

        # Suggest validation
        echo ""
        echo "Run validation: i3-project-validate $project_name"

        # If this is the active project, suggest switching to reload
        local active_project
        active_project=$(get_active_project 2>/dev/null) || active_project=""
        if [ "$active_project" = "$project_name" ]; then
            echo "Project is active - changes will apply on next switch"
        fi
    else
        echo "No changes made"
    fi
}

main "$@"
