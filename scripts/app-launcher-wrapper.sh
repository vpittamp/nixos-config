#!/usr/bin/env bash
#
# Application Launcher Wrapper Script
#
# Feature: 034-create-a-feature
# Purpose: Runtime execution layer for unified application launcher
#
# This script:
# 1. Loads registry JSON
# 2. Queries i3pm daemon for project context
# 3. Substitutes variables in parameters
# 4. Validates directory paths
# 5. Executes application with proper argument array
#
# Usage: app-launcher-wrapper.sh <app-name>
#
# Environment Variables:
#   DRY_RUN=1  - Show resolved command without executing
#   DEBUG=1    - Enable verbose logging
#   FALLBACK   - Override fallback behavior (skip/use_home/error)

set -euo pipefail

# Configuration
REGISTRY="${HOME}/.config/i3/application-registry.json"
LOG_FILE="${HOME}/.local/state/app-launcher.log"
LOG_MAX_LINES=1000

# Ensure log directory exists
mkdir -p "$(dirname "$LOG_FILE")"

# Logging function
log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp
    timestamp=$(date -Iseconds)

    echo "[$timestamp] $level $message" >> "$LOG_FILE"

    if [[ "${DEBUG:-0}" == "1" ]]; then
        echo "[$level] $message" >&2
    fi
}

# Error handling
error() {
    log "ERROR" "$@"
    echo "Error: $*" >&2
    exit 1
}

warn() {
    log "WARN" "$@"
    if [[ "${DEBUG:-0}" == "1" ]]; then
        echo "Warning: $*" >&2
    fi
}

