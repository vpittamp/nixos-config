#!/usr/bin/env bash
# Complete Orchestrator Viewing Experience
# Shows both the orchestrator demo and the monitoring dashboard with grid overview

set -euo pipefail

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
BOLD='\033[1m'
NC='\033[0m'

echo -e "${BOLD}${CYAN}═══════════════════════════════════════════${NC}"
echo -e "${BOLD}${CYAN}    Complete Orchestrator Dashboard${NC}"
echo -e "${BOLD}${CYAN}═══════════════════════════════════════════${NC}"
echo ""

# Check if sessions exist
if ! tmux has-session -t orchestrator-demo 2>/dev/null; then
    echo -e "${YELLOW}Orchestrator demo not running. Starting...${NC}"
    /etc/nixos/scripts/orchestrator-demo-project.sh
fi

if ! tmux has-session -t orchestrator-monitor 2>/dev/null; then
    echo -e "${YELLOW}Monitor not running. Starting...${NC}"
    ORCHESTRATOR_SESSION=orchestrator-demo /etc/nixos/scripts/orchestrator-monitor.sh create
fi

# Check if grid window exists in monitor
if ! tmux list-windows -t orchestrator-monitor | grep -q "grid"; then
    echo -e "${YELLOW}Adding grid overview...${NC}"
    # Create grid window
    tmux new-window -t orchestrator-monitor -n grid
    for i in {1..5}; do
        tmux split-window -t orchestrator-monitor:grid
        tmux select-layout -t orchestrator-monitor:grid tiled
    done

    # Populate grid
    ORCHESTRATOR_SESSION=orchestrator-demo
    COORDINATION_DIR="$HOME/coordination"

    tmux send-keys -t orchestrator-monitor:grid.1 \
        "watch -t -n 2 'echo \"[ORCHESTRATOR]\" && tmux capture-pane -t orchestrator-demo:orchestrator -p 2>/dev/null | tail -8'" Enter

    tmux send-keys -t orchestrator-monitor:grid.2 \
        "watch -t -n 2 'echo \"[MANAGER]\" && tmux capture-pane -t orchestrator-demo:manager-todoapp -p 2>/dev/null | tail -8'" Enter

    tmux send-keys -t orchestrator-monitor:grid.3 \
        "watch -t -n 2 'echo \"[ENGINEERS]\" && tmux capture-pane -t orchestrator-demo:engineers -p 2>/dev/null | tail -8'" Enter

    tmux send-keys -t orchestrator-monitor:grid.4 \
        "watch -t -n 2 'echo \"[MESSAGES]\" && echo \"Queue: O:\$(find $COORDINATION_DIR/message_queue/orchestrator -name \"*.msg\" 2>/dev/null | wc -l) M:\$(find $COORDINATION_DIR/message_queue/managers -name \"*.msg\" 2>/dev/null | wc -l) E:\$(find $COORDINATION_DIR/message_queue/engineers -name \"*.msg\" 2>/dev/null | wc -l)\"'" Enter

    tmux send-keys -t orchestrator-monitor:grid.5 \
        "watch -t -n 3 'echo \"[TASKS]\" && jq -r \".pending_tasks[0:3] | .[] | \\\"• \\(.description | .[0:25])\\\"\" $COORDINATION_DIR/active_work_registry.json 2>/dev/null'" Enter

    tmux send-keys -t orchestrator-monitor:grid.6 \
        "watch -t -n 2 'echo \"[STATUS]\" && sessions=\$(tmux ls | wc -l) && windows=\$(tmux list-windows -t orchestrator-demo 2>/dev/null | wc -l) && echo \"Sessions: \$sessions, Windows: \$windows\"'" Enter
fi

echo -e "${GREEN}✓ All systems ready!${NC}"
echo ""
echo -e "${CYAN}━━━ Monitoring Dashboard ━━━${NC}"
echo "The monitor has 5 windows:"
echo -e "  ${YELLOW}1.${NC} agents    - Detailed agent status"
echo -e "  ${YELLOW}2.${NC} messages  - Message flow visualization"
echo -e "  ${YELLOW}3.${NC} progress  - Task tracking"
echo -e "  ${YELLOW}4.${NC} alerts    - System notifications"
echo -e "  ${MAGENTA}5.${NC} grid      - ${BOLD}6-pane overview (NEW!)${NC}"
echo ""
echo -e "${CYAN}━━━ View Options ━━━${NC}"
echo ""
echo -e "${GREEN}Option 1:${NC} View grid overview (recommended)"
echo "  tmux attach -t orchestrator-monitor \\; select-window -t 5"
echo ""
echo -e "${GREEN}Option 2:${NC} View in Konsole with small font"
echo "  konsole --profile Supervisor -e tmux attach -t orchestrator-monitor \\; select-window -t 5 &"
echo ""
echo -e "${GREEN}Option 3:${NC} View orchestrator agents"
echo "  tmux attach -t orchestrator-demo"
echo ""
echo -e "${CYAN}━━━ Navigation Tips ━━━${NC}"
echo "  • Switch windows: Ctrl-b + number (1-5)"
echo "  • Switch sessions: Ctrl-b + s"
echo "  • Zoom pane: Ctrl-b + z"
echo "  • Detach: Ctrl-b + d"
echo ""
echo -e "${CYAN}━━━ Grid Layout (Window 5) ━━━${NC}"
echo "  ┌─────────────┬─────────────┬─────────────┐"
echo "  │ Orchestrator│   Manager   │  Engineers  │"
echo "  ├─────────────┼─────────────┼─────────────┤"
echo "  │  Messages   │    Tasks    │   Status    │"
echo "  └─────────────┴─────────────┴─────────────┘"
echo ""

# Launch in Konsole if requested
if [[ "${1:-}" == "--launch" ]]; then
    if command -v konsole &> /dev/null; then
        echo -e "${GREEN}Launching in Konsole...${NC}"
        konsole --profile Supervisor \
            --workdir "$HOME/test-project-multiagent" \
            -e bash -c "tmux attach-session -t orchestrator-monitor \\; select-window -t 5" &
    else
        echo -e "${YELLOW}Konsole not found. Attach manually with commands above.${NC}"
    fi
fi