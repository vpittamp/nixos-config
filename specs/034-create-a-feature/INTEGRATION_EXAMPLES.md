# Feature 034: i3pm Daemon Integration Examples

## Overview

This document provides production-ready code examples for integrating the i3pm daemon's project context API into the Feature 034 Unified Application Launcher.

---

## 1. Complete Bash Launcher Wrapper

This is a production-ready wrapper script that handles all error cases:

```bash
#!/usr/bin/env bash
# feature-034-launcher-wrapper.sh
# 
# Unified application launcher with project context support
# Handles variable substitution for $PROJECT_NAME, $PROJECT_DIR, $SESSION_NAME

set -euo pipefail

# Configuration
readonly SOCKET_PATH="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/i3-project-daemon/ipc.sock"
readonly CONFIG_DIR="${HOME}/.config/i3/projects"
readonly TIMEOUT=5
readonly MAX_RETRIES=3

# Colors (if stdout is TTY)
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Helper functions

log_error() {
    if [ -t 2 ]; then
        echo -e "${RED}✗ Error: $*${NC}" >&2
    else
        echo "Error: $*" >&2
    fi
}

log_success() {
    if [ -t 1 ]; then
        echo -e "${GREEN}✓ $*${NC}"
    else
        echo "$*"
    fi
}

log_warn() {
    if [ -t 2 ]; then
        echo -e "${YELLOW}⚠ $*${NC}" >&2
    else
        echo "Warning: $*" >&2
    fi
}

log_debug() {
    if [ "${DEBUG:-0}" == "1" ]; then
        echo "[DEBUG] $*" >&2
    fi
}

# Check if daemon is running
check_daemon() {
    if [ ! -S "$SOCKET_PATH" ]; then
        log_error "i3pm daemon not running"
        log_error "Daemon socket not found at: $SOCKET_PATH"
        log_error "Restart daemon with: systemctl --user restart i3-project-event-listener"
        return 1
    fi
    log_debug "Daemon socket found at $SOCKET_PATH"
    return 0
}

# Query current project via CLI (simple, recommended)
query_project_cli() {
    log_debug "Querying project via i3pm CLI..."
    
    # Retry with exponential backoff
    local retry=0
    while [ $retry -lt $MAX_RETRIES ]; do
        if PROJECT=$(timeout $TIMEOUT i3pm project current 2>/dev/null); then
            [ -n "$PROJECT" ] && log_debug "Got project: $PROJECT" || log_debug "Global mode (no project)"
            echo "$PROJECT"
            return 0
        fi
        
        retry=$((retry + 1))
        if [ $retry -lt $MAX_RETRIES ]; then
            sleep 0.$((100 * retry))  # 100ms, 200ms, 300ms backoff
            log_debug "Retry $retry/$MAX_RETRIES after timeout"
        fi
    done
    
    log_debug "Failed to query project after $MAX_RETRIES retries"
    return 1
}

# Query current project via direct RPC (fast, if CLI fails)
query_project_rpc() {
    log_debug "Querying project via direct RPC..."
    
    local request='{"jsonrpc":"2.0","method":"get_current_project","params":{},"id":1}'
    local response
    
    response=$(echo "$request" | nc -U -N "$SOCKET_PATH" -W 1 2>/dev/null || true)
    
    if [ -z "$response" ]; then
        log_debug "No response from RPC query"
        return 1
    fi
    
    local project
    project=$(echo "$response" | jq -r '.result.project // empty' 2>/dev/null || true)
    
    if [ -z "$project" ]; then
        log_debug "No project in RPC response"
        echo ""  # Return empty string for global mode
        return 0
    fi
    
    log_debug "Got project from RPC: $project"
    echo "$project"
    return 0
}

# Get current project (try CLI, fallback to RPC)
get_current_project() {
    local project
    
    # Try CLI first (more robust error handling)
    project=$(query_project_cli) || project=$(query_project_rpc) || {
        log_debug "Both CLI and RPC queries failed"
        return 1
    }
    
    echo "$project"
    return 0
}

# Load project configuration
load_project_config() {
    local project="$1"
    local config_file="$CONFIG_DIR/$project.json"
    
    if [ ! -f "$config_file" ]; then
        log_error "Project configuration not found: $config_file"
        log_error "Run 'i3pm project validate' to check project configurations"
        return 1
    fi
    
    log_debug "Loading project config from $config_file"
    
    # Extract required fields
    local directory
    directory=$(jq -r '.directory // empty' "$config_file" 2>/dev/null) || {
        log_error "Invalid project JSON: $config_file"
        return 1
    }
    
    if [ -z "$directory" ]; then
        log_error "Project configuration missing 'directory' field: $config_file"
        return 1
    fi
    
    # Validate directory exists
    if [ ! -d "$directory" ]; then
        log_error "Project directory not found: $directory"
        return 1
    fi
    
    log_debug "Project directory: $directory"
    echo "$directory"
    return 0
}

# Substitute variables in command
substitute_variables() {
    local command="$1"
    local project_name="$2"
    local project_dir="$3"
    local session_name="$4"
    
    log_debug "Substituting variables in command: $command"
    
    # Perform substitutions
    command="${command//\$PROJECT_NAME/$project_name}"
    command="${command//\$PROJECT_DIR/$project_dir}"
    command="${command//\$SESSION_NAME/$session_name}"
    
    log_debug "After substitution: $command"
    echo "$command"
}

# Main launch function
launch_command() {
    local command="$1"
    local allow_global="${2:-0}"  # Whether to allow launching in global mode
    
    log_debug "Launching command: $command"
    log_debug "Allow global mode: $allow_global"
    
    # Check daemon is running
    check_daemon || return 1
    
    # Get current project
    local project_name
    project_name=$(get_current_project) || {
        log_error "Failed to query current project"
        return 1
    }
    
    # Handle global mode
    if [ -z "$project_name" ]; then
        if [ "$allow_global" == "0" ]; then
            log_error "Cannot launch project-scoped command in global mode"
            log_error "Switch to a project with: i3pm project switch <name>"
            return 1
        fi
        
        log_warn "Launching in global mode (no active project)"
        
        # Allow substitution with placeholder values
        local project_dir="$HOME"
        local session_name="default"
        
        command=$(substitute_variables "$command" "global" "$project_dir" "$session_name")
    else
        # Load project configuration
        local project_dir
        project_dir=$(load_project_config "$project_name") || return 1
        
        local session_name="$project_name"
        
        # Substitute variables
        command=$(substitute_variables "$command" "$project_name" "$project_dir" "$session_name")
    fi
    
    # Export context variables for use in command
    export PROJECT_NAME="${project_name:-global}"
    export PROJECT_DIR="${project_dir}"
    export SESSION_NAME="${session_name}"
    
    log_success "Project context:"
    log_success "  PROJECT_NAME=$PROJECT_NAME"
    log_success "  PROJECT_DIR=$PROJECT_DIR"
    log_success "  SESSION_NAME=$SESSION_NAME"
    
    log_debug "Executing command: $command"
    
    # Execute command in project directory context
    cd "$PROJECT_DIR" || {
        log_error "Cannot change to project directory: $PROJECT_DIR"
        return 1
    }
    
    eval "$command"
}

# Main script

usage() {
    cat <<EOF
Usage: $0 [OPTIONS] COMMAND

Launch applications with project context variable substitution.

OPTIONS:
    --project NAME      Override active project (for testing)
    --allow-global      Allow launching in global mode (default: fail)
    --debug             Show debug output
    -h, --help          Show this help message

COMMAND:
    Shell command to execute with variable substitution

VARIABLES:
    \$PROJECT_NAME   - Current project name (e.g., "nixos")
    \$PROJECT_DIR    - Project directory (e.g., "/etc/nixos")
    \$SESSION_NAME   - Session name (same as project name)

EXAMPLES:
    # Launch terminal in project directory
    $0 "ghostty --working-directory=\$PROJECT_DIR"
    
    # Launch editor in project
    $0 "code \$PROJECT_DIR"
    
    # Launch tmux session
    $0 "tmux new-session -s \$SESSION_NAME -c \$PROJECT_DIR"

