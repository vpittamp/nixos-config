# Decision: Custom Layout Format with i3ipc

**Date**: 2025-10-20
**Status**: Recommended
**Context**: Layout save/restore for i3 project management system

---

## Decision

**Use custom JSON format with i3ipc GET_TREE for layout capture and i3 IPC commands for restoration.**

Do NOT use i3's native `i3-save-tree`/`append_layout` approach.

---

## Rationale

### Why NOT i3's Native Format

1. **Manual editing required** - `i3-save-tree` output is intentionally incomplete and requires human intervention to specify swallow criteria
2. **Placeholder complexity** - Must manage placeholder windows that wait indefinitely for matching apps
3. **Limited window matching** - Only supports class/instance/title (no marks, no process info)
4. **Multi-monitor inflexibility** - Can't adapt when monitor configuration changes
5. **JSON format quirks** - Non-standard JSON (comments, multiple top-level objects) makes parsing harder

### Why Custom Format

1. **Already using i3ipc** - Event-driven daemon already uses i3ipc for all window management
2. **Full control** - Can implement intelligent matching beyond simple class/title criteria
3. **Better integration** - Reuse existing WindowInfo model and app classification system
4. **Mark-based matching** - Leverage existing project marks (e.g., `project:nixos`)
5. **Adaptive restoration** - Can detect monitor config changes and adapt layout
6. **Progressive enhancement** - Start simple (workspace positions only), add features incrementally

---

## Implementation Strategy

### Phase 1: Basic Layout (MVP)

**Scope**: Capture and restore window-to-workspace assignments only.

**Features**:
- Save which windows belong to which workspace
- Save window class, instance, marks for matching
- Restore windows to correct workspaces (no geometry)
- Skip missing applications with warning

**Data Model**:
```python
@dataclass
class LayoutWindow:
    window_class: str
    window_instance: str
    app_identifier: str
    workspace: str
    output: str
    project: Optional[str]
    marks: List[str]

@dataclass
class WorkspaceLayout:
    workspace_name: str
    output: str
    windows: List[LayoutWindow]

@dataclass
class ProjectLayout:
    project_name: str
    created: datetime
    monitor_count: int
    workspaces: List[WorkspaceLayout]
```

**CLI Commands**:
```bash
# Save current layout
i3-project-layout-save nixos

# Restore saved layout
i3-project-layout-restore nixos

# List saved layouts
i3-project-layout-list
```

**File Location**: `~/.config/i3/layouts/{project}.json`

### Phase 2: Geometry & Floating (Future)

**Add**:
- Floating window positions (x, y, width, height)
- Window geometry for tiled windows (percent of split)
- Floating state restoration

### Phase 3: Container Hierarchy (Future)

**Add**:
- H-split / V-split containers
- Tabbed containers
- Stacked containers
- Nested container hierarchy

---

## Window Matching Strategy

### Priority Order

1. **Project marks** (e.g., `project:nixos`) - Most reliable for existing windows
2. **WM_CLASS** (instance + class) - Best for application identification
3. **Window title** - Fallback when class isn't unique
4. **App identifier** - Use existing app classification system

### Restoration Approach

**Sequential**: Launch apps first, then move to positions (NOT placeholder-based).

```python
async def restore_workspace_layout(ws_layout, i3, state):
    for window_spec in ws_layout.windows:
        # 1. Check if window already exists (by mark)
        existing = find_window_by_mark_and_class(
            mark=f"project:{window_spec.project}",
            window_class=window_spec.window_class
        )

        if existing:
            # Move existing window to workspace
            await i3.command(
                f'[con_id={existing.id}] move to workspace {ws_layout.workspace_name}'
            )
        else:
            # Skip (don't auto-launch)
            logger.warning(f"Window not found: {window_spec.window_class}")
```

---

## Edge Case Handling

### 1. Missing Applications

**Behavior**: Skip with warning, don't create placeholders.

**Rationale**: User should explicitly launch apps, not auto-launch unknown commands.

### 2. Changed Monitor Configuration

**Behavior**: Detect and log warning, restore to available monitors.

```python
if current_monitor_count < saved_monitor_count:
    logger.warning(
        f"Layout saved for {saved_monitor_count} monitors, "
        f"you have {current_monitor_count}. Some windows may not restore correctly."
    )
```

### 3. Window Already on Different Workspace

**Behavior**: Move window to layout's workspace.

**Rationale**: Layout restoration takes priority over current state.

### 4. Multiple Windows with Same Class

**Behavior**: Match by marks first, then by class (first match wins).

**Limitation**: Can't reliably distinguish multiple identical unmarked windows.

---

