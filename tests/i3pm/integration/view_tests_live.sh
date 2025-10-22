#!/usr/bin/env bash
# View integration tests live via VNC
# This script:
# 1. Starts x11vnc server on display :99
# 2. Opens VNC viewer window
# 3. Ready to run tests and watch them live

set -euo pipefail

echo "========================================="
echo "i3pm Live Test Viewer Setup"
echo "========================================="
echo ""

# Check if tests are running (Xvfb should be on :99)
if ! ps aux | grep -q "[X]vfb.*:99"; then
    echo "⚠️  No Xvfb running on :99"
    echo ""
    echo "Start tests first with:"
    echo "  ./run_quick_test_standalone.sh"
    echo "  OR"
    echo "  ./run_comprehensive_tests.sh"
    echo ""
    echo "Then run this script in a separate terminal/pane."
    exit 1
fi

echo "✅ Xvfb detected on :99"
echo ""

# Check if x11vnc is already running
if ps aux | grep -q "[x]11vnc.*:99"; then
    echo "⚠️  x11vnc already running on :99"
    echo "    Killing existing instance..."
    pkill -f "x11vnc.*:99" || true
    sleep 1
fi

echo "Starting x11vnc server on :99..."
echo ""

# Start x11vnc in background
DISPLAY=:99 x11vnc -display :99 -forever -shared -nopw -bg -o /tmp/x11vnc.log

# Wait for x11vnc to start
sleep 2

# Check if x11vnc started successfully
if ! ps aux | grep -q "[x]11vnc.*:99"; then
    echo "❌ Failed to start x11vnc"
    echo "Log contents:"
    cat /tmp/x11vnc.log
    exit 1
fi

echo "✅ x11vnc server started on localhost:5900"
echo ""

# Check for VNC viewer
if command -v vncviewer &> /dev/null; then
    echo "Opening VNC viewer window..."
    echo ""
    vncviewer localhost:5900 &
    VNC_PID=$!
    echo "✅ VNC viewer opened (PID: $VNC_PID)"
elif command -v krdc &> /dev/null; then
    echo "Opening Krdc (KDE Remote Desktop)..."
    echo ""
    krdc vnc://localhost:5900 &
    VNC_PID=$!
    echo "✅ Krdc opened (PID: $VNC_PID)"
else
    echo "⚠️  No VNC viewer found"
    echo ""
    echo "VNC server is running on localhost:5900"
    echo ""
    echo "Connect manually with:"
    echo "  - From Mac: VNC Viewer to <server-ip>:5900"
    echo "  - From Linux: vncviewer localhost:5900"
    echo "  - From KDE: krdc vnc://localhost:5900"
fi

echo ""
echo "========================================="
echo "✅ VNC Setup Complete"
echo "========================================="
echo ""
echo "You should now see the test display :99"
echo ""
echo "To run tests and watch them live:"
echo "  In another terminal/pane, run:"
echo "    ./run_quick_test_standalone.sh"
echo "    OR"
echo "    ./run_comprehensive_tests.sh"
echo ""
echo "To stop VNC server:"
echo "  pkill -f 'x11vnc.*:99'"
echo ""
