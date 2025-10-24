#!/usr/bin/env bash
# Example: Query i3pm project context for variable substitution
#
# This script demonstrates how the unified application launcher
# should query the i3pm daemon to get project context for
# substituting variables like $PROJECT_DIR, $PROJECT_NAME, $SESSION_NAME

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${BLUE}[INFO]${NC} $*"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $*"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $*"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*"
}

# ============================================================================
# Method 1: Using i3pm CLI (Recommended for simplicity)
# ============================================================================
query_project_cli() {
    log_info "Method 1: Using i3pm CLI command"

    # Query current project (piped output is plain text)
    if ! PROJECT_NAME=$(i3pm project current 2>/dev/null); then
        log_error "Failed to query daemon via CLI"
        return 1
    fi

    # Check for global mode (empty string)
    if [ -z "$PROJECT_NAME" ]; then
        log_warning "No active project (global mode)"
        return 1
    fi

    log_success "Active project: $PROJECT_NAME"

    # Load project metadata from config file
    PROJECT_FILE="$HOME/.config/i3/projects/${PROJECT_NAME}.json"
    if [ ! -f "$PROJECT_FILE" ]; then
        log_error "Project configuration not found: $PROJECT_FILE"
        return 1
    fi

    # Extract fields using jq
    PROJECT_DIR=$(jq -r '.directory' "$PROJECT_FILE")
    DISPLAY_NAME=$(jq -r '.display_name' "$PROJECT_FILE")
    ICON=$(jq -r '.icon' "$PROJECT_FILE")

    # Session name convention: session name = project name
    SESSION_NAME="$PROJECT_NAME"

    # Display results
    echo ""
    log_success "Project Context Loaded:"
    echo "  PROJECT_NAME:  $PROJECT_NAME"
    echo "  DISPLAY_NAME:  $DISPLAY_NAME"
    echo "  ICON:          $ICON"
    echo "  PROJECT_DIR:   $PROJECT_DIR"
    echo "  SESSION_NAME:  $SESSION_NAME"

    # Export for use in launcher commands
    export PROJECT_NAME
    export PROJECT_DIR
    export SESSION_NAME

    return 0
}

# ============================================================================
# Method 2: Direct JSON-RPC Query (For maximum performance)
# ============================================================================
query_project_jsonrpc() {
    log_info "Method 2: Direct JSON-RPC query"

    # Discover socket path
    SOCKET_PATH="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/i3-project-daemon/ipc.sock"

    # Check socket exists
    if [ ! -S "$SOCKET_PATH" ]; then
        log_error "Daemon socket not found: $SOCKET_PATH"
        log_error "Is the daemon running? Check: systemctl --user status i3-project-event-listener"
        return 1
    fi

    log_info "Socket path: $SOCKET_PATH"

    # Send JSON-RPC request
    REQUEST='{"jsonrpc":"2.0","method":"get_current_project","params":{},"id":1}'

    # Use nc (netcat) to send request and read response
    if ! RESPONSE=$(echo "$REQUEST" | nc -U "$SOCKET_PATH" 2>/dev/null); then
        log_error "Failed to query daemon via JSON-RPC"
        return 1
    fi

    log_info "Response: $RESPONSE"

    # Parse response with jq
    PROJECT_NAME=$(echo "$RESPONSE" | jq -r '.result.project // empty')

    if [ -z "$PROJECT_NAME" ]; then
        log_warning "No active project (global mode)"
        return 1
    fi

    log_success "Active project: $PROJECT_NAME"

    # Load project metadata (same as Method 1)
    PROJECT_FILE="$HOME/.config/i3/projects/${PROJECT_NAME}.json"
    if [ ! -f "$PROJECT_FILE" ]; then
        log_error "Project configuration not found: $PROJECT_FILE"
        return 1
    fi

    PROJECT_DIR=$(jq -r '.directory' "$PROJECT_FILE")
    SESSION_NAME="$PROJECT_NAME"

    echo ""
    log_success "Project Context (via JSON-RPC):"
    echo "  PROJECT_NAME:  $PROJECT_NAME"
    echo "  PROJECT_DIR:   $PROJECT_DIR"
    echo "  SESSION_NAME:  $SESSION_NAME"

    return 0
}

