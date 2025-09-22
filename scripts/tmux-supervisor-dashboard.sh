#!/usr/bin/env bash
# Tmux Supervisor Dashboard - Cross-Activity Session Manager
# Provides a unified view of all tmux sessions with broadcasting capabilities

set -euo pipefail

# Configuration
SUPERVISOR_SESSION="supervisor-dashboard"
SUPERVISOR_WINDOW="main"
COMMAND_HISTORY_FILE="/tmp/tmux-supervisor-history"
DEBUG=${DEBUG:-0}

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Debug function
debug() {
    [[ $DEBUG -eq 1 ]] && echo -e "${CYAN}[DEBUG]${NC} $*" >&2
}

# Info function
info() {
    echo -e "${BLUE}[INFO]${NC} $*"
}

# Success function
success() {
    echo -e "${GREEN}[SUCCESS]${NC} $*"
}

# Error function
error() {
    echo -e "${RED}[ERROR]${NC} $*" >&2
}

# Warning function
warning() {
    echo -e "${YELLOW}[WARNING]${NC} $*"
}

# Function to check if tmux is running
check_tmux() {
    if ! command -v tmux &> /dev/null; then
        error "tmux is not installed"
        exit 1
    fi

    if ! tmux ls &> /dev/null; then
        warning "No tmux sessions are currently running"
        return 1
    fi
    return 0
}

# Function to get all tmux sessions with metadata
get_all_sessions() {
    tmux ls -F '#{session_name}:#{session_id}:#{session_attached}:#{session_windows}:#{session_created}' 2>/dev/null || true
}

# Function to get session activity (try to map to KDE activity)
get_session_activity() {
    local session_name="$1"

    # Map session names to activities based on your configuration
    case "$session_name" in
        backstage*) echo "Backstage" ;;
        monitoring*) echo "Monitoring" ;;
        nix*) echo "NixOS" ;;
        nixos*) echo "NixOS" ;;
        stacks*) echo "Stacks" ;;
        dev*) echo "Dev" ;;
        *) echo "General" ;;
    esac
}

