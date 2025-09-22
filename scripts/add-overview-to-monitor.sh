#!/usr/bin/env bash
# Add overview grid to existing orchestrator-monitor session

set -euo pipefail

MONITOR_SESSION="orchestrator-monitor"
ORCHESTRATOR_SESSION="${ORCHESTRATOR_SESSION:-orchestrator-demo}"
COORDINATION_DIR="${COORDINATION_DIR:-$HOME/coordination}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
BOLD='\033[1m'
NC='\033[0m'

add_overview() {
    if ! tmux has-session -t "$MONITOR_SESSION" 2>/dev/null; then
        echo -e "${RED}Monitor not running. Start it first with:${NC}"
        echo "  orchestrator-monitor create"
        exit 1
    fi

    echo -e "${CYAN}Adding overview grid to monitor...${NC}"

    # Check if grid window already exists
    if tmux list-windows -t "$MONITOR_SESSION" | grep -q "grid"; then
        echo -e "${YELLOW}Grid window already exists, recreating...${NC}"
        tmux kill-window -t "$MONITOR_SESSION:grid" 2>/dev/null || true
    fi

    # Create new window for grid overview
    tmux new-window -t "$MONITOR_SESSION" -n "grid" -c "$HOME"

    # Create a 2x3 grid (6 panes)
    # Start with first pane (already created)

    # Pane 1: Orchestrator status
    tmux send-keys -t "$MONITOR_SESSION:grid.1" \
        "watch -t -n 2 'printf \"\\033[1;36m%-20s\\033[0m\\n\" \"[ORCHESTRATOR]\" && \
        tmux capture-pane -t $ORCHESTRATOR_SESSION:orchestrator -p 2>/dev/null | tail -10 || \
        echo \"Session not found\"'" Enter

    # Pane 2: Manager status (split horizontally)
    tmux split-window -t "$MONITOR_SESSION:grid.1" -h
    tmux send-keys -t "$MONITOR_SESSION:grid" \
        "watch -t -n 2 'printf \"\\033[1;35m%-20s\\033[0m\\n\" \"[MANAGER]\" && \
        tmux capture-pane -t $ORCHESTRATOR_SESSION:manager-todoapp -p 2>/dev/null | tail -10 || \
        echo \"Session not found\"'" Enter

    # Pane 3: Engineers status (split horizontally)
    tmux split-window -t "$MONITOR_SESSION:grid.2" -h
    tmux send-keys -t "$MONITOR_SESSION:grid" \
        "watch -t -n 2 'printf \"\\033[1;34m%-20s\\033[0m\\n\" \"[ENGINEERS]\" && \
        echo \"== Engineer 1 ==\" && \
        tmux capture-pane -t $ORCHESTRATOR_SESSION:engineers.1 -p 2>/dev/null | tail -4 && \
        echo \"\" && \
        echo \"== Engineer 2 ==\" && \
        tmux capture-pane -t $ORCHESTRATOR_SESSION:engineers.2 -p 2>/dev/null | tail -4 || \
        echo \"No engineers\"'" Enter

    # Now split each column vertically for bottom row
    # Pane 4: Messages (bottom-left)
    tmux select-pane -t "$MONITOR_SESSION:grid.1"
    tmux split-window -v
    tmux send-keys -t "$MONITOR_SESSION:grid" \
        "watch -t -n 2 'printf \"\\033[1;33m%-20s\\033[0m\\n\" \"[MESSAGES]\" && \
        o_msgs=\$(find $COORDINATION_DIR/message_queue/orchestrator -name \"*.msg\" 2>/dev/null | wc -l) && \
        m_msgs=\$(find $COORDINATION_DIR/message_queue/managers -name \"*.msg\" 2>/dev/null | wc -l) && \
        e_msgs=\$(find $COORDINATION_DIR/message_queue/engineers -name \"*.msg\" 2>/dev/null | wc -l) && \
        echo \"Orchestrator: \$o_msgs\" && \
        echo \"Managers: \$m_msgs\" && \
        echo \"Engineers: \$e_msgs\" && \
        total=\$((o_msgs + m_msgs + e_msgs)) && \
        echo \"\" && \
        if [[ \$total -gt 20 ]]; then \
            printf \"\\033[1;33m⚠ High queue: %d\\033[0m\\n\" \$total; \
        else \
            printf \"\\033[0;32m✓ Total: %d\\033[0m\\n\" \$total; \
        fi'" Enter

    # Pane 5: Tasks (bottom-center)
    tmux select-pane -t "$MONITOR_SESSION:grid.2"
    tmux split-window -v
    tmux send-keys -t "$MONITOR_SESSION:grid" \
        "watch -t -n 3 'printf \"\\033[1;32m%-20s\\033[0m\\n\" \"[TASKS]\" && \
        if [[ -f $COORDINATION_DIR/active_work_registry.json ]]; then \
            pending=\$(jq \".pending_tasks | length\" $COORDINATION_DIR/active_work_registry.json 2>/dev/null || echo 0) && \
            echo \"Pending: \$pending\" && \
            echo \"\" && \
            jq -r \".pending_tasks[0:3] | .[] | \\\"• \\(.description | .[0:30])\\\"\" \
                $COORDINATION_DIR/active_work_registry.json 2>/dev/null || echo \"No tasks\"; \
        else \
            echo \"No task registry\"; \
        fi && \
        echo \"\" && \
        locks=\$(find $COORDINATION_DIR/agent_locks -name \"*.lock\" 2>/dev/null | wc -l) && \
        echo \"File locks: \$locks\"'" Enter

    # Pane 6: System status (bottom-right)
    tmux select-pane -t "$MONITOR_SESSION:grid.3"
    tmux split-window -v
    tmux send-keys -t "$MONITOR_SESSION:grid" \
        "watch -t -n 2 'printf \"\\033[1;31m%-20s\\033[0m\\n\" \"[STATUS]\" && \
        if tmux has-session -t $ORCHESTRATOR_SESSION 2>/dev/null; then \
            printf \"\\033[0;32m● Orchestrator OK\\033[0m\\n\"; \
        else \
            printf \"\\033[0;31m● Orchestrator DOWN\\033[0m\\n\"; \
        fi && \
        if tmux has-session -t orchestrator-monitor 2>/dev/null; then \
            printf \"\\033[0;32m● Monitor OK\\033[0m\\n\"; \
        else \
            printf \"\\033[1;33m● Monitor Issue\\033[0m\\n\"; \
        fi && \
        echo \"\" && \
        windows=\$(tmux list-windows -t $ORCHESTRATOR_SESSION 2>/dev/null | wc -l || echo 0) && \
        echo \"Windows: \$windows\" && \
        sessions=\$(tmux ls 2>/dev/null | wc -l) && \
        echo \"Sessions: \$sessions\"'" Enter

    # Apply tiled layout for even distribution
    tmux select-layout -t "$MONITOR_SESSION:grid" tiled

    echo -e "${GREEN}✓ Grid overview added to monitor${NC}"
    echo -e "${CYAN}Navigate to it with: Ctrl-b + 5 (in monitor session)${NC}"
    echo -e "${CYAN}Or directly: tmux select-window -t orchestrator-monitor:grid${NC}"
}

# Main
case "${1:-add}" in
    add)
        add_overview
        ;;
    show)
        if tmux has-session -t "$MONITOR_SESSION" 2>/dev/null; then
            tmux select-window -t "$MONITOR_SESSION:grid"
            echo -e "${GREEN}Switched to grid view${NC}"
        else
            echo -e "${RED}Monitor not running${NC}"
        fi
        ;;
    *)
        echo "Usage: $0 {add|show}"
        echo "  add  - Add grid overview to monitor"
        echo "  show - Switch to grid view"
        ;;
esac