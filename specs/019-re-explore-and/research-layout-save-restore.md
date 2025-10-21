# Research: i3 Window Manager Layout Save/Restore Approaches

**Date**: 2025-10-20
**Context**: Need to capture current window arrangement (positions, workspaces, sizes) and restore it later for i3 project management system

---

## Table of Contents

1. [Executive Summary](#executive-summary)
2. [i3 Native Layout Format](#i3-native-layout-format)
3. [Alternative Approaches](#alternative-approaches)
4. [Window Matching Strategies](#window-matching-strategies)
5. [Edge Cases & Challenges](#edge-cases--challenges)
6. [Recommendation](#recommendation)
7. [Implementation Examples](#implementation-examples)
8. [References](#references)

---

## Executive Summary

### Decision: Custom Format with i3 IPC GET_TREE

**Rationale**:
1. **i3's native format requires manual editing** - `i3-save-tree` output is intentionally incomplete and needs human intervention to specify swallow criteria
2. **Better integration with existing daemon** - Already using i3ipc for event-driven architecture, can reuse for layout capture
3. **More control over restoration** - Can implement intelligent window matching beyond simple class/title criteria
4. **Multi-monitor flexibility** - Custom format can store output assignments and adapt to changed monitor configurations
5. **Progressive enhancement** - Start simple (positions, workspaces), add features incrementally (floating, splits, tabs/stacks)

### Key Trade-offs

| Aspect | Native i3 Format | Custom Format |
|--------|-----------------|---------------|
| **Manual editing** | Required (swallow criteria) | Not required |
| **i3 integration** | Uses `append_layout` | Uses i3 IPC commands |
| **Window matching** | Class/instance/title only | Extensible (process, marks, etc.) |
| **Complexity** | Simple for basic layouts | More code, more control |
| **Multi-monitor** | Limited support | Full control over output assignment |
| **Missing apps** | Placeholder windows remain | Can skip or prompt user |

---

## i3 Native Layout Format

### Overview

i3 provides built-in layout saving via `i3-save-tree` and restoration via `append_layout`. Introduced in i3 v4.8.

### How It Works

```bash
# Save workspace layout
i3-save-tree --workspace 1 > ~/.config/i3/workspace-1.json

# Save entire output (monitor)
i3-save-tree --output HDMI1 > ~/.config/i3/output-hdmi1.json

# Restore layout
i3-msg 'workspace 1; append_layout ~/.config/i3/workspace-1.json'
```

### JSON Format Structure

```json
{
    "border": "pixel",
    "current_border_width": 1,
    "floating": "auto_off",
    "geometry": {
        "height": 1040,
        "width": 1920,
        "x": 0,
        "y": 0
    },
    "marks": [],
    "name": "Terminal",
    "percent": 0.5,
    "swallows": [
        {
            "class": "^URxvt$",
            "instance": "^terminal1$"
        }
    ],
    "type": "con"
}
```

### Key Properties

- **swallows**: Criteria array for window matching
- **geometry**: Original window size/position before i3 mapped it
- **percent**: Size ratio in split (e.g., 0.5 = 50% of parent container)
- **floating**: Whether window floats
- **border**: Border style (normal, pixel, none)
- **type**: Container type (con, floating_con, workspace, output)

### Swallow Criteria

Windows match when they satisfy ANY of these properties:
- `class`: WM_CLASS class (regex)
- `instance`: WM_CLASS instance (regex)
- `title`: Window title / _NET_WM_NAME (regex)
- `window_role`: WM_WINDOW_ROLE (regex)

Best practice: **Be as specific as possible** to avoid matching wrong windows.

### Limitations

1. **Manual editing required**: Output is intentionally incomplete and commented
2. **No program launching**: Only creates placeholder windows, doesn't start applications
3. **Multiple identical apps**: Difficult to distinguish (need unique titles/instances)
4. **Placeholder cleanup**: Must manually close placeholders if apps don't launch
5. **Multi-monitor**: Limited flexibility when monitor config changes
6. **JSON format quirks**: Multiple top-level objects, allows comments (non-standard JSON)

### Example Workflow

```bash
# 1. Save layout
i3-save-tree --workspace 1 > ws1.json

# 2. Edit ws1.json (uncomment swallow criteria, make specific)
# Change:
#    "class": "^URxvt$",
# To:
    "class": "^URxvt$",
    "instance": "^irssi$"

# 3. In i3 config, restore on startup
exec --no-startup-id "i3-msg 'workspace 1; append_layout ~/.config/i3/workspace-1.json'"

# 4. Launch applications (order doesn't matter, i3 matches them)
exec urxvt -name irssi -e irssi
exec code /etc/nixos
```

---

## Alternative Approaches

### 1. i3-resurrect (Most Popular)

**Repository**: https://github.com/JonnyHaystack/i3-resurrect

**Approach**:
- Uses i3ipc to extract workspace tree information
- Saves both layout AND program information (cmdline, cwd)
- Stores in custom JSON format
- Launches programs with subprocess
- Uses xdotool to unmap/remap windows to trigger swallowing

**Pros**:
- Fully automated (no manual editing)
- Saves running programs with their context
- Works with multiple identical applications

**Cons**:
- Depends on xdotool (X11 only, not Wayland-compatible)
- Reimplements i3-save-tree entirely
- Complex window matching logic

**Example**:
```bash
# Save workspace
i3-resurrect save -w 1

# Restore workspace
i3-resurrect restore -w 1
```

### 2. i3-layout-manager

**Repository**: https://github.com/klaxalk/i3-layout-manager

**Approach**:
- Shell script wrapper around i3's native layout features
- Uses rofi for user interaction
- Automates extraction of root splits and floating windows
- Does NOT launch programs (layout only)

**Pros**:
- Simple shell script
- Uses i3's native features
- Good for quick layout switching

**Cons**:
- Doesn't launch programs
- Limited to i3's native format constraints
- Still requires some manual setup

### 3. i3-clever-layout

**Repository**: https://github.com/talwrii/i3-clever-layout

**Approach**:
- Attempts to automate both saving and restoring
- Optionally runs applications contained in layout
- Custom format

**Pros**:
- Automated workflow
- Can launch applications

**Cons**:
- Less maintained
- Complex implementation
- Limited documentation

### 4. Custom Format via i3ipc (Recommended)

**Approach**:
- Use i3ipc GET_TREE to capture window hierarchy
- Store in simplified custom JSON format
- Use i3 IPC commands to restore positions
- Integrate with existing i3-project-daemon

**Pros**:
- Full control over format and matching
- Integrates with existing event-driven system
- No external dependencies (already using i3ipc)
- Can adapt to multi-monitor changes
- Extensible for future features

**Cons**:
- More code to write/maintain
- Must implement own restoration logic
- Need to handle edge cases manually

---

## Window Matching Strategies

### 1. WM_CLASS Matching (Priority 1)

**Most reliable** for matching application windows.

```python
# WM_CLASS has two parts:
# - instance: First part (often customizable via -name flag)
# - class: Second part (usually fixed by application)

# Example: URxvt terminal
instance = "terminal1"  # Can set with: urxvt -name terminal1
class_ = "URxvt"        # Fixed by urxvt

# Best practice: Match both for specificity
swallow = {
    "class": "^URxvt$",
    "instance": "^terminal1$"
}
```

**Tools to inspect**:
```bash
# Get WM_CLASS for focused window
xprop WM_CLASS  # Click window
# Output: WM_CLASS(STRING) = "terminal1", "URxvt"
#                             ^instance    ^class

# Or use i3ipc
import i3ipc
i3 = i3ipc.Connection()
focused = i3.get_tree().find_focused()
print(f"Instance: {focused.window_instance}")
print(f"Class: {focused.window_class}")
```

### 2. Window Title Matching (Priority 2)

**Useful** when class isn't specific enough, but titles can change.

```python
# Title matches against _NET_WM_NAME
swallow = {
    "title": "^Neovim - /etc/nixos$"  # Regex pattern
}

# Warning: Titles change frequently
# - Terminals: Show current directory or command
# - Editors: Show filename
# - Browsers: Show page title
```

### 3. Window Marks (Priority 3 - Custom)

**Best for project system** - already using marks for project tracking.

```python
# Current system already marks windows
# Format: "project:nixos"

# Can extend with layout marks
# Format: "layout:workspace1:position0"

# Advantage: Marks persist across i3 restarts
# Disadvantage: Must manually mark or use daemon to auto-mark
```

### 4. Process Information (Priority 4 - Custom)

**Used by i3-resurrect** - store cmdline and cwd for relaunching.

```python
# Get process info from /proc
def get_process_info(window_id: int) -> dict:
    # X11: Get _NET_WM_PID property
    pid = get_window_pid(window_id)

    # Read from /proc
    cmdline = Path(f"/proc/{pid}/cmdline").read_text().split('\0')
    cwd = os.readlink(f"/proc/{pid}/cwd")

    return {
        "pid": pid,
        "cmdline": cmdline,
        "cwd": cwd
    }
```

### 5. Application Identifier (Priority 5 - Custom)

**Extend current app classification system** to support layout restoration.

```python
# Already have app_identifier in WindowInfo
# Can use this for intelligent matching

# Example:
{
    "app_identifier": "ghostty",
    "match_criteria": {
        "class": "org.kde.ghostty",
        "project_mark": "project:nixos"
    },
    "launch_command": ["ghostty", "--working-directory", "/etc/nixos"]
}
```

---

## Edge Cases & Challenges

### 1. Missing Applications

**Problem**: Layout references app that isn't installed or running.

**i3 Native Behavior**:
- Creates placeholder window
- Placeholder waits indefinitely for matching window
- User must manually close placeholder

**Custom Solution Options**:
- **Skip**: Don't create container for missing app
- **Prompt**: Ask user if they want to install/launch app
- **Timeout**: Wait N seconds, then remove placeholder
- **Partial restore**: Restore layout for available apps only

**Recommendation**: Skip with warning message.

```python
async def restore_layout(layout: dict, i3: Connection):
    for window_spec in layout["windows"]:
        if not can_launch_app(window_spec):
            logger.warning(
                f"Skipping {window_spec['app']}: not installed"
            )
            continue

        # Create placeholder or launch app
        await restore_window(window_spec, i3)
```

### 2. Changed Monitor Configuration

**Problem**: Saved layout for 3 monitors, now only have 1 monitor.

**i3 Native Behavior**:
- Workspace output assignments may fail
- Windows placed on non-existent output → moved to primary
- Layout structure mostly preserved, but positions wrong

**Custom Solution Options**:
- **Detect monitor count**: Query GET_OUTPUTS before restore
- **Adapt layout**: Compress multi-monitor layout to fewer monitors
- **Prompt user**: "Layout saved for 3 monitors, you have 1. Restore anyway?"
- **Store multiple variants**: Save layouts for 1-mon, 2-mon, 3-mon configs

**Recommendation**: Detect and adapt automatically.

```python
async def restore_layout(layout: dict, i3: Connection):
    saved_outputs = layout["outputs"]  # ["eDP-1", "HDMI-1", "DP-1"]
    current_outputs = [o.name for o in await i3.get_outputs() if o.active]

    if len(current_outputs) < len(saved_outputs):
        logger.warning(
            f"Layout saved for {len(saved_outputs)} monitors, "
            f"you have {len(current_outputs)}. Adapting layout..."
        )
        layout = adapt_layout_to_outputs(layout, current_outputs)

    await apply_layout(layout, i3)
```

### 3. Window Geometry Reliability

**Problem**: Capturing accurate window size/position from i3 tree.

**i3 IPC GET_TREE Rect Properties**:
- `rect`: Container position/size (includes decorations, borders)
- `window_rect`: Actual window content area
- `deco_rect`: Decoration area (title bar, etc.)
- `geometry`: Original size window requested (before i3 tiled it)

**Best Practice**: Use `rect` for container layout, `geometry` for floating windows.

```python
async def capture_window_geometry(con: Con) -> dict:
    if con.floating == "user_on":
        # Floating: Use geometry (original size)
        return {
            "floating": True,
            "x": con.rect.x,
            "y": con.rect.y,
            "width": con.geometry.width,
            "height": con.geometry.height,
        }
    else:
        # Tiled: Use percent of parent container
        return {
            "floating": False,
            "percent": con.percent,  # 0.5 = 50% of split
            "workspace": con.workspace().name,
        }
```

### 4. Split Containers & Tabs/Stacks

**Problem**: i3 supports complex layouts (h-split, v-split, tabbed, stacked).

**i3 Tree Structure**:
```
workspace
├── splitv (vertical split container)
│   ├── window 1 (50%)
│   └── splith (horizontal split container, 50%)
│       ├── window 2 (50%)
│       └── window 3 (50%)
└── tabbed container
    ├── window 4 (tab 1)
    └── window 5 (tab 2)
```

**Custom Format Approach**:
```json
{
  "workspace": "1",
  "root_container": {
    "type": "splitv",
    "children": [
      {
        "type": "window",
        "class": "Code",
        "percent": 0.5
      },
      {
        "type": "splith",
        "percent": 0.5,
        "children": [
          {"type": "window", "class": "firefox", "percent": 0.5},
          {"type": "window", "class": "org.kde.ghostty", "percent": 0.5}
        ]
      }
    ]
  }
}
```

**Recommendation**: Start with simple (no nested splits), add later if needed.

### 5. Window Launch Order

**Problem**: Must windows launch before restoring layout, or can layout create placeholders?

**i3 Native Approach**:
1. Create layout with placeholders (append_layout)
2. Launch applications (any order)
3. Windows automatically swallowed into placeholders

**i3-resurrect Approach**:
1. Launch all applications first
2. Wait for windows to appear
3. Use xdotool to unmap/remap → triggers swallowing

**Custom Approach Options**:
- **Parallel**: Create placeholders + launch apps simultaneously
- **Sequential**: Launch apps first, then move to positions
- **Hybrid**: Use marks to identify windows, move after launch

**Recommendation**: Sequential with mark-based matching.

```python
async def restore_workspace_layout(layout: dict, i3: Connection):
    # 1. Launch all applications (with project marks)
    launched_windows = []
    for window_spec in layout["windows"]:
        window = await launch_app_with_mark(
            window_spec,
            mark=f"restore:{window_spec['id']}"
        )
        launched_windows.append(window)

    # 2. Wait for windows to appear (poll for marks)
    await wait_for_windows(launched_windows, timeout=10)

    # 3. Move windows to correct positions
    for window_spec in layout["windows"]:
        window = i3.get_tree().find_marked(f"restore:{window_spec['id']}")[0]

        # Move to workspace
        await i3.command(f'[con_id={window.id}] move to workspace {window_spec["workspace"]}')

        # Set floating if needed
        if window_spec.get("floating"):
            await i3.command(
                f'[con_id={window.id}] floating enable; '
                f'resize set {window_spec["width"]} {window_spec["height"]}; '
                f'move position {window_spec["x"]} {window_spec["y"]}'
            )
```

---

## Recommendation

### Proposed Approach: Custom Format with i3ipc

#### Phase 1: Basic Layout Capture/Restore

**Scope**:
- Capture window positions (workspace, output)
- Store window matching criteria (class, marks)
- Restore windows to correct workspaces
- No floating, no splits (tiled only)

**Data Model**:
```python
@dataclass
class LayoutWindow:
    """Window in a saved layout."""

    # Identity
    window_class: str
    window_instance: str
    app_identifier: str  # Reuse from WindowInfo

    # Position
    workspace: str
    output: str

    # Project context
    project: Optional[str]
    marks: List[str]

    # Launch info (optional)
    cmdline: Optional[List[str]] = None
    cwd: Optional[Path] = None

@dataclass
class WorkspaceLayout:
    """Layout for a single workspace."""

    workspace_name: str
    output: str
    windows: List[LayoutWindow]

@dataclass
class ProjectLayout:
    """Full layout for a project."""

    project_name: str
    created: datetime
    monitor_count: int  # Number of monitors when saved
    workspaces: List[WorkspaceLayout]
```

**Capture Implementation**:
```python
async def capture_project_layout(
    project: str,
    i3: Connection,
    state: StateManager
) -> ProjectLayout:
    """Capture current layout for a project."""

    # Get all windows for this project
    windows = await state.get_windows_by_project(project)

    # Get current outputs
    outputs = await i3.get_outputs()
    active_outputs = [o for o in outputs if o.active]

    # Group windows by workspace
    workspaces_dict: Dict[str, List[LayoutWindow]] = {}

    for window_info in windows:
        if window_info.workspace not in workspaces_dict:
            workspaces_dict[window_info.workspace] = []

        # Create layout window
        layout_window = LayoutWindow(
            window_class=window_info.window_class,
            window_instance=window_info.window_instance,
            app_identifier=window_info.app_identifier,
            workspace=window_info.workspace,
            output=window_info.output,
            project=window_info.project,
            marks=window_info.marks,
        )

        workspaces_dict[window_info.workspace].append(layout_window)

    # Create workspace layouts
    workspace_layouts = []
    for ws_name, ws_windows in workspaces_dict.items():
        # Find output for this workspace
        tree = await i3.get_tree()
        ws_con = tree.find_named(ws_name)[0]
        output_name = ws_con.ipc_data.get("output", "")

        workspace_layouts.append(WorkspaceLayout(
            workspace_name=ws_name,
            output=output_name,
            windows=ws_windows,
        ))

    return ProjectLayout(
        project_name=project,
        created=datetime.now(),
        monitor_count=len(active_outputs),
        workspaces=workspace_layouts,
    )
```

**Restore Implementation**:
```python
async def restore_project_layout(
    layout: ProjectLayout,
    i3: Connection,
    state: StateManager
) -> None:
    """Restore a saved layout for a project."""

    # Check monitor compatibility
    outputs = await i3.get_outputs()
    active_outputs = [o for o in outputs if o.active]

    if len(active_outputs) < layout.monitor_count:
        logger.warning(
            f"Layout saved for {layout.monitor_count} monitors, "
            f"you have {len(active_outputs)}. Some windows may not restore correctly."
        )

    # Restore each workspace
    for ws_layout in layout.workspaces:
        await restore_workspace(ws_layout, i3, state)

async def restore_workspace(
    ws_layout: WorkspaceLayout,
    i3: Connection,
    state: StateManager
) -> None:
    """Restore windows in a workspace."""

    for window_spec in ws_layout.windows:
        # Check if window already exists (by mark)
        existing_windows = i3.get_tree().find_marked(f"project:{window_spec.project}")
        existing = next(
            (w for w in existing_windows if w.window_class == window_spec.window_class),
            None
        )

        if existing:
            # Move existing window
            await i3.command(
                f'[con_id={existing.id}] move to workspace {ws_layout.workspace_name}'
            )
        else:
            # Launch new window
            # (Assumes app launcher adds project mark automatically)
            logger.info(f"Need to launch {window_spec.app_identifier} for workspace {ws_layout.workspace_name}")
            # TODO: Implement app launching based on app_identifier
```

#### Phase 2: Advanced Features (Future)

**Add incrementally**:
1. **Floating windows**: Capture x, y, width, height
2. **Split containers**: Capture h-split/v-split hierarchy
3. **Tabs/stacks**: Capture tabbed/stacked containers
4. **Focus tracking**: Restore which window was focused
5. **Fullscreen state**: Restore fullscreen windows

---

## Implementation Examples

### Example 1: Capture Layout via i3ipc

```python
#!/usr/bin/env python3
"""Capture i3 layout using i3ipc."""

import asyncio
import json
from datetime import datetime
from pathlib import Path
from i3ipc.aio import Connection

async def capture_layout(workspace: str, output_file: Path):
    """Capture layout for a workspace."""
    i3 = await Connection().connect()

    # Get workspace container
    tree = await i3.get_tree()
    ws = tree.find_named(workspace)[0]

    if not ws:
        print(f"Workspace {workspace} not found")
        return

    # Extract window info
    windows = []

    def scan_container(con):
        """Recursively scan container for windows."""
        if con.window:  # This is a window
            windows.append({
                "window_id": con.window,
                "class": con.window_class,
                "instance": con.window_instance,
                "title": con.name,
                "marks": con.marks,
                "floating": con.floating == "user_on",
                "rect": {
                    "x": con.rect.x,
                    "y": con.rect.y,
                    "width": con.rect.width,
                    "height": con.rect.height,
                },
                "percent": con.percent,
            })

        # Recurse
        for child in con.nodes + con.floating_nodes:
            scan_container(child)

    scan_container(ws)

    # Create layout
    layout = {
        "workspace": workspace,
        "output": ws.ipc_data.get("output"),
        "created": datetime.now().isoformat(),
        "windows": windows,
    }

    # Save to file
    output_file.write_text(json.dumps(layout, indent=2))
    print(f"Saved layout to {output_file}")
    print(f"  Workspace: {workspace}")
    print(f"  Windows: {len(windows)}")

if __name__ == "__main__":
    asyncio.run(capture_layout("1", Path("workspace-1-layout.json")))
```

**Output Example**:
```json
{
  "workspace": "1",
  "output": "eDP-1",
  "created": "2025-10-20T10:30:00",
  "windows": [
    {
      "window_id": 94557896564,
      "class": "Code",
      "instance": "code",
      "title": "NixOS - Visual Studio Code",
      "marks": ["project:nixos"],
      "floating": false,
      "rect": {"x": 0, "y": 0, "width": 1920, "height": 1080},
      "percent": 0.5
    },
    {
      "window_id": 94557896565,
      "class": "org.kde.ghostty",
      "instance": "ghostty",
      "title": "ghostty - /etc/nixos",
      "marks": ["project:nixos"],
      "floating": false,
      "rect": {"x": 1920, "y": 0, "width": 1920, "height": 1080},
      "percent": 0.5
    }
  ]
}
```

### Example 2: Restore Layout via i3 Commands

```python
#!/usr/bin/env python3
"""Restore i3 layout using i3 IPC commands."""

import asyncio
import json
from pathlib import Path
from i3ipc.aio import Connection

async def restore_layout(layout_file: Path):
    """Restore layout from file."""
    i3 = await Connection().connect()

    # Load layout
    layout = json.loads(layout_file.read_text())

    workspace = layout["workspace"]
    windows = layout["windows"]

    print(f"Restoring layout for workspace {workspace}")
    print(f"  {len(windows)} windows to restore")

    # Switch to workspace (create if doesn't exist)
    await i3.command(f"workspace {workspace}")

    for window_spec in windows:
        # Check if window with mark already exists
        tree = await i3.get_tree()
        existing = None

        for mark in window_spec["marks"]:
            marked_windows = tree.find_marked(mark)
            if marked_windows:
                # Find by class
                existing = next(
                    (w for w in marked_windows if w.window_class == window_spec["class"]),
                    None
                )
                break

        if existing:
            print(f"  ✓ Found existing window: {window_spec['class']}")

            # Move to workspace if not already there
            if existing.workspace().name != workspace:
                await i3.command(f'[con_id={existing.id}] move to workspace {workspace}')
                print(f"    Moved to workspace {workspace}")

            # Set floating state
            if window_spec["floating"]:
                rect = window_spec["rect"]
                await i3.command(
                    f'[con_id={existing.id}] floating enable; '
                    f'resize set {rect["width"]} {rect["height"]}; '
                    f'move position {rect["x"]} {rect["y"]}'
                )
                print(f"    Set floating: {rect['width']}x{rect['height']} at ({rect['x']}, {rect['y']})")
        else:
            print(f"  ✗ Window not found: {window_spec['class']}")
            print(f"    Marks: {window_spec['marks']}")
            print(f"    You may need to launch this application manually")

if __name__ == "__main__":
    asyncio.run(restore_layout(Path("workspace-1-layout.json")))
```

### Example 3: Integration with i3-project-daemon

```python
# Add to home-modules/desktop/i3-project-event-daemon/handlers.py

async def handle_save_layout_command(
    state: StateManager,
    i3: Connection,
    project: str,
    output_file: Path
) -> dict:
    """Handle layout save command from CLI/IPC.

    Args:
        state: Daemon state manager
        i3: i3 IPC connection
        project: Project name to save layout for
        output_file: Where to save layout JSON

    Returns:
        Status dict with success/error info
    """
    try:
        # Capture layout
        layout = await capture_project_layout(project, i3, state)

        # Save to file
        import json
        from dataclasses import asdict

        layout_dict = asdict(layout)
        # Convert datetime to ISO string
        layout_dict["created"] = layout_dict["created"].isoformat()

        output_file.write_text(json.dumps(layout_dict, indent=2))

        logger.info(f"Saved layout for project {project} to {output_file}")

        return {
            "success": True,
            "project": project,
            "file": str(output_file),
            "workspace_count": len(layout.workspaces),
            "window_count": sum(len(ws.windows) for ws in layout.workspaces),
        }

    except Exception as e:
        logger.error(f"Failed to save layout: {e}")
        return {
            "success": False,
            "error": str(e),
        }
```

**CLI Command**:
```bash
# New command to add
i3-project-layout-save nixos --output ~/.config/i3/layouts/nixos.json

# Or use short form
i3-project-layout-save nixos  # Defaults to ~/.config/i3/layouts/{project}.json
```

---

## References

### Official Documentation

- [i3 Layout Saving Documentation](https://i3wm.org/docs/layout-saving.html)
- [i3 IPC Interface](https://i3wm.org/docs/ipc.html)
- [i3 User's Guide - Layout Saving](https://i3wm.org/docs/userguide.html#_layout_saving)

### Third-Party Tools

- [i3-resurrect](https://github.com/JonnyHaystack/i3-resurrect) - Save/restore workspaces with programs
- [i3-layout-manager](https://github.com/klaxalk/i3-layout-manager) - Interactive layout management
- [i3-clever-layout](https://github.com/talwrii/i3-clever-layout) - Automated layout save/restore
- [i3ipc-python](https://github.com/altdesktop/i3ipc-python) - Python i3 IPC library

### Related Resources

- [i3 FAQ: Setting layouts upon launch](https://faq.i3wm.org/question/260/setting-layouts-upon-i3-launch.1.html)
- [Saving i3 Workspace Layout (Blog Post)](https://wes.today/saving-i3-workspace/)
- [Using preset layouts in i3 (Blog Post)](https://gideonwolfe.com/posts/workflow/i3/layouts/)
- [Stack Overflow: Populate pre-configured workspace](https://unix.stackexchange.com/questions/152093/populate-an-entire-pre-configured-workspace-in-i3wm)

### Code Examples

- [i3ipc-python examples](https://github.com/altdesktop/i3ipc-python/tree/master/examples)
- [i3-resurrect source](https://github.com/JonnyHaystack/i3-resurrect/blob/master/i3-resurrect)
- [i3-layout-manager source](https://github.com/klaxalk/i3-layout-manager/blob/master/i3-layout-manager.sh)

---

## Next Steps

1. **Implement Phase 1**: Basic layout capture/restore
   - Add LayoutWindow, WorkspaceLayout, ProjectLayout models to `models.py`
   - Implement `capture_project_layout()` function
   - Implement `restore_project_layout()` function
   - Add CLI commands: `i3-project-layout-save`, `i3-project-layout-restore`

2. **Test with current project system**:
   - Save layout for nixos project
   - Switch to another project
   - Restore nixos layout
   - Verify windows return to correct positions

3. **Add to daemon IPC**:
   - Expose save_layout and restore_layout via IPC server
   - Update daemon status to show saved layouts available

4. **Consider automatic layout save**:
   - Save layout on project switch (optional)
   - Restore layout on project activation (optional)
   - Add config option to enable/disable auto-save/restore

5. **Future enhancements** (Phase 2):
   - Floating window support
   - Split container hierarchy
   - Tabs/stacks
   - Multi-monitor layout adaptation
   - Layout templates (predefined layouts for new projects)

---

**Document Version**: 1.0
**Last Updated**: 2025-10-20
