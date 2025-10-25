#!/usr/bin/env bash
#
# Setup SSH + tmux Test Session Helper
#
# Run this script from your RDP session to get instructions
# for setting up a safe testing environment via SSH

set -euo pipefail

# Colors
BLUE='\033[0;34m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Feature 035 Test Setup Helper${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Detect current environment
CURRENT_DISPLAY="${DISPLAY:-}"
CURRENT_USER="$(whoami)"
HOSTNAME="$(hostname)"

echo -e "${GREEN}Current Environment:${NC}"
echo "  User: $CURRENT_USER"
echo "  Hostname: $HOSTNAME"
echo "  DISPLAY: ${CURRENT_DISPLAY:-<not set>}"
echo "  Session: ${XDG_SESSION_TYPE:-unknown}"
echo ""

# Check if in tmux
if [[ -n "${TMUX:-}" ]]; then
    echo -e "${GREEN}✓ Already in tmux session${NC}"
    TMUX_SESSION=$(tmux display-message -p '#S')
    echo "  Session name: $TMUX_SESSION"
    echo ""
    echo -e "${YELLOW}Ready to run tests!${NC}"
    echo ""
    echo "Run:"
    echo "  cd /etc/nixos"
    echo "  ./scripts/test-feature-035.sh --quick"
    exit 0
fi

# Check if via SSH
if [[ -n "${SSH_CONNECTION:-}" ]]; then
    echo -e "${GREEN}✓ Connected via SSH${NC}"
    echo ""
    echo "To run tests in persistent session:"
    echo ""
    echo -e "${YELLOW}1. Start tmux:${NC}"
    echo "   tmux new-session -s i3pm-tests"
    echo ""
    echo -e "${YELLOW}2. Set DISPLAY (if not set):${NC}"
    echo "   export DISPLAY=$CURRENT_DISPLAY"
    echo ""
    echo -e "${YELLOW}3. Run tests:${NC}"
    echo "   cd /etc/nixos"
    echo "   ./scripts/test-feature-035.sh --quick"
    exit 0
fi

# Likely in RDP session
echo -e "${YELLOW}⚠ Appears to be RDP session${NC}"
echo ""
echo "For safe testing without disrupting your RDP session:"
echo ""
echo -e "${GREEN}Option 1: SSH from another device (Recommended)${NC}"
echo "----------------------------------------"
echo "From your laptop, phone, or another terminal:"
echo ""
echo "  ssh $CURRENT_USER@$HOSTNAME"
echo "  tmux new-session -s i3pm-tests"
echo "  export DISPLAY=$CURRENT_DISPLAY"
echo "  cd /etc/nixos"
echo "  ./scripts/test-feature-035.sh --quick"
echo ""
echo "To detach from tmux: Ctrl+b, then d"
echo "To reattach: tmux attach-session -t i3pm-tests"
echo ""

echo -e "${GREEN}Option 2: Run in this RDP session (Will create test windows)${NC}"
echo "----------------------------------------"
echo "Run tests directly (windows will be visible):"
echo ""
echo "  cd /etc/nixos"
echo "  ./scripts/test-feature-035.sh --quick"
echo ""

echo -e "${GREEN}Option 3: Dry-run mode (Safest for RDP)${NC}"
echo "----------------------------------------"
echo "Test without creating windows:"
echo ""
echo "  cd /etc/nixos"
echo "  ./scripts/test-feature-035.sh --quick --dry-run"
echo ""

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "For detailed instructions, see:"
echo "  /etc/nixos/specs/035-now-that-we/TESTING_GUIDE.md"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
