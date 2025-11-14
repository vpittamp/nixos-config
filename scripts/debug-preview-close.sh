#!/usr/bin/env bash
# Debug script for workspace preview not closing after project switch
# Run this on Hetzner to diagnose the issue

echo "=== Workspace Preview Debug Script ==="
echo ""

# Check if Eww workspace-preview window is open
echo "1. Checking if workspace-preview window is currently open..."
WINDOWS=$(eww --config ~/.config/eww-workspace-bar list-windows 2>/dev/null)
if echo "$WINDOWS" | grep -q "workspace-preview"; then
    echo "   ✓ workspace-preview window IS OPEN"
else
    echo "   ✗ workspace-preview window is NOT open"
fi
echo ""

# Check daemon status
echo "2. Checking workspace-preview-daemon status..."
systemctl --user is-active workspace-preview-daemon >/dev/null 2>&1
if [ $? -eq 0 ]; then
    echo "   ✓ workspace-preview-daemon is running"
else
    echo "   ✗ workspace-preview-daemon is NOT running"
fi
echo ""

# Check recent daemon logs for project_mode events
echo "3. Recent project_mode execute events (last 10)..."
journalctl --user -u workspace-preview-daemon --since "10 minutes ago" --no-pager 2>/dev/null | \
    grep "project_mode event: type=execute" | tail -10
echo ""

# Check if eww close commands were issued
echo "4. Recent eww close commands (last 10)..."
journalctl --user -u workspace-preview-daemon --since "10 minutes ago" --no-pager 2>/dev/null | \
    grep -i "closed eww window\|close workspace-preview" | tail -10
echo ""

# Check workspace mode state
echo "5. Current workspace mode state..."
i3pm-workspace-mode state 2>/dev/null || echo "   Failed to get state"
echo ""

# Test manual close
echo "6. Testing manual close..."
eww --config ~/.config/eww-workspace-bar close workspace-preview 2>&1
if [ $? -eq 0 ]; then
    echo "   ✓ Manual close succeeded"
else
    echo "   ✗ Manual close failed"
fi
echo ""

# Check if window closed
sleep 0.5
WINDOWS_AFTER=$(eww --config ~/.config/eww-workspace-bar list-windows 2>/dev/null)
if echo "$WINDOWS_AFTER" | grep -q "workspace-preview"; then
    echo "   ✗ Window STILL OPEN after manual close!"
else
    echo "   ✓ Window closed successfully"
fi
echo ""

echo "=== Debug complete ==="
echo ""
echo "To reproduce the issue:"
echo "1. Press Ctrl+0 to open workspace mode"
echo "2. Type ':' then project letters (e.g., ':nix')"
echo "3. Press Enter"
echo "4. Run this script again to see if window is still open"
