#!/usr/bin/env bash
# i3 Project Manager - Common Library
# Shared functions for logging, error handling, and i3 IPC operations
#
# Usage: source ~/.config/i3/scripts/common.sh

# Configuration
PROJECT_DIR="${HOME}/.config/i3/projects"
ACTIVE_PROJECT_FILE="${HOME}/.config/i3/active-project"
APP_CLASSES_FILE="${HOME}/.config/i3/app-classes.json"
LOG_FILE="${HOME}/.config/i3/project-manager.log"
MAX_LOG_SIZE=1048576  # 1MB

# Enable debug mode if environment variable is set
DEBUG="${I3_PROJECT_DEBUG:-0}"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

#######################################
# Initialization
#######################################

# Ensure active-project file exists and is writable
# (It may be a read-only symlink from home-manager on first run)
if [ -L "$ACTIVE_PROJECT_FILE" ]; then
    # It's a symlink to nix store - remove it and create real file
    rm -f "$ACTIVE_PROJECT_FILE"
    touch "$ACTIVE_PROJECT_FILE"
elif [ ! -f "$ACTIVE_PROJECT_FILE" ]; then
    # Doesn't exist - create it
    touch "$ACTIVE_PROJECT_FILE" 2>/dev/null || true
fi

#######################################
# Logging Functions
#######################################

# Log message to file
# Arguments:
#   $1 - Log level (INFO, WARN, ERROR, DEBUG)
#   $@ - Log message
log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    # Rotate log if too large
    if [ -f "$LOG_FILE" ] && [ $(stat -f%z "$LOG_FILE" 2>/dev/null || stat -c%s "$LOG_FILE") -gt "$MAX_LOG_SIZE" ]; then
        mv "$LOG_FILE" "${LOG_FILE}.old"
    fi

    echo "[$timestamp] [$level] $message" >> "$LOG_FILE"

    # Print to stderr if debug mode or error
    if [ "$DEBUG" = "1" ] || [ "$level" = "ERROR" ]; then
        echo "[$level] $message" >&2
    fi
}

log_info() {
    log "INFO" "$@"
}

log_warn() {
    log "WARN" "$@"
}

log_error() {
    log "ERROR" "$@"
}

log_debug() {
    if [ "$DEBUG" = "1" ]; then
        log "DEBUG" "$@"
    fi
}

#######################################
# Error Handling Functions
#######################################

# Exit with error message
# Arguments:
#   $1 - Error message
#   $2 - Exit code (optional, default 1)
die() {
    local message="$1"
    local code="${2:-1}"
    log_error "$message"
    echo -e "${RED}Error: $message${NC}" >&2
    exit "$code"
}

# Check if command exists
# Arguments:
#   $1 - Command name
require_command() {
    local cmd="$1"
    if ! command -v "$cmd" &> /dev/null; then
        die "Required command '$cmd' not found. Please install it."
    fi
}

# Check if i3 is running
check_i3_running() {
    if ! i3-msg -t get_version &> /dev/null; then
        die "i3 window manager is not running or IPC socket is not accessible"
    fi
}

#######################################
# i3 IPC Helper Functions
#######################################

# Send i3 command with error handling
# Arguments:
#   $@ - i3 command
i3_cmd() {
    local cmd="$*"
    log_debug "Executing i3 command: $cmd"

    local output
    if ! output=$(i3-msg "$cmd" 2>&1); then
        log_error "i3 command failed: $cmd"
        log_error "Output: $output"
        return 1
    fi

    # Check if command reported success
    if echo "$output" | jq -e '.[] | select(.success == false)' &> /dev/null; then
        log_error "i3 command reported failure: $cmd"
        log_error "Output: $output"
        return 1
    fi

    echo "$output"
    return 0
}

# Send i3 tick event
# Arguments:
#   $1 - Event payload (plain string, NOT JSON)
i3_send_tick() {
    local payload="$1"
    log_debug "Sending tick event: $payload"
    i3-msg -t send_tick "$payload" &> /dev/null || log_warn "Failed to send tick event"
}

# Get all window IDs with specific mark (prefix match)
# Arguments:
#   $1 - Mark name (will match marks starting with this)
i3_get_windows_by_mark() {
    local mark="$1"
    # Match marks that START with the given mark name
    i3-msg -t get_tree | jq -r ".. | select(.marks? | length > 0) | select(.marks[] | startswith(\"$mark\")) | .window" 2>/dev/null | sort -u || true
}

# Move windows with mark to scratchpad
# Arguments:
#   $1 - Mark name
i3_hide_windows_by_mark() {
    local mark="$1"
    log_debug "Hiding windows with mark prefix: $mark"
    # Use regex to match marks that START with the project name
    # This handles both "project:nixos" and "project:nixos:term0" formats
    i3_cmd "[con_mark=\"^$mark\"] move scratchpad" > /dev/null
}

# Show windows with mark from scratchpad
# Arguments:
#   $1 - Mark name
i3_show_windows_by_mark() {
    local mark="$1"
    log_debug "Showing windows with mark: $mark"

    # Get all windows with this mark
    local windows
    windows=$(i3_get_windows_by_mark "$mark")

    if [ -z "$windows" ]; then
        log_debug "No windows found with mark: $mark"
        return 0
    fi

    # Show each window from scratchpad
    while IFS= read -r window_id; do
        [ -z "$window_id" ] && continue
        i3_cmd "[id=$window_id] scratchpad show" > /dev/null
    done <<< "$windows"
}