# ============================================================================
# Method 3: With Error Handling and Retries
# ============================================================================
query_project_robust() {
    log_info "Method 3: Robust query with retries"

    local timeout=5
    local max_retries=3
    local retry=0

    while [ $retry -lt $max_retries ]; do
        log_info "Attempt $((retry + 1))/$max_retries"

        # Use timeout to prevent hanging
        if PROJECT_NAME=$(timeout "$timeout" i3pm project current 2>&1); then
            if [ -n "$PROJECT_NAME" ]; then
                log_success "Query succeeded on attempt $((retry + 1))"

                # Load metadata
                PROJECT_FILE="$HOME/.config/i3/projects/${PROJECT_NAME}.json"
                if [ ! -f "$PROJECT_FILE" ]; then
                    log_error "Project config not found: $PROJECT_FILE"
                    return 1
                fi

                PROJECT_DIR=$(jq -r '.directory' "$PROJECT_FILE")
                SESSION_NAME="$PROJECT_NAME"

                echo ""
                log_success "Project Context (with retries):"
                echo "  PROJECT_NAME:  $PROJECT_NAME"
                echo "  PROJECT_DIR:   $PROJECT_DIR"
                echo "  SESSION_NAME:  $SESSION_NAME"

                return 0
            else
                log_warning "No active project"
                return 1
            fi
        fi

        retry=$((retry + 1))
        if [ $retry -lt $max_retries ]; then
            log_warning "Query failed, retrying in 0.5s..."
            sleep 0.5
        fi
    done

    log_error "Failed to query project after $max_retries attempts"
    return 1
}

# ============================================================================
# Example: Substitute variables in a command
# ============================================================================
demonstrate_substitution() {
    log_info "Demonstrating variable substitution in launcher commands"

    # Query project context
    if ! PROJECT_NAME=$(i3pm project current 2>/dev/null); then
        log_error "Cannot demonstrate: daemon not responding"
        return 1
    fi

    if [ -z "$PROJECT_NAME" ]; then
        log_warning "Cannot demonstrate: no active project"
        echo ""
        echo "To activate a project, run:"
        echo "  i3pm project switch <name>"
        return 1
    fi

    # Load project config
    PROJECT_FILE="$HOME/.config/i3/projects/${PROJECT_NAME}.json"
    PROJECT_DIR=$(jq -r '.directory' "$PROJECT_FILE")
    SESSION_NAME="$PROJECT_NAME"

    echo ""
    log_success "Variable Substitution Examples:"
    echo ""

    # Example 1: Terminal with sesh session
    TEMPLATE='ghostty -e sesh connect $SESSION_NAME'
    SUBSTITUTED="${TEMPLATE//\$SESSION_NAME/$SESSION_NAME}"
    echo "  Template:     $TEMPLATE"
    echo "  Substituted:  $SUBSTITUTED"
    echo ""

    # Example 2: VS Code in project directory
    TEMPLATE='code $PROJECT_DIR'
    SUBSTITUTED="${TEMPLATE//\$PROJECT_DIR/$PROJECT_DIR}"
    echo "  Template:     $TEMPLATE"
    echo "  Substituted:  $SUBSTITUTED"
    echo ""

    # Example 3: Lazygit in project directory
    TEMPLATE='ghostty --working-directory=$PROJECT_DIR -e lazygit'
    SUBSTITUTED="${TEMPLATE//\$PROJECT_DIR/$PROJECT_DIR}"
    echo "  Template:     $TEMPLATE"
    echo "  Substituted:  $SUBSTITUTED"
    echo ""

    # Example 4: Multiple variables
    TEMPLATE='echo "Project: $PROJECT_NAME at $PROJECT_DIR with session $SESSION_NAME"'
    SUBSTITUTED="$TEMPLATE"
    SUBSTITUTED="${SUBSTITUTED//\$PROJECT_NAME/$PROJECT_NAME}"
    SUBSTITUTED="${SUBSTITUTED//\$PROJECT_DIR/$PROJECT_DIR}"
    SUBSTITUTED="${SUBSTITUTED//\$SESSION_NAME/$SESSION_NAME}"
    echo "  Template:     $TEMPLATE"
    echo "  Substituted:  $SUBSTITUTED"
    echo ""

    log_info "Executing substituted command:"
    eval "$SUBSTITUTED"
}

# ============================================================================
# Main
# ============================================================================
main() {
    echo "========================================="
    echo "i3pm Project Context Query Examples"
    echo "Feature 034: Unified Application Launcher"
    echo "========================================="
    echo ""

    # Run all methods
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    query_project_cli
    echo ""

    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    query_project_jsonrpc
    echo ""

    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    query_project_robust
    echo ""

    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    demonstrate_substitution
    echo ""

    echo "========================================="
    log_success "All examples completed"
    echo "========================================="
}

# Run if executed directly
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    main "$@"
fi
