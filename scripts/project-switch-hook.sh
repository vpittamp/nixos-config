#!/usr/bin/env bash
# T002: Project Switch Hook - Dynamic Window Management
# Automatically shows/hides project-scoped windows when switching projects
#
# Usage: project-switch-hook.sh [project-id]
#   project-id: Target project to activate (empty = global mode)
#
# This script is called by project-set.sh after project activation

set -euo pipefail

# Dependencies will be injected by Nix when deployed via home-manager
# For now, use system paths for development
JQ="${JQ:-jq}"
I3MSG="${I3MSG:-i3-msg}"

# Configuration paths
PROJECT_FILE="${PROJECT_FILE:-$HOME/.config/i3-projects/projects.json}"
STATE_FILE="${STATE_FILE:-$HOME/.config/i3/current-project}"
LOG_FILE="${LOG_FILE:-$HOME/.config/i3/project-switch.log}"

# Enable logging
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG_FILE"
}

# T004/T016/T026: Window-to-project matching logic with tracking file support
# Extracts project ID from window title pattern AND tracking file
# Returns: JSON array of window objects with con_id and workspace
get_project_windows() {
    local project_id="$1"

    # T016: Validate input
    if [ -z "$project_id" ]; then
        log "ERROR: get_project_windows called with empty project_id"
        echo "[]"
        return 1
    fi

    # Query i3 window tree and extract windows with matching project tag
    local windows
    windows=$("$I3MSG" -t get_tree 2>&1)
    local exit_code=$?

    # T016: Handle i3-msg errors
    if [ $exit_code -ne 0 ]; then
        log "ERROR: Failed to query i3 window tree: $windows"
        echo "[]"
        return 1
    fi

    # T026: Parse window tree and match against BOTH title and tracking file
    WINDOW_MAP_FILE="$HOME/.config/i3/window-project-map.json"

    # Get all windows from i3 tree
    local all_windows
    all_windows=$(echo "$windows" | "$JQ" '
        [.. |
         select(type == "object") |
         select(has("window")) |
         select(.window != null) |
         {
            con_id: .id,
            window_id: .window,
            title: (.name // ""),
            wmClass: (.window_properties.class // ""),
            workspace: (.workspace // ""),
            # Extract project ID from title using regex
            project_id: (
                (.name // "") |
                if test("\\[PROJECT:[a-z0-9]+\\]") then
                    capture("\\[PROJECT:(?<proj>[a-z0-9]+)\\]") | .proj
                else
                    ""
                end
            )
        }]
    ' 2>/dev/null || echo "[]")

    # Load tracking file if it exists
    local tracked_windows
    if [ -f "$WINDOW_MAP_FILE" ]; then
        tracked_windows=$(cat "$WINDOW_MAP_FILE")
    else
        tracked_windows='{"windows":{}}'
    fi

    # Merge results: match by title OR tracking file
    echo "$all_windows" | "$JQ" --arg pid "$project_id" --argjson tracked "$tracked_windows" '
        map(
            # Match if title has project ID OR window is in tracking file
            if (.project_id == $pid) then
                .
            elif ($tracked.windows[.window_id | tostring].project_id == $pid) then
                . + {project_id: $pid, tracked: true}
            else
                empty
            end
        )
    ' 2>/dev/null || echo "[]"
}

# T005/T016: Scratchpad hiding mechanism with error handling
# Moves windows to scratchpad to hide them
hide_project_windows() {
    local project_id="$1"

    # T016: Validate input
    if [ -z "$project_id" ]; then
        log "ERROR: hide_project_windows called with empty project_id"
        return 1
    fi

    local windows
    windows=$(get_project_windows "$project_id")
    local get_windows_status=$?

    # T016: Handle get_project_windows errors
    if [ $get_windows_status -ne 0 ]; then
        log "ERROR: Failed to get windows for project: $project_id"
        return 1
    fi

    local count
    count=$(echo "$windows" | "$JQ" 'length' 2>/dev/null || echo "0")

    if [ "$count" -eq 0 ]; then
        log "No windows found for project: $project_id"
        return 0
    fi

    log "Hiding $count window(s) for project: $project_id"

    # Move each window to scratchpad with error handling
    echo "$windows" | "$JQ" -r '.[].con_id' 2>/dev/null | while read -r con_id; do
        if [ -n "$con_id" ]; then
            if "$I3MSG" "[con_id=\"$con_id\"] move scratchpad" > /dev/null 2>&1; then
                log "  Moved window $con_id to scratchpad"
            else
                log "  WARNING: Failed to move window $con_id to scratchpad"
            fi
        fi
    done
}

# T028: Register untracked windows for this project
# Finds windows matching project-scoped apps and registers them
register_untracked_windows() {
    local project_id="$1"
    local project_config="$2"

    WINDOW_MAP_FILE="$HOME/.config/i3/window-project-map.json"

    # Get list of project-scoped wmClasses for this project
    local project_classes
    project_classes=$("$JQ" -r --arg pid "$project_id" '
        .workspaces[]? |
        .applications[]? |
        select(.projectScoped == true) |
        .wmClass
    ' <<< "$project_config" 2>/dev/null | sort -u)

    if [ -z "$project_classes" ]; then
        return 0
    fi

    # For each project-scoped class, find windows and register if not tracked
    while read -r wm_class; do
        [ -z "$wm_class" ] && continue

        # Find all windows with this class
        local window_ids
        window_ids=$("$I3MSG" -t get_tree | "$JQ" -r --arg wmClass "$wm_class" '
            [.. |
             select(type == "object") |
             select(has("window")) |
             select(.window != null) |
             select(.window_properties.class == $wmClass)] |
            .[].window
        ' 2>/dev/null)

        # Register each window if not already tracked
        while read -r window_id; do
            [ -z "$window_id" ] || [ "$window_id" = "null" ] && continue

            # Check if already registered
            local is_tracked
            is_tracked=$("$JQ" --arg wid "$window_id" '.windows | has($wid)' "$WINDOW_MAP_FILE" 2>/dev/null)

            if [ "$is_tracked" != "true" ]; then
                # Register window
                local timestamp
                timestamp=$(date -Iseconds)
                "$JQ" --arg wid "$window_id" \
                      --arg pid "$project_id" \
                      --arg wmClass "$wm_class" \
                      --arg ts "$timestamp" \
                      '.windows[$wid] = {
                          project_id: $pid,
                          wmClass: $wmClass,
                          registered_at: $ts,
                          auto_registered: true
                      }' "$WINDOW_MAP_FILE" > "$WINDOW_MAP_FILE.tmp" && \
                mv "$WINDOW_MAP_FILE.tmp" "$WINDOW_MAP_FILE"

                log "  Auto-registered existing window $window_id ($wm_class) for project: $project_id"
            fi
        done <<< "$window_ids"
    done <<< "$project_classes"
}

# T006/T016: Workspace reassignment logic with error handling
# Moves windows from scratchpad to designated workspaces
show_project_windows() {
    local project_id="$1"

    # T016: Validate input
    if [ -z "$project_id" ]; then
        log "ERROR: show_project_windows called with empty project_id"
        return 1
    fi

    # T016: Validate project file exists
    if [ ! -f "$PROJECT_FILE" ]; then
        log "ERROR: Project configuration file not found: $PROJECT_FILE"
        return 1
    fi

    # Get project configuration to find workspace assignments
    local project_config
    project_config=$("$JQ" -r --arg pid "$project_id" '.projects[$pid]' "$PROJECT_FILE" 2>/dev/null)

    # T016: Handle missing project configuration
    if [ -z "$project_config" ] || [ "$project_config" = "null" ]; then
        log "ERROR: Project configuration not found: $project_id"
        return 1
    fi

    # T028: Register untracked windows before querying
    register_untracked_windows "$project_id" "$project_config"

    local windows
    windows=$(get_project_windows "$project_id")
    local get_windows_status=$?

    # T016: Handle get_project_windows errors
    if [ $get_windows_status -ne 0 ]; then
        log "ERROR: Failed to get windows for project: $project_id"
        return 1
    fi

    local count
    count=$(echo "$windows" | "$JQ" 'length' 2>/dev/null || echo "0")

    if [ "$count" -eq 0 ]; then
        log "No windows found for project: $project_id"
        return 0
    fi

    log "Showing $count window(s) for project: $project_id"

    # Move each window from scratchpad to its designated workspace
    echo "$windows" | "$JQ" -c '.[]' 2>/dev/null | while read -r window; do
        local con_id
        local wm_class
        local target_workspace

        con_id=$(echo "$window" | "$JQ" -r '.con_id' 2>/dev/null)
        wm_class=$(echo "$window" | "$JQ" -r '.wmClass' 2>/dev/null)

        # T016: Skip if window data is invalid
        if [ -z "$con_id" ] || [ "$con_id" = "null" ]; then
            log "  WARNING: Skipping window with invalid con_id"
            continue
        fi

        # Find target workspace for this window based on wmClass
        target_workspace=$(echo "$project_config" | "$JQ" -r --arg wmClass "$wm_class" '
            .workspaces[]? |
            .applications[]? |
            select(.wmClass == $wmClass) |
            .number // empty
        ' 2>/dev/null | head -1)

        # If no specific workspace found, use primary workspace
        if [ -z "$target_workspace" ] || [ "$target_workspace" = "null" ]; then
            target_workspace=$(echo "$project_config" | "$JQ" -r '.primaryWorkspace' 2>/dev/null)
        fi

        # T016: Validate target workspace before moving
        if [ -n "$target_workspace" ] && [ "$target_workspace" != "null" ]; then
            if "$I3MSG" "[con_id=\"$con_id\"] move to workspace number $target_workspace" > /dev/null 2>&1; then
                log "  Moved window $con_id to workspace $target_workspace"
                # Disable floating mode to ensure windows are tiled properly
                "$I3MSG" "[con_id=\"$con_id\"] floating disable" > /dev/null 2>&1 || true
            else
                log "  WARNING: Failed to move window $con_id to workspace $target_workspace"
            fi
        else
            log "  WARNING: No valid workspace found for window $con_id (wmClass: $wm_class)"
        fi
    done
}

# T047: Show all project windows (for global mode)
# Moves all project-scoped windows from scratchpad back to their workspaces
show_all_project_windows() {
    log "Showing all project windows (global mode)"

    # T016: Validate project file exists
    if [ ! -f "$PROJECT_FILE" ]; then
        log "ERROR: Project configuration file not found: $PROJECT_FILE"
        return 1
    fi

    # Get all project IDs
    local all_projects
    all_projects=$("$JQ" -r '.projects | keys[]' "$PROJECT_FILE" 2>/dev/null)

    # For each project, show its windows
    while read -r project_id; do
        [ -z "$project_id" ] && continue

        log "  Showing windows for project: $project_id"

        # Get project configuration
        local project_config
        project_config=$("$JQ" -r --arg pid "$project_id" '.projects[$pid]' "$PROJECT_FILE" 2>/dev/null)

        if [ -z "$project_config" ] || [ "$project_config" = "null" ]; then
            log "  WARNING: Project configuration not found: $project_id"
            continue
        fi

        # Register untracked windows
        register_untracked_windows "$project_id" "$project_config"

        # Get and show windows for this project
        local windows
        windows=$(get_project_windows "$project_id")
        local count
        count=$(echo "$windows" | "$JQ" 'length' 2>/dev/null || echo "0")

        if [ "$count" -eq 0 ]; then
            log "    No windows found for project: $project_id"
            continue
        fi

        log "    Found $count window(s) for project: $project_id"

        # Move each window from scratchpad to its workspace
        echo "$windows" | "$JQ" -c '.[]' 2>/dev/null | while read -r window; do
            local con_id
            local wm_class
            local target_workspace

            con_id=$(echo "$window" | "$JQ" -r '.con_id' 2>/dev/null)
            wm_class=$(echo "$window" | "$JQ" -r '.wmClass' 2>/dev/null)

            if [ -z "$con_id" ] || [ "$con_id" = "null" ]; then
                continue
            fi

            # Find target workspace
            target_workspace=$(echo "$project_config" | "$JQ" -r --arg wmClass "$wm_class" '
                .workspaces[]? |
                .applications[]? |
                select(.wmClass == $wmClass) |
                .number // empty
            ' 2>/dev/null | head -1)

            if [ -z "$target_workspace" ] || [ "$target_workspace" = "null" ]; then
                target_workspace=$(echo "$project_config" | "$JQ" -r '.primaryWorkspace' 2>/dev/null)
            fi

            if [ -n "$target_workspace" ] && [ "$target_workspace" != "null" ]; then
                "$I3MSG" "[con_id=\"$con_id\"] move to workspace number $target_workspace" > /dev/null 2>&1 || true
                # Disable floating mode to ensure windows are tiled properly
                "$I3MSG" "[con_id=\"$con_id\"] floating disable" > /dev/null 2>&1 || true
                log "      Moved window $con_id to workspace $target_workspace"
            fi
        done
    done <<< "$all_projects"

    log "All project windows shown"
}

# Main execution
main() {
    local old_project="${1:-}"
    local new_project="${2:-}"

    log "=== Project Switch Hook Started ==="
    log "Old project: ${old_project:-NONE}"
    log "New project: ${new_project:-GLOBAL MODE}"

    # T009: Accept old and new project as arguments instead of reading state
    # This fixes the race condition where state was already updated

    # If no change, skip
    if [ "$old_project" = "$new_project" ]; then
        log "No project change detected, skipping"
        return 0
    fi

    # T046/T047: If new_project is empty, show all windows (global mode)
    if [ -z "$new_project" ]; then
        log "Entering global mode - showing all windows"

        # Hide old project windows if applicable
        if [ -n "$old_project" ]; then
            hide_project_windows "$old_project"
        fi

        # Show all project windows
        show_all_project_windows
        log "=== Project Switch Hook Complete (Global Mode) ==="
        return 0
    fi

    # T014: Project switch workflow orchestration
    # 1. Hide old project windows
    if [ -n "$old_project" ]; then
        log "Hiding windows for project: $old_project"
        hide_project_windows "$old_project"
    fi

    # 2. Show new project windows
    if [ -n "$new_project" ]; then
        log "Showing windows for project: $new_project"
        show_project_windows "$new_project"
    fi

    log "=== Project Switch Hook Complete ==="
}

# Run main function
main "$@"
