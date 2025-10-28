# Quickstart Guide: Hetzner Cloud Sway with Headless Wayland

**Feature**: Feature 046 - Hetzner Cloud Sway Configuration with Headless Wayland
**Created**: 2025-10-28
**Status**: Planning Phase

## Overview

This guide provides step-by-step test scenarios for validating the headless Sway configuration on Hetzner Cloud VM. Each scenario corresponds to a user story from the feature specification.

## Prerequisites

- Hetzner Cloud VM with NixOS installed
- SSH access to VM: `ssh vpittamp@<hetzner-ip>`
- VNC client installed on local machine (TigerVNC, RealVNC, or Screen Sharing)
- Existing hetzner configuration working correctly (i3/X11)

---

## Test Scenario 1: Headless Sway Session Startup

**User Story**: US1 - Headless Sway Session on Hetzner Cloud (Priority: P1)

**Goal**: Verify Sway starts in headless mode with functional VNC remote access

### Step 1.1: Deploy hetzner-sway Configuration

```bash
# On local machine or Codespace
cd /path/to/nixos

# Build configuration (test evaluation)
nixos-rebuild dry-build --flake .#hetzner-sway --target-host vpittamp@<hetzner-ip> --use-remote-sudo

# Deploy configuration
nixos-rebuild switch --flake .#hetzner-sway --target-host vpittamp@<hetzner-ip> --use-remote-sudo

# Reboot VM to start headless session
ssh vpittamp@<hetzner-ip> 'sudo reboot'

# Wait 30 seconds for system to boot
sleep 30
```

**Expected Result**: VM reboots successfully and greetd display manager starts

---

### Step 1.2: Verify Headless Sway Running

```bash
# SSH into VM
ssh vpittamp@<hetzner-ip>

# Check Sway socket exists
echo $SWAYSOCK
# Expected: /run/user/1000/sway-ipc.<PID>.sock

# Verify Sway is running
swaymsg -t get_version
# Expected output:
# {
#   "human_readable": "sway version 1.9",
#   "major": 1,
#   "minor": 9,
#   ...
# }

# Check virtual output created
swaymsg -t get_outputs | jq '.[] | {name, make, model, rect}'
# Expected output:
# {
#   "name": "HEADLESS-1",
#   "make": "headless",
#   "model": "headless",
#   "rect": {"x": 0, "y": 0, "width": 1920, "height": 1080}
# }
```

**Expected Result**:
- ✅ SWAYSOCK environment variable set
- ✅ swaymsg responds with version info
- ✅ Virtual output "HEADLESS-1" exists with 1920x1080 resolution

**Acceptance Criteria**: US1-AS1 (Sway session starts successfully in headless mode)

---

### Step 1.3: Verify wayvnc Service Running

```bash
# Check wayvnc service status
systemctl --user status wayvnc.service
# Expected: active (running) since <timestamp>

# Check port 5900 listening
netstat -tlnp | grep 5900
# Expected: tcp 0 0 0.0.0.0:5900 0.0.0.0:* LISTEN <PID>/wayvnc

# Check wayvnc logs
journalctl --user -u wayvnc.service -n 20
# Expected: "Listening for connections on 0.0.0.0:5900"
```

**Expected Result**:
- ✅ wayvnc.service is active
- ✅ Port 5900 is listening
- ✅ Logs show successful startup

**Acceptance Criteria**: US1-AS2 (wayvnc service starts and listens on port 5900)

---

### Step 1.4: Connect via VNC and Test Window Management

```bash
# On local machine
vncviewer <hetzner-ip>:5900

# Enter credentials when prompted:
# Username: vpittamp
# Password: [your system password]
```

**In VNC session**, test the following keybindings:

| Keybinding | Action | Expected Result |
|------------|--------|----------------|
| `Meta+Return` | Open terminal | Ghostty terminal appears tiled |
| `Meta+Return` (again) | Open second terminal | Window tiles horizontally |
| `Meta+Arrow` keys | Navigate windows | Focus moves between terminals |
| `Ctrl+2` | Switch to workspace 2 | Workspace switches, empty workspace shown |
| `Ctrl+1` | Switch back to workspace 1 | Returns to workspace with terminals |
| `Meta+Shift+Q` | Close focused window | Window closes gracefully |

