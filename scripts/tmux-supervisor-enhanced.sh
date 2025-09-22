#!/usr/bin/env bash
# Enhanced Tmux Supervisor Dashboard with optimized viewing

set -euo pipefail

SUPERVISOR_SESSION="supervisor-dashboard"

# Colors for terminal output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Function to create or recreate the dashboard
create_dashboard() {
    # Kill old session if exists
    tmux kill-session -t "$SUPERVISOR_SESSION" 2>/dev/null || true

    # Create new session
    tmux new-session -d -s "$SUPERVISOR_SESSION" -n main

    # Get list of sessions (excluding supervisor)
    local sessions=($(tmux ls -F '#{session_name}' | grep -v "^$SUPERVISOR_SESSION$" || true))

    if [[ ${#sessions[@]} -eq 0 ]]; then
        echo -e "${YELLOW}No sessions to monitor${NC}"
        tmux send-keys -t "$SUPERVISOR_SESSION:main" "echo 'No sessions to monitor. Start some tmux sessions first.'" Enter
        return
    fi

    echo -e "${GREEN}Creating dashboard for ${#sessions[@]} sessions${NC}"

    # Create monitoring panes
    for i in "${!sessions[@]}"; do
        local session="${sessions[$i]}"
        local activity=$(get_activity_for_session "$session")

        # Skip first pane (already exists)
        if [[ $i -gt 0 ]]; then
            tmux split-window -t "$SUPERVISOR_SESSION:main" -v
            tmux select-layout -t "$SUPERVISOR_SESSION:main" tiled
        fi

        # Get the pane index
        local pane_idx=$(( i + 1 ))

        # Create a compact header and start monitoring
        # Using more lines (40 instead of 20) since we have smaller font
        tmux send-keys -t "$SUPERVISOR_SESSION:main.$pane_idx" \
            "echo -e '${BLUE}━━━ $session [$activity] ━━━${NC}' && watch -t -n 2 'tmux capture-pane -t $session -p 2>/dev/null | head -40 || echo \"Session unavailable\"'" Enter
    done

    # Add command pane at bottom - smaller since we have more space
    tmux split-window -t "$SUPERVISOR_SESSION:main" -v -l 3
    local cmd_pane=$(tmux list-panes -t "$SUPERVISOR_SESSION:main" -F '#{pane_index}' | tail -1)

    # Compact command center
    tmux send-keys -t "$SUPERVISOR_SESSION:main.$cmd_pane" \
        "echo -e '${GREEN}[SUPERVISOR]${NC} broadcast \"msg\" | send <session> \"msg\" | sync on/off | refresh'" Enter

    # Final layout adjustment
    tmux select-layout -t "$SUPERVISOR_SESSION:main" tiled

    # Set window options for better visibility
    tmux set-window-option -t "$SUPERVISOR_SESSION:main" pane-border-status top
    tmux set-window-option -t "$SUPERVISOR_SESSION:main" pane-border-format "#{pane_index}: #{pane_title}"

    echo -e "${GREEN}Dashboard ready!${NC}"
}

# Function to determine activity for a session
get_activity_for_session() {
    local session="$1"
    case "$session" in
        backstage*) echo "Backstage" ;;
        monitoring*) echo "Monitor" ;;
        nix*|nixos*) echo "NixOS" ;;
        stacks*) echo "Stacks" ;;
        dev*) echo "Dev" ;;
        workspace*) echo "Work" ;;
        *) echo "General" ;;
    esac
}

# Function to broadcast to all sessions
broadcast() {
    local message="$*"
    if [[ -z "$message" ]]; then
        echo -e "${RED}Error: No message provided${NC}"
        return 1
    fi

    echo -e "${BLUE}Broadcasting:${NC} $message"

    local sessions=($(tmux ls -F '#{session_name}' | grep -v "^$SUPERVISOR_SESSION$"))
    for session in "${sessions[@]}"; do
        tmux send-keys -t "$session" "$message" Enter 2>/dev/null && \
            echo -e "  ${GREEN}✓${NC} $session" || \
            echo -e "  ${RED}✗${NC} $session"
    done
}

# Function to send to specific session
send_to_session() {
    local session="$1"
    shift
    local message="$*"

    if [[ -z "$session" || -z "$message" ]]; then
        echo -e "${RED}Usage: send <session> <message>${NC}"
        return 1
    fi

    echo -e "${BLUE}Sending to $session:${NC} $message"
    if tmux send-keys -t "$session" "$message" Enter 2>/dev/null; then
        echo -e "${GREEN}✓ Sent successfully${NC}"
    else
        echo -e "${RED}✗ Failed - session not found${NC}"
    fi
}

# Function to toggle synchronize panes
toggle_sync() {
    local state="${1:-toggle}"

    case "$state" in
        on)
            tmux set-window-option -t "$SUPERVISOR_SESSION:main" synchronize-panes on
            echo -e "${GREEN}Synchronize panes: ON${NC}"
            ;;
        off)
            tmux set-window-option -t "$SUPERVISOR_SESSION:main" synchronize-panes off
            echo -e "${YELLOW}Synchronize panes: OFF${NC}"
            ;;
        toggle|*)
            if tmux show-window-options -t "$SUPERVISOR_SESSION:main" | grep -q "synchronize-panes on"; then
                toggle_sync off
            else
                toggle_sync on
            fi
            ;;
    esac
}

# Function to refresh dashboard
refresh_dashboard() {
    echo -e "${BLUE}Refreshing dashboard...${NC}"
    create_dashboard
}

# Main command processing
case "${1:-create}" in
    create|start)
        create_dashboard
        ;;
    attach)
        if tmux has-session -t "$SUPERVISOR_SESSION" 2>/dev/null; then
            tmux attach -t "$SUPERVISOR_SESSION"
        else
            echo -e "${YELLOW}No supervisor session found. Creating one...${NC}"
            create_dashboard
            tmux attach -t "$SUPERVISOR_SESSION"
        fi
        ;;
    broadcast)
        shift
        broadcast "$@"
        ;;
    send)
        shift
        send_to_session "$@"
        ;;
    sync)
        shift
        toggle_sync "$@"
        ;;
    refresh)
        refresh_dashboard
        ;;
    help)
        echo "Tmux Supervisor Dashboard - Enhanced Version"
        echo ""
        echo "Usage: $0 [command] [args]"
        echo ""
        echo "Commands:"
        echo "  create/start       - Create the supervisor dashboard"
        echo "  attach            - Attach to the dashboard"
        echo "  broadcast <msg>   - Send message to all sessions"
        echo "  send <sess> <msg> - Send message to specific session"
        echo "  sync [on|off]     - Toggle synchronize-panes"
        echo "  refresh           - Refresh the dashboard"
        echo "  help              - Show this help"
        echo ""
        echo "Launch with small font:"
        echo "  konsole --profile Supervisor"
        echo ""
        ;;
    *)
        # Default: create and attach
        create_dashboard
        if [[ -t 0 ]] && [[ -t 1 ]]; then
            # If running interactively, attach
            tmux attach -t "$SUPERVISOR_SESSION"
        else
            echo -e "${GREEN}Dashboard created.${NC} Attach with: tmux attach -t $SUPERVISOR_SESSION"
        fi
        ;;
esac