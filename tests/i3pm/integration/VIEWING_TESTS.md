# Viewing Integration Tests Live

You can watch integration tests run in real-time by connecting to the test X server display.

## Methods to View Live Tests

### Method 1: x11vnc (Recommended)

The easiest way to view tests is using VNC to connect to the Xvfb display.

#### Setup (one-time)

```bash
# Install x11vnc (should already be available on NixOS)
nix-shell -p x11vnc
```

#### Run Tests with VNC Viewing

**Terminal 1: Start VNC server on the test display**
```bash
# Wait for tests to start, then run:
DISPLAY=:99 x11vnc -display :99 -forever -shared -nopw

# Or with password:
DISPLAY=:99 x11vnc -display :99 -forever -shared -passwd mypassword
```

**Terminal 2: Start integration tests**
```bash
cd /etc/nixos/tests/i3pm/integration

# Run comprehensive tests
./run_comprehensive_tests.sh

# Or run specific test
nix-shell -p python3Packages.pytest python3Packages.pytest-asyncio python3Packages.textual python3Packages.psutil xorg.xorgserver i3 xdotool xterm x11vnc --run \
  "python -m pytest tests/i3pm/integration/test_user_workflows.py::test_full_user_session_workflow -v -s"
```

**Terminal 3: Connect VNC viewer**
```bash
# Using vncviewer (install if needed)
vncviewer localhost:5900

# Or use any VNC client:
# - RealVNC Viewer
# - TigerVNC
# - Remmina (on Linux)
#
# Connect to: localhost:5900
```

**You'll see:**
- i3 window manager
- Windows opening/closing
- Applications launching (xterm, etc.)
- Workspace switching
- Window marking
- Complete test execution in real-time!

---

### Method 2: X11 Forwarding over SSH

If running tests on a remote server, use X11 forwarding to view locally.

```bash
# SSH with X11 forwarding enabled
ssh -X user@remote-server

# Run tests - they'll display on your local machine
cd /etc/nixos/tests/i3pm/integration
./run_comprehensive_tests.sh
```

**Note:** This requires:
- X server running locally (XQuartz on macOS, X.Org on Linux)
- X11 forwarding enabled in SSH config
- May be slower over network

---

### Method 3: xpra (X Persistent Remote Applications)

For better performance and seamless window integration.

```bash
# Start xpra server on test display
xpra start :99 --bind-tcp=localhost:14500

# Connect from local machine
xpra attach tcp://localhost:14500

# Run tests
./run_comprehensive_tests.sh
```

---

### Method 4: Record to Video

Record test execution for later viewing or sharing.

```bash
# Install ffmpeg with x11grab
nix-shell -p ffmpeg xorg.xorgserver i3

# Start recording
ffmpeg -f x11grab -framerate 30 -video_size 1920x1080 -i :99 \
  -c:v libx264 -preset ultrafast -crf 18 \
  /tmp/test-recording.mp4 &

FFMPEG_PID=$!

# Run tests
./run_comprehensive_tests.sh

# Stop recording
kill $FFMPEG_PID

# View recording
mpv /tmp/test-recording.mp4
```

---

## Viewing Specific Test Scenarios

### Watch User Workflow Test
```bash
# Terminal 1: Start VNC
DISPLAY=:99 x11vnc -display :99 -forever -shared -nopw

# Terminal 2: Run test with delays for viewing
nix-shell -p python3Packages.pytest python3Packages.pytest-asyncio python3Packages.textual python3Packages.psutil xorg.xorgserver i3 xdotool xterm x11vnc --run \
  "python -m pytest tests/i3pm/integration/test_user_workflows.py::test_full_user_session_workflow -v -s"

# Terminal 3: Connect VNC
vncviewer localhost:5900
```

You'll see:
1. i3 starts with test config
2. Project created
3. Application launches (xterm)
4. Layout saved
5. Project switched
6. Layout restored
7. All windows managed automatically

### Watch TUI Interaction Test
```bash
# View TUI navigation
nix-shell -p python3Packages.pytest python3Packages.pytest-asyncio python3Packages.textual python3Packages.psutil xorg.xorgserver i3 xdotool xterm x11vnc --run \
  "python -m pytest tests/i3pm/integration/test_tui_interactions.py::test_tui_full_navigation_workflow -v -s"
```

You'll see:
- TUI application launch
- Tab switching
- Keyboard navigation
- Projects list
- Real Textual UI rendering

### Watch Daemon Integration Test
```bash
# View daemon workflow
nix-shell -p python3Packages.pytest python3Packages.pytest-asyncio python3Packages.textual python3Packages.psutil xorg.xorgserver i3 xdotool xterm x11vnc --run \
  "python -m pytest tests/i3pm/integration/test_daemon_integration.py::test_daemon_full_workflow_simulation -v -s"
```

You'll see:
- Windows opening
- Windows being marked (visible in i3 tree)
- Project context switching
- Window visibility changes

