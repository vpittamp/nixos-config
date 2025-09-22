#!/usr/bin/env bash
# Quick launcher to view orchestrator demo in Konsole

set -euo pipefail

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${CYAN}═══════════════════════════════════════════${NC}"
echo -e "${CYAN}    Orchestrator Demo Viewer${NC}"
echo -e "${CYAN}═══════════════════════════════════════════${NC}"
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

# Launch in Konsole with Supervisor profile
if command -v konsole &> /dev/null; then
    echo -e "${GREEN}Launching orchestrator monitor in Konsole...${NC}"
    konsole --profile Supervisor \
        --workdir "$HOME/test-project-multiagent" \
        -e tmux attach-session -t orchestrator-monitor &

    sleep 1

    echo -e "${GREEN}Launching orchestrator demo in separate Konsole...${NC}"
    konsole --profile Default \
        --workdir "$HOME/test-project-multiagent" \
        -e tmux attach-session -t orchestrator-demo &
else
    echo -e "${YELLOW}Konsole not found. Attach manually:${NC}"
    echo "  Monitor: tmux attach -t orchestrator-monitor"
    echo "  Demo: tmux attach -t orchestrator-demo"
fi

echo ""
echo -e "${GREEN}Demo Ready!${NC}"
echo ""
echo -e "${CYAN}Project:${NC} $HOME/test-project-multiagent"
echo ""
echo -e "${YELLOW}Quick Actions:${NC}"
echo "  • View TODO App code: cd ~/test-project-multiagent && ls -la src/"
echo "  • Check messages: agent-message read engineers"
echo "  • View locks: agent-lock list"
echo "  • Send test message: agent-message send orchestrator test 'Hello from user'"
echo ""