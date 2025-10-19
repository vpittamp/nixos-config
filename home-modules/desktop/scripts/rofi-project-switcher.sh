#!/usr/bin/env bash
# rofi-project-switcher - Interactive project switcher using rofi
#
# Usage: rofi-project-switcher

# shellcheck source=./i3-project-common.sh
source "${HOME}/.config/i3/scripts/common.sh" || exit 1

main() {
    # Check if rofi is available
    if ! command -v rofi >/dev/null 2>&1; then
        die "rofi is not installed"
    fi

    # Get list of projects
    if [ ! -d "$PROJECT_DIR" ]; then
        die "Project directory does not exist: $PROJECT_DIR"
    fi

    # Get active project
    local active_project
    active_project=$(get_active_project 2>/dev/null) || active_project=""

    # Build project list with icons and display names
    local project_list=""
    local project_names=()

    # Add "Clear Project" option at the top
    if [ -n "$active_project" ]; then
        project_list="  Clear Project (Return to Global Mode)\n"
        project_names+=("__CLEAR__")
    fi

    # Scan for project JSON files
    while IFS= read -r -d '' project_file; do
        local project_name
        project_name=$(basename "$project_file" .json)

        if [ -f "$project_file" ]; then
            local project_json
            project_json=$(cat "$project_file")

            local display_name icon
            display_name=$(echo "$project_json" | jq -r '.project.displayName // .project.name')
            icon=$(echo "$project_json" | jq -r '.project.icon // ""')

            # Mark active project
            local marker=""
            if [ "$project_name" = "$active_project" ]; then
                marker=" (active)"
            fi

            # Build display line
            if [ -n "$icon" ]; then
                project_list+="$icon  ${display_name}${marker}\n"
            else
                project_list+="  ${display_name}${marker}\n"
            fi

            project_names+=("$project_name")
        fi
    done < <(find "$PROJECT_DIR" -maxdepth 1 -name "*.json" -print0 | sort -z)

    if [ ${#project_names[@]} -eq 0 ] && [ -z "$active_project" ]; then
        echo "No projects found"
        exit 0
    fi

    # Show rofi menu
    local selection
    selection=$(echo -e "$project_list" | rofi -dmenu -i -p "Project" -theme-str 'window {width: 40%;}' -no-custom)

    if [ -z "$selection" ]; then
        # User cancelled
        exit 0
    fi

    # Find which project was selected by matching the display line
    local selected_index=-1
    local index=0

    while IFS= read -r line; do
        if [ "$line" = "$selection" ]; then
            selected_index=$index
            break
        fi
        ((index++))
    done <<< "$(echo -e "$project_list")"

    if [ $selected_index -lt 0 ] || [ $selected_index -ge ${#project_names[@]} ]; then
        log_error "Invalid selection index: $selected_index"
        exit 1
    fi

    local selected_project="${project_names[$selected_index]}"

    # Handle selection
    if [ "$selected_project" = "__CLEAR__" ]; then
        log_info "Clearing active project via rofi"
        exec "$HOME/.config/i3/scripts/project-clear.sh"
    elif [ "$selected_project" = "$active_project" ]; then
        # Already active, nothing to do
        echo "Project '$selected_project' is already active"
    else
        log_info "Switching to project via rofi: $selected_project"
        exec "$HOME/.config/i3/scripts/project-switch.sh" "$selected_project"
    fi
}

main "$@"
