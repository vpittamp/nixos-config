#!/usr/bin/env bash
# Manual Test: Cross-Project Return to Claude Code Terminal (User Story 1)
#
# PURPOSE: Verify notification callback switches projects and focuses correct terminal
#
# PREREQUISITES:
# - SwayNC running
# - Ghostty terminal available
# - i3pm daemon running
# - Two projects created (e.g., nixos-090, nixos-089)
# - Claude Code stop-notification scripts enhanced with project switching logic

set -euo pipefail

echo "=== Manual Test: Cross-Project Return (US1) ==="
echo ""
echo "SETUP:"
echo "1. Create/switch to test project A (e.g., nixos-090)"
echo "2. Open terminal on workspace 1"
echo "3. Get terminal window ID and project name"
echo "4. Switch to test project B (e.g., nixos-089)"
echo "5. Trigger notification with project context"
echo "6. Click 'Return to Window' or press Ctrl+R"
echo "7. Verify system switches back to project A and focuses terminal"
echo ""

# Prerequisite check
if ! pgrep -f "i3-project-event-listener" >/dev/null 2>&1; then
    echo "ERROR: i3pm daemon not running"
    echo "Start with: systemctl --user start i3-project-event-listener"
    exit 1
fi

# Step 1: Get current project (or create test project)
CURRENT_PROJECT=$(i3pm project current 2>/dev/null | grep "^Current project:" | awk '{print $3}')

if [ -z "$CURRENT_PROJECT" ]; then
    echo "WARNING: No active project. Using global mode for test."
    PROJECT_A="global"
else
    PROJECT_A="$CURRENT_PROJECT"
fi

echo "Step 1: Test project A: $PROJECT_A"

# Step 2: Ensure terminal on workspace 1
echo "Step 2: Ensuring terminal on workspace 1..."
swaymsg "workspace 1"
sleep 0.5

TERMINAL_COUNT=$(swaymsg -t get_tree | jq '[.. | objects | select(.type=="con") | select(.app_id=="com.mitchellh.ghostty")] | length')

if [ "$TERMINAL_COUNT" -eq "0" ]; then
    echo "  Launching terminal..."
    ghostty &
    sleep 2
fi

# Step 3: Get window ID and verify project context
echo "Step 3: Getting terminal window ID and project..."
WINDOW_ID=$(swaymsg -t get_tree | jq -r '.. | objects | select(.type=="con") | select(.focused==true) | .id' | head -1)

if [ -z "$WINDOW_ID" ]; then
    echo "  ERROR: Could not get window ID"
    exit 1
fi

echo "  Terminal Window ID: $WINDOW_ID"
echo "  Project A: $PROJECT_A"

# Step 4: Switch to different project (or different workspace for global mode)
echo "Step 4: Switching context..."

if [ "$PROJECT_A" != "global" ]; then
    # Try to switch to a different project
    AVAILABLE_PROJECTS=$(i3pm project list 2>/dev/null | tail -n +2)
    PROJECT_B=$(echo "$AVAILABLE_PROJECTS" | grep -v "$PROJECT_A" | head -1)
    
    if [ -n "$PROJECT_B" ]; then
        echo "  Switching to project B: $PROJECT_B"
        i3pm project switch "$PROJECT_B"
        sleep 1
    else
        echo "  WARNING: Only one project available, using workspace switch instead"
        swaymsg "workspace 5"
        PROJECT_B="workspace-5"
    fi
else
    echo "  Global mode - switching to workspace 5"
    swaymsg "workspace 5"
    PROJECT_B="workspace-5"
fi

# Step 5: Trigger notification with project context
echo "Step 5: Triggering notification with project context..."
echo "  Running notification handler in background..."

# Simulate notification handler call WITH project name
nohup scripts/claude-hooks/stop-notification-handler.sh \
    "$WINDOW_ID" \
    "Test notification - Click 'Return to Window' to return to project $PROJECT_A" \
    "" \
    "" \
    "$PROJECT_A" \
    >/dev/null 2>&1 &

HANDLER_PID=$!
echo "  Notification handler PID: $HANDLER_PID"

# Step 6: User interaction
echo ""
echo "==== USER ACTION REQUIRED ===="
echo "You should now see a notification:"
echo "  'Test notification - Click Return to Window to return to project $PROJECT_A'"
echo ""
echo "Click 'Return to Window' or press Ctrl+R"
echo ""
echo "Press Enter when you've clicked the notification action..."
read -r

# Step 7: Verify results
echo ""
echo "Step 7: Verifying results..."
sleep 1

# Check focused workspace and window
FOCUSED_WS=$(swaymsg -t get_workspaces | jq -r '.[] | select(.focused==true) | .num')
FOCUSED_WINDOW=$(swaymsg -t get_tree | jq -r '.. | objects | select(.type=="con") | select(.focused==true) | .app_id' | head -1)

# Check current project (if not global)
CURRENT_PROJECT_AFTER=""
if [ "$PROJECT_A" != "global" ]; then
    CURRENT_PROJECT_AFTER=$(i3pm project current 2>/dev/null | grep "^Current project:" | awk '{print $3}')
fi

echo "  Focused workspace: $FOCUSED_WS (expected: 1)"
echo "  Focused window app_id: $FOCUSED_WINDOW (expected: com.mitchellh.ghostty)"

if [ "$PROJECT_A" != "global" ]; then
    echo "  Current project: $CURRENT_PROJECT_AFTER (expected: $PROJECT_A)"
fi

# Determine test result
SUCCESS=true

if [ "$FOCUSED_WS" -ne "1" ] || [ "$FOCUSED_WINDOW" != "com.mitchellh.ghostty" ]; then
    SUCCESS=false
fi

if [ "$PROJECT_A" != "global" ] && [ "$CURRENT_PROJECT_AFTER" != "$PROJECT_A" ]; then
    SUCCESS=false
fi

if [ "$SUCCESS" = true ]; then
    echo ""
    echo "✅ TEST PASSED: Cross-project navigation successful"
    if [ "$PROJECT_A" != "global" ]; then
        echo "  - Project switched back to $PROJECT_A"
    fi
    echo "  - Workspace 1 focused"
    echo "  - Terminal focused"
    exit 0
else
    echo ""
    echo "❌ TEST FAILED: Cross-project navigation failed"
    echo "  Expected: project=$PROJECT_A, workspace=1, window=com.mitchellh.ghostty"
    echo "  Got: project=$CURRENT_PROJECT_AFTER, workspace=$FOCUSED_WS, window=$FOCUSED_WINDOW"
    exit 1
fi
