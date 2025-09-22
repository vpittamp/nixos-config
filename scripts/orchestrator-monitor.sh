#!/usr/bin/env bash
# Orchestrator-Specific Monitoring Dashboard
# Provides real-time monitoring of multi-agent system with activity indicators

set -euo pipefail

MONITOR_SESSION="orchestrator-monitor"
COORDINATION_DIR="${COORDINATION_DIR:-$HOME/coordination}"
ORCHESTRATOR_SESSION="${ORCHESTRATOR_SESSION:-orchestrator}"

# Colors for visual indicators
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

# Activity indicators
ACTIVE='●'
IDLE='○'
ALERT='▲'
MESSAGE='✉'

# Function to check if orchestrator is running
is_orchestrator_running() {
    tmux has-session -t "$ORCHESTRATOR_SESSION" 2>/dev/null
}

# Function to get agent status
get_agent_status() {
    local agent_id="$1"
    local registry_file="$COORDINATION_DIR/active_work_registry.json"

    if [[ -f "$registry_file" ]]; then
        local status=$(jq -r "
            if .orchestrator.id == \"$agent_id\" then
                .orchestrator.status
            elif .managers[\"$agent_id\"] then
                .managers[\"$agent_id\"].status
            elif .engineers[\"$agent_id\"] then
                .engineers[\"$agent_id\"].status
            else
                \"unknown\"
            end
        " "$registry_file" 2>/dev/null || echo "unknown")
        echo "$status"
    else
        echo "unknown"
    fi
}

# Function to count pending messages
count_pending_messages() {
    local queue="$1"
    local count=0

    if [[ -d "$COORDINATION_DIR/message_queue/$queue" ]]; then
        count=$(find "$COORDINATION_DIR/message_queue/$queue" -name "*.msg" 2>/dev/null | wc -l)
    fi

    echo "$count"
}

# Function to get active locks
get_active_locks() {
    local count=0

    if [[ -d "$COORDINATION_DIR/agent_locks" ]]; then
        count=$(find "$COORDINATION_DIR/agent_locks" -name "*.lock" 2>/dev/null | wc -l)
    fi

    echo "$count"
}

# Function to create monitoring dashboard
create_monitor() {
    # Kill old session if exists
    tmux kill-session -t "$MONITOR_SESSION" 2>/dev/null || true

    # Create new session with multiple windows
    tmux new-session -d -s "$MONITOR_SESSION" -n "agents"

    # Window 1: Agent Status Overview (4 panes)
    # Top-left: Orchestrator
    tmux send-keys -t "$MONITOR_SESSION:agents" \
        "watch -t -n 2 -c 'echo -e \"${BOLD}${CYAN}═══ ORCHESTRATOR STATUS ═══${NC}\" && \
        if tmux capture-pane -t $ORCHESTRATOR_SESSION:orchestrator -p 2>/dev/null | tail -15; then \
            echo -e \"\\n${GREEN}${ACTIVE} Active${NC}\"; \
        else \
            echo -e \"\\n${RED}${IDLE} No orchestrator session${NC}\"; \
        fi'" Enter

    # Top-right: Managers overview
    tmux split-window -t "$MONITOR_SESSION:agents" -h
    tmux send-keys -t "$MONITOR_SESSION:agents" \
        "watch -t -n 2 -c 'echo -e \"${BOLD}${MAGENTA}═══ MANAGERS STATUS ═══${NC}\" && \
        for window in \$(tmux list-windows -t $ORCHESTRATOR_SESSION -F \"#{window_name}\" 2>/dev/null | grep -E \"manager|Manager\" || echo \"\"); do \
            if [[ -n \"\$window\" ]]; then \
                echo -e \"\\n${YELLOW}▸ \$window:${NC}\"; \
                tmux capture-pane -t \"$ORCHESTRATOR_SESSION:\$window\" -p 2>/dev/null | tail -5 | sed \"s/^/  /\"; \
            fi; \
        done; \
        if [[ -z \"\$(tmux list-windows -t $ORCHESTRATOR_SESSION -F \"#{window_name}\" 2>/dev/null | grep -E \"manager|Manager\" || echo \"\")\" ]]; then \
            echo -e \"\\n${DIM}No managers active${NC}\"; \
        fi'" Enter

    # Bottom-left: Engineers overview
    tmux select-pane -t "$MONITOR_SESSION:agents.1"
    tmux split-window -v
    tmux send-keys -t "$MONITOR_SESSION:agents" \
        "watch -t -n 2 -c 'echo -e \"${BOLD}${BLUE}═══ ENGINEERS STATUS ═══${NC}\" && \
        for window in \$(tmux list-windows -t $ORCHESTRATOR_SESSION -F \"#{window_name}\" 2>/dev/null | grep -E \"eng|engineer|Engineer\" || echo \"\"); do \
            if [[ -n \"\$window\" ]]; then \
                echo -e \"\\n${YELLOW}▸ \$window:${NC}\"; \
                tmux capture-pane -t \"$ORCHESTRATOR_SESSION:\$window\" -p 2>/dev/null | tail -5 | sed \"s/^/  /\"; \
            fi; \
        done; \
        if [[ -z \"\$(tmux list-windows -t $ORCHESTRATOR_SESSION -F \"#{window_name}\" 2>/dev/null | grep -E \"eng|engineer|Engineer\" || echo \"\")\" ]]; then \
            echo -e \"\\n${DIM}No engineers active${NC}\"; \
        fi'" Enter

    # Bottom-right: Activity monitor
    tmux select-pane -t "$MONITOR_SESSION:agents.2"
    tmux split-window -v
    tmux send-keys -t "$MONITOR_SESSION:agents" \
        "watch -t -n 1 -c 'echo -e \"${BOLD}${GREEN}═══ ACTIVITY MONITOR ═══${NC}\" && \
        echo -e \"\\n${CYAN}Messages:${NC}\" && \
        echo \"  Orchestrator: \$(find $COORDINATION_DIR/message_queue/orchestrator -name \"*.msg\" 2>/dev/null | wc -l) pending\" && \
        echo \"  Managers: \$(find $COORDINATION_DIR/message_queue/managers -name \"*.msg\" 2>/dev/null | wc -l) pending\" && \
        echo \"  Engineers: \$(find $COORDINATION_DIR/message_queue/engineers -name \"*.msg\" 2>/dev/null | wc -l) pending\" && \
        echo -e \"\\n${YELLOW}Locks:${NC} \$(find $COORDINATION_DIR/agent_locks -name \"*.lock\" 2>/dev/null | wc -l) active\" && \
        echo -e \"\\n${MAGENTA}Registry:${NC}\" && \
        if [[ -f $COORDINATION_DIR/active_work_registry.json ]]; then \
            jq -r \"\\\"  Orchestrator: \\(.orchestrator.status // \\\"idle\\\")\\\\n  Managers: \\(.managers | length)\\\\n  Engineers: \\(.engineers | length)\\\"\" $COORDINATION_DIR/active_work_registry.json 2>/dev/null || echo \"  Parse error\"; \
        else \
            echo \"  No registry\"; \
        fi'" Enter

    # Set even layout
    tmux select-layout -t "$MONITOR_SESSION:agents" tiled

    # Window 2: Message Flow
    tmux new-window -t "$MONITOR_SESSION" -n "messages"

    # Split into 3 panes for each message queue
    tmux send-keys -t "$MONITOR_SESSION:messages" \
        "watch -t -n 2 -c 'echo -e \"${BOLD}${CYAN}═══ ORCHESTRATOR MESSAGES ═══${NC}\" && \
        for msg in \$(ls -t $COORDINATION_DIR/message_queue/orchestrator/*.msg 2>/dev/null | head -5); do \
            if [[ -f \"\$msg\" ]]; then \
                echo -e \"\\n${YELLOW}$(basename \$msg):${NC}\"; \
                jq -r \".message\" \"\$msg\" 2>/dev/null | head -3; \
            fi; \
        done; \
        if [[ -z \"\$(ls $COORDINATION_DIR/message_queue/orchestrator/*.msg 2>/dev/null)\" ]]; then \
            echo -e \"\\n${DIM}No pending messages${NC}\"; \
        fi'" Enter

    tmux split-window -t "$MONITOR_SESSION:messages" -h
    tmux send-keys -t "$MONITOR_SESSION:messages" \
        "watch -t -n 2 -c 'echo -e \"${BOLD}${MAGENTA}═══ MANAGER MESSAGES ═══${NC}\" && \
        for msg in \$(ls -t $COORDINATION_DIR/message_queue/managers/*.msg 2>/dev/null | head -5); do \
            if [[ -f \"\$msg\" ]]; then \
                echo -e \"\\n${YELLOW}$(basename \$msg):${NC}\"; \
                jq -r \".message\" \"\$msg\" 2>/dev/null | head -3; \
            fi; \
        done; \
        if [[ -z \"\$(ls $COORDINATION_DIR/message_queue/managers/*.msg 2>/dev/null)\" ]]; then \
            echo -e \"\\n${DIM}No pending messages${NC}\"; \
        fi'" Enter

    tmux split-window -t "$MONITOR_SESSION:messages" -h
    tmux send-keys -t "$MONITOR_SESSION:messages" \
        "watch -t -n 2 -c 'echo -e \"${BOLD}${BLUE}═══ ENGINEER MESSAGES ═══${NC}\" && \
        for msg in \$(ls -t $COORDINATION_DIR/message_queue/engineers/*.msg 2>/dev/null | head -5); do \
            if [[ -f \"\$msg\" ]]; then \
                echo -e \"\\n${YELLOW}$(basename \$msg):${NC}\"; \
                jq -r \".message\" \"\$msg\" 2>/dev/null | head -3; \
            fi; \
        done; \
        if [[ -z \"\$(ls $COORDINATION_DIR/message_queue/engineers/*.msg 2>/dev/null)\" ]]; then \
            echo -e \"\\n${DIM}No pending messages${NC}\"; \
        fi'" Enter

    tmux select-layout -t "$MONITOR_SESSION:messages" even-horizontal

    # Window 3: Work Progress
    tmux new-window -t "$MONITOR_SESSION" -n "progress"

    # Active tasks
    tmux send-keys -t "$MONITOR_SESSION:progress" \
        "watch -t -n 3 -c 'echo -e \"${BOLD}${GREEN}═══ ACTIVE WORK ═══${NC}\" && \
        if [[ -f $COORDINATION_DIR/active_work_registry.json ]]; then \
            echo -e \"\\n${CYAN}Orchestrator:${NC}\"; \
            jq -r \"if .orchestrator.current_task then \\\"  Task: \\(.orchestrator.current_task)\\\\n  Status: \\(.orchestrator.status)\\\" else \\\"  No active task\\\" end\" $COORDINATION_DIR/active_work_registry.json 2>/dev/null; \
            echo -e \"\\n${MAGENTA}Managers:${NC}\"; \
            jq -r \".managers | to_entries[] | \\\"  \\(.key): \\(.value.current_task // \\\"idle\\\")\\\"\" $COORDINATION_DIR/active_work_registry.json 2>/dev/null || echo \"  None active\"; \
            echo -e \"\\n${BLUE}Engineers:${NC}\"; \
            jq -r \".engineers | to_entries[] | \\\"  \\(.key): \\(.value.current_task // \\\"idle\\\")\\\"\" $COORDINATION_DIR/active_work_registry.json 2>/dev/null || echo \"  None active\"; \
        else \
            echo -e \"\\n${DIM}No work registry found${NC}\"; \
        fi'" Enter

    # Completed work log
    tmux split-window -t "$MONITOR_SESSION:progress" -v
    tmux send-keys -t "$MONITOR_SESSION:progress" \
        "watch -t -n 5 -c 'echo -e \"${BOLD}${YELLOW}═══ COMPLETED WORK (Last 10) ═══${NC}\" && \
        if [[ -f $COORDINATION_DIR/completed_work_log.json ]]; then \
            jq -r \".tasks[-10:] | reverse | .[] | \\\"[\\(.completed_at // \\\"unknown\\\")] \\(.agent_id): \\(.task)\\\"\" $COORDINATION_DIR/completed_work_log.json 2>/dev/null | head -15 || echo \"No completed tasks\"; \
        else \
            echo -e \"\\n${DIM}No completion log found${NC}\"; \
        fi'" Enter

    # Window 4: Alerts & Notifications
    tmux new-window -t "$MONITOR_SESSION" -n "alerts"

    tmux send-keys -t "$MONITOR_SESSION:alerts" \
        "while true; do \
            clear; \
            echo -e \"${BOLD}${RED}═══ ALERTS & NOTIFICATIONS ═══${NC}\"; \
            echo \"\"; \

            # Check for stale locks
            stale_locks=\$(find $COORDINATION_DIR/agent_locks -name \"*.lock\" -mmin +30 2>/dev/null | wc -l); \
            if [[ \$stale_locks -gt 0 ]]; then \
                echo -e \"${RED}${ALERT} ALERT: \$stale_locks stale locks detected (>30 min)${NC}\"; \
            fi; \

            # Check message queue buildup
            total_msgs=\$(find $COORDINATION_DIR/message_queue -name \"*.msg\" 2>/dev/null | wc -l); \
            if [[ \$total_msgs -gt 20 ]]; then \
                echo -e \"${YELLOW}${ALERT} WARNING: High message queue (\$total_msgs messages)${NC}\"; \
            fi; \

            # Check for inactive agents
            if tmux has-session -t $ORCHESTRATOR_SESSION 2>/dev/null; then \
                inactive_windows=\$(tmux list-windows -t $ORCHESTRATOR_SESSION -F \"#{window_name}:#{window_activity}\" | \
                    awk -F: '\$2 < '\$(date +%s)' - 300 {print \$1}' | wc -l); \
                if [[ \$inactive_windows -gt 0 ]]; then \
                    echo -e \"${YELLOW}${IDLE} \$inactive_windows agents inactive >5 min${NC}\"; \
                fi; \
            else \
                echo -e \"${RED}${IDLE} Orchestrator session not running${NC}\"; \
            fi; \

            # Show recent important events
            echo \"\"; \
            echo -e \"${CYAN}Recent Events:${NC}\"; \
            if [[ -f $COORDINATION_DIR/completed_work_log.json ]]; then \
                jq -r \".tasks[-5:] | reverse | .[] | \\\"  [\\(.completed_at // \\\"unknown\\\" | split(\\\"T\\\")[1] | split(\\\".\\\")[0])] \\(.agent_id) completed: \\(.task)\\\"\" \
                    $COORDINATION_DIR/completed_work_log.json 2>/dev/null | head -5 || echo \"  No recent completions\"; \
            fi; \

            # Instructions
            echo \"\"; \
            echo -e \"${DIM}═══════════════════════════════════════${NC}\"; \
            echo -e \"${GREEN}Navigation:${NC}\"; \
            echo \"  • Switch windows: Ctrl-b + number (1-4)\"; \
            echo \"  • Switch panes: Ctrl-b + arrow keys\"; \
            echo \"  • Zoom pane: Ctrl-b + z\"; \
            echo \"  • Detach: Ctrl-b + d\"; \
            echo \"\"; \
            echo -e \"${YELLOW}Actions Required:${NC}\"; \

            if [[ \$stale_locks -gt 0 ]]; then \
                echo \"  • Run: agent-lock clean\"; \
            fi; \

            if [[ \$total_msgs -gt 20 ]]; then \
                echo \"  • Process messages: agent-message read <queue>\"; \
            fi; \

            sleep 5; \
        done" Enter

    # Enable activity monitoring on all windows
    tmux set-option -t "$MONITOR_SESSION" -g monitor-activity on
    tmux set-option -t "$MONITOR_SESSION" -g visual-activity on
    tmux set-option -t "$MONITOR_SESSION" -g activity-action other

    # Set status bar to show activity
    tmux set-option -t "$MONITOR_SESSION" -g status-left-length 30
    tmux set-option -t "$MONITOR_SESSION" -g status-left "#[fg=green]Orchestrator Monitor "
    tmux set-option -t "$MONITOR_SESSION" -g status-right "#[fg=yellow]Messages: #(find $COORDINATION_DIR/message_queue -name '*.msg' 2>/dev/null | wc -l) | Locks: #(find $COORDINATION_DIR/agent_locks -name '*.lock' 2>/dev/null | wc -l)"
    tmux set-option -t "$MONITOR_SESSION" -g status-interval 2

    # Go back to first window
    tmux select-window -t "$MONITOR_SESSION:agents"

    echo -e "${GREEN}✓ Orchestrator monitor created${NC}"
    echo -e "${CYAN}View with: tmux attach -t $MONITOR_SESSION${NC}"
    echo -e "${YELLOW}Windows:${NC}"
    echo "  1. agents   - Live agent status"
    echo "  2. messages - Message flow monitoring"
    echo "  3. progress - Work progress tracking"
    echo "  4. alerts   - Alerts & notifications"
}

# Function to attach to monitor with Konsole profile
attach_with_profile() {
    local profile="${1:-Supervisor}"

    if command -v konsole &> /dev/null; then
        konsole --profile "$profile" -e tmux attach-session -t "$MONITOR_SESSION" &
        echo -e "${GREEN}Launched in Konsole with $profile profile${NC}"
    else
        echo -e "${YELLOW}Konsole not found, attaching in current terminal${NC}"
        tmux attach-session -t "$MONITOR_SESSION"
    fi
}

# Main command handler
case "${1:-create}" in
    create|start)
        if ! is_orchestrator_running; then
            echo -e "${YELLOW}Warning: Orchestrator session not found${NC}"
            echo "Start orchestrator first with: claude-orchestrator launch"
            echo ""
        fi
        create_monitor
        ;;

    attach|view)
        if tmux has-session -t "$MONITOR_SESSION" 2>/dev/null; then
            attach_with_profile "${2:-Supervisor}"
        else
            echo -e "${RED}Monitor not running. Start with: $0 create${NC}"
            exit 1
        fi
        ;;

    stop|kill)
        tmux kill-session -t "$MONITOR_SESSION" 2>/dev/null || true
        echo -e "${YELLOW}Monitor stopped${NC}"
        ;;

    status)
        if tmux has-session -t "$MONITOR_SESSION" 2>/dev/null; then
            echo -e "${GREEN}Monitor is running${NC}"
            tmux list-windows -t "$MONITOR_SESSION"
        else
            echo -e "${RED}Monitor is not running${NC}"
            exit 1
        fi
        ;;

    restart)
        "$0" stop
        sleep 1
        "$0" create
        ;;

    help|*)
        cat <<EOF
Orchestrator Monitoring Dashboard

Usage: $0 <command> [options]

Commands:
  create|start     - Create the monitoring dashboard
  attach|view      - Attach to running monitor
  stop|kill        - Stop the monitor
  status           - Check monitor status
  restart          - Restart the monitor
  help             - Show this help

Features:
  • Real-time agent status monitoring
  • Message queue visualization
  • Work progress tracking
  • Alert notifications for:
    - Stale locks (>30 min)
    - Message queue buildup
    - Inactive agents (>5 min)
  • Activity indicators with colors

Windows:
  1. agents   - Live status of all agents
  2. messages - Message flow between agents
  3. progress - Active and completed work
  4. alerts   - System alerts and notifications

Navigation:
  Switch windows: Ctrl-b + 1/2/3/4
  Switch panes: Ctrl-b + arrows
  Zoom pane: Ctrl-b + z
  Detach: Ctrl-b + d

Examples:
  # Start monitoring
  $0 create

  # View in Konsole with small font
  $0 view Supervisor

  # Check status
  $0 status

EOF
        ;;
esac