# Function to create supervisor dashboard session
create_supervisor_session() {
    info "Creating supervisor dashboard session..."

    # Check if supervisor session already exists
    if tmux has-session -t "$SUPERVISOR_SESSION" 2>/dev/null; then
        warning "Supervisor session already exists. Killing old session..."
        tmux kill-session -t "$SUPERVISOR_SESSION"
    fi

    # Create new supervisor session
    tmux new-session -d -s "$SUPERVISOR_SESSION" -n "$SUPERVISOR_WINDOW"

    # Get all current sessions
    local sessions=($(tmux ls -F '#{session_name}' 2>/dev/null | grep -v "^$SUPERVISOR_SESSION$" || true))
    local num_sessions=${#sessions[@]}

    if [[ $num_sessions -eq 0 ]]; then
        warning "No other tmux sessions found to monitor"
        # Create a single pane with instructions
        tmux send-keys -t "$SUPERVISOR_SESSION:$SUPERVISOR_WINDOW" \
            "echo 'No tmux sessions to monitor. Start some sessions and refresh.'" Enter
        return
    fi

    info "Found $num_sessions session(s) to monitor: ${sessions[*]}"

    # Calculate grid layout
    local cols rows
    if [[ $num_sessions -le 2 ]]; then
        cols=2; rows=1
    elif [[ $num_sessions -le 4 ]]; then
        cols=2; rows=2
    elif [[ $num_sessions -le 6 ]]; then
        cols=3; rows=2
    elif [[ $num_sessions -le 9 ]]; then
        cols=3; rows=3
    else
        cols=4; rows=3
    fi

    debug "Creating grid layout: ${cols}x${rows} for $num_sessions sessions"

    # Create panes for each session
    local pane_index=1
    for session in "${sessions[@]}"; do
        if [[ $pane_index -gt 1 ]]; then
            # Create new pane
            tmux split-window -t "$SUPERVISOR_SESSION:$SUPERVISOR_WINDOW" -v
            tmux select-layout -t "$SUPERVISOR_SESSION:$SUPERVISOR_WINDOW" tiled
        fi

        # Get the actual pane index (last created)
        local current_pane=$(tmux list-panes -t "$SUPERVISOR_SESSION:$SUPERVISOR_WINDOW" -F '#{pane_index}' | tail -1)

        # Set up the pane to show session info and allow interaction
        local activity=$(get_session_activity "$session")
        setup_monitor_pane "$SUPERVISOR_SESSION:$SUPERVISOR_WINDOW.$current_pane" "$session" "$activity"

        ((pane_index++))
    done

    # Rebalance panes to make them equal size
    tmux select-layout -t "$SUPERVISOR_SESSION:$SUPERVISOR_WINDOW" tiled

    # Create command pane at the bottom
    create_command_pane

    success "Supervisor dashboard created successfully"
}

# Function to setup a monitoring pane for a session
setup_monitor_pane() {
    local pane="$1"
    local session="$2"
    local activity="$3"

    debug "Setting up monitor for session: $session (Activity: $activity)"

    # Send commands directly to show session info and monitoring
    tmux send-keys -t "$pane" C-c 2>/dev/null || true
    tmux send-keys -t "$pane" "clear" Enter
    tmux send-keys -t "$pane" "echo '╔════════════════════════════════════════╗'" Enter
    tmux send-keys -t "$pane" "echo '║ Session: $session'" Enter
    tmux send-keys -t "$pane" "echo '║ Activity: $activity'" Enter
    tmux send-keys -t "$pane" "echo '╚════════════════════════════════════════╝'" Enter
    tmux send-keys -t "$pane" "echo ''" Enter

    # Use tmux capture-pane to show content from the target session
    tmux send-keys -t "$pane" "watch -n 2 \"tmux capture-pane -t '$session' -p 2>/dev/null | head -30 || echo 'Session not available'\"" Enter
}

# Function to create command pane at the bottom
create_command_pane() {
    info "Creating command pane..."

    # Split the window horizontally to add command pane at bottom
    tmux split-window -t "$SUPERVISOR_SESSION:$SUPERVISOR_WINDOW" -v -l 8
    local cmd_pane=$(tmux list-panes -t "$SUPERVISOR_SESSION:$SUPERVISOR_WINDOW" -F '#{pane_index}' | tail -1)

    # Just show instructions - don't run an interactive script
    tmux send-keys -t "$SUPERVISOR_SESSION:$SUPERVISOR_WINDOW.$cmd_pane" "clear" Enter
    tmux send-keys -t "$SUPERVISOR_SESSION:$SUPERVISOR_WINDOW.$cmd_pane" "echo '╔════════════════════════════════════════════════════════════════╗'" Enter
    tmux send-keys -t "$SUPERVISOR_SESSION:$SUPERVISOR_WINDOW.$cmd_pane" "echo '║                    SUPERVISOR COMMAND CENTER                      ║'" Enter
    tmux send-keys -t "$SUPERVISOR_SESSION:$SUPERVISOR_WINDOW.$cmd_pane" "echo '╚════════════════════════════════════════════════════════════════╝'" Enter
    tmux send-keys -t "$SUPERVISOR_SESSION:$SUPERVISOR_WINDOW.$cmd_pane" "echo ''" Enter
    tmux send-keys -t "$SUPERVISOR_SESSION:$SUPERVISOR_WINDOW.$cmd_pane" "echo 'Commands (run from here):'" Enter
    tmux send-keys -t "$SUPERVISOR_SESSION:$SUPERVISOR_WINDOW.$cmd_pane" "echo '  tmux-supervisor broadcast \"message\"   # Send to all sessions'" Enter
    tmux send-keys -t "$SUPERVISOR_SESSION:$SUPERVISOR_WINDOW.$cmd_pane" "echo '  tmux-supervisor send session \"msg\"    # Send to specific session'" Enter
    tmux send-keys -t "$SUPERVISOR_SESSION:$SUPERVISOR_WINDOW.$cmd_pane" "echo '  tmux setw synchronize-panes on/off    # Toggle sync mode'" Enter
    tmux send-keys -t "$SUPERVISOR_SESSION:$SUPERVISOR_WINDOW.$cmd_pane" "echo ''" Enter
    tmux send-keys -t "$SUPERVISOR_SESSION:$SUPERVISOR_WINDOW.$cmd_pane" "echo 'Ready for commands...'" Enter
    tmux send-keys -t "$SUPERVISOR_SESSION:$SUPERVISOR_WINDOW.$cmd_pane" "echo ''" Enter

    # Leave at a prompt ready for commands
    return 0
}

# Function to attach to supervisor session
attach_supervisor() {
    if ! tmux has-session -t "$SUPERVISOR_SESSION" 2>/dev/null; then
        error "Supervisor session does not exist. Creating it first..."
        create_supervisor_session
    fi

    info "Attaching to supervisor dashboard..."
    tmux attach-session -t "$SUPERVISOR_SESSION"
}

# Function to send command to all sessions
broadcast_command() {
    local message="$1"

    if [[ -z "$message" ]]; then
        error "No message provided to broadcast"
        exit 1
    fi

    info "Broadcasting: $message"

    # Log to history
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] BROADCAST: $message" >> "$COMMAND_HISTORY_FILE"

    # Send to all panes except supervisor dashboard
    local count=0
    tmux list-panes -a -F '#{session_name}:#{window_index}.#{pane_index}' | \
        grep -v "^$SUPERVISOR_SESSION:" | \
        while read pane; do
            tmux send-keys -t "$pane" "$message" Enter 2>/dev/null && ((count++)) || true
        done

    success "Message broadcast to all sessions"
}

