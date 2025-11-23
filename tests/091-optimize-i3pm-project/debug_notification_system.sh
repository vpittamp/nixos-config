#!/usr/bin/env bash
# Debug notification system configuration and test callback execution

set -euo pipefail

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

echo "========================================="
echo "Notification System Debug"
echo "========================================="
echo ""

# Check 1: SwayNC service
echo -e "${BLUE}[1/7]${NC} Checking SwayNC service..."
if systemctl --user is-active --quiet swaync; then
    echo -e "  ${GREEN}✓${NC} SwayNC is running"
else
    echo -e "  ${RED}✗${NC} SwayNC is NOT running"
    echo "  Start with: systemctl --user start swaync"
fi
echo ""

# Check 2: SwayNC configuration
echo -e "${BLUE}[2/7]${NC} Checking SwayNC configuration..."
SWAYNC_CONFIG=$(readlink -f ~/.config/swaync/config.json)
if [ -f "$SWAYNC_CONFIG" ]; then
    echo -e "  ${GREEN}✓${NC} Config file exists: $SWAYNC_CONFIG"

    # Check for script configuration
    if jq -e '.scripts."claude-code-callback"' "$SWAYNC_CONFIG" >/dev/null 2>&1; then
        echo -e "  ${GREEN}✓${NC} claude-code-callback script configured"

        SCRIPT_PATH=$(jq -r '.scripts."claude-code-callback".exec' "$SWAYNC_CONFIG" | awk '{print $NF}')
        echo "  Script path: $SCRIPT_PATH"

        if [ -f "$SCRIPT_PATH" ]; then
            echo -e "  ${GREEN}✓${NC} Callback script exists"
        else
            echo -e "  ${RED}✗${NC} Callback script NOT found at: $SCRIPT_PATH"
        fi
    else
        echo -e "  ${RED}✗${NC} claude-code-callback script NOT configured"
        echo "  SwayNC won't know to run the callback script!"
    fi
else
    echo -e "  ${RED}✗${NC} Config file NOT found"
fi
echo ""

# Check 3: Callback script
echo -e "${BLUE}[3/7]${NC} Checking callback script..."
CALLBACK_SCRIPT="/etc/nixos/scripts/claude-hooks/swaync-action-callback.sh"
if [ -f "$CALLBACK_SCRIPT" ]; then
    echo -e "  ${GREEN}✓${NC} Callback script exists"

    if [ -x "$CALLBACK_SCRIPT" ]; then
        echo -e "  ${GREEN}✓${NC} Callback script is executable"
    else
        echo -e "  ${RED}✗${NC} Callback script is NOT executable"
        echo "  Fix with: chmod +x $CALLBACK_SCRIPT"
    fi

    # Check for syntax errors
    if bash -n "$CALLBACK_SCRIPT" 2>/dev/null; then
        echo -e "  ${GREEN}✓${NC} No syntax errors"
    else
        echo -e "  ${RED}✗${NC} Syntax errors detected!"
    fi
else
    echo -e "  ${RED}✗${NC} Callback script NOT found at: $CALLBACK_SCRIPT"
fi
echo ""

# Check 4: i3pm daemon
echo -e "${BLUE}[4/7]${NC} Checking i3pm daemon..."
if ps aux | grep -v grep | grep -q "python.*i3_project_daemon"; then
    echo -e "  ${GREEN}✓${NC} i3pm daemon is running"

    if command -v i3pm >/dev/null 2>&1; then
        echo -e "  ${GREEN}✓${NC} i3pm command available"

        if i3pm project current >/dev/null 2>&1; then
            echo -e "  ${GREEN}✓${NC} i3pm daemon responding"
        else
            echo -e "  ${RED}✗${NC} i3pm daemon NOT responding"
        fi
    else
        echo -e "  ${RED}✗${NC} i3pm command NOT in PATH"
    fi
else
    echo -e "  ${RED}✗${NC} i3pm daemon is NOT running"
fi
echo ""

# Check 5: Test notification sending
echo -e "${BLUE}[5/7]${NC} Testing notification sending..."
TEST_NOTIF=$(notify-send -p "Test" "This is a test notification" 2>&1)
if [ -n "$TEST_NOTIF" ]; then
    echo -e "  ${GREEN}✓${NC} Notification sent successfully (ID: $TEST_NOTIF)"
else
    echo -e "  ${RED}✗${NC} Failed to send notification"
fi
echo ""

# Check 6: Test action button
echo -e "${BLUE}[6/7]${NC} Testing action button notification..."
ACTION_NOTIF=$(notify-send -p -A "test=Test Action" "Action Test" "Click the action button to test" 2>&1)
if [ -n "$ACTION_NOTIF" ]; then
    echo -e "  ${GREEN}✓${NC} Action notification sent (ID: $ACTION_NOTIF)"
    echo "  You should see a notification with a 'Test Action' button"
else
    echo -e "  ${RED}✗${NC} Failed to send action notification"
fi
echo ""

# Check 7: Recent SwayNC errors
echo -e "${BLUE}[7/7]${NC} Checking recent SwayNC errors..."
ERROR_COUNT=$(journalctl --user -u swaync --since "5 minutes ago" --priority=err 2>/dev/null | wc -l)
if [ "$ERROR_COUNT" -eq 0 ]; then
    echo -e "  ${GREEN}✓${NC} No recent errors"
else
    echo -e "  ${YELLOW}!${NC} Found $ERROR_COUNT errors in last 5 minutes:"
    journalctl --user -u swaync --since "5 minutes ago" --priority=err 2>/dev/null | tail -10 | sed 's/^/  /'
fi
echo ""

# Summary
echo "========================================="
echo "Diagnostic Summary"
echo "========================================="
echo ""

# Check if SwayNC script configuration matches our callback
CONFIGURED_SCRIPT=$(jq -r '.scripts."claude-code-callback".exec // "NONE"' "$SWAYNC_CONFIG" 2>/dev/null | awk '{print $NF}')
if [ "$CONFIGURED_SCRIPT" = "$CALLBACK_SCRIPT" ]; then
    echo -e "${GREEN}✓${NC} SwayNC is configured to call the correct callback script"
elif [ "$CONFIGURED_SCRIPT" = "NONE" ]; then
    echo -e "${RED}✗${NC} SwayNC script configuration is MISSING!"
    echo ""
    echo "Add this to $SWAYNC_CONFIG:"
    echo '  "scripts": {'
    echo '    "claude-code-callback": {'
    echo '      "exec": "/etc/nixos/scripts/claude-hooks/swaync-action-callback.sh",'
    echo '      "run-on": "action",'
    echo '      "summary": "Claude Code Ready"'
    echo '    }'
    echo '  }'
else
    echo -e "${YELLOW}!${NC} Script path mismatch:"
    echo "  Configured: $CONFIGURED_SCRIPT"
    echo "  Expected: $CALLBACK_SCRIPT"
fi

echo ""
echo "To test notifications manually, run:"
echo -e "  ${BLUE}./tests/091-optimize-i3pm-project/test_manual_notification.sh${NC}"
echo ""
