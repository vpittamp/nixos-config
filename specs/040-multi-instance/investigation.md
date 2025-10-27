# Multi-Instance App Project Tracking Investigation

**Feature**: 040-multi-instance
**Date**: 2025-10-27
**Status**: Investigation

## Problem Statement

VS Code (and potentially other apps) uses single-instance mode where multiple windows share one process. This causes project tracking issues:

1. **Shared Process Environment**: All windows inherit I3PM_* environment from first launch
2. **Wrong Initial Marking**: Second window reads old environment, gets marked with wrong project
3. **Delayed Correction**: Title-based detection fixes it 1 second later (fragile workaround)

### Current Behavior Example

```bash
# Launch VS Code for nixos project
app-launcher-wrapper.sh vscode  # Creates PID 503543 with I3PM_PROJECT_NAME=nixos

# Launch VS Code for stacks project (reuses same process)
app-launcher-wrapper.sh vscode  # Window reads PID 503543 environment → nixos (WRONG!)

# 1 second later: Title changes to "stacks - nixos - Visual Studio Code"
# Daemon parses title, corrects mark: nixos → stacks (FRAGILE!)
```

### Impact

- **User Experience**: 1-second delay before correct project assignment
- **Reliability**: Depends on VS Code title format (can break with updates)
- **Scalability**: Only VS Code has workaround; other multi-instance apps broken
- **Correctness**: Window initially filtered/hidden incorrectly

## Alternative Approaches

### Approach 1: Force Separate Processes

**Mechanism**: Add `--new-instance` flag to VS Code launch command

**Implementation**:
```nix
# app-registry-data.nix
(mkApp {
  name = "vscode";
  command = "code";
  parameters = "--new-window --new-instance $PROJECT_DIR";  # Add --new-instance
  # ...
})
```

**How It Works**:
- Each `code --new-instance` spawns separate process with unique PID
- Each process gets correct I3PM_* environment from launch context
- Daemon reads /proc/{unique_pid}/environ → correct project every time

**Pros**:
- ✅ **Simple**: One-line config change
- ✅ **Deterministic**: No delay, no title parsing, no race conditions
- ✅ **Reliable**: Not dependent on app behavior
- ✅ **Immediate**: Works from window creation

**Cons**:
- ❌ **Memory overhead**: ~200-400MB per instance (shared libs help, but still significant)
- ❌ **Lost features**:
  - No shared clipboard across windows
  - No unified recent files list
  - Extensions run in separate processes (increased CPU/memory)
  - Can't drag tabs between windows
- ❌ **User expectations**: VS Code users expect single-instance behavior
- ❌ **Startup time**: Slower window creation (no process reuse)

**Testing**:
```bash
# Test memory impact
ps aux | grep "code.*new-instance" | awk '{sum+=$6} END {print sum/1024 "MB total"}'

# Test functionality
code --new-instance /etc/nixos &
code --new-instance ~/stacks &
# Verify: Try drag tab from one window to another (should fail)
```

**Recommendation**: **Good for user opt-in**, but shouldn't be default due to UX impact.

---

### Approach 2: X Window Properties

**Mechanism**: Store project info in X11 window properties instead of process environment

**Implementation**:
```bash
# app-launcher-wrapper.sh enhancement
# After launching app, wait for window creation and set X properties

# 1. Launch app
systemd-run --setenv=I3PM_APP_NAME=vscode ... code --new-window $PROJECT_DIR &
LAUNCHER_PID=$!

# 2. Wait for window to appear
while ! xdotool search --pid $LAUNCHER_PID 2>/dev/null; do sleep 0.1; done

# 3. Set X properties on window
WINDOW_ID=$(xdotool search --pid $LAUNCHER_PID | tail -1)
xprop -id $WINDOW_ID -f I3PM_PROJECT_NAME 8s -set I3PM_PROJECT_NAME "nixos"
xprop -id $WINDOW_ID -f I3PM_APP_NAME 8s -set I3PM_APP_NAME "vscode"
```

**Daemon Changes**:
```python
# handlers.py - on_window_new()
async def get_window_project(conn, window_id):
    """Read project from X property instead of /proc"""
    # Try X property first
    result = subprocess.run(
        ["xprop", "-id", str(window_id), "I3PM_PROJECT_NAME"],
        capture_output=True, text=True
    )
    if result.returncode == 0:
        match = re.search(r'= "(.*)"', result.stdout)
        if match:
            return match.group(1)

    # Fallback to /proc environment
    return await get_window_project_from_proc(window_id)
```