#######################################
# JSON Helper Functions
#######################################

# Validate JSON file
# Arguments:
#   $1 - JSON file path
validate_json() {
    local file="$1"

    if [ ! -f "$file" ]; then
        log_error "JSON file not found: $file"
        return 1
    fi

    if ! jq empty "$file" 2>/dev/null; then
        log_error "Invalid JSON in file: $file"
        return 1
    fi

    return 0
}

# Read project JSON
# Arguments:
#   $1 - Project name
get_project_json() {
    local project_name="$1"
    local project_file="${PROJECT_DIR}/${project_name}.json"

    if ! validate_json "$project_file"; then
        return 1
    fi

    cat "$project_file"
}

# Get active project name
get_active_project() {
    if [ ! -f "$ACTIVE_PROJECT_FILE" ]; then
        return 1
    fi

    local content
    content=$(cat "$ACTIVE_PROJECT_FILE")

    if [ -z "$content" ]; then
        return 1
    fi

    # Try to parse as JSON (Feature 013: new format)
    if command -v jq >/dev/null 2>&1; then
        local project_name
        project_name=$(echo "$content" | jq -r '.name // empty' 2>/dev/null)

        if [ -n "$project_name" ] && [ "$project_name" != "null" ]; then
            echo "$project_name"
            return 0
        fi
    fi

    # Fallback: treat as plain text (old format for backward compatibility)
    local project_name
    project_name=$(echo "$content" | tr -d '[:space:]')

    if [ -z "$project_name" ]; then
        return 1
    fi

    echo "$project_name"
}

#######################################
# Application Classification Functions
#######################################

# Check if application class is project-scoped
# Arguments:
#   $1 - WM_CLASS value
is_app_scoped() {
    local wm_class="$1"

    # Read from app-classes.json if it exists
    if [ -f "$APP_CLASSES_FILE" ]; then
        local scoped
        scoped=$(jq -r --arg class "$wm_class" \
            '.classes[] | select(.class == $class) | .scoped' \
            "$APP_CLASSES_FILE" 2>/dev/null)

        if [ -n "$scoped" ] && [ "$scoped" != "null" ]; then
            [ "$scoped" = "true" ] && return 0 || return 1
        fi
    fi

    # Default heuristics if not in config
    case "$wm_class" in
        *[Tt]erm*|*[Kk]onsole*|[Gg]hostty|[Aa]lacritty)
            return 0  # Terminals are scoped
            ;;
        [Cc]ode|*vim*|*emacs*|*[Ii]dea*)
            return 0  # Editors are scoped
            ;;
        *git*|lazygit|gitg)
            return 0  # Git tools are scoped
            ;;
        yazi|ranger|nnn)
            return 0  # File managers are scoped
            ;;
        *)
            return 1  # Default to global
            ;;
    esac
}

# Get default workspace for application class
# Arguments:
#   $1 - WM_CLASS value
get_app_workspace() {
    local wm_class="$1"

    if [ -f "$APP_CLASSES_FILE" ]; then
        local workspace
        workspace=$(jq -r --arg class "$wm_class" \
            '.classes[] | select(.class == $class) | .workspace // empty' \
            "$APP_CLASSES_FILE" 2>/dev/null)

        if [ -n "$workspace" ] && [ "$workspace" != "null" ]; then
            echo "$workspace"
            return 0
        fi
    fi

    # Return empty if no specific workspace configured
    return 1
}

#######################################
# Window ID Retrieval Functions
#######################################

# Get window ID for most recently launched window
# Arguments:
#   $1 - PID of launched process
#   $2 - Timeout in seconds (default 2)
get_window_id_by_pid() {
    local pid="$1"
    local timeout="${2:-2}"
    local start_time
    start_time=$(date +%s)

    log_debug "Waiting for window from PID $pid (timeout: ${timeout}s)"

    while true; do
        # Try to find window with xdotool
        local window_id
        window_id=$(xdotool search --pid "$pid" 2>/dev/null | head -1)

        if [ -n "$window_id" ]; then
            log_debug "Found window ID: $window_id"
            echo "$window_id"
            return 0
        fi

        # Check timeout
        local current_time
        current_time=$(date +%s)
        if [ $((current_time - start_time)) -ge "$timeout" ]; then
            log_warn "Timeout waiting for window from PID $pid"
            return 1
        fi

        sleep 0.1
    done
}

# Mark window with project mark
# Arguments:
#   $1 - Window ID
#   $2 - Project name
mark_window_with_project() {
    local window_id="$1"
    local project_name="$2"
    local mark="project:${project_name}"

    log_debug "Marking window $window_id with $mark"
    i3_cmd "[id=$window_id] mark --add \"$mark\"" > /dev/null
}

#######################################
# Initialization
#######################################

# Ensure required directories exist
mkdir -p "$PROJECT_DIR"
mkdir -p "$(dirname "$LOG_FILE")"

# Ensure active project file exists
touch "$ACTIVE_PROJECT_FILE"

# Check required commands
require_command "jq"
require_command "i3-msg"

log_debug "Common library loaded successfully"
