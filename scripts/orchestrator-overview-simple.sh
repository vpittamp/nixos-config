#!/usr/bin/env bash
# Simplified Orchestrator Overview - 6 pane grid view

set -euo pipefail

OVERVIEW_SESSION="orchestrator-overview"
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

create_overview() {
    echo -e "${CYAN}Creating Simplified Orchestrator Overview (2x3 grid)...${NC}"

    # Kill old session
    tmux kill-session -t "$OVERVIEW_SESSION" 2>/dev/null || true

    # Create new session
    tmux new-session -d -s "$OVERVIEW_SESSION" -n "grid"

    # === Create 6-pane layout (2 rows, 3 columns) ===

    # Row 1, Pane 1: Orchestrator
    tmux send-keys -t "$OVERVIEW_SESSION:grid" \
        "watch -t -n 2 'echo -e \"${BOLD}${CYAN}[ORCHESTRATOR]${NC}\" && \
        tmux capture-pane -t $ORCHESTRATOR_SESSION:orchestrator -p 2>/dev/null | tail -12 || \
        echo \"Not running\"'" Enter

    # Row 1, Pane 2: Manager
    tmux split-window -t "$OVERVIEW_SESSION:grid" -h -p 66
    tmux send-keys -t "$OVERVIEW_SESSION:grid" \
        "watch -t -n 2 'echo -e \"${BOLD}${MAGENTA}[MANAGER]${NC}\" && \
        tmux capture-pane -t $ORCHESTRATOR_SESSION:manager-todoapp -p 2>/dev/null | tail -12 || \
        echo \"Not running\"'" Enter

    # Row 1, Pane 3: Engineers
    tmux split-window -t "$OVERVIEW_SESSION:grid" -h -p 50
    tmux send-keys -t "$OVERVIEW_SESSION:grid" \
        "watch -t -n 2 'echo -e \"${BOLD}${BLUE}[ENGINEERS]${NC}\" && \
        echo \"Engineer 1:\" && \
        tmux capture-pane -t $ORCHESTRATOR_SESSION:engineers.1 -p 2>/dev/null | tail -5 || echo \"N/A\" && \
        echo \"---\" && \
        echo \"Engineer 2:\" && \
        tmux capture-pane -t $ORCHESTRATOR_SESSION:engineers.2 -p 2>/dev/null | tail -5 || echo \"N/A\"'" Enter

    # Row 2, Pane 4: Messages & Queues
    tmux select-pane -t "$OVERVIEW_SESSION:grid.1"
    tmux split-window -v -p 50
    tmux send-keys -t "$OVERVIEW_SESSION:grid" \
        "watch -t -n 2 'echo -e \"${BOLD}${YELLOW}[MESSAGES]${NC}\" && \
        echo \"Queues:\" && \
        echo \"  Orch: \$(find $COORDINATION_DIR/message_queue/orchestrator -name \"*.msg\" 2>/dev/null | wc -l) msgs\" && \
        echo \"  Mgrs: \$(find $COORDINATION_DIR/message_queue/managers -name \"*.msg\" 2>/dev/null | wc -l) msgs\" && \
        echo \"  Engs: \$(find $COORDINATION_DIR/message_queue/engineers -name \"*.msg\" 2>/dev/null | wc -l) msgs\" && \
        echo \"\" && \
        echo \"Latest message:\" && \
        latest=\$(ls -t $COORDINATION_DIR/message_queue/*/*.msg 2>/dev/null | head -1) && \
        if [[ -n \"\$latest\" ]]; then \
            jq -r \".message | .[0:40]\" \"\$latest\" 2>/dev/null; \
        else \
            echo \"No messages\"; \
        fi'" Enter

    # Row 2, Pane 5: Active Tasks
    tmux select-pane -t "$OVERVIEW_SESSION:grid.2"
    tmux split-window -v -p 50
    tmux send-keys -t "$OVERVIEW_SESSION:grid" \
        "watch -t -n 3 'echo -e \"${BOLD}${GREEN}[ACTIVE TASKS]${NC}\" && \
        if [[ -f $COORDINATION_DIR/active_work_registry.json ]]; then \
            echo \"Pending:\" && \
            jq -r \".pending_tasks[] | select(.status == \\\"pending\\\") | \\\"• \\(.description | .[0:35])\\\"\" \
                $COORDINATION_DIR/active_work_registry.json 2>/dev/null | head -4 || echo \"None\"; \
            echo \"\" && \
            echo \"Locks: \$(find $COORDINATION_DIR/agent_locks -name \"*.lock\" 2>/dev/null | wc -l) active\"; \
        else \
            echo \"No registry\"; \
        fi'" Enter

    # Row 2, Pane 6: System Status
    tmux select-pane -t "$OVERVIEW_SESSION:grid.3"
    tmux split-window -v -p 50
    tmux send-keys -t "$OVERVIEW_SESSION:grid" \
        "watch -t -n 2 'echo -e \"${BOLD}${RED}[STATUS/ALERTS]${NC}\" && \
        # Check sessions
        if tmux has-session -t $ORCHESTRATOR_SESSION 2>/dev/null; then \
            echo -e \"Orchestrator: ${GREEN}●${NC} Running\"; \
        else \
            echo -e \"Orchestrator: ${RED}●${NC} Down\"; \
        fi; \
        if tmux has-session -t orchestrator-monitor 2>/dev/null; then \
            echo -e \"Monitor: ${GREEN}●${NC} Running\"; \
        else \
            echo -e \"Monitor: ${YELLOW}●${NC} Not running\"; \
        fi; \
        echo \"\" && \
        # Check for alerts
        stale=\$(find $COORDINATION_DIR/agent_locks -name \"*.lock\" -mmin +30 2>/dev/null | wc -l); \
        if [[ \$stale -gt 0 ]]; then \
            echo -e \"${YELLOW}⚠ \$stale stale locks${NC}\"; \
        fi; \
        msgs=\$(find $COORDINATION_DIR/message_queue -name \"*.msg\" 2>/dev/null | wc -l); \
        if [[ \$msgs -gt 20 ]]; then \
            echo -e \"${YELLOW}⚠ High msg queue (\$msgs)${NC}\"; \
        elif [[ \$msgs -eq 0 ]]; then \
            echo -e \"${GREEN}✓ All messages processed${NC}\"; \
        else \
            echo -e \"${GREEN}✓ Messages: \$msgs${NC}\"; \
        fi'" Enter

    # Set layout to tiled for even distribution
    tmux select-layout -t "$OVERVIEW_SESSION:grid" tiled

    # Add status bar
    tmux set-option -t "$OVERVIEW_SESSION" -g status-left "#[fg=cyan,bold]📊 Overview "
    tmux set-option -t "$OVERVIEW_SESSION" -g status-right \
        "#[fg=yellow]M:#(find $COORDINATION_DIR/message_queue -name '*.msg' 2>/dev/null | wc -l) #[fg=green]L:#(find $COORDINATION_DIR/agent_locks -name '*.lock' 2>/dev/null | wc -l) #[fg=cyan]%H:%M"

    echo -e "${GREEN}✓ Simplified overview created (6 panes)${NC}"
    echo -e "${CYAN}View with: tmux attach -t $OVERVIEW_SESSION${NC}"
}

# Add to monitor as new window
add_to_monitor() {
    if tmux has-session -t orchestrator-monitor 2>/dev/null; then
        echo -e "${CYAN}Adding grid to monitor...${NC}"

        # Create new window in monitor
        tmux new-window -t orchestrator-monitor -n "grid" 2>/dev/null || \
            tmux select-window -t orchestrator-monitor:grid

        # Send the same 6-pane setup
        for i in {1..5}; do
            tmux split-window -t orchestrator-monitor:grid 2>/dev/null || true
        done

        tmux select-layout -t orchestrator-monitor:grid tiled

        echo -e "${GREEN}✓ Added to monitor${NC}"
    else
        echo -e "${YELLOW}Monitor not running${NC}"
    fi
}

case "${1:-create}" in
    create)
        create_overview
        ;;
    add-to-monitor)
        add_to_monitor
        ;;
    attach)
        tmux attach -t "$OVERVIEW_SESSION"
        ;;
    kill)
        tmux kill-session -t "$OVERVIEW_SESSION" 2>/dev/null || true
        ;;
    *)
        echo "Usage: $0 {create|add-to-monitor|attach|kill}"
        ;;
esac