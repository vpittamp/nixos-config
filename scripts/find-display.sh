#!/usr/bin/env bash
#
# Find DISPLAY for active X11/RDP sessions
# Helps SSH users connect to the correct X server

set -euo pipefail

echo "Searching for active X11 sessions..."
echo ""

# Method 1: Check for X processes
echo "Active X servers:"
ps aux | grep -E "Xorg|X11|xrdp" | grep -v grep | awk '{print $1, $2, $11, $12, $13, $14}'
echo ""

# Method 2: Look for DISPLAY in process environments
echo "X11 sessions by user:"
for pid in $(pgrep -u "$USER" | head -20); do
    if [[ -r "/proc/$pid/environ" ]]; then
        display=$(tr '\0' '\n' < "/proc/$pid/environ" 2>/dev/null | grep "^DISPLAY=" | cut -d= -f2)
        if [[ -n "$display" ]]; then
            cmdline=$(tr '\0' ' ' < "/proc/$pid/cmdline" 2>/dev/null | cut -c1-60)
            echo "  PID $pid: DISPLAY=$display ($cmdline...)"
        fi
    fi
done | sort -u
echo ""

# Method 3: Check who output with tty
echo "Login sessions:"
who
echo ""

# Method 4: Find xrdp sessions
if command -v loginctl >/dev/null 2>&1; then
    echo "Active sessions (loginctl):"
    loginctl list-sessions --no-pager 2>/dev/null || true
    echo ""
fi

# Recommendation
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "RECOMMENDATION:"
echo ""
most_common=$(for pid in $(pgrep -u "$USER" | head -20); do
    if [[ -r "/proc/$pid/environ" ]]; then
        tr '\0' '\n' < "/proc/$pid/environ" 2>/dev/null | grep "^DISPLAY=" | cut -d= -f2
    fi
done | sort | uniq -c | sort -rn | head -1 | awk '{print $2}')

if [[ -n "$most_common" ]]; then
    echo "Your RDP session appears to be using: DISPLAY=$most_common"
    echo ""
    echo "To use this in your SSH session, run:"
    echo "  export DISPLAY=$most_common"
    echo ""
    echo "Then test it with:"
    echo "  echo \$DISPLAY"
    echo "  xdpyinfo | head -5"
else
    echo "Could not automatically detect DISPLAY."
    echo "Common values for xrdp are: :10, :11, :12"
    echo ""
    echo "Try:"
    echo "  export DISPLAY=:10"
    echo "  xdpyinfo | head -5"
    echo ""
    echo "If that doesn't work, try :11, :12, etc."
fi
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