---

## Slowing Down Tests for Viewing

Modify tests to add delays for better viewing:

**Option 1: Add environment variable support**

Edit test file to add delays:
```python
import os

# At start of test
DEMO_MODE = os.getenv('DEMO_MODE', 'false').lower() == 'true'
DEMO_DELAY = float(os.getenv('DEMO_DELAY', '2.0'))

# Before/after actions
if DEMO_MODE:
    await asyncio.sleep(DEMO_DELAY)
```

Run with delays:
```bash
DEMO_MODE=true DEMO_DELAY=3.0 python -m pytest tests/i3pm/integration/test_user_workflows.py -v -s
```

**Option 2: Use pytest --capture=no and add pauses**

Tests already use `await asyncio.sleep()` for stability.
Increase these values in the test files for slower execution:

```python
# Before:
await asyncio.sleep(0.5)

# For demo:
await asyncio.sleep(2.0)  # 2 second pause to observe
```

---

## Complete Live Demo Workflow

Here's a complete script to run a live demo:

```bash
#!/usr/bin/env bash
# Live test demo script

set -e

echo "=== i3pm Integration Test Live Demo ==="
echo ""
echo "Starting in 5 seconds..."
echo "This will:"
echo "  1. Start VNC server on :99 (port 5900)"
echo "  2. Run comprehensive user workflow test"
echo "  3. You can connect with: vncviewer localhost:5900"
echo ""
sleep 5

# Start VNC in background
DISPLAY=:99 x11vnc -display :99 -forever -shared -nopw -bg -o /tmp/vnc.log

echo "✅ VNC server started on localhost:5900"
echo "   Connect now with: vncviewer localhost:5900"
echo ""
echo "Starting test in 5 seconds..."
sleep 5

# Run test
nix-shell -p python3Packages.pytest python3Packages.pytest-asyncio python3Packages.textual python3Packages.psutil xorg.xorgserver i3 xdotool xterm x11vnc --run \
  "python -m pytest tests/i3pm/integration/test_user_workflows.py::test_full_user_session_workflow -v -s"

echo ""
echo "✅ Test complete!"
echo "VNC server still running. Kill with: pkill x11vnc"
```

Save as `demo-live-test.sh`, make executable, and run!

---

## Troubleshooting

### VNC shows black screen
```bash
# Check if Xvfb is running
ps aux | grep Xvfb

# Check if i3 is running
DISPLAY=:99 i3-msg -t get_version

# Restart VNC with verbose output
DISPLAY=:99 x11vnc -display :99 -forever -shared -nopw -v
```

### Can't connect to VNC
```bash
# Check VNC is listening
netstat -tlnp | grep 5900

# Try different port
DISPLAY=:99 x11vnc -display :99 -rfbport 5901 -forever -shared -nopw
```

### Tests run too fast to see
- Add `DEMO_MODE=true` environment variable
- Increase `asyncio.sleep()` durations in tests
- Record to video and play back slowly

---

## What You'll See

### Quick Validation Test (~5s)
- Clean i3 window manager
- Workspace bar (if enabled)
- No windows initially
- Quick status checks
- Clean shutdown

### User Workflow Test (~8s)
- i3 starts
- Project created
- xterm window appears
- Window disappears (project switch)
- Window reappears (layout restore)
- Clean shutdown

### Multi-Project Test (~30s)
- Multiple xterm windows
- Windows appearing/disappearing
- Workspaces being used
- Project transitions visible

### TUI Test (varies)
- Textual UI application launches
- Tab bar visible
- Tables with data
- Keyboard navigation visible
- Status updates

---

## Tips for Best Viewing Experience

1. **Use VNC** - Most reliable, shows exactly what's happening
2. **Increase delays** - Modify tests to pause longer between steps
3. **Record videos** - Great for documentation or bug reports
4. **Split screen** - VNC viewer on one monitor, logs on another
5. **Use tmux** - Multiple panes for VNC, logs, and control

**Example tmux layout:**
```bash
tmux new-session -d -s test-demo
tmux split-window -h
tmux split-window -v
tmux select-pane -t 0
tmux send-keys "DISPLAY=:99 x11vnc -display :99 -forever -shared -nopw" C-m
tmux select-pane -t 1
tmux send-keys "vncviewer localhost:5900" C-m
tmux select-pane -t 2
tmux send-keys "cd /etc/nixos/tests/i3pm/integration" C-m
tmux attach-session -t test-demo
```

---

## Summary

✅ **Best Method**: VNC with x11vnc - Simple, reliable, shows everything
✅ **Best for Demos**: Record to video with ffmpeg
✅ **Best for Development**: VNC + tmux split screen

You can now watch your integration tests run live and see:
- Applications launching
- Windows being managed
- TUI navigation
- Project switching
- Complete user workflows

Perfect for debugging, demos, and understanding test behavior!