**Expected Result**:
- ✅ Terminal opens within 500ms
- ✅ Tiling works correctly
- ✅ Focus navigation works
- ✅ Workspace switching works
- ✅ Window closes correctly

**Acceptance Criteria**: US1-AS3, US1-AS4, US1-AS5 (Window management via VNC)

**Success Criteria**: SC-001 (User can perform basic window management via VNC)

---

### Step 1.5: Verify Display Resolution Adaptation

**In VNC client**:
1. Resize VNC client window to 1280x720
2. Observe Sway desktop adapts to new size
3. Resize VNC client window to 2560x1440
4. Observe Sway desktop adapts

**Expected Result**: Sway virtual display scales correctly to VNC client resolution

**Acceptance Criteria**: US1-AS6 (Sway virtual display adapts to VNC resolution)

**Success Criteria**: SC-005 (VNC session provides acceptable performance)

---

## Test Scenario 2: i3pm Daemon Integration

**User Story**: US2 - i3pm Daemon Integration for Headless Sway (Priority: P1)

**Goal**: Verify i3pm daemon connects to headless Sway and provides project management

### Step 2.1: Verify Daemon Connected to Sway

```bash
# SSH into VM
ssh vpittamp@<hetzner-ip>

# Check daemon status
i3pm daemon status

# Expected output:
# i3pm Daemon Status
# ==================
# Status: Connected
# Sway IPC Socket: /run/user/1000/sway-ipc.<PID>.sock
# Uptime: 0:05:23
# Event Subscriptions: window, workspace, output, tick
# Window Tracking: 0 windows tracked
```

**Expected Result**:
- ✅ Status shows "Connected"
- ✅ Daemon connected within 2 seconds of Sway start
- ✅ All event subscriptions active

**Acceptance Criteria**: US2-AS1 (Daemon connects to Sway IPC and loads project configurations)

**Success Criteria**: SC-002 (i3pm daemon connects within 2 seconds)

---

### Step 2.2: Test Project Creation

```bash
# Create test project
i3pm project create test-project \
  --directory ~/test-project \
  --display-name "Test Project" \
  --icon "🧪"

# Verify project created
i3pm project list
# Expected output:
# Available Projects:
# - nixos (NixOS Configuration) [❄️]
# - stacks (Stacks Project) [📚]
# - personal (Personal) [👤]
# - test-project (Test Project) [🧪]

# Switch to test project
i3pm project switch test-project
# Or: pswitch test-project

# Verify active project
i3pm project current
# Expected: test-project
```

**Expected Result**:
- ✅ Project created successfully
- ✅ Project appears in list
- ✅ Can switch to project

**Acceptance Criteria**: US2-AS1 (Daemon loads project configurations)

---

### Step 2.3: Test Application Launch with Project Context

```bash
# SSH into VM with X11 forwarding (if using VNC, skip this and use VNC session)
ssh -X vpittamp@<hetzner-ip>

# Or via VNC: Press Meta+D to open Walker
```

**Via VNC**:
1. Press `Meta+D` to open Walker
2. Type `code` (VS Code)
3. Press `Return`

**Verify window receives project mark**:
```bash
# SSH session
swaymsg -t get_tree | jq '.. | select(.marks?) | select(.marks | length > 0) | {id, app_id, marks, workspace}'

# Expected output:
# {
#   "id": 94532735639728,
#   "app_id": "Code",
#   "marks": ["project:test-project:94532735639728"],
#   "workspace": 2
# }
```

**Expected Result**:
- ✅ VS Code launches within 2 seconds
- ✅ Window receives project mark
- ✅ Window opens on workspace 2 (from registry)

**Acceptance Criteria**: US2-AS2 (VS Code receives project:test-project mark)

**Success Criteria**: SC-006 (Multi-instance applications receive correct project marks)

---

### Step 2.4: Test Project Switching with Window Hiding

```bash
# Launch another application in test-project
# Via VNC: Meta+Return (open terminal)

# Verify both windows marked with test-project
swaymsg -t get_tree | jq '.. | select(.marks?) | select(.marks | contains(["project:test-project"])) | {id, app_id, marks}'

# Switch to different project
i3pm project switch nixos

# Verify test-project windows hidden
swaymsg -t get_tree | jq '.. | select(.marks?) | select(.marks | contains(["project:test-project"])) | {id, scratchpad_state}'
# Expected: scratchpad_state: "changed" (in scratchpad)

# Via VNC: Verify windows no longer visible
```