## File Format Example

```json
{
  "project_name": "nixos",
  "created": "2025-10-20T10:30:00Z",
  "monitor_count": 2,
  "workspaces": [
    {
      "workspace_name": "1",
      "output": "eDP-1",
      "windows": [
        {
          "window_class": "Code",
          "window_instance": "code",
          "app_identifier": "code",
          "workspace": "1",
          "output": "eDP-1",
          "project": "nixos",
          "marks": ["project:nixos"]
        },
        {
          "window_class": "org.kde.ghostty",
          "window_instance": "ghostty",
          "app_identifier": "ghostty",
          "workspace": "1",
          "output": "eDP-1",
          "project": "nixos",
          "marks": ["project:nixos"]
        }
      ]
    },
    {
      "workspace_name": "2",
      "output": "HDMI-1",
      "windows": [
        {
          "window_class": "firefox",
          "window_instance": "Navigator",
          "app_identifier": "firefox",
          "workspace": "2",
          "output": "HDMI-1",
          "project": null,
          "marks": []
        }
      ]
    }
  ]
}
```

---

## Integration Points

### 1. Daemon IPC Commands

Add new methods to `ipc_server.py`:
- `save_layout(project: str, output_file: Optional[Path]) -> dict`
- `restore_layout(project: str, layout_file: Optional[Path]) -> dict`
- `list_layouts() -> List[dict]`

### 2. CLI Commands

Add new scripts in `home-modules/desktop/i3-project-event-daemon/cli/`:
- `i3-project-layout-save` - Wrapper around daemon IPC `save_layout`
- `i3-project-layout-restore` - Wrapper around daemon IPC `restore_layout`
- `i3-project-layout-list` - Wrapper around daemon IPC `list_layouts`

### 3. Project Configuration

Optionally add to `ProjectConfig`:
```python
@dataclass
class ProjectConfig:
    # ... existing fields ...

    # Layout management
    auto_save_layout: bool = False  # Save layout on project switch
    auto_restore_layout: bool = False  # Restore layout on project activation
    layout_file: Optional[Path] = None  # Path to saved layout (if exists)
```

---

## Testing Plan

### 1. Basic Capture

```bash
# Setup: nixos project with 2 workspaces, 3 windows
i3-project-switch nixos
code /etc/nixos  # Workspace 1
ghostty          # Workspace 1
firefox          # Workspace 2

# Capture
i3-project-layout-save nixos

# Verify
cat ~/.config/i3/layouts/nixos.json
# Should show 2 workspaces, 3 windows
```

### 2. Basic Restore

```bash
# Move all windows to workspace 3
i3-msg '[class="Code"] move to workspace 3'
i3-msg '[class="org.kde.ghostty"] move to workspace 3'
i3-msg '[class="firefox"] move to workspace 3'

# Restore
i3-project-layout-restore nixos

# Verify
i3-msg -t get_tree | jq '.nodes[].nodes[].nodes[] | select(.name=="1") | .nodes[].window_properties.class'
# Should show Code and ghostty

i3-msg -t get_tree | jq '.nodes[].nodes[].nodes[] | select(.name=="2") | .nodes[].window_properties.class'
# Should show firefox
```

### 3. Missing Application

```bash
# Close Code window
i3-msg '[class="Code"] kill'

# Restore
i3-project-layout-restore nixos

# Should show warning:
# WARNING: Window not found: Code (project:nixos)
# Skipping window restoration
```

### 4. Changed Monitor Config

```bash
# Save layout with 2 monitors
i3-project-layout-save nixos

# Disconnect monitor
xrandr --output HDMI-1 --off

# Restore
i3-project-layout-restore nixos

# Should show warning:
# WARNING: Layout saved for 2 monitors, you have 1.
# Some windows may not restore correctly.
```

---

## Future Enhancements

1. **Layout templates** - Predefined layouts for new projects
2. **Automatic save on switch** - Save current layout when switching projects
3. **Automatic restore on activate** - Restore layout when activating project
4. **Layout versioning** - Keep history of saved layouts
5. **Layout diff** - Show what changed between current and saved layout
6. **Layout merge** - Combine multiple layouts
7. **Export/import** - Share layouts between machines

---

## References

- Full research document: `research-layout-save-restore.md`
- i3 documentation: https://i3wm.org/docs/layout-saving.html
- i3ipc-python: https://github.com/altdesktop/i3ipc-python
- i3-resurrect: https://github.com/JonnyHaystack/i3-resurrect (for inspiration)

---

**Decision Made By**: Research analysis
**Implementation**: Pending
**Next Steps**: Add data models to `models.py`, implement capture/restore functions
