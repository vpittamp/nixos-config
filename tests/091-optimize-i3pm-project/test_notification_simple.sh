#!/usr/bin/env bash
# Simple notification test without requiring i3pm daemon
# Tests SwayNC notification with action button

set -euo pipefail

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo "========================================="
echo "SwayNC Notification Action Button Test"
echo "========================================="
echo ""

# Check SwayNC
if ! systemctl --user is-active --quiet swaync 2>/dev/null; then
    echo -e "${YELLOW}⚠${NC}  SwayNC is not running"
    echo "  Start with: systemctl --user start swaync"
    exit 1
fi

echo -e "${GREEN}✓${NC} SwayNC is running"
echo ""

# Get current terminal window ID
WINDOW_ID=$(swaymsg -t get_tree | jq -r '.. | objects | select(.type=="con") | select(.focused==true) | .id' | head -1)

echo "Current terminal window ID: $WINDOW_ID"
echo ""

# Send test notification with action button
echo -e "${BLUE}Sending test notification...${NC}"
echo ""

# Get project name if available
PROJECT_NAME="${I3PM_PROJECT_NAME:-test-project}"

# Send notification
NOTIFICATION_OUTPUT=$(notify-send \
    -i "robot" \
    -u normal \
    -p \
    -A "focus=🖥️  Return to Window" \
    "Claude Code Ready (TEST)" \
    "This is a test notification to verify action buttons work.\n\n📁 ${PROJECT_NAME}\n\nClick 'Return to Window' or press Enter to test callback." 2>&1)

NOTIFICATION_ID="$NOTIFICATION_OUTPUT"

echo -e "${GREEN}✓${NC} Notification sent (ID: $NOTIFICATION_ID)"
echo ""

# Create metadata file for callback
STATE_FILE="/tmp/claude-code-notification-${NOTIFICATION_ID}.meta"
cat > "$STATE_FILE" << METADATA
WINDOW_ID=$WINDOW_ID
PROJECT_NAME=$PROJECT_NAME
TMUX_SESSION=
TMUX_WINDOW=
METADATA

echo -e "${GREEN}✓${NC} Metadata file created: $STATE_FILE"
echo ""

# Check if callback script exists
CALLBACK_SCRIPT="/etc/nixos/scripts/claude-hooks/swaync-action-callback.sh"
if [ -f "$CALLBACK_SCRIPT" ]; then
    echo -e "${GREEN}✓${NC} Callback script exists: $CALLBACK_SCRIPT"
else
    echo -e "${YELLOW}⚠${NC}  Callback script not found at: $CALLBACK_SCRIPT"
    echo "  Check your NixOS configuration"
fi
echo ""

# Instructions
echo "========================================="
echo "Test Instructions"
echo "========================================="
echo ""
echo "You should see a notification now. Test it by:"
echo ""
echo "1. ${YELLOW}Click the 'Return to Window' button${NC}"
echo "   - OR -"
echo "2. ${YELLOW}Press Enter while notification is focused${NC}"
echo ""
echo "Expected behavior:"
echo "  ✓ Focus returns to this terminal"
echo "  ✓ No errors in logs"
echo ""
echo "To monitor callback execution:"
echo "  ${BLUE}journalctl --user -t claude-callback -f${NC}"
echo ""
echo "To check SwayNC logs:"
echo "  ${BLUE}journalctl --user -u swaync -f${NC}"
echo ""

# Check if we can detect when notification is clicked
echo "Waiting for callback (30 seconds)..."
echo "(If notification is clicked, you should see callback logs)"
echo ""

# Monitor for callback execution
timeout 30s bash -c '
    journalctl --user -t claude-callback -f 2>/dev/null &
    MONITOR_PID=$!
    sleep 30
    kill $MONITOR_PID 2>/dev/null
' || true

echo ""
echo "Test complete!"
echo ""
echo "If the notification worked:"
echo "  ✓ You clicked the button and focus returned"
echo "  ✓ You saw callback logs above"
echo ""
echo "If it didn't work:"
echo "  - Check SwayNC config: ~/.config/swaync/config.json"
echo "  - Verify callback script: $CALLBACK_SCRIPT"
echo "  - Check logs: journalctl --user -u swaync | tail -50"
echo ""