# Check arguments
if [[ $# -lt 1 ]]; then
    error "Usage: app-launcher-wrapper.sh <app-name>"
fi

APP_NAME="$1"
log "INFO" "Launching: $APP_NAME"

# Check registry exists
if [[ ! -f "$REGISTRY" ]]; then
    error "Registry file not found: $REGISTRY
  Run 'sudo nixos-rebuild switch' to generate the registry."
fi

# Load application from registry
COMMAND=$(jq -r --arg name "$APP_NAME" \
    '.applications[] | select(.name == $name) | .command' \
    "$REGISTRY" 2>/dev/null || echo "")

if [[ -z "$COMMAND" ]]; then
    error "Application '$APP_NAME' not found in registry
  Registry: $REGISTRY
  Available applications: $(jq -r '.applications[].name' "$REGISTRY" | tr '\n' ' ')"
fi

# Load application properties
PARAMETERS=$(jq -r --arg name "$APP_NAME" \
    '.applications[] | select(.name == $name) | .parameters // ""' \
    "$REGISTRY")
FALLBACK_BEHAVIOR=$(jq -r --arg name "$APP_NAME" \
    '.applications[] | select(.name == $name) | .fallback_behavior // "skip"' \
    "$REGISTRY")
PREFERRED_WORKSPACE=$(jq -r --arg name "$APP_NAME" \
    '.applications[] | select(.name == $name) | .preferred_workspace // ""' \
    "$REGISTRY")

# Override fallback if environment variable set
if [[ -n "${FALLBACK:-}" ]]; then
    FALLBACK_BEHAVIOR="$FALLBACK"
fi

log "DEBUG" "Command: $COMMAND"
log "DEBUG" "Parameters: $PARAMETERS"
log "DEBUG" "Fallback: $FALLBACK_BEHAVIOR"

# Query daemon for project context
log "DEBUG" "Querying daemon for project context"
PROJECT_JSON=$(i3pm project current --json 2>/dev/null || echo '{}')

PROJECT_NAME=$(echo "$PROJECT_JSON" | jq -r '.name // ""')
PROJECT_DIR=$(echo "$PROJECT_JSON" | jq -r '.directory // ""')
PROJECT_DISPLAY_NAME=$(echo "$PROJECT_JSON" | jq -r '.display_name // ""')
PROJECT_ICON=$(echo "$PROJECT_JSON" | jq -r '.icon // ""')
SESSION_NAME="$PROJECT_NAME"
USER_HOME="${HOME}"

log "DEBUG" "Project name: ${PROJECT_NAME:-<none>}"
log "DEBUG" "Project directory: ${PROJECT_DIR:-<none>}"

# Validate project directory if present
if [[ -n "$PROJECT_DIR" ]]; then
    # Must be absolute path
    if [[ "$PROJECT_DIR" != /* ]]; then
        warn "Project directory is not absolute: $PROJECT_DIR"
        PROJECT_DIR=""
    fi

    # Must exist
    if [[ -n "$PROJECT_DIR" ]] && [[ ! -d "$PROJECT_DIR" ]]; then
        warn "Project directory does not exist: $PROJECT_DIR"
        PROJECT_DIR=""
    fi

    # Must not contain newlines or null bytes
    if [[ -n "$PROJECT_DIR" ]] && [[ "$PROJECT_DIR" == *$'\n'* ]]; then
        warn "Project directory contains newlines"
        PROJECT_DIR=""
    fi
fi

# Apply fallback if no project context and parameters reference project variables
if [[ -z "$PROJECT_NAME" ]] && [[ "$PARAMETERS" == *'$PROJECT'* ]]; then
    log "WARN" "No project active for $APP_NAME, applying fallback: $FALLBACK_BEHAVIOR"

    case "$FALLBACK_BEHAVIOR" in
        "skip")
            # Remove project variables from parameters
            PARAMETERS=$(echo "$PARAMETERS" | sed 's/\$PROJECT_DIR//g; s/\$PROJECT_NAME//g; s/\$SESSION_NAME//g' | xargs)
            log "INFO" "Fallback (skip): Removed project variables"
            ;;
        "use_home")
            # Substitute HOME for PROJECT_DIR
            PROJECT_DIR="$USER_HOME"
            PROJECT_NAME=""
            SESSION_NAME=""
            log "INFO" "Fallback (use_home): Using $USER_HOME"
            ;;
        "error")
            error "No project active and fallback behavior is 'error'
  This application requires a project context.
  Use 'i3pm project switch <name>' to activate a project."
            ;;
        *)
            error "Unknown fallback behavior: $FALLBACK_BEHAVIOR"
            ;;
    esac
fi

# Substitute variables in parameters
PARAM_RESOLVED="$PARAMETERS"

if [[ -n "$PROJECT_DIR" ]]; then
    PARAM_RESOLVED="${PARAM_RESOLVED//\$PROJECT_DIR/$PROJECT_DIR}"
    log "DEBUG" "Substituted \$PROJECT_DIR -> $PROJECT_DIR"
fi

if [[ -n "$PROJECT_NAME" ]]; then
    PARAM_RESOLVED="${PARAM_RESOLVED//\$PROJECT_NAME/$PROJECT_NAME}"
    log "DEBUG" "Substituted \$PROJECT_NAME -> $PROJECT_NAME"
fi

if [[ -n "$SESSION_NAME" ]]; then
    PARAM_RESOLVED="${PARAM_RESOLVED//\$SESSION_NAME/$SESSION_NAME}"
    log "DEBUG" "Substituted \$SESSION_NAME -> $SESSION_NAME"
fi

if [[ -n "$USER_HOME" ]]; then
    PARAM_RESOLVED="${PARAM_RESOLVED//\$HOME/$USER_HOME}"
    log "DEBUG" "Substituted \$HOME -> $USER_HOME"
fi

if [[ -n "$PROJECT_DISPLAY_NAME" ]]; then
    PARAM_RESOLVED="${PARAM_RESOLVED//\$PROJECT_DISPLAY_NAME/$PROJECT_DISPLAY_NAME}"
fi

if [[ -n "$PROJECT_ICON" ]]; then
    PARAM_RESOLVED="${PARAM_RESOLVED//\$PROJECT_ICON/$PROJECT_ICON}"
fi

if [[ -n "$PREFERRED_WORKSPACE" ]]; then
    PARAM_RESOLVED="${PARAM_RESOLVED//\$WORKSPACE/$PREFERRED_WORKSPACE}"
    log "DEBUG" "Substituted \$WORKSPACE -> $PREFERRED_WORKSPACE"
fi

# Build argument array
ARGS=("$COMMAND")
if [[ -n "$PARAM_RESOLVED" ]]; then
    # Split on whitespace but preserve the parameter structure
    # Note: Complex quoting is handled by using argument arrays
    read -ra PARAMS <<< "$PARAM_RESOLVED"
    ARGS+=("${PARAMS[@]}")
fi

log "INFO" "Resolved command: ${ARGS[*]}"

# Dry-run mode
if [[ "${DRY_RUN:-0}" == "1" ]]; then
    echo "[DRY RUN] Would execute:"
    echo "  Command: $COMMAND"
    echo "  Arguments: ${PARAM_RESOLVED:-<none>}"
    echo "  Project: ${PROJECT_NAME:-<none>} (${PROJECT_DIR:-<none>})"
    echo "  Full command: ${ARGS[*]}"
    exit 0
fi

# Verify command exists
if ! command -v "$COMMAND" &>/dev/null; then
    # Extract package name from registry if available
    NIX_PACKAGE=$(jq -r --arg name "$APP_NAME" \
        '.applications[] | select(.name == $name) | .nix_package // ""' \
        "$REGISTRY")

    error "Command not found: $COMMAND
  Package: ${NIX_PACKAGE:-<unknown>}
  Install package or add command to PATH."
fi

# Execute application (replaces this process with the application)
log "INFO" "Executing: ${ARGS[*]}"

# Rotate log if too large
if [[ -f "$LOG_FILE" ]]; then
    LINE_COUNT=$(wc -l < "$LOG_FILE")
    if [[ "$LINE_COUNT" -gt "$LOG_MAX_LINES" ]]; then
        tail -n $((LOG_MAX_LINES / 2)) "$LOG_FILE" > "${LOG_FILE}.tmp"
        mv "${LOG_FILE}.tmp" "$LOG_FILE"
        log "INFO" "Rotated log file (was $LINE_COUNT lines)"
    fi
fi

# Execute with exec to replace this process
exec "${ARGS[@]}"
