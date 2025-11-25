#!/usr/bin/env bash
# Manual Test: Notification Dismissal Without Focus Change (User Story 3)
#
# PURPOSE: Verify notification can be dismissed without changing focus
#
# PREREQUISITES:
# - SwayNC running
# - Ghostty terminal available
# - Claude Code stop-notification scripts installed

set -euo pipefail

echo "=== Manual Test: Notification Dismissal (US3) ==="
echo ""
echo "SETUP:"
echo "1. Open terminal on workspace 1"
echo "2. Switch to workspace 5"
echo "3. Trigger notification"
echo "4. Press Escape to dismiss notification"
echo "5. Verify focus remains on workspace 5 (no change)"
echo ""

# Step 1: Ensure terminal on workspace 1
echo "Step 1: Ensuring terminal on workspace 1..."
swaymsg "workspace 1"
sleep 0.5

TERMINAL_COUNT=$(swaymsg -t get_tree | jq '[.. | objects | select(.type=="con") | select(.app_id=="com.mitchellh.ghostty")] | length')

if [ "$TERMINAL_COUNT" -eq "0" ]; then
    echo "  Launching terminal..."
    ghostty &
    sleep 2
fi

# Step 2: Get window ID
echo "Step 2: Getting terminal window ID..."
WINDOW_ID=$(swaymsg -t get_tree | jq -r '.. | objects | select(.type=="con") | select(.focused==true) | .id' | head -1)

if [ -z "$WINDOW_ID" ]; then
    echo "  ERROR: Could not get window ID"
    exit 1
fi

echo "  Terminal Window ID: $WINDOW_ID"

# Step 3: Switch to workspace 5
echo "Step 3: Switching to workspace 5..."
swaymsg "workspace 5"
sleep 0.5

# Verify we're on workspace 5
FOCUSED_WS_BEFORE=$(swaymsg -t get_workspaces | jq -r '.[] | select(.focused==true) | .num')
echo "  Current workspace: $FOCUSED_WS_BEFORE"

# Step 4: Trigger notification
echo "Step 4: Triggering notification..."
echo "  Running notification handler in background..."

# Simulate notification handler call
nohup scripts/claude-hooks/stop-notification-handler.sh \
    "$WINDOW_ID" \
    "Test notification - Press Escape to dismiss without changing focus" \
    "" \
    "" \
    "" \
    >/dev/null 2>&1 &

HANDLER_PID=$!
echo "  Notification handler PID: $HANDLER_PID"

# Step 5: User interaction
echo ""
echo "==== USER ACTION REQUIRED ===="
echo "You should now see a notification:"
echo "  'Test notification - Press Escape to dismiss without changing focus'"
echo ""
echo "Press Escape to dismiss the notification (do NOT click 'Return to Window')"
echo ""
echo "Press Enter when you've dismissed the notification..."
read -r

# Step 6: Verify results
echo ""
echo "Step 6: Verifying results..."
sleep 0.5

# Check focused workspace (should still be 5)
FOCUSED_WS_AFTER=$(swaymsg -t get_workspaces | jq -r '.[] | select(.focused==true) | .num')
FOCUSED_WINDOW=$(swaymsg -t get_tree | jq -r '.. | objects | select(.type=="con") | select(.focused==true) | .app_id' | head -1)

echo "  Focused workspace before: $FOCUSED_WS_BEFORE"
echo "  Focused workspace after:  $FOCUSED_WS_AFTER (expected: $FOCUSED_WS_BEFORE)"

# Determine test result
if [ "$FOCUSED_WS_BEFORE" -eq "$FOCUSED_WS_AFTER" ]; then
    echo ""
    echo "✅ TEST PASSED: Focus remained on workspace $FOCUSED_WS_AFTER"
    echo "  - Notification dismissed successfully"
    echo "  - No unwanted focus change occurred"
    exit 0
else
    echo ""
    echo "❌ TEST FAILED: Focus changed unexpectedly"
    echo "  Expected: workspace $FOCUSED_WS_BEFORE"
    echo "  Got: workspace $FOCUSED_WS_AFTER"
    exit 1
fi
