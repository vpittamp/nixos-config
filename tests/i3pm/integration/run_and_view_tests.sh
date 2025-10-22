#!/usr/bin/env bash
# Run integration tests with live VNC viewing
# This script sets up everything needed to watch tests live

set -euo pipefail

DISPLAY_NUM=99
export DISPLAY=":${DISPLAY_NUM}"

echo "========================================="
echo "i3pm Integration Tests - Live Viewing"
echo "Started: $(date)"
echo "========================================="
echo ""

# Cleanup function
cleanup_all() {
    echo ""
    echo "Cleaning up..."
    pkill -f "x11vnc.*:${DISPLAY_NUM}" 2>/dev/null || true
    ps aux | grep -E "Xvfb.*:${DISPLAY_NUM}" | grep -v grep | awk '{print $2}' | xargs -r kill -9 2>/dev/null || true
    ps aux | grep -E "i3.*DISPLAY=:${DISPLAY_NUM}" | grep -v grep | awk '{print $2}' | xargs -r kill -9 2>/dev/null || true
    ps aux | grep -E "xterm.*DISPLAY=:${DISPLAY_NUM}" | grep -v grep | awk '{print $2}' | xargs -r kill -9 2>/dev/null || true
    echo "Cleanup complete"
}

trap cleanup_all EXIT INT TERM

# Initial cleanup
cleanup_all
sleep 1

echo "Step 1: Starting test environment (Xvfb + i3)..."
echo ""

cd /etc/nixos

# Start test in background with longer timeout to keep environment alive
nix-shell \
    -p python3Packages.pytest \
       python3Packages.pytest-asyncio \
       python3Packages.textual \
       python3Packages.psutil \
       xorg.xorgserver \
       i3 \
       xdotool \
       xterm \
       x11vnc \
       tigervnc \
    --run "python -m pytest tests/i3pm/integration/test_user_workflows.py::test_full_user_session_workflow -v -s --tb=short" &

TEST_PID=$!

echo "Test started (PID: $TEST_PID)"
echo ""

# Wait for Xvfb to start
echo "Step 2: Waiting for Xvfb to start..."
for i in {1..10}; do
    if ps aux | grep -q "[X]vfb.*:${DISPLAY_NUM}"; then
        echo "✅ Xvfb detected on :${DISPLAY_NUM}"
        break
    fi
    sleep 1
done

if ! ps aux | grep -q "[X]vfb.*:${DISPLAY_NUM}"; then
    echo "❌ Xvfb failed to start"
    exit 1
fi

sleep 2

echo ""
echo "Step 3: Starting x11vnc server..."
DISPLAY=:${DISPLAY_NUM} x11vnc -display :${DISPLAY_NUM} -forever -shared -nopw -bg -o /tmp/x11vnc.log

sleep 2

if ! ps aux | grep -q "[x]11vnc.*:${DISPLAY_NUM}"; then
    echo "❌ x11vnc failed to start"
    cat /tmp/x11vnc.log
    exit 1
fi

echo "✅ x11vnc started on localhost:5900"
echo ""

echo "Step 4: Opening VNC viewer..."
if command -v vncviewer &> /dev/null; then
    vncviewer localhost:5900 &
    echo "✅ VNC viewer opened"
elif command -v krdc &> /dev/null; then
    krdc vnc://localhost:5900 &
    echo "✅ Krdc opened"
else
    echo "⚠️  No VNC viewer found"
    echo "   Connect manually to localhost:5900"
fi

echo ""
echo "========================================="
echo "✅ VNC Viewing Active"
echo "========================================="
echo ""
echo "You should now see a window showing the test display!"
echo ""
echo "Watching test execution..."
echo "Press Ctrl+C to stop"
echo ""

# Wait for test to complete
wait $TEST_PID
TEST_EXIT=$?

echo ""
echo "========================================="
echo "Test completed: $(date)"
echo "Exit code: $TEST_EXIT"
echo "========================================="

exit $TEST_EXIT