**Expected Result**:
- ✅ Windows move to scratchpad within 500ms
- ✅ Windows no longer visible in VNC session
- ✅ Other project windows remain visible

**Acceptance Criteria**: US2-AS3 (Windows hide when switching projects)

**Success Criteria**: SC-003 (Project switch hides windows within 500ms)

---

### Step 2.5: Test Project Restoration

```bash
# Switch back to test-project
i3pm project switch test-project

# Verify windows restored
swaymsg -t get_tree | jq '.. | select(.marks?) | select(.marks | contains(["project:test-project"])) | {id, workspace, scratchpad_state}'
# Expected: scratchpad_state: "none" (visible), workspace: 2

# Via VNC: Verify windows reappear on correct workspaces
```

**Expected Result**:
- ✅ Windows restore from scratchpad within 500ms
- ✅ Windows return to original workspaces
- ✅ Windows visible in VNC session

**Acceptance Criteria**: US2-AS4 (Windows restore when switching back to project)

**Success Criteria**: SC-003 (Project switch shows windows within 500ms)

---

### Step 2.6: Test Daemon Event Processing Latency

```bash
# Monitor daemon events in real-time
i3pm daemon events --follow

# In VNC session: Open new window (Meta+Return)

# Observe event log shows:
# - window::new event received
# - Window marked with project within 100ms
# - Event processing time displayed

# Press Ctrl+C to stop following events
```

**Expected Result**:
- ✅ Events processed within 100ms
- ✅ No errors in event log

**Acceptance Criteria**: US2-AS5 (Window receives mark within 100ms)

**Success Criteria**: SC-002 (Event processing latency <100ms)

---

## Test Scenario 3: Walker Launcher Integration

**User Story**: US3 - Walker Launcher on Headless Sway (Priority: P1)

**Goal**: Verify Walker works on headless Sway with all providers functional

### Step 3.1: Test Application Launcher

**Via VNC**:
1. Press `Meta+D` to open Walker
2. Type `code`
3. Observe VS Code appears in results within 200ms
4. Press `Return`
5. Verify VS Code launches with project context

**Expected Result**:
- ✅ Walker opens centered on virtual display
- ✅ Search results appear within 200ms
- ✅ Application launches via app-launcher-wrapper

**Acceptance Criteria**: US3-AS1, US3-AS2, US3-AS3 (Walker application launcher)

**Success Criteria**: SC-004 (Walker and all providers function correctly)

---

### Step 3.2: Test Calculator Provider

**Via VNC**:
1. Press `Meta+D`
2. Type `=2+2`
3. Observe result "4" appears
4. Press `Return`
5. Verify result copied to clipboard

**Test clipboard**:
```bash
# SSH session
wl-paste
# Expected: 4
```

**Expected Result**:
- ✅ Calculator evaluates expression
- ✅ Result copies to clipboard

**Acceptance Criteria**: US3-AS4 (Calculator provider works)

---

### Step 3.3: Test Project Switcher

**Via VNC**:
1. Press `Meta+D`
2. Type `;p ` (semicolon, p, space)
3. Observe list of projects appears with icons
4. Select "nixos" project
5. Press `Return`
6. Verify project switches and i3bar updates

**Expected Result**:
- ✅ Project list shows all projects
- ✅ Active project indicated
- ✅ Project switches correctly

**Acceptance Criteria**: US3-AS5 (Project switcher works)

---

### Step 3.4: Test Clipboard Provider (Wayland wl-clipboard)

**Via VNC**:
1. Open terminal (Meta+Return)
2. Copy text: `echo "test" | wl-copy`
3. Press `Meta+D`
4. Type `:` (colon)
5. Observe clipboard history shows "test"
6. Select entry and press `Return`
7. Verify text pastes at cursor

**Expected Result**:
- ✅ Clipboard history populated
- ✅ wl-clipboard integration works

**Acceptance Criteria**: US3-AS6 (Clipboard provider works with Wayland)

---

## Test Scenario 4: Remote Desktop Performance

**User Story**: US4 - Remote Desktop Performance Optimization (Priority: P2)