# Function to send command to specific session
send_to_session() {
    local session="$1"
    local message="$2"

    if [[ -z "$session" || -z "$message" ]]; then
        error "Usage: send <session> <message>"
        exit 1
    fi

    info "Sending to $session: $message"

    # Log to history
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] SEND to $session: $message" >> "$COMMAND_HISTORY_FILE"

    if tmux has-session -t "$session" 2>/dev/null; then
        tmux send-keys -t "$session" "$message" Enter
        success "Message sent to $session"
    else
        error "Session $session not found"
        exit 1
    fi
}

# Function to show status
show_status() {
    echo "════════════════════════════════════════════════"
    echo "     Tmux Supervisor Dashboard Status"
    echo "════════════════════════════════════════════════"
    echo ""

    # Check supervisor session
    if tmux has-session -t "$SUPERVISOR_SESSION" 2>/dev/null; then
        success "Supervisor session is running"
        echo ""

        # Show monitored sessions
        echo "Monitored Sessions:"
        tmux ls -F '  #{session_name}: #{session_windows} windows, #{?session_attached,attached,detached}' | \
            grep -v "^  $SUPERVISOR_SESSION:" || echo "  No sessions being monitored"
    else
        warning "Supervisor session is not running"
    fi

    echo ""

    # Show recent command history
    if [[ -f "$COMMAND_HISTORY_FILE" ]]; then
        echo "Recent Commands:"
        tail -5 "$COMMAND_HISTORY_FILE" 2>/dev/null || echo "  No recent commands"
    fi

    echo "════════════════════════════════════════════════"
}

# Main command handler
main() {
    local command="${1:-}"
    shift || true

    case "$command" in
        start)
            check_tmux || exit 0
            create_supervisor_session
            # Don't auto-attach when creating, let user attach manually or with 'attach' command
            info "Supervisor dashboard created. Use 'tmux attach -t $SUPERVISOR_SESSION' to view it."
            ;;
        attach)
            attach_supervisor
            ;;
        broadcast)
            broadcast_command "$*"
            ;;
        send)
            send_to_session "$@"
            ;;
        status)
            show_status
            ;;
        help|--help|-h)
            echo "Tmux Supervisor Dashboard - Cross-Activity Session Manager"
            echo ""
            echo "Usage: $0 <command> [arguments]"
            echo ""
            echo "Commands:"
            echo "  start              - Create and attach to supervisor dashboard"
            echo "  attach             - Attach to existing supervisor dashboard"
            echo "  broadcast <msg>    - Send message to all sessions"
            echo "  send <sess> <msg>  - Send message to specific session"
            echo "  status             - Show supervisor status"
            echo "  help               - Show this help message"
            echo ""
            echo "Examples:"
            echo "  $0 start                     # Start supervisor dashboard"
            echo "  $0 broadcast 'clear'         # Clear all sessions"
            echo "  $0 send monitoring 'htop'    # Send htop command to monitoring session"
            echo ""
            ;;
        *)
            if [[ -z "$command" ]]; then
                # No command provided, default to start
                check_tmux || exit 0
                create_supervisor_session
                attach_supervisor
            else
                error "Unknown command: $command"
                echo "Use '$0 help' for usage information"
                exit 1
            fi
            ;;
    esac
}

# Run main function
main "$@"