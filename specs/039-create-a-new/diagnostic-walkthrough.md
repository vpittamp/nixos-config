# Feature 039 Diagnostic Walkthrough
## Verify Application Launch, Workspace Assignment, and Project Filtering

### Step 1: Check System Health
**Goal**: Verify daemon is running and healthy before testing

```bash
# Check daemon health
i3pm-diagnose health
```

**Expected Output**:
- ✓ HEALTHY status
- IPC Connection: Connected
- Event Subscriptions: 4/4 active
- No health issues

**If unhealthy**: Check daemon with `sudo systemctl status i3-project-daemon.service`

---

### Step 2: View Current Projects
**Goal**: Know what projects are available

```bash
# List all projects
i3pm project list

# Check active project
i3pm project current
```

**Expected Output**:
```
Available projects:
- nixos (/etc/nixos)
- stacks (~/stacks)
- personal (~)
```

---

### Step 3: Clear to Global Mode (Baseline)
**Goal**: Start from a clean state with no active project

```bash
# Clear active project
pclear  # or: i3pm project clear
```

**Verify**:
```bash
i3pm project current
# Should show: No active project
```

---

### Step 4: Launch Application WITHOUT Project Context
**Goal**: See how app launches in global mode

```bash
# Launch VS Code from terminal (without project)
code &

# Wait 1-2 seconds for window to appear
sleep 2
```

---

### Step 5: Inspect the Window
**Goal**: Get window ID and verify its properties

```bash
# Get focused window ID
WINDOW_ID=$(i3-msg -t get_tree | jq '.. | select(.focused? == true) | .id')
echo "Window ID: $WINDOW_ID"

# Inspect window with diagnostic tool
i3pm-diagnose window $WINDOW_ID
```

**Expected Output**:
```
Window Identity

Basic Properties
┌─────────────┬──────────────────┐
│ Window ID   │ 94532735639728   │
│ Class       │ Code             │
│ Instance    │ code             │
│ Title       │ Visual Studio... │
│ Workspace   │ 2                │
│ Output      │ Virtual-1        │
└─────────────┴──────────────────┘

I3PM Environment
┌──────────────┬────────┐
│ APP_NAME     │ None   │
│ PROJECT_NAME │ None   │
│ SCOPE        │ None   │
└──────────────┴────────┘

Registry Matching
┌─────────────┬────────┐
│ Matched App │ None   │
│ Match Type  │ none   │
└─────────────┴────────┘
```

**Key Observations**:
- ❌ No I3PM environment variables (launched without wrapper)
- ❌ Not matched to registry
- ⚠️ Window appeared on current workspace (not configured workspace)

**Close this window**: `i3-msg '[id="'$WINDOW_ID'"]' kill`

---

### Step 6: Switch to a Project
**Goal**: Activate project context

```bash
# Switch to nixos project
pswitch nixos  # or: i3pm project switch nixos

# Verify active project
i3pm project current
```

**Expected Output**:
```
Active project: nixos (/etc/nixos)
```

---

### Step 7: Launch Application WITH Project Context
**Goal**: Launch app through project-aware wrapper

```bash
# Launch VS Code via app-launcher wrapper
~/.local/bin/app-launcher-wrapper.sh vscode &

# OR if in PATH:
# app-launcher-wrapper.sh vscode &

# Wait for window
sleep 2
```

---

### Step 8: Inspect Project-Aware Window
**Goal**: Verify I3PM environment and workspace assignment

```bash
# Get window ID again
WINDOW_ID=$(i3-msg -t get_tree | jq '.. | select(.focused? == true) | .id')

# Inspect with diagnostic tool
i3pm-diagnose window $WINDOW_ID
```

**Expected Output**:
```
Window Identity

Basic Properties
┌─────────────┬──────────────────┐
│ Window ID   │ 94532735640123   │
│ Class       │ Code             │
│ Instance    │ code             │
│ Title       │ nixos - Visual...│
│ Workspace   │ 2                │  ← Should be on configured workspace!
│ Output      │ Virtual-1        │
└─────────────┴──────────────────┘

I3PM Environment
┌──────────────┬─────────────────────────────┐
│ APP_NAME     │ vscode                      │  ✓ Has app name
│ PROJECT_NAME │ nixos                       │  ✓ Has project
│ SCOPE        │ scoped                      │  ✓ Project-scoped
│ APP_ID       │ vscode-nixos-12345-1234567 │  ✓ Unique ID
└──────────────┴─────────────────────────────┘

Registry Matching
┌─────────────┬─────────┐
│ Matched App │ vscode  │  ✓ Matched to registry
│ Match Type  │ exact   │
└─────────────┴─────────┘
```