**Goal**: Verify acceptable performance for remote desktop workflows

### Step 4.1: Test Window Creation Latency

**Via VNC**:
1. Press `Meta+Return` to open terminal
2. Start stopwatch
3. Measure time until terminal fully visible
4. Repeat 5 times and calculate average

**Expected Result**: Average latency <500ms

**Acceptance Criteria**: US4-AS1 (Window appears within 500ms)

**Success Criteria**: SC-005 (Window creation <500ms)

---

### Step 4.2: Test Workspace Switching Latency

**Via VNC**:
1. Press `Ctrl+2` to switch to workspace 2
2. Start stopwatch
3. Measure time until workspace fully rendered
4. Repeat 5 times and calculate average

**Expected Result**: Average latency <200ms

**Acceptance Criteria**: US4-AS2 (Workspace switch completes within 200ms)

**Success Criteria**: SC-005 (Workspace switching <200ms)

---

### Step 4.3: Test Project Switching Performance

**Via VNC**:
1. Ensure 5+ windows open in current project
2. Press `Meta+P` and switch to different project
3. Start stopwatch
4. Measure time until windows hide/show operations complete
5. Repeat 3 times and calculate average

**Expected Result**: Average latency <500ms with minimal visual artifacts

**Acceptance Criteria**: US4-AS3 (Windows hide/show with minimal artifacts)

**Success Criteria**: SC-003 (Project switch within 500ms)

---

### Step 4.4: Test Resource Usage (Idle)

```bash
# SSH into VM
ssh vpittamp@<hetzner-ip>

# Check Sway memory usage
ps aux | grep sway | grep -v grep
# Expected: RSS <50MB

# Check wayvnc memory usage
ps aux | grep wayvnc | grep -v grep
# Expected: RSS <50MB

# Check i3pm daemon memory usage
ps aux | grep i3pm | grep -v grep
# Expected: RSS <15MB

# Check overall CPU usage (idle state)
top -bn1 | grep "Cpu(s)"
# Expected: <10% total CPU usage
```

**Expected Result**:
- ✅ Sway uses <50MB RAM
- ✅ wayvnc uses <50MB RAM
- ✅ i3pm daemon uses <15MB RAM
- ✅ Total CPU <10% when idle

**Acceptance Criteria**: US4-AS4 (Idle resource usage acceptable)

---

### Step 4.5: Test Keyboard Input Latency

**Via VNC**:
1. Open terminal (Meta+Return)
2. Type rapidly: "the quick brown fox jumps over the lazy dog"
3. Observe character echoing latency
4. Use ping to measure network latency: `ping <hetzner-ip>`

**Expected Result**:
- ✅ Keyboard input latency <100ms (including network latency)
- ✅ No dropped characters
- ✅ Text appears smoothly

**Acceptance Criteria**: US4-AS5 (Keyboard input latency under 100ms)

**Success Criteria**: SC-005 (Keyboard latency <100ms)

---

## Test Scenario 5: Configuration Isolation

**User Story**: US5 - Configuration Isolation from Existing Hetzner (Priority: P2)

**Goal**: Verify hetzner configuration remains unchanged and independent

### Step 5.1: Verify hetzner Configuration Unchanged

```bash
# On local machine
cd /path/to/nixos

# Build hetzner configuration (NOT hetzner-sway)
nixos-rebuild dry-build --flake .#hetzner --target-host vpittamp@<hetzner-ip> --use-remote-sudo

# Check configuration imports i3wm.nix (not sway.nix)
nix eval .#nixosConfigurations.hetzner.config.imports --apply builtins.toString | grep -o "i3wm\|sway"
# Expected: i3wm (not sway)

# Check no Wayland packages in hetzner config
nix eval .#nixosConfigurations.hetzner.config.environment.systemPackages --apply builtins.length
# Compare with hetzner-sway package count (should differ)
```

**Expected Result**:
- ✅ hetzner configuration imports i3wm.nix
- ✅ No Sway or wayvnc packages in hetzner config
- ✅ Configuration evaluates successfully

**Acceptance Criteria**: US5-AS1, US5-AS2 (hetzner config unchanged, no Sway packages)

---

### Step 5.2: Test Switching Between Configurations

