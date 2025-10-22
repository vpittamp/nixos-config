#!/usr/bin/env bash
# Watch integration tests live - fully automated
# This script:
# 1. Starts extended integration test in background
# 2. Waits for Xvfb to be ready
# 3. Starts x11vnc server on test display
# 4. Opens VNC viewer window on your current display
# 5. You watch the tests run for ~30 seconds!

set -euo pipefail

echo "========================================="
echo "i3pm Integration Tests - Live Viewing"
echo "========================================="
echo ""

# Detect current display
CURRENT_DISPLAY="${DISPLAY:-:10}"
TEST_DISPLAY=":99"

echo "Your display: $CURRENT_DISPLAY"
echo "Test display: $TEST_DISPLAY"
echo ""

# Cleanup function
cleanup() {
    echo ""
    echo "Cleaning up..."
    pkill -f "x11vnc.*:99" 2>/dev/null || true
    pkill -f "vncviewer.*5900" 2>/dev/null || true
    echo "Cleanup complete"
}

trap cleanup EXIT INT TERM

# Initial cleanup
cleanup
sleep 1

echo "========================================="
echo "Step 1: Starting extended test in background"
echo "========================================="
echo ""

cd /etc/nixos

# Start test in background
nix-shell \
    -p python3Packages.pytest \
       python3Packages.pytest-asyncio \
       python3Packages.textual \
       python3Packages.psutil \
       xorg.xorgserver \
       i3 \
       xdotool \
       xterm \
    --run "python -m pytest tests/i3pm/integration/test_extended_scenarios.py::test_progressive_window_launching -v -s" \
    > /tmp/watch_tests_output.log 2>&1 &

TEST_PID=$!
echo "✅ Test started (PID: $TEST_PID)"
echo "   Log: /tmp/watch_tests_output.log"
echo ""

echo "========================================="
echo "Step 2: Waiting for test environment..."
echo "========================================="
echo ""

# Wait for Xvfb to start (max 15 seconds)
echo "Waiting for Xvfb on $TEST_DISPLAY..."
for i in {1..15}; do
    if ls /tmp/.X11-unix/X99 > /dev/null 2>&1; then
        echo "✅ Xvfb detected on $TEST_DISPLAY"
        break
    fi
    sleep 1
    echo -n "."
done
echo ""

if ! ls /tmp/.X11-unix/X99 > /dev/null 2>&1; then
    echo "❌ Xvfb failed to start"
    echo ""
    echo "Test output:"
    tail -20 /tmp/watch_tests_output.log
    exit 1
fi

# Wait a bit more for i3 to be ready
sleep 3

echo ""
echo "========================================="
echo "Step 3: Starting VNC server"
echo "========================================="
echo ""

# Start x11vnc
nix-shell -p x11vnc --run "DISPLAY=$TEST_DISPLAY x11vnc -display $TEST_DISPLAY -forever -shared -nopw -bg -o /tmp/watch_tests_vnc.log"

sleep 2

if ! ps aux | grep -q "[x]11vnc.*:99"; then
    echo "❌ x11vnc failed to start"
    cat /tmp/watch_tests_vnc.log
    exit 1
fi

echo "✅ x11vnc started on localhost:5900"
echo ""

echo "========================================="
echo "Step 4: Opening VNC viewer"
echo "========================================="
echo ""

# Launch VNC viewer on current display
echo "Launching VNC viewer on display $CURRENT_DISPLAY..."
nix-shell -p tigervnc --run "DISPLAY=$CURRENT_DISPLAY vncviewer localhost:5900" &
VNC_VIEWER_PID=$!

sleep 2

if ps -p $VNC_VIEWER_PID > /dev/null 2>&1; then
    echo "✅ VNC viewer opened (PID: $VNC_VIEWER_PID)"
else
    echo "⚠️  VNC viewer may not have opened a window"
    echo "   You can manually connect to: localhost:5900"
fi

echo ""
echo "========================================="
echo "✅ LIVE VIEWING ACTIVE"
echo "========================================="
echo ""
echo "You should now see a VNC viewer window showing:"
echo "  - i3 window manager (test environment)"
echo "  - Windows appearing progressively"
echo "  - 3-4 second pauses between actions"
echo ""
echo "Test will run for approximately 30 seconds."
echo ""
echo "Waiting for test to complete..."
echo "Press Ctrl+C to stop early"
echo ""

# Wait for test to complete
wait $TEST_PID
TEST_EXIT=$?

echo ""
echo "========================================="
echo "Test Complete"
echo "========================================="
echo ""
echo "Exit code: $TEST_EXIT"
echo ""

if [ $TEST_EXIT -eq 0 ]; then
    echo "✅ Test PASSED"
else
    echo "❌ Test FAILED"
    echo ""
    echo "Test output:"
    tail -30 /tmp/watch_tests_output.log
fi

echo ""
echo "Full test output: /tmp/watch_tests_output.log"
echo "VNC log: /tmp/watch_tests_vnc.log"
echo ""

exit $TEST_EXIT
