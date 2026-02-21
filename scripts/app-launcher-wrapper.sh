#!/usr/bin/env bash
#
# Unified Application Launcher
#
# Feature: 056-pwa-window-tracking-fix
# Purpose: Consolidated launch wrapper for ALL applications (regular apps, PWAs, VS Code)
#
# This script provides:
# 1. Unified I3PM_* environment variable injection for ALL app types
# 2. Launch notification to daemon (Feature 041)
# 3. Workspace assignment via I3PM_TARGET_WORKSPACE
# 4. systemd-run process isolation
# 5. Project context propagation
#
# Usage: app-launcher-wrapper.sh <app-name>
#
# Supported App Types:
# - Regular applications (firefox, thunar, btop, etc.)
# - Firefox PWAs (claude-pwa, youtube-pwa, etc.) - deterministic class matching
# - VS Code (multi-instance with project context)
# - Terminal apps (alacritty, ghostty with sesh integration)
#
# Environment Variables:
#   DRY_RUN=1  - Show resolved command without executing
#   DEBUG=1    - Enable verbose logging

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

# Escape a literal string for use in regex matching.
escape_regex() {
    local input="$1"
    printf '%s' "$input" | sed -e 's/[][(){}.^$*+?|\\/]/\\&/g'
}

normalize_session_name_key() {
    local input="$1"
    # Treat stacks/main, stacks_main, and stacks-main as equivalent identifiers.
    printf '%s' "$input" \
        | tr '[:upper:]' '[:lower:]' \
        | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//'
}

normalize_connection_key() {
    local input="$1"
    printf '%s' "$input" \
        | tr '[:upper:]' '[:lower:]' \
        | sed -E 's/[^a-z0-9@._:-]+/-/g'
}