```bash
# Deploy hetzner configuration (i3/X11)
nixos-rebuild switch --flake .#hetzner --target-host vpittamp@<hetzner-ip> --use-remote-sudo

# Reboot and verify i3 session starts
ssh vpittamp@<hetzner-ip> 'sudo reboot'
sleep 30

ssh vpittamp@<hetzner-ip>
echo $I3SOCK
# Expected: /run/user/1000/i3/ipc-socket.<PID>

ps aux | grep -E "i3|sway" | grep -v grep
# Expected: i3 process running (not sway)

# Deploy hetzner-sway configuration (Sway/Wayland)
nixos-rebuild switch --flake .#hetzner-sway --target-host vpittamp@<hetzner-ip> --use-remote-sudo

# Reboot and verify Sway session starts
ssh vpittamp@<hetzner-ip> 'sudo reboot'
sleep 30

ssh vpittamp@<hetzner-ip>
echo $SWAYSOCK
# Expected: /run/user/1000/sway-ipc.<PID>.sock

ps aux | grep -E "i3|sway" | grep -v grep
# Expected: sway process running (not i3)
```

**Expected Result**:
- ✅ Can switch from hetzner-sway back to hetzner
- ✅ i3 session starts correctly when using hetzner config
- ✅ Sway session starts correctly when using hetzner-sway config

**Acceptance Criteria**: US5-AS3 (Can switch configurations via NixOS generations)

**Success Criteria**: SC-007, SC-008 (Both configs buildable and deployable, hetzner unchanged)

---

### Step 5.3: Verify No Wayland Packages in hetzner

```bash
# Deploy hetzner configuration
nixos-rebuild switch --flake .#hetzner --target-host vpittamp@<hetzner-ip> --use-remote-sudo

# Check for wayvnc package
ssh vpittamp@<hetzner-ip> 'which wayvnc'
# Expected: command not found

# Check for wl-clipboard
ssh vpittamp@<hetzner-ip> 'which wl-copy'
# Expected: command not found

# Check for Sway
ssh vpittamp@<hetzner-ip> 'which sway'
# Expected: command not found
```

**Expected Result**:
- ✅ Wayland-specific packages not installed in hetzner config

**Acceptance Criteria**: US5-AS4 (No Wayland-specific packages in hetzner)

---

### Step 5.4: Verify Both Configs Build from Same Flake

```bash
# On local machine
cd /path/to/nixos

# Build both configurations (dry-build)
nixos-rebuild dry-build --flake .#hetzner --target-host vpittamp@<hetzner-ip> --use-remote-sudo
# Expected: Success

nixos-rebuild dry-build --flake .#hetzner-sway --target-host vpittamp@<hetzner-ip> --use-remote-sudo
# Expected: Success

# Compare system closures
nix build .#nixosConfigurations.hetzner.config.system.build.toplevel -o result-hetzner
nix build .#nixosConfigurations.hetzner-sway.config.system.build.toplevel -o result-hetzner-sway

ls -lh result-hetzner result-hetzner-sway
# Expected: Different system closures (different output paths)

# Clean up
rm result-hetzner result-hetzner-sway
```

**Expected Result**:
- ✅ Both configurations build successfully
- ✅ System closures are distinct

**Acceptance Criteria**: US5-AS5 (Both configs produce distinct system closures)

**Success Criteria**: SC-007 (Both configs buildable and deployable simultaneously)

---

## Test Scenario 6: Multi-Monitor Support (Virtual Outputs)

**User Story**: US6 - Multi-Monitor Support via Virtual Displays (Priority: P3)

**Goal**: Verify support for multiple virtual outputs in headless mode

### Step 6.1: Test Single Virtual Output (Default)

```bash
# SSH into VM
ssh vpittamp@<hetzner-ip>

# Check output configuration
swaymsg -t get_outputs | jq '.[] | {name, active}'
# Expected: Single output HEADLESS-1, active: true

# Check workspace distribution
i3pm monitors status
# Expected output:
# Monitor Status
# ==============
# Output         | Workspaces      | Primary
# --------------|-----------------|--------
# HEADLESS-1    | 1-70            | Yes
```

**Expected Result**:
- ✅ Single virtual output created
- ✅ All workspaces assigned to HEADLESS-1

**Acceptance Criteria**: US6-AS1 (All workspaces on single output)

