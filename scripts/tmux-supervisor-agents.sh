#!/usr/bin/env bash
# Enhanced Tmux Supervisor Dashboard with Agent Support

set -euo pipefail

SUPERVISOR_SESSION="supervisor-dashboard"
ORCHESTRATOR_SESSION="agent-orchestrator"
COORDINATION_DIR="${COORDINATION_DIR:-$HOME/coordination}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

# Function to create enhanced dashboard
create_agent_dashboard() {
    # Kill old session if exists
    tmux kill-session -t "$SUPERVISOR_SESSION" 2>/dev/null || true

    # Create new session
    tmux new-session -d -s "$SUPERVISOR_SESSION" -n main

    # Get list of regular sessions (non-agent)
    local regular_sessions=($(tmux ls -F '#{session_name}' 2>/dev/null | \
        grep -v -E "^($SUPERVISOR_SESSION|$ORCHESTRATOR_SESSION)$" || true))

    # Check if orchestrator is running
    local has_orchestrator=0
    if tmux has-session -t "$ORCHESTRATOR_SESSION" 2>/dev/null; then
        has_orchestrator=1
    fi

    if [[ ${#regular_sessions[@]} -eq 0 ]] && [[ $has_orchestrator -eq 0 ]]; then
        echo -e "${YELLOW}No sessions to monitor${NC}"
        tmux send-keys -t "$SUPERVISOR_SESSION:main" \
            "echo 'No sessions to monitor. Start some tmux sessions or launch the orchestrator.'" Enter
        return
    fi

    echo -e "${GREEN}Creating enhanced dashboard...${NC}"

    # Create panes for regular sessions
    local pane_index=1
    for session in "${regular_sessions[@]}"; do
        if [[ $pane_index -gt 1 ]]; then
            tmux split-window -t "$SUPERVISOR_SESSION:main" -v
            tmux select-layout -t "$SUPERVISOR_SESSION:main" tiled
        fi

        # Monitor regular session
        tmux send-keys -t "$SUPERVISOR_SESSION:main.$pane_index" \
            "echo -e '${CYAN}━━━ Session: $session ━━━${NC}' && watch -t -n 2 'tmux capture-pane -t $session -p 2>/dev/null | head -35 || echo \"Session unavailable\"'" Enter

        ((pane_index++))
    done

    # Add orchestrator monitoring pane if running
    if [[ $has_orchestrator -eq 1 ]]; then
        tmux split-window -t "$SUPERVISOR_SESSION:main" -v
        tmux select-layout -t "$SUPERVISOR_SESSION:main" tiled

        # Monitor orchestrator
        tmux send-keys -t "$SUPERVISOR_SESSION:main.$pane_index" \
            "echo -e '${PURPLE}━━━ AGENT ORCHESTRATOR ━━━${NC}' && watch -t -n 2 'echo \"Active Agents:\"; ls -1 $COORDINATION_DIR/agent_locks/*.lock 2>/dev/null | wc -l; echo \"\"; echo \"Recent Messages:\"; find $COORDINATION_DIR/message_queue -name \"*.msg\" -type f -mmin -5 2>/dev/null | wc -l; echo \"\"; echo \"Work Registry:\"; jq -r \"\\\"Orchestrator: \\\" + (.orchestrator.status // \\\"inactive\\\") + \\\"\\nManagers: \\\" + (.managers | length | tostring) + \\\"\\nEngineers: \\\" + (.engineers | length | tostring)\" $COORDINATION_DIR/active_work_registry.json 2>/dev/null || echo \"No registry\"'" Enter

        ((pane_index++))
    fi

    # Add command pane at bottom
    tmux split-window -t "$SUPERVISOR_SESSION:main" -v -l 4
    tmux send-keys -t "$SUPERVISOR_SESSION:main.$pane_index" \
        "echo -e '${GREEN}[SUPERVISOR]${NC} Commands: broadcast \"msg\" | agent-status | orchestrator-launch'" Enter

    # Final layout adjustment
    tmux select-layout -t "$SUPERVISOR_SESSION:main" tiled

    echo -e "${GREEN}Enhanced dashboard ready!${NC}"
}

# Function to show agent status
show_agent_status() {
    echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}                 AGENT STATUS REPORT${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"
    echo ""

    # Check orchestrator session
    if tmux has-session -t "$ORCHESTRATOR_SESSION" 2>/dev/null; then
        echo -e "${GREEN}✓ Orchestrator session is running${NC}"

        # List orchestrator windows
        echo -e "\n${CYAN}Agent Windows:${NC}"
        tmux list-windows -t "$ORCHESTRATOR_SESSION" -F '  • #{window_name} (#{window_panes} panes)'
    else
        echo -e "${YELLOW}✗ Orchestrator session not running${NC}"
        echo "  Run: claude-orchestrator launch"
    fi

    # Check coordination directory
    if [[ -d "$COORDINATION_DIR" ]]; then
        echo -e "\n${CYAN}Coordination Status:${NC}"

        # Active agents
        local agent_count=$(ls -1 "$COORDINATION_DIR"/agent_locks/*.lock 2>/dev/null | wc -l)
        echo "  • Active agents: $agent_count"

        # Message queues
        local orchestrator_msgs=$(ls -1 "$COORDINATION_DIR"/message_queue/orchestrator/*.msg 2>/dev/null | wc -l)
        local manager_msgs=$(ls -1 "$COORDINATION_DIR"/message_queue/managers/*.msg 2>/dev/null | wc -l)
        local engineer_msgs=$(ls -1 "$COORDINATION_DIR"/message_queue/engineers/*.msg 2>/dev/null | wc -l)

        echo "  • Messages in queues:"
        echo "    - Orchestrator: $orchestrator_msgs"
        echo "    - Managers: $manager_msgs"
        echo "    - Engineers: $engineer_msgs"

        # Work registry summary
        if [[ -f "$COORDINATION_DIR/active_work_registry.json" ]]; then
            echo -e "\n${CYAN}Work Registry:${NC}"
            jq -r '
                "  • Orchestrator: " + (.orchestrator.status // "inactive") + "\n" +
                "  • Active Managers: " + (.managers | length | tostring) + "\n" +
                "  • Active Engineers: " + (.engineers | length | tostring)
            ' "$COORDINATION_DIR/active_work_registry.json" 2>/dev/null || echo "  Registry error"
        fi
    else
        echo -e "\n${YELLOW}Coordination directory not found${NC}"
    fi

    echo ""
}

# Function to launch orchestrator from supervisor
launch_orchestrator_from_supervisor() {
    echo -e "${BLUE}Launching orchestrator...${NC}"

    # Check if already running
    if tmux has-session -t "$ORCHESTRATOR_SESSION" 2>/dev/null; then
        echo -e "${YELLOW}Orchestrator already running${NC}"
        return
    fi

    # Launch orchestrator
    /etc/nixos/scripts/claude-orchestrator.sh launch

    echo -e "${GREEN}Orchestrator launched!${NC}"
    echo "Attach with: tmux attach -t $ORCHESTRATOR_SESSION"
}

# Main command processing
case "${1:-create}" in
    create)
        create_agent_dashboard
        ;;

    attach)
        if tmux has-session -t "$SUPERVISOR_SESSION" 2>/dev/null; then
            tmux attach -t "$SUPERVISOR_SESSION"
        else
            echo -e "${YELLOW}No supervisor session found. Creating...${NC}"
            create_agent_dashboard
            tmux attach -t "$SUPERVISOR_SESSION"
        fi
        ;;

    status)
        show_agent_status
        ;;

    launch-orchestrator)
        launch_orchestrator_from_supervisor
        ;;

    broadcast)
        shift
        # Broadcast to all sessions including agents
        message="$*"
        echo -e "${BLUE}Broadcasting: $message${NC}"

        # Send to regular sessions
        for session in $(tmux ls -F '#{session_name}' | grep -v -E "^($SUPERVISOR_SESSION|$ORCHESTRATOR_SESSION)$"); do
            tmux send-keys -t "$session" "$message" Enter 2>/dev/null && \
                echo -e "  ${GREEN}✓${NC} $session" || \
                echo -e "  ${RED}✗${NC} $session"
        done

        # Send to orchestrator if running
        if tmux has-session -t "$ORCHESTRATOR_SESSION" 2>/dev/null; then
            /etc/nixos/scripts/claude-orchestrator.sh broadcast "$message"
        fi
        ;;

    help)
        cat <<EOF
Enhanced Tmux Supervisor with Agent Support

Usage: $0 [command] [args]

Commands:
  create              - Create enhanced dashboard
  attach              - Attach to dashboard
  status              - Show agent and session status
  launch-orchestrator - Launch the agent orchestrator
  broadcast <msg>     - Broadcast to all sessions and agents
  help                - Show this help

The enhanced dashboard shows:
  - Regular tmux sessions
  - Agent orchestrator status (if running)
  - Message queue statistics
  - Active agent counts
  - Work registry summary

Integration with Orchestrator:
  - Monitors both regular sessions and agent system
  - Shows real-time agent coordination metrics
  - Provides unified broadcast capability

EOF
        ;;

    *)
        create_agent_dashboard
        if [[ -t 0 ]] && [[ -t 1 ]]; then
            tmux attach -t "$SUPERVISOR_SESSION"
        else
            echo -e "${GREEN}Dashboard created.${NC} Attach with: tmux attach -t $SUPERVISOR_SESSION"
        fi
        ;;
esac