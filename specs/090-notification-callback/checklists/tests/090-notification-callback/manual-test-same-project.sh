#!/usr/bin/env bash
# Manual Test: Same-Project Terminal Focus (User Story 2)
#
# PURPOSE: Verify notification callback focuses correct terminal in same project
#
# PREREQUISITES:
# - SwayNC running
# - Ghostty terminal available
# - swaymsg available
# - Claude Code stop-notification scripts enhanced with window focus logic

set -euo pipefail

echo "=== Manual Test: Same-Project Terminal Focus (US2) ==="
echo ""
echo "SETUP:"
echo "1. Open terminal on workspace 1"
echo "2. Get terminal window ID"
echo "3. Switch to workspace 3"
echo "4. Trigger notification with terminal window ID"
echo "5. Click 'Return to Window' or press Ctrl+R"
echo "6. Verify workspace 1 focused and terminal receives input"
echo ""

# Step 1: Launch terminal on workspace 1 (if not already open)
echo "Step 1: Ensuring terminal on workspace 1..."
swaymsg "workspace 1"
sleep 0.5

# Check if terminal already open
TERMINAL_COUNT=$(swaymsg -t get_tree | jq '[.. | objects | select(.type=="con") | select(.app_id=="com.mitchellh.ghostty")] | length')

if [ "$TERMINAL_COUNT" -eq "0" ]; then
    echo "  Launching terminal..."
    ghostty &
    sleep 2
fi

# Step 2: Get terminal window ID
echo "Step 2: Getting terminal window ID..."
WINDOW_ID=$(swaymsg -t get_tree | jq -r '.. | objects | select(.type=="con") | select(.focused==true) | .id' | head -1)

if [ -z "$WINDOW_ID" ]; then
    echo "  ERROR: Could not get window ID"
    exit 1
fi

echo "  Terminal Window ID: $WINDOW_ID"

# Step 3: Switch to workspace 3
echo "Step 3: Switching to workspace 3..."
swaymsg "workspace 3"
sleep 0.5

# Step 4: Trigger notification
echo "Step 4: Triggering notification..."
echo "  Running notification handler in background..."

# Simulate notification handler call (without project switching for US2)
nohup scripts/claude-hooks/stop-notification-handler.sh \
    "$WINDOW_ID" \
    "Test notification - Click 'Return to Window' to focus terminal on workspace 1" \
    "" \
    "" \
    >/dev/null 2>&1 &

HANDLER_PID=$!
echo "  Notification handler PID: $HANDLER_PID"

# Step 5: User interaction
echo ""
echo "==== USER ACTION REQUIRED ===="
echo "You should now see a notification with two buttons:"
echo "  - 'Return to Window' (or press Ctrl+R)"
echo "  - 'Dismiss' (or press Escape)"
echo ""
echo "Click 'Return to Window' or press Ctrl+R"
echo ""
echo "Press Enter when you've clicked the notification action..."
read -r

# Step 6: Verify results
echo ""
echo "Step 6: Verifying results..."
sleep 0.5

FOCUSED_WS=$(swaymsg -t get_workspaces | jq -r '.[] | select(.focused==true) | .num')
FOCUSED_WINDOW=$(swaymsg -t get_tree | jq -r '.. | objects | select(.type=="con") | select(.focused==true) | .app_id' | head -1)

echo "  Focused workspace: $FOCUSED_WS (expected: 1)"
echo "  Focused window app_id: $FOCUSED_WINDOW (expected: com.mitchellh.ghostty)"

if [ "$FOCUSED_WS" -eq "1" ] && [ "$FOCUSED_WINDOW" = "com.mitchellh.ghostty" ]; then
    echo ""
    echo "✅ TEST PASSED: Terminal focused on workspace 1"
    exit 0
else
    echo ""
    echo "❌ TEST FAILED: Focus did not return to terminal"
    echo "  Expected: workspace 1, com.mitchellh.ghostty"
    echo "  Got: workspace $FOCUSED_WS, $FOCUSED_WINDOW"
    exit 1
fi