---

### Step 6.2: Configure Two Virtual Outputs

```bash
# Edit Sway configuration to add second output
# (This step requires NixOS config update - document process)

# Example Sway config addition:
# output HEADLESS-2 {
#   mode 1920x1080@60Hz
#   position 1920 0
# }

# Reload Sway configuration
swaymsg reload

# Verify two outputs
swaymsg -t get_outputs | jq '.[] | {name, active, rect}'
# Expected:
# {"name": "HEADLESS-1", "active": true, "rect": {"x": 0, "y": 0, "width": 1920, "height": 1080}}
# {"name": "HEADLESS-2", "active": true, "rect": {"x": 1920, "y": 0, "width": 1920, "height": 1080}}
```

**Expected Result**:
- ✅ Two virtual outputs created
- ✅ Positioned side-by-side in compositor layout

**Acceptance Criteria**: US6-AS2 (Two virtual outputs configured)

---

### Step 6.3: Test Workspace Distribution Across Outputs

```bash
# Check workspace-to-monitor mapping
i3pm monitors status
# Expected output:
# Monitor Status
# ==============
# Output         | Workspaces      | Primary
# --------------|-----------------|--------
# HEADLESS-1    | 1-2             | Yes
# HEADLESS-2    | 3-70            | No

# Switch to workspace 3
swaymsg workspace 3

# Verify workspace on correct output
swaymsg -t get_workspaces | jq '.[] | select(.num == 3) | {num, output}'
# Expected: {"num": 3, "output": "HEADLESS-2"}
```

**Expected Result**:
- ✅ Workspaces distributed per configuration
- ✅ WS 1-2 on HEADLESS-1, WS 3-70 on HEADLESS-2

**Acceptance Criteria**: US6-AS2 (Workspace distribution works with two outputs)

---

### Step 6.4: Test VNC Access to Second Output

**Note**: wayvnc exposes one output per instance. To access second output, configure second wayvnc instance on different port or switch wayvnc output configuration.

```bash
# Edit wayvnc config to select HEADLESS-2
echo "output=HEADLESS-2" >> ~/.config/wayvnc/config

# Restart wayvnc
systemctl --user restart wayvnc.service

# Check logs
journalctl --user -u wayvnc.service -n 20
# Expected: "Output: HEADLESS-2"

# Via VNC client: Connect to port 5900
# Verify workspace 3+ visible (workspaces on HEADLESS-2)
```

**Expected Result**:
- ✅ wayvnc can switch between virtual outputs
- ✅ VNC client shows content from HEADLESS-2

**Acceptance Criteria**: US6-AS3 (VNC shows content from second output)

---

### Step 6.5: Verify Monitor Status Command

```bash
# Run monitor status command
i3pm monitors status

# Expected output with two outputs:
# Monitor Status
# ==============
# Output         | Workspaces      | Primary
# --------------|-----------------|--------
# HEADLESS-1    | 1-2             | Yes
# HEADLESS-2    | 3-70            | No

# Total Outputs: 2
# Total Workspaces: 70
```

**Expected Result**:
- ✅ Command shows all virtual outputs
- ✅ Workspace assignments displayed correctly

**Acceptance Criteria**: US6-AS4 (Monitor status shows both outputs)

---

## Edge Case Testing

### Edge Case 1: VNC Connection Drops During Active Session

**Scenario**: Network interruption while working remotely

**Procedure**:
1. Connect via VNC and open multiple windows
2. Disconnect VNC client (simulate network drop)
3. Wait 60 seconds
4. Reconnect VNC client

**Expected Result**:
- ✅ Sway session continues running during disconnect
- ✅ VNC client reconnects without session restart
- ✅ All windows remain in same state (no data loss)

**Acceptance Criteria**: Edge case documentation - Sway continues headless

---

### Edge Case 2: wayvnc Service Failure

**Scenario**: wayvnc crashes but Sway continues running

**Procedure**:
```bash
# SSH into VM
ssh vpittamp@<hetzner-ip>

# Kill wayvnc process
systemctl --user stop wayvnc.service

# Verify Sway still running
swaymsg -t get_version
# Expected: Success

# Check wayvnc auto-restart
sleep 2
systemctl --user status wayvnc.service
# Expected: active (running) - systemd restarted it
```