**Key Observations**:
- ✅ Has I3PM_PROJECT_NAME=nixos
- ✅ Has I3PM_APP_NAME=vscode
- ✅ Has I3PM_SCOPE=scoped
- ✅ Opened on Workspace 2 (configured workspace for vscode)
- ✅ Matched to application registry

---

### Step 9: Monitor Events in Real-Time
**Goal**: Watch daemon process events

```bash
# In a separate terminal, start event monitor
i3pm-diagnose events --follow
```

**Expected Output** (live stream):
```
Recent Events
┏━━━━━━━━━━━━━━┳━━━━━━━━━━━━━┳━━━━━━━━┳━━━━━━━━┳━━━━┳━━━━━━━━━━┳━━━━━━━━┓
┃ Time         ┃ Type        ┃ Change ┃ Window ┃ WS ┃ Duration ┃ Status ┃
┡━━━━━━━━━━━━━━╇━━━━━━━━━━━━━╇━━━━━━━━╇━━━━━━━━╇━━━━╇━━━━━━━━━━╇━━━━━━━━┩
│ 08:45:12.123 │ window::new │        │ Code   │  2 │    45ms  │ ✓      │
└──────────────┴─────────────┴────────┴────────┴────┴──────────┴────────┘
```

**Keep this running** to see events as they happen.

---

### Step 10: Launch Second Application (Same Project)
**Goal**: Verify multiple apps in same project

```bash
# In main terminal, launch Ghostty terminal
~/.local/bin/app-launcher-wrapper.sh terminal &

sleep 2

# Get its window ID
TERM_ID=$(i3-msg -t get_tree | jq '.. | select(.focused? == true) | .id')

# Inspect it
i3pm-diagnose window $TERM_ID
```

**Expected Output**:
```
I3PM Environment
┌──────────────┬────────┐
│ APP_NAME     │ terminal  │
│ PROJECT_NAME │ nixos     │  ✓ Same project
│ SCOPE        │ scoped    │
└──────────────┴──────────┘
```

**Event Monitor** should show:
```
│ 08:46:22.456 │ window::new │        │ ghostty │  3 │    38ms  │ ✓      │
```

---

### Step 11: Switch Projects (Test Filtering)
**Goal**: Verify scoped windows hide when switching projects

```bash
# Before switching, count visible windows
i3pm windows --table | grep Code

# Switch to different project
pswitch stacks

# Wait for filtering to complete
sleep 1

# Check if VS Code is still visible
i3pm windows --table | grep Code
```

**Expected Behavior**:
- ❌ VS Code should NOT appear in visible windows
- ❌ Ghostty terminal should NOT appear
- ✅ Only 'stacks' project windows visible (or none if no stacks apps open)

---

### Step 12: Verify Windows Are Hidden (Not Killed)
**Goal**: Confirm windows moved to scratchpad, not closed

```bash
# Check all windows including scratchpad
i3pm windows --json | jq '.outputs[].workspaces[] | select(.name == "__i3_scratch") | .windows[] | select(.class == "Code")'
```

**Expected Output**:
```json
{
  "id": 94532735640123,
  "class": "Code",
  "title": "nixos - Visual Studio Code",
  "workspace": "__i3_scratch",
  "is_hidden": true,
  "project": "nixos"
}
```

**Key Observations**:
- ✅ Window exists in scratchpad workspace
- ✅ Still has project association
- ✅ Not killed, just hidden

---

### Step 13: Switch Back and Verify Restore
**Goal**: Verify windows restore when returning to project

```bash
# Switch back to nixos project
pswitch nixos

# Wait for restore
sleep 1

# Check visible windows
i3pm windows --table | grep -E "Code|ghostty"
```

**Expected Output**:
```
VS Code    | Code    | nixos - Visual...  | 2  | nixos  | visible
Ghostty    | ghostty | terminal           | 3  | nixos  | visible
```

**Key Observations**:
- ✅ Windows restored from scratchpad
- ✅ Back on original workspaces (2 and 3)
- ✅ Still associated with nixos project

---

### Step 14: Validate Daemon State
**Goal**: Ensure daemon state matches i3 reality