**Pros**:
- ✅ **Per-window tracking**: Each window gets unique project property
- ✅ **No process dependency**: Works with shared processes
- ✅ **Updatable**: Can change property if window moves to different project
- ✅ **Standard mechanism**: X properties are designed for this use case

**Cons**:
- ❌ **X11 only**: Doesn't work on Wayland (need separate implementation)
- ❌ **Timing complexity**: Must wait for window creation (race conditions)
- ❌ **Fragile PID mapping**: xdotool search --pid not 100% reliable for multi-window apps
- ❌ **Synchronous overhead**: xprop calls block daemon event loop
- ❌ **Property persistence**: Lost if window reparented/remapped

**Testing**:
```bash
# Test setting properties
xprop -id $(xdotool getactivewindow) -f I3PM_PROJECT_NAME 8s -set I3PM_PROJECT_NAME "test"

# Verify reading
xprop -id $(xdotool getactivewindow) I3PM_PROJECT_NAME

# Test with VS Code multi-window
code --new-window /etc/nixos &
code --new-window ~/stacks &
# Check if both windows get unique properties
```

**Recommendation**: **Promising for X11**, but requires Wayland solution for long-term viability.

---

### Approach 3: IPC Communication on Window Creation

**Mechanism**: Apps query daemon for active project when creating windows

**Architecture**:
```
┌──────────────────┐
│ app-launcher     │ Sets active project in daemon
│ (wrapper script) │───────┐
└──────────────────┘       │
                           ▼
                    ┌──────────────┐
                    │   Daemon     │ Stores: current_project = "nixos"
                    │              │         launch_context[nixos] = {...}
                    └──────────────┘
                           ▲
                           │ Query: "What's the active project?"
┌──────────────────┐       │ Response: "nixos"
│  VS Code         │───────┘
│  (on window new) │
└──────────────────┘
```

**Implementation**:

1. **Enhance wrapper to notify daemon**:
```bash
# app-launcher-wrapper.sh
# Tell daemon: "I'm about to launch vscode for project nixos"
i3pm daemon notify-launch vscode nixos &

# Launch app
code --new-window $PROJECT_DIR
```

2. **Daemon tracks launch context**:
```python
# daemon.py
class LaunchContext:
    """Track recent app launches for window correlation"""
    def __init__(self):
        self.pending_launches = []  # [(app_name, project, timestamp)]

    async def notify_launch(self, app_name: str, project: str):
        """App launcher notifying of imminent launch"""
        self.pending_launches.append({
            "app": app_name,
            "project": project,
            "timestamp": time.time(),
        })
        # Clean old entries (>5 seconds)
        cutoff = time.time() - 5
        self.pending_launches = [
            l for l in self.pending_launches if l["timestamp"] > cutoff
        ]
```

3. **Match windows to launch context**:
```python
# handlers.py - on_window_new()
async def match_window_to_launch(window_class: str):
    """Match new window to pending launch"""
    # Look for recent launch of this app class
    for launch in daemon.launch_context.pending_launches:
        if launch["app"] == "vscode" and window_class == "Code":
            # Found matching launch within 5 seconds
            return launch["project"]

    # Fallback: Check active project
    return daemon.get_active_project()
```

**Pros**:
- ✅ **Process-independent**: Works with any app, shared or separate processes
- ✅ **No title parsing**: Deterministic project assignment
- ✅ **Immediate**: Correct from window creation
- ✅ **Wayland compatible**: Doesn't rely on X properties
- ✅ **Flexible**: Can enhance with more context (workspace, timestamp)

**Cons**:
- ❌ **Timing assumptions**: Window must appear within 5 seconds of launch
- ❌ **Ambiguity**: If user launches 2 VS Code windows rapidly, which is which?
- ❌ **Wrapper dependency**: Requires all launches go through wrapper
- ❌ **No manual correction**: If user launches VS Code directly (not via wrapper), no context available

**Timing Ambiguity Example**:
```bash
# User rapidly launches two windows
app-launcher-wrapper.sh vscode &  # Notifies: vscode for nixos
app-launcher-wrapper.sh vscode &  # Notifies: vscode for stacks

# Both windows appear ~same time
# Daemon sees: pending_launches = [
#   {app: vscode, project: nixos, timestamp: T},
#   {app: vscode, project: stacks, timestamp: T+0.1s}
# ]
# Which window is which? 🤔
```

**Mitigation**: Use more signals for correlation (PID, workspace, launch order)

**Testing**:
```bash
# Test launch notification
i3pm daemon notify-launch vscode nixos
code --new-window /etc/nixos &
sleep 0.5
# Check daemon matched window to nixos

# Test rapid launches
i3pm daemon notify-launch vscode nixos &
i3pm daemon notify-launch vscode stacks &
code --new-window /etc/nixos &
code --new-window ~/stacks &
# Verify both windows get correct projects
```

