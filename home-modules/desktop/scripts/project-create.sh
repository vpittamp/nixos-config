#!/usr/bin/env bash
# i3-project-create - Create new project configuration
#
# Usage: i3-project-create --name NAME --dir DIRECTORY [--icon ICON] [--display-name NAME]
#
# Creates a JSON configuration file for a new project

# shellcheck source=./i3-project-common.sh
source "${HOME}/.config/i3/scripts/common.sh" || exit 1

#######################################
# Print usage information
#######################################
usage() {
    cat <<EOF
Usage: i3-project-create --name NAME --dir DIRECTORY [OPTIONS]

Create a new i3 project configuration.

Required Arguments:
    --name NAME            Project identifier (alphanumeric, dash, underscore)
    --dir DIRECTORY        Project working directory (absolute path)

Optional Arguments:
    --icon ICON            Icon for project display (emoji or nerd font)
    --display-name NAME    Human-readable project name (defaults to name)
    --help                 Show this help message

Examples:
    # Create minimal project
    i3-project-create --name nixos --dir /etc/nixos

    # Create project with icon and display name
    i3-project-create --name stacks --dir ~/code/stacks \\
        --icon "" --display-name "Stacks Project"

    # Create project with custom display name
    i3-project-create --name api --dir ~/code/api-gateway \\
        --display-name "API Gateway"

Project files are created in: ~/.config/i3/projects/
EOF
}

#######################################
# Validate project name
# Arguments:
#   $1 - Project name
#######################################
validate_project_name() {
    local name="$1"

    if [ -z "$name" ]; then
        die "Project name cannot be empty"
    fi

    # Check for invalid characters
    if ! [[ "$name" =~ ^[a-zA-Z0-9_-]+$ ]]; then
        die "Project name must contain only alphanumeric characters, dash, or underscore: $name"
    fi

    return 0
}

#######################################
# Validate directory path
# Arguments:
#   $1 - Directory path
#######################################
validate_directory() {
    local dir="$1"

    if [ -z "$dir" ]; then
        die "Project directory cannot be empty"
    fi

    # Check if absolute path
    if [[ "$dir" != /* ]]; then
        die "Project directory must be an absolute path: $dir"
    fi

    # Warn if directory doesn't exist (but allow creation)
    if [ ! -d "$dir" ]; then
        log_warn "Directory does not exist: $dir"
        echo "Warning: Directory '$dir' does not exist" >&2
        echo "Project will be created anyway. Directory can be created later." >&2
    fi

    return 0
}

#######################################
# Main script logic
#######################################
main() {
    # Parse command line arguments
    local project_name=""
    local project_dir=""
    local project_icon=""
    local display_name=""

    while [[ $# -gt 0 ]]; do
        case $1 in
            --name)
                project_name="$2"
                shift 2
                ;;
            --dir)
                project_dir="$2"
                shift 2
                ;;
            --icon)
                project_icon="$2"
                shift 2
                ;;
            --display-name)
                display_name="$2"
                shift 2
                ;;
            --help)
                usage
                exit 0
                ;;
            *)
                echo "Error: Unknown option: $1" >&2
                echo "Try 'i3-project-create --help' for more information." >&2
                exit 1
                ;;
        esac
    done

    # Validate required arguments
    if [ -z "$project_name" ]; then
        echo "Error: Missing required argument: --name" >&2
        usage
        exit 1
    fi

    if [ -z "$project_dir" ]; then
        echo "Error: Missing required argument: --dir" >&2
        usage
        exit 1
    fi

    # Validate inputs
    validate_project_name "$project_name"
    validate_directory "$project_dir"

    # Set defaults
    if [ -z "$display_name" ]; then
        display_name="$project_name"
    fi

    # Check if project already exists
    local project_file="${PROJECT_DIR}/${project_name}.json"
    if [ -f "$project_file" ]; then
        die "Project '$project_name' already exists at: $project_file"
    fi

    # Create project JSON with minimal schema
    log_info "Creating project: $project_name"

    local temp_file="${project_file}.tmp"
    cat > "$temp_file" <<EOF
{
  "version": "1.0",
  "project": {
    "name": "$project_name",
    "displayName": "$display_name",
    "icon": "$project_icon",
    "directory": "$project_dir"
  },
  "workspaces": {},
  "workspaceOutputs": {},
  "appClasses": []
}
EOF

    # Validate generated JSON
    if ! validate_json "$temp_file"; then
        rm -f "$temp_file"
        die "Failed to generate valid JSON for project"
    fi

    # Atomic rename
    mv "$temp_file" "$project_file"

    log_info "Project created successfully: $project_file"
    echo -e "${GREEN}✓${NC} Created project '$project_name' at ${BLUE}$project_file${NC}"

    # Show next steps
    cat <<EOF

Next steps:
  1. Switch to project:     i3-project-switch $project_name
  2. Edit configuration:    i3-project-edit $project_name
  3. Validate configuration: i3-project-validate $project_name

To add workspace layouts and launch commands, edit the JSON file.
See ~/.config/i3/projects/README.md for examples.
EOF
}

# Run main function
main "$@"