# Find an existing scoped/global window ID by unified mark format:
#   scope:app:project:window_id
# Optional context mark filter:
#   ctx:qualified_project::variant::connection_key
find_window_id_by_mark() {
    local scope="$1"
    local app_name="$2"
    local project_name="$3"
    local context_key="${4:-}"

    if ! command -v swaymsg >/dev/null 2>&1; then
        return 1
    fi

    local project_re mark_re tree_json window_id ctx_mark
    project_re=$(escape_regex "$project_name")
    mark_re="^${scope}:${app_name}:${project_re}:[0-9]+$"
    ctx_mark=""
    if [[ -n "$context_key" ]]; then
        ctx_mark="ctx:${context_key}"
    fi

    tree_json=$(swaymsg -t get_tree -r 2>/dev/null || true)
    if [[ -z "$tree_json" ]]; then
        return 1
    fi

    window_id=$(
        printf '%s\n' "$tree_json" \
            | jq -r --arg mark_re "$mark_re" --arg ctx_mark "$ctx_mark" '
                first(
                    recurse(.nodes[]?, .floating_nodes[]?)
                    | select((.window != null) or (.app_id != null))
                    | select((.marks // []) | any(test($mark_re)))
                    | select(($ctx_mark == "") or ((.marks // []) | index($ctx_mark)))
                    | .id
                ) // empty
            ' 2>/dev/null || true
    )

    if [[ "$window_id" =~ ^[0-9]+$ ]]; then
        printf '%s\n' "$window_id"
        return 0
    fi

    return 1
}

# Focus an existing project-scoped window if one is already open.
focus_existing_project_window() {
    local scope="$1"
    local app_name="$2"
    local project_name="$3"
    local context_key="${4:-}"

    local window_id
    if ! window_id=$(find_window_id_by_mark "$scope" "$app_name" "$project_name" "$context_key"); then
        return 1
    fi

    local focus_result
    focus_result=$(swaymsg "[con_id=${window_id}] focus" 2>/dev/null || true)
    if printf '%s\n' "$focus_result" | jq -e 'type == "array" and any(.[]; .success == true)' >/dev/null 2>&1; then
        log "INFO" "Focused existing window $window_id for ${scope}:${app_name}:${project_name}"
        return 0
    fi

    warn "Failed to focus existing window $window_id for ${scope}:${app_name}:${project_name}"
    return 1
}

# Focus an existing project-scoped terminal window for a specific remote session.
focus_existing_remote_session_window() {
    local scope="$1"
    local app_name="$2"
    local project_name="$3"
    local session_name="$4"
    local context_key="${5:-}"

    if [[ -z "$session_name" ]]; then
        return 1
    fi

    if ! command -v swaymsg >/dev/null 2>&1; then
        return 1
    fi

    local project_re mark_re tree_json window_id="" session_lc session_key window_rows ctx_mark
    project_re=$(escape_regex "$project_name")
    mark_re="^${scope}:${app_name}:${project_re}:[0-9]+$"
    session_lc=$(printf '%s' "$session_name" | tr '[:upper:]' '[:lower:]')
    session_key=$(normalize_session_name_key "$session_name")
    ctx_mark=""
    if [[ -n "$context_key" ]]; then
        ctx_mark="ctx:${context_key}"
    fi

    tree_json=$(swaymsg -t get_tree -r 2>/dev/null || true)
    if [[ -z "$tree_json" ]]; then
        return 1
    fi

    window_rows=$(
        printf '%s\n' "$tree_json" \
            | jq -r --arg mark_re "$mark_re" --arg ctx_mark "$ctx_mark" '
                recurse(.nodes[]?, .floating_nodes[]?)
                | select((.window != null) or (.app_id != null))
                | select((.marks // []) | any(test($mark_re)))
                | select(($ctx_mark == "") or ((.marks // []) | index($ctx_mark)))
                | [(.id // 0), (.pid // 0), (.name // ""), (.window_properties.title // ""), (.window_properties.instance // "")]
                | @tsv
            ' 2>/dev/null || true
    )

    if [[ -z "$window_rows" ]]; then
        return 1
    fi

    # Prefer exact env-level match when the terminal was launched with an explicit
    # remote session override (I3PM_REMOTE_SESSION_NAME).
    local candidate_id candidate_pid candidate_name candidate_title candidate_instance pid_session_name pid_session_key fallback_id combined_text combined_text_lc combined_session_name combined_session_key
    fallback_id=""
    while IFS=$'\t' read -r candidate_id candidate_pid candidate_name candidate_title candidate_instance; do
        if [[ ! "$candidate_id" =~ ^[0-9]+$ ]]; then
            continue
        fi

        if [[ "$candidate_pid" =~ ^[0-9]+$ ]] && [[ "$candidate_pid" -gt 1 ]] && [[ -r "/proc/${candidate_pid}/environ" ]]; then
            pid_session_name=$(
                { tr '\0' '\n' < "/proc/${candidate_pid}/environ" 2>/dev/null || true; } \
                    | sed -n 's/^I3PM_REMOTE_SESSION_NAME=//p' \
                    | head -n1
            )
            pid_session_key=$(normalize_session_name_key "$pid_session_name")
            if [[ -n "$pid_session_name" ]] && [[ "$pid_session_name" == "$session_name" || "$pid_session_key" == "$session_key" ]]; then
                window_id="$candidate_id"
                break
            fi
        fi

        if [[ -z "$fallback_id" ]]; then
            combined_text="${candidate_name} ${candidate_title} ${candidate_instance}"
            combined_text_lc=$(printf '%s' "$combined_text" | tr '[:upper:]' '[:lower:]')
            combined_session_name="${candidate_name} ${candidate_title} ${candidate_instance}"
            combined_session_key=$(normalize_session_name_key "$combined_session_name")
            if [[ "$combined_text_lc" == *"$session_lc"* ]]; then
                fallback_id="$candidate_id"
            elif [[ -n "$session_key" ]] && [[ "$combined_session_key" == *"$session_key"* ]]; then
                fallback_id="$candidate_id"
            fi
        fi
    done <<< "$window_rows"

    if [[ -z "$window_id" ]]; then
        window_id="$fallback_id"
    fi

    if [[ ! "${window_id:-}" =~ ^[0-9]+$ ]]; then
        return 1
    fi

    local focus_result
    focus_result=$(swaymsg "[con_id=${window_id}] focus" 2>/dev/null || true)
    if printf '%s\n' "$focus_result" | jq -e 'type == "array" and any(.[]; .success == true)' >/dev/null 2>&1; then
        log "INFO" "Focused existing remote session window $window_id for ${scope}:${app_name}:${project_name}:${session_name}"
        return 0
    fi

    warn "Failed to focus remote session window $window_id for ${scope}:${app_name}:${project_name}:${session_name}"
    return 1
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
APP_JSON=$(jq --arg name "$APP_NAME" \
    '.applications[] | select(.name == $name)' \
    "$REGISTRY" 2>/dev/null || echo "{}")

if [[ "$APP_JSON" == "{}" ]]; then
    error "Application '$APP_NAME' not found in registry
  Registry: $REGISTRY
  Available applications: $(jq -r '.applications[].name' "$REGISTRY" | tr '\n' ' ')"
fi

# Extract application properties
COMMAND=$(echo "$APP_JSON" | jq -r '.command')
PARAMETERS=$(echo "$APP_JSON" | jq -r 'if .parameters then (.parameters | join(" ")) else "" end')
FALLBACK_BEHAVIOR=$(echo "$APP_JSON" | jq -r '.fallback_behavior // "skip"')
PREFERRED_WORKSPACE=$(echo "$APP_JSON" | jq -r '.preferred_workspace // ""')
SCOPE=$(echo "$APP_JSON" | jq -r '.scope // "global"')
EXPECTED_CLASS=$(echo "$APP_JSON" | jq -r '.expected_class // ""')
# Feature 087: Terminal app detection for SSH wrapping.
# Prefer explicit registry metadata, but fall back to command heuristics so
# terminal-based launchers are covered consistently in remote mode.
IS_TERMINAL_REGISTRY=$(echo "$APP_JSON" | jq -r '.terminal // false')
COMMAND_BASENAME="${COMMAND##*/}"
IS_TERMINAL="false"
if [[ "$IS_TERMINAL_REGISTRY" == "true" ]]; then
    IS_TERMINAL="true"
else
    case "$COMMAND_BASENAME" in
        ghostty|alacritty|kitty|wezterm|foot|footclient|gnome-terminal|konsole|xterm|urxvt|tilix)
            IS_TERMINAL="true"
            ;;
    esac

    case " $PARAMETERS " in
        *" -e "*)
            IS_TERMINAL="true"
            ;;
    esac

    case "$APP_NAME" in
        terminal|ghostty|alacritty|kitty|wezterm|foot)
            IS_TERMINAL="true"
            ;;
    esac
fi

log "DEBUG" "Command: $COMMAND"
log "DEBUG" "Parameters: $PARAMETERS"
log "DEBUG" "Scope: $SCOPE"
log "DEBUG" "Expected class: $EXPECTED_CLASS"
log "DEBUG" "Terminal detected: $IS_TERMINAL (registry=$IS_TERMINAL_REGISTRY, command=$COMMAND_BASENAME)"

# Query active worktree context
# active-worktree.json is the single source of truth for project context
log "DEBUG" "Querying active worktree context"
WORKTREE_CONTEXT_FILE="$HOME/.config/i3/active-worktree.json"
USER_HOME="${HOME}"

if [[ -f "$WORKTREE_CONTEXT_FILE" ]]; then
    WORKTREE_JSON=$(cat "$WORKTREE_CONTEXT_FILE" 2>/dev/null || echo '{}')
    PROJECT_NAME=$(echo "$WORKTREE_JSON" | jq -r '.qualified_name // ""')
    PROJECT_DIR=$(echo "$WORKTREE_JSON" | jq -r '.directory // ""')
    LOCAL_PROJECT_DIR=$(echo "$WORKTREE_JSON" | jq -r '.local_directory // .directory // ""')
    WORKTREE_BRANCH=$(echo "$WORKTREE_JSON" | jq -r '.branch // ""')
    WORKTREE_ACCOUNT=$(echo "$WORKTREE_JSON" | jq -r '.account // ""')
    WORKTREE_REPO_NAME=$(echo "$WORKTREE_JSON" | jq -r '.repo_name // ""')
    REMOTE_ENABLED=$(echo "$WORKTREE_JSON" | jq -r '.remote.enabled // false')
    REMOTE_HOST=$(echo "$WORKTREE_JSON" | jq -r '.remote.host // ""')
    REMOTE_USER=$(echo "$WORKTREE_JSON" | jq -r '.remote.user // ""')
    REMOTE_WORKING_DIR=$(echo "$WORKTREE_JSON" | jq -r '.remote.remote_dir // .remote.working_dir // ""')
    REMOTE_PORT=$(echo "$WORKTREE_JSON" | jq -r '.remote.port // 22')

    # User preference: default SSH target uses Tailscale alias "ryzen".
    if [[ "$REMOTE_ENABLED" == "true" ]] && [[ -z "$REMOTE_HOST" ]]; then
        REMOTE_HOST="ryzen"
    fi
    if [[ "$REMOTE_ENABLED" == "true" ]] && [[ -z "$REMOTE_USER" ]]; then
        REMOTE_USER="${USER:-vpittamp}"
    fi
    if [[ "$REMOTE_ENABLED" == "true" ]] && [[ -z "$REMOTE_WORKING_DIR" ]]; then
        REMOTE_WORKING_DIR="$PROJECT_DIR"
    fi

    PROJECT_DISPLAY_NAME="$WORKTREE_BRANCH"
    # Use repo_branch format for unique session names (e.g., nixos-config_main)
    SESSION_NAME="${WORKTREE_REPO_NAME}_${WORKTREE_BRANCH}"
    PROJECT_ICON=""
    log "INFO" "Using worktree context - name: $PROJECT_NAME, dir: $PROJECT_DIR, local_dir: $LOCAL_PROJECT_DIR, branch: $WORKTREE_BRANCH"
else
    # No active worktree - global mode
    PROJECT_NAME=""
    PROJECT_DIR=""
    LOCAL_PROJECT_DIR=""
    PROJECT_DISPLAY_NAME=""
    PROJECT_ICON=""
    SESSION_NAME=""
    WORKTREE_BRANCH=""
    WORKTREE_ACCOUNT=""
    WORKTREE_REPO_NAME=""
    REMOTE_ENABLED="false"
    REMOTE_HOST=""
    REMOTE_USER=""
    REMOTE_WORKING_DIR=""
    REMOTE_PORT="22"
    log "DEBUG" "No active worktree context (global mode)"
fi

# Git metadata from worktree (simplified - can be extended if needed)
GIT_BRANCH="$WORKTREE_BRANCH"
GIT_COMMIT=""
GIT_IS_CLEAN=""
GIT_AHEAD=""
GIT_BEHIND=""

log "DEBUG" "Project name: ${PROJECT_NAME:-<none>}"
log "DEBUG" "Project directory: ${PROJECT_DIR:-<none>}"
log "DEBUG" "Local project directory: ${LOCAL_PROJECT_DIR:-<none>}"
log "DEBUG" "Worktree branch: ${WORKTREE_BRANCH:-<none>}"
log "DEBUG" "Remote enabled: ${REMOTE_ENABLED:-false}"
if [[ "${REMOTE_ENABLED:-false}" == "true" ]]; then
    log "DEBUG" "Remote host: ${REMOTE_USER}@${REMOTE_HOST}:${REMOTE_WORKING_DIR} (port ${REMOTE_PORT})"
fi

# Validate project directory if present
if [[ -n "$PROJECT_DIR" ]] && [[ "$PROJECT_DIR" == *$'\n'* ]]; then
    warn "Project directory contains newlines"
    PROJECT_DIR=""
fi

# Validate local project directory (used for local app launches and path substitutions)
if [[ -n "$LOCAL_PROJECT_DIR" ]]; then
    if [[ "$LOCAL_PROJECT_DIR" != /* ]]; then
        warn "Local project directory is not absolute: $LOCAL_PROJECT_DIR"
        LOCAL_PROJECT_DIR=""
    fi

    if [[ -n "$LOCAL_PROJECT_DIR" ]] && [[ ! -d "$LOCAL_PROJECT_DIR" ]]; then
        warn "Local project directory does not exist: $LOCAL_PROJECT_DIR"
        LOCAL_PROJECT_DIR=""
    fi

    if [[ -n "$LOCAL_PROJECT_DIR" ]] && [[ "$LOCAL_PROJECT_DIR" == *$'\n'* ]]; then
        warn "Local project directory contains newlines"
        LOCAL_PROJECT_DIR=""
    fi
fi

# For local projects (non-remote), project_dir must exist on local filesystem.
if [[ "$REMOTE_ENABLED" != "true" ]] && [[ -n "$PROJECT_DIR" ]] && [[ ! -d "$PROJECT_DIR" ]]; then
    warn "Project directory does not exist: $PROJECT_DIR"
    PROJECT_DIR=""
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
            LOCAL_PROJECT_DIR="$USER_HOME"
            PROJECT_NAME=""
            SESSION_NAME=""
            log "INFO" "Fallback (use_home): Using $USER_HOME"
            ;;
        "error")
            error "No project active and fallback behavior is 'error'
  This application requires a project context.
  Use 'i3pm worktree switch <name>' to activate a project."
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
    read -ra PARAMS <<< "$PARAM_RESOLVED"
    ARGS+=("${PARAMS[@]}")
fi

# ============================================================================
# DEVENV INTEGRATION
# ============================================================================
# For terminal apps, if the project has devenv.nix, use devenv-aware launcher
# which creates a tmux session with a dedicated "devenv" window running `devenv up`
#
# This enables:
# - Automatic devenv environment activation via direnv
# - Dedicated window for devenv services (devenv up)
# - Fallback to standard sesh for non-devenv projects

if [[ "$APP_NAME" == "terminal" ]] && [[ "$REMOTE_ENABLED" != "true" ]] && [[ -n "$LOCAL_PROJECT_DIR" ]] && [[ -f "$LOCAL_PROJECT_DIR/devenv.nix" ]]; then
    log "INFO" "Devenv project detected at $LOCAL_PROJECT_DIR, using devenv-terminal-launch"
    # Override ARGS to use devenv-aware terminal launcher
    # devenv-terminal-launch handles: session creation, devenv window, sesh fallback
    # Use script path relative to this script's location (both in scripts/)
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    DEVENV_LAUNCHER="$SCRIPT_DIR/devenv-terminal-launch.sh"
    ARGS=("$COMMAND" "-e" "$DEVENV_LAUNCHER" "$LOCAL_PROJECT_DIR" "$SESSION_NAME")
    log "DEBUG" "Devenv ARGS: ${ARGS[*]}"
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
    NIX_PACKAGE=$(echo "$APP_JSON" | jq -r '.nix_package // ""')

    error "Command not found: $COMMAND
  Package: ${NIX_PACKAGE:-<unknown>}
  Install package or add command to PATH."
fi

# ============================================================================
# UNIFIED I3PM ENVIRONMENT VARIABLE INJECTION
# ============================================================================
# These variables enable window-to-project association for ALL app types:
# - Regular apps: Tier 1 matching via /proc/<pid>/environ
# - PWAs: Deterministic class matching + env context for project filtering
# - VS Code: Multi-instance tracking with unique app IDs

# Generate unique application instance ID
# Format: ${app_name}-${project_name}-${pid}-${timestamp}
generate_app_instance_id() {
    local app_name="$1"
    local project_name="${2:-global}"
    local timestamp
    timestamp=$(date +%s)
    echo "${app_name}-${project_name}-$$-${timestamp}"
}

# Support I3PM_APP_ID_OVERRIDE for layout restore (Feature 030)
if [[ -n "${I3PM_APP_ID_OVERRIDE:-}" ]]; then
    APP_INSTANCE_ID="$I3PM_APP_ID_OVERRIDE"
    log "INFO" "Using overridden APP_ID for layout restore: $APP_INSTANCE_ID"
else
    APP_INSTANCE_ID=$(generate_app_instance_id "$APP_NAME" "$PROJECT_NAME")
fi

# I3PM environment variables (injected for ALL apps)
export I3PM_APP_ID="$APP_INSTANCE_ID"
export I3PM_APP_NAME="$APP_NAME"
export I3PM_PROJECT_NAME="${PROJECT_NAME:-}"
export I3PM_PROJECT_DIR="${PROJECT_DIR:-}"
export I3PM_LOCAL_PROJECT_DIR="${LOCAL_PROJECT_DIR:-}"
export I3PM_PROJECT_DISPLAY_NAME="${PROJECT_DISPLAY_NAME:-}"
export I3PM_PROJECT_ICON="${PROJECT_ICON:-}"
export I3PM_SCOPE="$SCOPE"
export I3PM_ACTIVE=$(if [[ -n "$PROJECT_NAME" ]]; then echo "true"; else echo "false"; fi)
export I3PM_LAUNCH_TIME="$(date +%s)"
export I3PM_LAUNCHER_PID="$$"
export I3PM_REMOTE_ENABLED="${REMOTE_ENABLED:-false}"
export I3PM_REMOTE_HOST="${REMOTE_HOST:-}"
export I3PM_REMOTE_USER="${REMOTE_USER:-}"
export I3PM_REMOTE_PORT="${REMOTE_PORT:-22}"
export I3PM_REMOTE_DIR="${REMOTE_WORKING_DIR:-}"
export I3PM_REMOTE_SESSION_NAME="${I3PM_REMOTE_SESSION_NAME_OVERRIDE:-}"
# Canonical context identity for host-aware dedupe and marking.
# - connection key: local@<host> or <user>@<host>:<port>
# - context key: <qualified_project>::<variant>::<connection_key>
LOCAL_HOSTNAME="$(hostname -s 2>/dev/null || hostname 2>/dev/null || true)"
LOCAL_HOSTNAME="${LOCAL_HOSTNAME:-${HOSTNAME:-localhost}}"
LOCAL_HOST_ALIAS="${I3PM_LOCAL_HOST_ALIAS:-$LOCAL_HOSTNAME}"
export I3PM_LOCAL_HOST_ALIAS="$LOCAL_HOST_ALIAS"
if [[ "${REMOTE_ENABLED:-false}" == "true" ]]; then
    export I3PM_CONTEXT_VARIANT="ssh"
    RAW_CONNECTION_KEY="${I3PM_REMOTE_USER:-${USER:-unknown}}@${I3PM_REMOTE_HOST:-unknown}:${I3PM_REMOTE_PORT:-22}"
    export I3PM_CONNECTION_KEY="$(normalize_connection_key "$RAW_CONNECTION_KEY")"
else
    export I3PM_CONTEXT_VARIANT="local"
    export I3PM_CONNECTION_KEY="local@$(normalize_connection_key "$LOCAL_HOST_ALIAS")"
fi
if [[ -n "${I3PM_PROJECT_NAME:-}" ]]; then
    export I3PM_CONTEXT_KEY="${I3PM_PROJECT_NAME}::${I3PM_CONTEXT_VARIANT}::${I3PM_CONNECTION_KEY}"
else
    export I3PM_CONTEXT_KEY=""
fi

# Worktree-specific environment variables
export I3PM_WORKTREE_BRANCH="${WORKTREE_BRANCH:-}"
export I3PM_WORKTREE_ACCOUNT="${WORKTREE_ACCOUNT:-}"
export I3PM_WORKTREE_REPO="${WORKTREE_REPO_NAME:-}"

log "DEBUG" "Env: I3PM_PROJECT_NAME=$I3PM_PROJECT_NAME, I3PM_PROJECT_DIR=$I3PM_PROJECT_DIR, I3PM_LOCAL_PROJECT_DIR=$I3PM_LOCAL_PROJECT_DIR, I3PM_REMOTE_ENABLED=$I3PM_REMOTE_ENABLED, I3PM_WORKTREE_BRANCH=$I3PM_WORKTREE_BRANCH"

# Workspace assignment (Feature 053: Reliable event-driven assignment)
export I3PM_TARGET_WORKSPACE="$PREFERRED_WORKSPACE"
export I3PM_EXPECTED_CLASS="$EXPECTED_CLASS"

# Feature 074: Layout restore correlation mark
# If I3PM_RESTORE_MARK is set (by AppLauncher during layout restore), export it
if [[ -n "${I3PM_RESTORE_MARK:-}" ]]; then
    export I3PM_RESTORE_MARK
    log "DEBUG" "I3PM_RESTORE_MARK=$I3PM_RESTORE_MARK (layout restore)"
fi

log "DEBUG" "I3PM_APP_ID=$I3PM_APP_ID"
log "DEBUG" "I3PM_APP_NAME=$I3PM_APP_NAME"
log "DEBUG" "I3PM_PROJECT_NAME=$I3PM_PROJECT_NAME"
log "DEBUG" "I3PM_SCOPE=$I3PM_SCOPE"
log "DEBUG" "I3PM_TARGET_WORKSPACE=$I3PM_TARGET_WORKSPACE"
log "DEBUG" "I3PM_EXPECTED_CLASS=$I3PM_EXPECTED_CLASS"
log "DEBUG" "I3PM_CONNECTION_KEY=$I3PM_CONNECTION_KEY"
log "DEBUG" "I3PM_CONTEXT_KEY=$I3PM_CONTEXT_KEY"

# Feature 087: Avoid duplicate SSH terminal windows.
# If a project-scoped terminal already exists for this remote project, focus it
# and skip launching a new terminal process.
if [[ "$APP_NAME" == "terminal" ]] && [[ "$REMOTE_ENABLED" == "true" ]] && [[ -n "${PROJECT_NAME:-}" ]]; then
    REMOTE_SESSION_NAME_OVERRIDE="${I3PM_REMOTE_SESSION_NAME_OVERRIDE:-}"
    CONTEXT_KEY_OVERRIDE="${I3PM_CONTEXT_KEY:-}"
    if [[ -n "$REMOTE_SESSION_NAME_OVERRIDE" ]]; then
        if [[ -n "$CONTEXT_KEY_OVERRIDE" ]] && focus_existing_remote_session_window "${SCOPE:-scoped}" "$APP_NAME" "$PROJECT_NAME" "$REMOTE_SESSION_NAME_OVERRIDE" "$CONTEXT_KEY_OVERRIDE"; then
            log "INFO" "Feature 087: Reused existing SSH terminal for project '$PROJECT_NAME' session '$REMOTE_SESSION_NAME_OVERRIDE' via context key"
            exit 0
        fi
        if focus_existing_remote_session_window "${SCOPE:-scoped}" "$APP_NAME" "$PROJECT_NAME" "$REMOTE_SESSION_NAME_OVERRIDE"; then
            log "INFO" "Feature 087: Reused existing SSH terminal for project '$PROJECT_NAME' session '$REMOTE_SESSION_NAME_OVERRIDE'"
            exit 0
        fi

        if [[ "${SCOPE:-scoped}" != "scoped" ]] && [[ -n "$CONTEXT_KEY_OVERRIDE" ]] && focus_existing_remote_session_window "scoped" "$APP_NAME" "$PROJECT_NAME" "$REMOTE_SESSION_NAME_OVERRIDE" "$CONTEXT_KEY_OVERRIDE"; then
            log "INFO" "Feature 087: Reused existing SSH terminal for project '$PROJECT_NAME' session '$REMOTE_SESSION_NAME_OVERRIDE' via scoped context key"
            exit 0
        fi
        if [[ "${SCOPE:-scoped}" != "scoped" ]] && focus_existing_remote_session_window "scoped" "$APP_NAME" "$PROJECT_NAME" "$REMOTE_SESSION_NAME_OVERRIDE"; then
            log "INFO" "Feature 087: Reused existing SSH terminal for project '$PROJECT_NAME' session '$REMOTE_SESSION_NAME_OVERRIDE'"
            exit 0
        fi
    else
        if [[ -n "$CONTEXT_KEY_OVERRIDE" ]] && focus_existing_project_window "${SCOPE:-scoped}" "$APP_NAME" "$PROJECT_NAME" "$CONTEXT_KEY_OVERRIDE"; then
            log "INFO" "Feature 087: Reused existing SSH terminal for project '$PROJECT_NAME' via context key"
            exit 0
        fi
        if focus_existing_project_window "${SCOPE:-scoped}" "$APP_NAME" "$PROJECT_NAME"; then
            log "INFO" "Feature 087: Reused existing SSH terminal for project '$PROJECT_NAME'"
            exit 0
        fi

        if [[ "${SCOPE:-scoped}" != "scoped" ]] && [[ -n "$CONTEXT_KEY_OVERRIDE" ]] && focus_existing_project_window "scoped" "$APP_NAME" "$PROJECT_NAME" "$CONTEXT_KEY_OVERRIDE"; then
            log "INFO" "Feature 087: Reused existing SSH terminal for project '$PROJECT_NAME' via scoped context key"
            exit 0
        fi
        if [[ "${SCOPE:-scoped}" != "scoped" ]] && focus_existing_project_window "scoped" "$APP_NAME" "$PROJECT_NAME"; then
            log "INFO" "Feature 087: Reused existing SSH terminal for project '$PROJECT_NAME'"
            exit 0
        fi
    fi
fi

# ============================================================================
# LAUNCH NOTIFICATION TO DAEMON (Feature 041)
# ============================================================================
# Notifies daemon BEFORE app launch for Tier 0 window correlation
# Works for ALL app types (regular, PWA, VS Code)

notify_launch() {
    local app_name="$1"
    local project_name="$2"
    local project_dir="$3"
    local workspace="$4"
    local timestamp="$5"
    local expected_class="$6"

    # Build JSON-RPC request
    local request
    request=$(jq -nc \
        --arg app "$app_name" \
        --arg proj "${project_name:-}" \
        --arg dir "${project_dir:-}" \
        --arg ws "$workspace" \
        --arg ts "$timestamp" \
        --arg pid "$$" \
        --arg class "$expected_class" \
        '{
            jsonrpc: "2.0",
            method: "notify_launch",
            params: {
                app_name: $app,
                project_name: $proj,
                project_directory: $dir,
                launcher_pid: ($pid | tonumber),
                workspace_number: ($ws | tonumber),
                timestamp: ($ts | tonumber),
                expected_class: $class
            },
            id: 1
        }')

    # Send to daemon via Unix socket
    # Feature 117: User socket only (daemon runs as user service)
    local socket="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/i3-project-daemon/ipc.sock"
    local response

    if [[ ! -S "$socket" ]]; then
        warn "Daemon socket not found: $socket (launch notification skipped)"
        return 1
    fi

    response=$(timeout 1s bash -c "echo '$request' | socat - UNIX-CONNECT:$socket" 2>&1 || echo "")

    if [[ -z "$response" ]]; then
        warn "No response from daemon for launch notification"
        return 1
    fi

    # Check for errors
    local error
    error=$(echo "$response" | jq -r '.error // empty' 2>/dev/null || echo "")

    if [[ -n "$error" ]]; then
        warn "Daemon returned error for launch notification: $error"
        return 1
    fi

    # Log success
    local launch_id
    launch_id=$(echo "$response" | jq -r '.result.launch_id // "unknown"' 2>/dev/null || echo "unknown")
    log "INFO" "Launch notification sent: launch_id=$launch_id, app=$app_name, class=$expected_class"

    return 0
}

# Send launch notification BEFORE executing app (Feature 041)
# Send for both scoped and global apps to enable Tier 0 matching for ALL apps
if [[ -n "$PREFERRED_WORKSPACE" ]]; then
    log "DEBUG" "Sending launch notification for $APP_NAME"

    LAUNCH_TIMESTAMP=$(date +%s.%N)

    if notify_launch "$APP_NAME" "$PROJECT_NAME" "$PROJECT_DIR" "$PREFERRED_WORKSPACE" "$LAUNCH_TIMESTAMP" "$EXPECTED_CLASS"; then
        log "INFO" "Launch notification successful for $APP_NAME"
    else
        warn "Launch notification failed for $APP_NAME (app will still launch)"
    fi
else
    log "DEBUG" "Skipping launch notification (no preferred workspace)"
fi

# ============================================================================
# EXECUTE APPLICATION VIA SWAY EXEC
# ============================================================================
# All apps launched through Sway exec for:
# - Proper display server context (WAYLAND_DISPLAY, etc.)
# - Reliable window creation in compositor environment
# - Independence from launcher process lifecycle
# - Environment variable propagation to spawned processes

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

# Build environment variable exports for shell command
# Export all I3PM_* variables so daemon can identify the window
ENV_EXPORTS=(
    "export I3PM_APP_ID='$I3PM_APP_ID'"
    "export I3PM_APP_NAME='$I3PM_APP_NAME'"
    "export I3PM_PROJECT_NAME='$I3PM_PROJECT_NAME'"
    "export I3PM_PROJECT_DIR='$I3PM_PROJECT_DIR'"
    "export I3PM_LOCAL_PROJECT_DIR='$I3PM_LOCAL_PROJECT_DIR'"
    "export I3PM_PROJECT_DISPLAY_NAME='$I3PM_PROJECT_DISPLAY_NAME'"
    "export I3PM_PROJECT_ICON='${PROJECT_ICON:-}'"
    "export I3PM_SCOPE='$I3PM_SCOPE'"
    "export I3PM_ACTIVE='$I3PM_ACTIVE'"
    "export I3PM_LAUNCH_TIME='$I3PM_LAUNCH_TIME'"
    "export I3PM_LAUNCHER_PID='$I3PM_LAUNCHER_PID'"
    "export I3PM_REMOTE_ENABLED='$I3PM_REMOTE_ENABLED'"
    "export I3PM_REMOTE_HOST='$I3PM_REMOTE_HOST'"
    "export I3PM_REMOTE_USER='$I3PM_REMOTE_USER'"
    "export I3PM_REMOTE_PORT='$I3PM_REMOTE_PORT'"
    "export I3PM_REMOTE_DIR='$I3PM_REMOTE_DIR'"
    "export I3PM_REMOTE_SESSION_NAME='$I3PM_REMOTE_SESSION_NAME'"
    "export I3PM_CONTEXT_VARIANT='${I3PM_CONTEXT_VARIANT:-}'"
    "export I3PM_CONNECTION_KEY='${I3PM_CONNECTION_KEY:-}'"
    "export I3PM_CONTEXT_KEY='${I3PM_CONTEXT_KEY:-}'"
    "export I3PM_TARGET_WORKSPACE='$I3PM_TARGET_WORKSPACE'"
    "export I3PM_EXPECTED_CLASS='$I3PM_EXPECTED_CLASS'"
)

# Feature 074: Add I3PM_RESTORE_MARK for layout restore correlation (if set)
# This ensures restoration marks are passed through swaymsg exec to launched processes
if [[ -n "${I3PM_RESTORE_MARK:-}" ]]; then
    ENV_EXPORTS+=("export I3PM_RESTORE_MARK='$I3PM_RESTORE_MARK'")
fi

# Feature 101: All projects are now worktrees (using active-worktree.json as single source of truth)
# I3PM_IS_WORKTREE is always true when we have an active worktree context
if [[ -n "$WORKTREE_BRANCH" ]]; then
    ENV_EXPORTS+=("export I3PM_IS_WORKTREE='true'")
    ENV_EXPORTS+=("export I3PM_FULL_BRANCH_NAME='$WORKTREE_BRANCH'")
fi

# Feature 098: Add git metadata environment variables (conditional - only if set)
if [[ -n "$GIT_BRANCH" ]]; then
    ENV_EXPORTS+=("export I3PM_GIT_BRANCH='$GIT_BRANCH'")
fi

if [[ -n "$GIT_COMMIT" ]]; then
    ENV_EXPORTS+=("export I3PM_GIT_COMMIT='$GIT_COMMIT'")
fi

if [[ -n "$GIT_IS_CLEAN" ]]; then
    # Convert to lowercase "true"/"false" string
    if [[ "$GIT_IS_CLEAN" == "true" ]]; then
        ENV_EXPORTS+=("export I3PM_GIT_IS_CLEAN='true'")
    else
        ENV_EXPORTS+=("export I3PM_GIT_IS_CLEAN='false'")
    fi
fi

if [[ -n "$GIT_AHEAD" ]] && [[ "$GIT_AHEAD" != "null" ]]; then
    ENV_EXPORTS+=("export I3PM_GIT_AHEAD='$GIT_AHEAD'")
fi

if [[ -n "$GIT_BEHIND" ]] && [[ "$GIT_BEHIND" != "null" ]]; then
    ENV_EXPORTS+=("export I3PM_GIT_BEHIND='$GIT_BEHIND'")
fi

# NOTE: I3PM_PWA_URL is intentionally NOT passed through ENV_EXPORTS
# It's read directly by launch-pwa-by-name from the calling environment
# Passing it through swaymsg exec would cause infinite loops when PWAs open
# external links (child processes inherit it and trigger loop prevention)

ENV_STRING=$(IFS='; '; echo "${ENV_EXPORTS[*]}")

# ============================================================================
# Feature 087: SSH WRAPPING FOR REMOTE PROJECTS
# ============================================================================
# Remote execution is only valid for project-scoped apps.
# Global apps (including PWAs/browsers) should always launch locally, even when
# the currently active worktree has remote mode enabled.

USE_REMOTE_EXECUTION="false"
if [[ "$SCOPE" == "scoped" ]] && [[ "$REMOTE_ENABLED" == "true" ]]; then
    USE_REMOTE_EXECUTION="true"
fi

# If this is a remote scoped project AND a terminal application, wrap command
# with SSH. This enables terminal-based apps to run on remote hosts while
# maintaining the same launch workflow (keybindings, project context, etc.)
if [[ "$USE_REMOTE_EXECUTION" == "true" ]] && [[ "$IS_TERMINAL" == "true" ]]; then
    log "INFO" "Feature 087: Applying SSH wrapping for remote terminal app"

    if [[ -z "$REMOTE_HOST" ]] || [[ -z "$REMOTE_USER" ]] || [[ -z "$REMOTE_WORKING_DIR" ]]; then
        error "Feature 087: Remote profile for '$PROJECT_NAME' is incomplete.
  Required: host, user, remote_dir.
  Configure with: i3pm worktree remote set '$PROJECT_NAME' --host ryzen --user ${USER:-vpittamp} --dir <remote-path>"
    fi

    # Extract command after -e flag for terminal applications
    # Terminal commands typically follow the pattern: ghostty -e <command>
    # We need to extract everything after -e to wrap it in SSH

    # Find the position of -e in ARGS array
    TERMINAL_CMD=""
    FOUND_E_FLAG=false
    for ((i=0; i<${#ARGS[@]}; i++)); do
        if [[ "${ARGS[$i]}" == "-e" ]]; then
            FOUND_E_FLAG=true
            # Everything after -e is the terminal command
            TERMINAL_CMD_ARRAY=("${ARGS[@]:$((i+1))}")
            TERMINAL_CMD="${TERMINAL_CMD_ARRAY[*]}"
            break
        fi
    done

    if [[ "$FOUND_E_FLAG" == "false" ]]; then
        warn "Feature 087: Terminal app without -e flag, cannot apply SSH wrapping"
        # Fall through to normal execution
    else
        # Substitute local project path with remote working directory in command.
        # In SSH mode, parameter substitution may already have used remote path.
        TERMINAL_CMD_REMOTE="$TERMINAL_CMD"
        if [[ -n "$LOCAL_PROJECT_DIR" ]] && [[ "$LOCAL_PROJECT_DIR" != "$REMOTE_WORKING_DIR" ]]; then
            TERMINAL_CMD_REMOTE="${TERMINAL_CMD_REMOTE//$LOCAL_PROJECT_DIR/$REMOTE_WORKING_DIR}"
        fi

        log "DEBUG" "Feature 087: Original terminal command: $TERMINAL_CMD"
        log "DEBUG" "Feature 087: Remote terminal command: $TERMINAL_CMD_REMOTE"
        log "DEBUG" "Feature 087: Substituted local path ($LOCAL_PROJECT_DIR) with remote path ($REMOTE_WORKING_DIR)"

        # Build SSH command safely as an argument array and execute it from a
        # temporary helper script. This avoids brittle nested bash -lc quoting.
        #
        # For the "terminal" app we always connect to a remote sesh session in
        # the active remote project directory, independent of local substitutions.
        if [[ "$APP_NAME" == "terminal" ]]; then
            REMOTE_WORKING_DIR_Q=$(printf '%q' "$REMOTE_WORKING_DIR")
            if [[ -n "${I3PM_REMOTE_SESSION_NAME_OVERRIDE:-}" ]]; then
                REMOTE_SESSION_NAME_Q=$(printf '%q' "$I3PM_REMOTE_SESSION_NAME_OVERRIDE")
                REMOTE_INNER_CMD="if ! command -v sesh >/dev/null 2>&1; then echo '[i3pm] sesh is not installed on remote host.'; exit 127; fi; if ! command -v tmux >/dev/null 2>&1; then echo '[i3pm] tmux is not installed on remote host.'; exit 127; fi; sesh connect ${REMOTE_SESSION_NAME_Q}"
                log "INFO" "Feature 087: terminal app in SSH mode will connect to remote sesh session: $I3PM_REMOTE_SESSION_NAME_OVERRIDE"
            else
                REMOTE_INNER_CMD="if ! command -v sesh >/dev/null 2>&1; then echo '[i3pm] sesh is not installed on remote host.'; exit 127; fi; if ! command -v tmux >/dev/null 2>&1; then echo '[i3pm] tmux is not installed on remote host.'; exit 127; fi; cd ${REMOTE_WORKING_DIR_Q} && sesh connect ${REMOTE_WORKING_DIR_Q}"
                log "INFO" "Feature 087: terminal app in SSH mode will connect to remote sesh path: $REMOTE_WORKING_DIR"
            fi
        else
            REMOTE_INNER_CMD="cd $(printf '%q' "$REMOTE_WORKING_DIR") && $TERMINAL_CMD_REMOTE"
        fi

        SSH_ARGS=(ssh -t)
        if [[ "$REMOTE_PORT" != "22" ]]; then
            SSH_ARGS+=(-p "$REMOTE_PORT")
        fi
        # ssh takes a single remote command string; build bash -lc with robust quoting.
        REMOTE_SSH_CMD="bash -lc $(printf '%q' "$REMOTE_INNER_CMD")"
        SSH_ARGS+=("$REMOTE_USER@$REMOTE_HOST" "$REMOTE_SSH_CMD")
        SSH_CMD_PREVIEW=$(printf '%q ' "${SSH_ARGS[@]}")
        SSH_CMD_PREVIEW="${SSH_CMD_PREVIEW% }"
        log "INFO" "Feature 087: SSH command: ${SSH_CMD_PREVIEW:0:200}..."

        RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
        mkdir -p "$RUNTIME_DIR"
        REMOTE_LAUNCH_SCRIPT="$(mktemp "$RUNTIME_DIR/i3pm-remote-launch.XXXXXX.sh")"
        chmod 700 "$REMOTE_LAUNCH_SCRIPT"
        {
            echo "#!/usr/bin/env bash"
            echo "set -euo pipefail"
            echo "ssh_cmd=("
            for arg in "${SSH_ARGS[@]}"; do
                printf '  %q\n' "$arg"
            done
            cat <<'EOF'
)
if ! "${ssh_cmd[@]}"; then
  echo
  echo "[i3pm] SSH launch failed for __REMOTE_TARGET__."
  echo "[i3pm] Press Enter to close..."
  read -r
fi
rm -f -- "$0" >/dev/null 2>&1 || true
EOF
        } > "$REMOTE_LAUNCH_SCRIPT"

        # Substitute target marker without disturbing shell quoting above.
        sed -i "s|__REMOTE_TARGET__|$REMOTE_USER@$REMOTE_HOST|g" "$REMOTE_LAUNCH_SCRIPT"

        # For remote execution, invoke terminal with helper script directly.
        REMOTE_TERMINAL_CMD="${ARGS[0]} -e $REMOTE_LAUNCH_SCRIPT"

        log "DEBUG" "Feature 087: Remote terminal command: ${REMOTE_TERMINAL_CMD:0:200}"
    fi

elif [[ "$USE_REMOTE_EXECUTION" == "true" ]] && [[ "$IS_TERMINAL" == "false" ]]; then
    # GUI app in remote project - reject with clear error
    error "Feature 087: Cannot launch GUI application '$APP_NAME' in remote project '$PROJECT_NAME'.
  Remote projects only support terminal-based applications.

  GUI apps require X11 forwarding or local execution, which is out of scope.

  Workarounds:
  - Use VS Code Remote-SSH extension for GUI editor access
  - Run GUI apps locally in global mode (i3pm worktree clear)
  - Use VNC/RDP to access full remote desktop (see WayVNC setup)"
fi

# Build application command with working directory
# Feature 087: For remote terminals, use the pre-built REMOTE_TERMINAL_CMD
if [[ -n "${REMOTE_TERMINAL_CMD:-}" ]]; then
    APP_CMD="cd '$HOME' && $REMOTE_TERMINAL_CMD"
# For scoped apps: use project directory (if available)
# For global apps: always use HOME to avoid AppImage/bubblewrap sandbox issues
elif [ "$SCOPE" = "scoped" ] && [ -n "$I3PM_PROJECT_DIR" ] && [ "$I3PM_PROJECT_DIR" != "" ]; then
    APP_CMD="cd '$I3PM_PROJECT_DIR' && ${ARGS[*]}"
else
    APP_CMD="cd '$HOME' && ${ARGS[*]}"
fi

# Complete shell command with environment setup
FULL_CMD="$ENV_STRING; $APP_CMD"

log "INFO" "Launching via Sway exec: ${FULL_CMD:0:200}..."  # Log first 200 chars

# Execute via Sway IPC - this runs in the compositor's context
if command -v swaymsg &>/dev/null; then
    # Use bash -c to run the command with exported variables
    SWAY_RESULT=$(swaymsg exec "bash -c \"$FULL_CMD\"" 2>&1)
    SWAY_EXIT=$?

    if [ $SWAY_EXIT -eq 0 ]; then
        log "INFO" "Sway exec successful: $SWAY_RESULT"
    else
        error "Sway exec failed (exit $SWAY_EXIT): $SWAY_RESULT"
    fi
else
    # Fallback to direct exec if swaymsg not available
    log "WARN" "swaymsg not found, using direct exec (may not work in all environments)"
    if [ "$REMOTE_ENABLED" != "true" ] && [ -n "$I3PM_PROJECT_DIR" ] && [ "$I3PM_PROJECT_DIR" != "" ]; then
        cd "$I3PM_PROJECT_DIR" || true
    fi
    exec "${ARGS[@]}"
fi