**Expected Result**:
- ✅ Sway continues running independently
- ✅ systemd restarts wayvnc automatically (RestartSec=1)
- ✅ VNC access restored within 2 seconds

**Acceptance Criteria**: Edge case documentation - wayvnc restart

---

### Edge Case 3: Display Scaling with Varying VNC Resolutions

**Scenario**: VNC client with different resolution than virtual output

**Procedure**:
1. Configure virtual output: 1920x1080
2. Connect VNC client with 1280x720 resolution
3. Observe display scaling behavior
4. Reconnect with 2560x1440 resolution
5. Observe display scaling behavior

**Expected Result**:
- ✅ VNC client scales Sway framebuffer to fit client window
- ✅ No distortion or corruption
- ✅ Mouse coordinates map correctly

**Acceptance Criteria**: Edge case documentation - display scaling

---

### Edge Case 4: Software Rendering Fallback

**Scenario**: GPU acceleration unavailable (typical for cloud VM)

**Procedure**:
```bash
# SSH into VM
ssh vpittamp@<hetzner-ip>

# Check renderer in use
echo $WLR_RENDERER
# Expected: pixman (software rendering)

# Verify Sway using CPU rendering
journalctl --user -n 100 | grep -i "renderer\|pixman"
# Expected: Logs mention pixman renderer
```

**Expected Result**:
- ✅ Sway uses pixman (CPU-based) renderer
- ✅ No GPU-related errors in logs
- ✅ Performance acceptable for remote desktop use

**Acceptance Criteria**: Edge case documentation - software rendering

---

### Edge Case 5: Simultaneous M1 and Hetzner Sway Deployments

**Scenario**: Both M1 (native Sway) and Hetzner (headless Sway) running from same flake

**Procedure**:
```bash
# On local machine
cd /path/to/nixos

# Build M1 config
nixos-rebuild dry-build --flake .#m1 --impure
# Expected: Success

# Build hetzner-sway config
nixos-rebuild dry-build --flake .#hetzner-sway --target-host vpittamp@<hetzner-ip> --use-remote-sudo
# Expected: Success

# Verify configurations are independent (no shared state)
nix eval .#nixosConfigurations.m1.config.wayland.windowManager.sway.enable
# Expected: true (native Sway)

nix eval .#nixosConfigurations.hetzner-sway.config.wayland.windowManager.sway.enable
# Expected: true (headless Sway)

# Verify environment variables differ
nix eval .#nixosConfigurations.m1.config.environment.sessionVariables.WLR_BACKENDS
# Expected: (empty - uses default native backend)

nix eval .#nixosConfigurations.hetzner-sway.config.environment.sessionVariables.WLR_BACKENDS
# Expected: "headless"
```

**Expected Result**:
- ✅ Both configurations build successfully
- ✅ No conflicts or shared state
- ✅ M1 uses native backend, hetzner-sway uses headless backend

**Acceptance Criteria**: Edge case documentation - parallel deployments

---

## System-Level Validation

### Validate All Functional Requirements

Run this comprehensive check after deployment:

```bash
# SSH into VM
ssh vpittamp@<hetzner-ip>

# FR-001 to FR-006: Headless Backend
echo "WLR_BACKENDS: $WLR_BACKENDS"  # Expected: headless
echo "WLR_LIBINPUT_NO_DEVICES: $WLR_LIBINPUT_NO_DEVICES"  # Expected: 1
echo "WLR_RENDERER: $WLR_RENDERER"  # Expected: pixman
swaymsg -t get_outputs | jq '.[0].name'  # Expected: HEADLESS-1

# FR-007 to FR-012: VNC Server
systemctl --user is-active wayvnc.service  # Expected: active
netstat -tlnp | grep 5900  # Expected: listening

# FR-013 to FR-018: i3pm Daemon
i3pm daemon status | grep Connected  # Expected: Connected
i3pm project current  # Expected: <project-name> or No active project

# FR-019 to FR-022: Walker
ps aux | grep elephant | grep -v grep  # Expected: elephant service running

# FR-023 to FR-028: Configuration Isolation
# (Verify via flake inspection - see Step 5.1)

# FR-029 to FR-031: Multi-Monitor
i3pm monitors status  # Expected: Output table with workspaces
```