**Recommendation**: **Best long-term solution** with proper correlation heuristics.

---

### Approach 4: Enhanced Title-Based Detection (Current + Improvements)

**Current Implementation**: Parse VS Code title to extract project name

**Enhancements**:

1. **Multi-app support**: Extend to Chrome, Firefox, etc.
```python
TITLE_PATTERNS = {
    "Code": r"(?:Code - )?([^-]+) -",  # VS Code: "project - host - ..."
    "Google-chrome": r"(.*) - Google Chrome",  # Chrome: "title - Google Chrome"
    "Firefox": r"(.*) — Mozilla Firefox",  # Firefox: "title — Mozilla Firefox"
}
```

2. **Project name matching improvements**:
```python
def fuzzy_match_project(title_text: str) -> Optional[str]:
    """Match title text to project using fuzzy matching"""
    title_lower = title_text.lower().strip()

    # Exact match
    if title_lower in projects:
        return title_lower

    # Path-based match: "/etc/nixos" in title → nixos
    for project_name, project_data in projects.items():
        if project_data["directory"] in title_text:
            return project_name

    # Directory name match: "my-app" in title and project.dir = "/home/user/my-app"
    for project_name, project_data in projects.items():
        dir_name = os.path.basename(project_data["directory"])
        if dir_name.lower() in title_lower:
            return project_name

    return None
```

3. **Immediate re-classification on title change**:
```python
# Currently: Title change triggers re-mark
# Enhancement: Also trigger window filtering immediately

async def on_window_title_change(event):
    window_id = event.container.id
    new_title = event.container.name

    # Re-classify and update marks
    new_project = await detect_project_from_title(new_title)
    if new_project != current_project:
        await update_window_mark(window_id, new_project)

        # ENHANCEMENT: Immediately re-filter windows
        await filter_windows_by_project(
            conn,
            active_project=daemon.get_active_project(),
            workspace_tracker=daemon.workspace_tracker
        )
```

**Pros**:
- ✅ **Already working**: Proven with VS Code
- ✅ **No app changes**: Works with existing apps
- ✅ **Zero overhead**: No extra processes or IPC
- ✅ **User-visible**: Title shows what daemon sees

**Cons**:
- ❌ **App-specific**: Requires pattern per app
- ❌ **Fragile**: Breaks if app changes title format
- ❌ **Delayed**: Still 1-second delay for title to update
- ❌ **Ambiguous titles**: "Untitled - VS Code" → which project?
- ❌ **Maintenance burden**: Must track title format changes across apps

**Testing**:
```bash
# Test Chrome title parsing
google-chrome --new-window https://github.com/user/nixos &
# Title: "user/nixos: Code - Google Chrome"
# Should extract: "nixos"

# Test Firefox
firefox -new-window https://github.com/user/stacks &
# Title: "user/stacks: Code — Mozilla Firefox"
# Should extract: "stacks"

# Test ambiguous titles
code --new-window &  # Opens without folder
# Title: "Untitled - Visual Studio Code"
# Should fallback to active project
```

**Recommendation**: **Keep as fallback**, but don't rely on it as primary mechanism.

---

### Approach 5: Desktop Files Per Project

**Mechanism**: Generate project-specific .desktop files with unique identifiers

**Implementation**:
```nix
# Generate desktop files dynamically
{ config, lib, pkgs, ... }:

let
  # For each project, create a vscode-{project}.desktop file
  generateProjectDesktopFiles = project:
    pkgs.writeTextFile {
      name = "vscode-${project.name}.desktop";
      destination = "/share/applications/vscode-${project.name}.desktop";
      text = ''
        [Desktop Entry]
        Type=Application
        Name=VS Code (${project.display_name})
        Exec=${config.home.homeDirectory}/.local/bin/app-launcher-wrapper.sh vscode-${project.name}
        Icon=vscode
        Terminal=false
        Categories=Development;
        StartupWMClass=code-${project.name}
        X-Project-Name=${project.name}
      '';
    };

  projectDesktopFiles = map generateProjectDesktopFiles [
    { name = "nixos"; display_name = "NixOS"; directory = "/etc/nixos"; }
    { name = "stacks"; display_name = "Stacks"; directory = "~/stacks"; }
  ];
in
{
  home.packages = projectDesktopFiles;
}
```

