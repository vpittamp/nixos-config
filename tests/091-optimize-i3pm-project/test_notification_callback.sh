#!/usr/bin/env bash
# Test script for Feature 090 Notification Callback with Feature 091 optimization
# Tests cross-project notification callback with 1s sleep (reduced from 6s)

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo "========================================="
echo "Feature 090 + 091: Notification Callback Test"
echo "========================================="
echo ""

# Function to show test step
show_step() {
    local step_num=$1
    local step_desc=$2
    echo -e "${BLUE}[Step $step_num]${NC} $step_desc"
}

# Function to show success
show_success() {
    echo -e "  ${GREEN}✓${NC} $1"
}

# Function to show warning
show_warning() {
    echo -e "  ${YELLOW}!${NC} $1"
}

# Function to show error
show_error() {
    echo -e "  ${RED}✗${NC} $1"
}

# Function to wait for user
wait_for_user() {
    echo ""
    echo -e "${YELLOW}Press Enter to continue...${NC}"
    read -r
}

# Check prerequisites
show_step 1 "Checking prerequisites"

# Check SwayNC
if systemctl --user is-active --quiet swaync 2>/dev/null; then
    show_success "SwayNC is running"
else
    show_error "SwayNC is not running"
    echo "  Start with: systemctl --user start swaync"
    exit 1
fi

# Check i3pm daemon
if systemctl --user is-active --quiet i3-project-event-listener 2>/dev/null; then
    show_success "i3pm daemon is running"
else
    show_error "i3pm daemon is not running"
    echo "  Start with: systemctl --user start i3-project-event-listener"
    exit 1
fi

# Check hooks
if [ -f ~/.config/claude-code/hooks/stop.sh ]; then
    show_success "Claude Code stop hook configured"
else
    show_warning "Claude Code stop hook not found"
    echo "  Expected at: ~/.config/claude-code/hooks/stop.sh"
fi

echo ""

# Get current project
CURRENT_PROJECT=$(i3pm project current 2>/dev/null || echo "none")
echo "Current project: ${CURRENT_PROJECT}"
echo ""

# Test workflow
show_step 2 "Simulating notification callback workflow"
echo ""
echo "This test simulates the cross-project callback scenario:"
echo "  1. You're in Project A (current: $CURRENT_PROJECT)"
echo "  2. Claude Code sends a notification"
echo "  3. You switch to Project B"
echo "  4. You click 'Return to Window' on the notification"
echo "  5. System switches back to Project A and focuses terminal"
echo ""

wait_for_user

# Get terminal window ID
WINDOW_ID=$(swaymsg -t get_tree | jq -r '.. | objects | select(.type=="con") | select(.focused==true) | .id' | head -1)
show_step 3 "Current terminal window ID: $WINDOW_ID"

# Send test notification
show_step 4 "Sending test notification..."

NOTIFICATION_OUTPUT=$(notify-send \
    -i "robot" \
    -u normal \
    -p \
    -A "focus=🖥️  Return to Window" \
    "Claude Code Ready (TEST)" \
    "This is a test notification.\n\n📁 ${CURRENT_PROJECT}\n\nClick 'Return to Window' to test callback" 2>&1)

NOTIFICATION_ID="$NOTIFICATION_OUTPUT"
show_success "Notification sent (ID: $NOTIFICATION_ID)"

# Create metadata file (simulating stop-notification.sh behavior)
STATE_FILE="/tmp/claude-code-notification-${NOTIFICATION_ID}.meta"
cat > "$STATE_FILE" << METADATA
WINDOW_ID=$WINDOW_ID
PROJECT_NAME=$CURRENT_PROJECT
TMUX_SESSION=
TMUX_WINDOW=
METADATA

show_success "Metadata file created: $STATE_FILE"
echo ""

# Instructions for manual testing
show_step 5 "Manual Testing Instructions"
echo "  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "  ${YELLOW}Test Scenario 1: Same Project Return${NC}"
echo "    1. You should see a notification now"
echo "    2. Click 'Return to Window' (or press Enter)"
echo "    3. ${GREEN}Verify:${NC} Focus returns to this terminal"
echo ""
echo "  ${YELLOW}Test Scenario 2: Cross-Project Return${NC}"
echo "    1. Switch to another project:"
echo "       ${GREEN}i3pm project switch <other-project>${NC}"
echo "    2. Click 'Return to Window' on the notification"
echo "    3. ${GREEN}Verify:${NC} System switches back to '${CURRENT_PROJECT}' and focuses terminal"
echo "    4. ${GREEN}Verify:${NC} Total callback time <1.5s (fast!)"
echo ""

# Performance monitoring
show_step 6 "Performance Monitoring"
echo "  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "  Watch callback performance in real-time:"
echo "  ${GREEN}journalctl --user -t claude-callback -f${NC}"
echo ""
echo "  Expected output:"
echo "    [Feature 091] Notification callback completed in XXXXms (project: ...)"
echo ""
echo "  Target: <1500ms (1s sleep + <500ms project switch)"
echo ""

# Check recent callback logs
show_step 7 "Recent callback performance"

CALLBACK_LOGS=$(journalctl --user -t claude-callback --since "5 minutes ago" 2>/dev/null || echo "")

if [ -n "$CALLBACK_LOGS" ]; then
    echo "$CALLBACK_LOGS" | tail -5 | sed 's/^/  /'
    echo ""

    # Extract timing if available
    TIMING=$(echo "$CALLBACK_LOGS" | grep -oP 'completed in \K[0-9]+(?=ms)' | tail -1 || echo "")
    if [ -n "$TIMING" ]; then
        if [ "$TIMING" -lt 1500 ]; then
            show_success "Last callback: ${TIMING}ms (<1500ms target ✓)"
        else
            show_warning "Last callback: ${TIMING}ms (exceeds 1500ms target)"
        fi
    fi
else
    show_warning "No recent callback logs found (test hasn't been run yet)"
fi
echo ""

# Summary
echo "========================================="
echo "Test Summary"
echo "========================================="
echo ""
echo "✓ Prerequisites met"
echo "✓ Test notification sent"
echo "✓ Metadata file created"
echo ""
echo "Next steps:"
echo "  1. Click 'Return to Window' on the notification"
echo "  2. Try cross-project callback (switch projects first)"
echo "  3. Monitor callback timing: journalctl --user -t claude-callback -f"
echo ""
echo "Success criteria:"
echo "  ✓ Focus returns to terminal"
echo "  ✓ Project switches correctly (if cross-project)"
echo "  ✓ Total callback time <1.5s"
echo ""
echo "Feature 091 benefit:"
echo "  Before: Required 6s sleep (5.3s project switch + buffer)"
echo "  After:  Only 1s sleep (<200ms project switch + buffer)"
echo "  Improvement: 5x faster callback!"
echo ""
