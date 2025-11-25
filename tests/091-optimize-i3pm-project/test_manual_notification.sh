#!/usr/bin/env bash
# Manual notification test - simulates Claude Code notification without needing Claude Code
# This allows testing the notification callback functionality independently

set -euo pipefail

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

echo "========================================="
echo "Manual Notification Test"
echo "========================================="
echo ""

# Get current window and project
WINDOW_ID=$(swaymsg -t get_tree | jq -r '.. | objects | select(.type=="con") | select(.focused==true) | .id')
CURRENT_PROJECT=$(i3pm project current 2>/dev/null | grep "Name:" | awk '{print $2}' || echo "none")

echo -e "${BLUE}Current State:${NC}"
echo "  Window ID: $WINDOW_ID"
echo "  Project: $CURRENT_PROJECT"
echo ""

# Send notification with action button
echo -e "${YELLOW}Sending notification...${NC}"

NOTIF_ID=$(notify-send \
    -i "robot" \
    -u normal \
    -p \
    -A "focus=🖥️  Return to Window" \
    "Test Notification - Feature 091" \
    "This is a test notification.\n\n📁 Project: ${CURRENT_PROJECT}\n🪟 Window: ${WINDOW_ID}\n\nClick 'Return to Window' or press Enter to test the callback." 2>&1)

echo -e "${GREEN}✓${NC} Notification sent (ID: $NOTIF_ID)"
echo ""

# Create metadata file for callback
STATE_FILE="/tmp/claude-code-notification-${NOTIF_ID}.meta"
cat > "$STATE_FILE" << EOF
WINDOW_ID=$WINDOW_ID
PROJECT_NAME=$CURRENT_PROJECT
TMUX_SESSION=
TMUX_WINDOW=
EOF

echo -e "${GREEN}✓${NC} Metadata file created: $STATE_FILE"
echo ""

# Display instructions
echo "========================================="
echo "Test Instructions"
echo "========================================="
echo ""
echo "The notification has been sent!"
echo ""
echo -e "${YELLOW}To test the callback:${NC}"
echo ""
echo "1. Switch to a different project:"
echo -e "   ${BLUE}i3pm project switch <another-project>${NC}"
echo ""
echo "2. Click the ${GREEN}'Return to Window'${NC} button on the notification"
echo "   (or press ${GREEN}Enter${NC} while the notification is focused)"
echo ""
echo "3. Expected behavior:"
echo "   ✓ System switches back to project: ${CURRENT_PROJECT}"
echo "   ✓ Focus returns to window: ${WINDOW_ID}"
echo "   ✓ Total time: <1.5 seconds"
echo ""
echo "========================================="
echo "Debugging"
echo "========================================="
echo ""
echo "To monitor the callback in real-time:"
echo -e "  ${BLUE}journalctl --user -t claude-callback -f${NC}"
echo ""
echo "To check SwayNC logs:"
echo -e "  ${BLUE}journalctl --user -u swaync -f${NC}"
echo ""
echo "To manually trigger the callback (for debugging):"
echo -e "  ${BLUE}export SWAYNC_ID=\"$NOTIF_ID\" && /etc/nixos/scripts/claude-hooks/swaync-action-callback.sh${NC}"
echo ""

# Set a cleanup timeout
(sleep 300 && rm -f "$STATE_FILE" 2>/dev/null) &

echo "Metadata file will auto-delete in 5 minutes."
echo ""