**Launcher Integration**:
```bash
# app-launcher-wrapper.sh handles vscode-{project}
if [[ "$APP_NAME" =~ ^vscode-(.+)$ ]]; then
    PROJECT_NAME="${BASH_REMATCH[1]}"
    # Force this specific project (not active project)
    export I3PM_PROJECT_NAME="$PROJECT_NAME"
    export I3PM_PROJECT_DIR=$(get_project_dir "$PROJECT_NAME")

    # Launch with project-specific class hint
    code --new-window --class="code-${PROJECT_NAME}" "$I3PM_PROJECT_DIR"
fi
```

**Window Matching**:
```python
# handlers.py - on_window_new()
window_class = event.container.window_class  # e.g., "code-nixos"

if window_class.startswith("code-"):
    # Extract project from class name
    project = window_class.replace("code-", "")
    # Directly assign without reading /proc
    await mark_window(window_id, project)
```

**Pros**:
- ✅ **Deterministic**: Each launcher explicitly tied to project
- ✅ **No process dependency**: Class name encodes project
- ✅ **User-visible**: Different icons/names in launcher
- ✅ **Taskbar separation**: Each project shows separately in taskbar

**Cons**:
- ❌ **Launcher explosion**: N projects × M apps = many desktop files
- ❌ **Dynamic project management**: Hard to add/remove projects (requires rebuild)
- ❌ **User confusion**: "Why do I have 5 VS Code icons?"
- ❌ **Class name limitations**: Not all apps respect --class flag
- ❌ **Doesn't help direct launches**: If user runs `code /etc/nixos` from terminal, no class hint

**Testing**:
```bash
# Test class-based launching
code --new-window --class="code-nixos" /etc/nixos &
xprop WM_CLASS  # Click window, verify: "code-nixos", "code-nixos"

# Test if VS Code respects class
code --new-window --class="code-stacks" ~/stacks &
xprop WM_CLASS  # Check if different from first window
```

**Recommendation**: **Interesting for power users**, but too complex for general use.

---

## Comparison Matrix

| Approach | Reliability | Complexity | Performance | UX Impact | Wayland Ready |
|----------|-------------|------------|-------------|-----------|---------------|
| 1. Separate Processes | ⭐⭐⭐⭐⭐ | ⭐ | ⭐⭐ (memory) | ⭐⭐ (lost features) | ✅ |
| 2. X Properties | ⭐⭐⭐⭐ | ⭐⭐⭐ | ⭐⭐⭐⭐ | ⭐⭐⭐⭐⭐ | ❌ |
| 3. IPC Launch Context | ⭐⭐⭐⭐ | ⭐⭐⭐⭐ | ⭐⭐⭐⭐⭐ | ⭐⭐⭐⭐⭐ | ✅ |
| 4. Enhanced Title Parse | ⭐⭐ | ⭐⭐ | ⭐⭐⭐⭐⭐ | ⭐⭐⭐⭐ (delay) | ✅ |
| 5. Desktop Per Project | ⭐⭐⭐⭐ | ⭐⭐⭐⭐⭐ | ⭐⭐⭐⭐⭐ | ⭐⭐ (clutter) | ✅ |

**Legend**: ⭐ = Poor, ⭐⭐⭐⭐⭐ = Excellent

---

## Recommended Solution: Hybrid Approach

Combine multiple approaches for best results:

### Primary: IPC Launch Context (Approach 3)
- Wrapper notifies daemon of launches
- Daemon matches windows to launch context
- Handles 95% of cases correctly

### Fallback 1: Title-Based Detection (Approach 4)
- If IPC matching fails (manual launch, timing issue)
- Parse title to extract project
- Currently working for VS Code

### Fallback 2: Active Project
- If both above fail
- Assign to currently active project
- Better than nothing

### Optional: Separate Processes (Approach 1)
- Make it a per-app configuration option
- Users can opt-in for apps where they prefer isolation
- Default: OFF (preserve UX)

```nix
# app-registry-data.nix
(mkApp {
  name = "vscode";
  command = "code";
  parameters = "--new-window $PROJECT_DIR";
  force_separate_process = false;  # User can override to true
  # ...
})
```

---

## Next Steps

1. **Prototype IPC launch context** (Approach 3)
2. **Add correlation heuristics** (PID tracking, timestamp windows)
3. **Test with rapid launches** to validate ambiguity resolution
4. **Implement fallback chain** (IPC → title → active project)
5. **Add separate process opt-in** for power users
6. **Document limitations** and workarounds

## Open Questions

1. **Correlation confidence**: How do we score window-to-launch matches?
2. **Launch timeout**: How long to wait for window after notify-launch?
3. **Multiple displays**: Does launch context work across monitors?
4. **Fallback priority**: Should title parsing override IPC for VS Code (since title is ground truth)?
5. **User override**: How can users manually fix incorrect assignments?
