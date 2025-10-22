#!/usr/bin/env bash
# Live demonstration of integration tests with VNC viewing
# Keeps environment alive longer with visual pauses

set -euo pipefail

DISPLAY_NUM=99
export DISPLAY=":${DISPLAY_NUM}"

echo "========================================="
echo "i3pm Integration Tests - Live Demo"
echo "Started: $(date)"
echo "========================================="
echo ""

# Cleanup function
cleanup_all() {
    echo ""
    echo "Cleaning up all processes..."
    pkill -f "x11vnc.*:${DISPLAY_NUM}" 2>/dev/null || true
    pkill -f "vncviewer.*5900" 2>/dev/null || true
    ps aux | grep -E "Xvfb.*:${DISPLAY_NUM}" | grep -v grep | awk '{print $2}' | xargs -r kill -9 2>/dev/null || true
    ps aux | grep -E "i3.*DISPLAY=:${DISPLAY_NUM}" | grep -v grep | awk '{print $2}' | xargs -r kill -9 2>/dev/null || true
    ps aux | grep -E "xterm.*DISPLAY=:${DISPLAY_NUM}" | grep -v grep | awk '{print $2}' | xargs -r kill -9 2>/dev/null || true
    echo "Cleanup complete"
}

trap cleanup_all EXIT INT TERM
cleanup_all
sleep 2

echo "========================================="
echo "Step 1: Starting Xvfb on :99"
echo "========================================="
echo ""

# Start Xvfb manually
Xvfb :${DISPLAY_NUM} -screen 0 1920x1080x24 -ac +extension GLX +render -noreset &
XVFB_PID=$!
echo "Xvfb started (PID: $XVFB_PID)"

# Wait for Xvfb to be ready
sleep 3

if ! ps -p $XVFB_PID > /dev/null; then
    echo "❌ Xvfb failed to start"
    exit 1
fi

echo "✅ Xvfb running on :${DISPLAY_NUM}"
echo ""

echo "========================================="
echo "Step 2: Starting i3 window manager"
echo "========================================="
echo ""

# Create minimal i3 config
I3_CONFIG_DIR="/tmp/i3_demo_config"
mkdir -p "$I3_CONFIG_DIR"

cat > "$I3_CONFIG_DIR/config" << 'EOF'
# i3 demo config
font pango:monospace 10

# Disable focus follows mouse
focus_follows_mouse no

# Window borders
default_border pixel 2
default_floating_border pixel 2

# Keybindings (minimal)
bindsym Mod4+Return exec xterm
bindsym Mod4+Shift+q kill
bindsym Mod4+Shift+e exit

# Workspaces
bindsym Mod4+1 workspace number 1
bindsym Mod4+2 workspace number 2

# Bar
bar {
    status_command i3status
    position top
}
EOF

# Start i3
DISPLAY=:${DISPLAY_NUM} i3 -c "$I3_CONFIG_DIR/config" > /tmp/i3_demo.log 2>&1 &
I3_PID=$!
echo "i3 started (PID: $I3_PID)"

# Wait for i3 to be ready
sleep 3

# Verify i3 is running
if ! DISPLAY=:${DISPLAY_NUM} i3-msg -t get_version > /dev/null 2>&1; then
    echo "❌ i3 failed to start"
    cat /tmp/i3_demo.log
    exit 1
fi

echo "✅ i3 window manager running"
echo ""

echo "========================================="
echo "Step 3: Starting x11vnc server"
echo "========================================="
echo ""

# Start x11vnc
DISPLAY=:${DISPLAY_NUM} x11vnc -display :${DISPLAY_NUM} -forever -shared -nopw -bg -o /tmp/x11vnc_demo.log

sleep 2

if ! ps aux | grep -q "[x]11vnc.*:${DISPLAY_NUM}"; then
    echo "❌ x11vnc failed to start"
    cat /tmp/x11vnc_demo.log
    exit 1
fi

echo "✅ x11vnc server running on localhost:5900"
echo ""

echo "========================================="
echo "Step 4: Opening VNC viewer"
echo "========================================="
echo ""

# Try to open VNC viewer
VNC_OPENED=false

if command -v vncviewer &> /dev/null; then
    echo "Launching TigerVNC viewer..."
    vncviewer localhost:5900 > /dev/null 2>&1 &
    VNC_PID=$!
    echo "✅ VNC viewer opened (PID: $VNC_PID)"
    VNC_OPENED=true
elif command -v krdc &> /dev/null; then
    echo "Launching Krdc..."
    krdc vnc://localhost:5900 > /dev/null 2>&1 &
    VNC_PID=$!
    echo "✅ Krdc opened (PID: $VNC_PID)"
    VNC_OPENED=true
fi

if [ "$VNC_OPENED" = false ]; then
    echo "⚠️  No VNC viewer found"
    echo ""
    echo "VNC server is running on localhost:5900"
    echo "Connect manually with a VNC client"
fi

echo ""
echo "========================================="
echo "✅ Environment Ready - VNC Viewing Active"
echo "========================================="
echo ""
echo "You should see a window showing i3 on display :99"
echo ""
echo "Now launching demo applications..."
echo ""

sleep 3

# Launch some demo windows
echo "Launching xterm windows (watch them appear in VNC!)..."
for i in {1..3}; do
    echo "  Launching xterm $i..."
    DISPLAY=:${DISPLAY_NUM} xterm -hold -e "echo 'Demo Window $i'; echo 'This is a test window'; bash" &
    sleep 2
done

echo ""
echo "✅ 3 xterm windows launched"
echo ""
echo "========================================="
echo "Demo Running"
echo "========================================="
echo ""
echo "What you should see in VNC viewer:"
echo "  - i3 window manager"
echo "  - i3bar at top showing workspace indicators"
echo "  - 3 xterm windows tiled automatically"
echo ""
echo "The environment will stay alive for 60 seconds."
echo "Press Ctrl+C to exit early."
echo ""

# Keep alive for 60 seconds
for i in {60..1}; do
    echo -ne "Time remaining: ${i}s \r"
    sleep 1
done

echo ""
echo ""
echo "Demo complete!"
