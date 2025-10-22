#!/usr/bin/env bash
# Simple script to view test display :99 on your RDP session (:10)

set -e

echo "========================================"
echo "VNC Viewer for Test Display"
echo "========================================"
echo ""
echo "Your RDP session: DISPLAY=:10"
echo "Test environment: DISPLAY=:99"
echo ""

# Check if test environment is running
if ! ls /tmp/.X11-unix/X99 > /dev/null 2>&1; then
    echo "❌ Test environment (:99) is not running"
    echo ""
    echo "Start it first with:"
    echo "  ./demo_live_viewing.sh"
    echo "  OR"
    echo "  ./run_and_view_tests.sh"
    exit 1
fi

echo "✅ Test environment (:99) detected"

# Check if x11vnc is running on :99
if ! ps aux | grep -q "[x]11vnc.*:99"; then
    echo ""
    echo "Starting x11vnc server on :99..."
    nix-shell -p x11vnc --run "DISPLAY=:99 x11vnc -display :99 -forever -shared -nopw -bg -o /tmp/x11vnc.log"
    sleep 2
fi

if ps aux | grep -q "[x]11vnc.*:99"; then
    echo "✅ x11vnc running on localhost:5900"
else
    echo "❌ Failed to start x11vnc"
    exit 1
fi

echo ""
echo "Opening VNC viewer on your RDP session..."
echo ""

# Launch VNC viewer on display :10 (your RDP session)
nix-shell -p tigervnc --run "DISPLAY=:10 vncviewer localhost:5900" &

echo "✅ VNC viewer launching..."
echo ""
echo "A window should appear showing the test display!"
echo ""