**Expected Result**: All functional requirements validated

**Success Criteria**: SC-001 through SC-010 (all success criteria pass)

---

## Troubleshooting Common Issues

### Issue 1: Sway Fails to Start

**Symptoms**: SWAYSOCK not set, swaymsg fails

**Debug**:
```bash
# Check greetd logs
journalctl -u greetd.service -n 50

# Check user session logs
journalctl --user -n 50 | grep sway

# Verify environment variables in greetd config
cat /etc/greetd/config.toml
```

**Solution**: Check greetd configuration and environment variables

---

### Issue 2: wayvnc Not Listening

**Symptoms**: Cannot connect via VNC, port 5900 not open

**Debug**:
```bash
# Check service status
systemctl --user status wayvnc.service

# Check logs
journalctl --user -u wayvnc.service -n 50

# Test manually
wayvnc --config=~/.config/wayvnc/config
```

**Solution**: Verify wayvnc config file exists and is valid

---

### Issue 3: i3pm Daemon Not Connecting

**Symptoms**: `i3pm daemon status` shows "Not connected"

**Debug**:
```bash
# Check daemon status
systemctl --user status i3-project-event-listener.service

# Check SWAYSOCK
echo $SWAYSOCK
ls -la $SWAYSOCK

# Test IPC manually
swaymsg -t get_version
```

**Solution**: Ensure Sway is running and SWAYSOCK is set

---

### Issue 4: Windows Not Receiving Project Marks

**Symptoms**: Windows open but no project marks applied

**Debug**:
```bash
# Check daemon events
i3pm daemon events --limit=20

# Launch window and check /proc environ
# (Get PID with xprop or ps)
cat /proc/<PID>/environ | tr '\0' '\n' | grep I3PM_
```

**Solution**: Verify app-launcher-wrapper is being used

---

## Automated Test Suite

### Run All Tests

```bash
# Create test script
cat > test-feature-046.sh <<'EOF'
#!/usr/bin/env bash
set -e

echo "=== Feature 046 Test Suite ==="

# Test 1: Headless Sway Running
echo "[TEST 1] Checking Sway..."
[[ -n "$SWAYSOCK" ]] && echo "✅ SWAYSOCK set" || echo "❌ SWAYSOCK not set"
swaymsg -t get_version &>/dev/null && echo "✅ Sway responding" || echo "❌ Sway not responding"

# Test 2: Virtual Output
echo "[TEST 2] Checking virtual output..."
OUTPUT=$(swaymsg -t get_outputs | jq -r '.[0].name')
[[ "$OUTPUT" == "HEADLESS-1" ]] && echo "✅ Virtual output created" || echo "❌ No virtual output"

# Test 3: wayvnc Service
echo "[TEST 3] Checking wayvnc..."
systemctl --user is-active wayvnc.service &>/dev/null && echo "✅ wayvnc running" || echo "❌ wayvnc not running"
netstat -tlnp 2>/dev/null | grep -q 5900 && echo "✅ Port 5900 listening" || echo "❌ Port 5900 not listening"

# Test 4: i3pm Daemon
echo "[TEST 4] Checking i3pm daemon..."
i3pm daemon status | grep -q Connected && echo "✅ Daemon connected" || echo "❌ Daemon not connected"

# Test 5: Walker/Elephant
echo "[TEST 5] Checking Elephant service..."
pgrep -f elephant &>/dev/null && echo "✅ Elephant running" || echo "❌ Elephant not running"

echo "=== Test Suite Complete ==="
EOF

chmod +x test-feature-046.sh
./test-feature-046.sh
```

**Expected Output**: All tests show ✅ (green checkmark)

---

## Documentation References

- **Spec**: `/etc/nixos/specs/046-revise-my-spec/spec.md`
- **Research**: `/etc/nixos/specs/046-revise-my-spec/research.md`
- **Data Model**: `/etc/nixos/specs/046-revise-my-spec/data-model.md`
- **Contracts**: `/etc/nixos/specs/046-revise-my-spec/contracts/`
  - Sway IPC Contract
  - wayvnc Configuration Contract
  - systemd Dependencies Contract

---

**Validation Status**: ⏳ Pending Feature 046 implementation

**Next Steps**: Implement hetzner-sway configuration per plan.md, then execute these test scenarios