```bash
# Run state validation
i3pm-diagnose validate
```

**Expected Output**:
```
State Validation
┌───────────────────────┬────────┐
│ Total Windows Checked │     15 │
│ Consistent            │     15 │
│ Inconsistent          │      0 │
│ Consistency           │ 100.0% │
└───────────────────────┴────────┘

✓ State is consistent
```

**If inconsistent**:
- Check mismatches table for details
- Common causes: manual window moves, workspace changes outside daemon

---

### Step 15: Test Global Application
**Goal**: Verify global apps stay visible across project switches

```bash
# Launch Firefox (global app)
firefox &
sleep 3

# Get window ID
FIREFOX_ID=$(i3-msg -t get_tree | jq '.. | select(.focused? == true) | .id')

# Inspect it
i3pm-diagnose window $FIREFOX_ID
```

**Expected Output**:
```
I3PM Environment
┌──────────────┬────────┐
│ APP_NAME     │ firefox   │
│ PROJECT_NAME │ None      │  ✓ No project (global)
│ SCOPE        │ global    │  ✓ Global scope
└──────────────┴──────────┘
```

**Now switch projects**:
```bash
pswitch stacks
i3pm windows --table | grep -i firefox
```

**Expected**: Firefox STILL visible (global apps don't hide)

---

### Step 16: Review Event History
**Goal**: Analyze what happened during testing

```bash
# Get last 50 events
i3pm-diagnose events --limit 50

# Filter by window events only
i3pm-diagnose events --limit 50 --type window

# Export to JSON for analysis
i3pm-diagnose events --limit 100 --json > /tmp/events.json
```

---

## Troubleshooting Guide

### Problem: Window not assigned to correct workspace

**Diagnostic**:
```bash
i3pm-diagnose window $WINDOW_ID
```

**Look for**:
- Registry Matching: Should show matched app
- Check "Workspace" property matches expected

**Fix**:
- Verify app-registry.nix has correct workspace
- Check window class matches expected_class in registry

---

### Problem: Window doesn't hide when switching projects

**Diagnostic**:
```bash
i3pm-diagnose window $WINDOW_ID
```

**Look for**:
- I3PM Environment → PROJECT_NAME should match old project
- SCOPE should be "scoped" (not "global")

**Fix**:
- If no I3PM env: Window launched without wrapper
- If SCOPE=global: App configured as global in registry
- Check window class in app-classes.json

---

### Problem: Window filtering slow (>200ms)

**Diagnostic**:
```bash
i3pm-diagnose events --limit 20 --type tick
```

**Look for**:
- Duration column should be <100ms
- If >200ms, check daemon logs

**Fix**:
```bash
journalctl --user -u i3-project-daemon -n 50 | grep "filtering"
```

---

### Problem: Daemon not responding

**Diagnostic**:
```bash
i3pm-diagnose health
```

**Expected error**: "Daemon socket not found" or timeout

**Fix**:
```bash
# Check daemon status
sudo systemctl status i3-project-daemon.service

# Restart daemon
sudo systemctl restart i3-project-daemon.service

# Verify socket exists
ls -la /run/i3-project-daemon/ipc.sock
```

---

## Quick Reference Commands

```bash
# System Health
i3pm-diagnose health              # Check daemon health
i3pm-diagnose validate            # Validate state consistency

# Window Inspection
i3pm-diagnose window <id>         # Inspect specific window
i3pm windows --table              # List all visible windows

# Event Monitoring
i3pm-diagnose events              # Recent events
i3pm-diagnose events --follow     # Live event stream
i3pm-diagnose events --type=window  # Filter by type

# Project Management
i3pm project list                 # List projects
i3pm project current              # Show active project
pswitch <name>                    # Switch project
pclear                            # Clear to global mode

# Application Launch
app-launcher-wrapper.sh <app>     # Launch with project context
```

---

## Success Criteria Checklist

After completing this walkthrough, you should have verified:

- ✅ Daemon is healthy and connected to i3
- ✅ Applications launch with I3PM environment variables
- ✅ Windows assigned to correct workspace on launch
- ✅ Windows hide when switching away from their project
- ✅ Windows restore when switching back to their project
- ✅ Global apps remain visible across all projects
- ✅ Event monitoring shows processing <100ms
- ✅ State validation shows 100% consistency
- ✅ Socket permissions are secure (0600)

