# Window State Visualization Design

**Feature**: Real-time window state monitoring with i3 JSON compatibility and visual representations

**Created**: 2025-10-22
**Status**: Design Phase

---

## Overview

Enhance i3pm with comprehensive real-time window state visualization that:
1. **Uses i3's native JSON format** as the foundation (extending, not replacing)
2. **Provides multiple visualizations**: Tree view, Table view, JSON export
3. **Real-time updates** via event subscriptions (no polling)
4. **Visual hierarchy** showing monitor → workspace → window relationships
5. **Project context** overlaid on i3's native structure

---

## i3 JSON Format Analysis

### Native i3 Window Node Structure

```json
{
  "id": 94489280512,
  "type": "con",
  "name": "nixos - Visual Studio Code",
  "window": 10485763,
  "window_class": "Code",
  "window_instance": "code",
  "window_title": "nixos - nixos - Visual Studio Code",
  "marks": [],
  "focused": true,
  "floating": "auto_off",
  "fullscreen_mode": 0,
  "layout": "splith",
  "workspace_layout": "default",
  "output": "rdp0",
  "rect": {"x": 0, "y": 0, "width": 1920, "height": 1080},
  "window_rect": {"x": 2, "y": 0, "width": 1916, "height": 1076},
  "nodes": [],
  "floating_nodes": []
}
```

### Our Extensions (i3pm Project Context)

We extend i3's JSON with **non-invasive additions**:

```json
{
  // ... all native i3 fields preserved ...

  "i3pm": {
    "project": "nixos",
    "project_mark": "project:nixos",
    "classification": "scoped",
    "classification_source": "app-classes",
    "hidden": false,
    "tracked": true,
    "app_identifier": "Code"
  }
}
```

**Key Principles**:
- ✅ All i3 native fields preserved exactly as-is
- ✅ Extensions in separate `i3pm` namespace
- ✅ Can strip `i3pm` key to get pure i3 JSON
- ✅ Compatible with i3-msg output format
- ✅ Can be imported/exported with `i3-save-tree` workflow

---

## Visualization Options

### 1. **Tree View** (Textual.widgets.Tree)

**Purpose**: Show hierarchical window organization

```
📺 Output: rdp0 (1920x1080) [Active Project: nixos]
├─ 📋 Workspace 1: Terminal
│  ├─ 🪟 Ghostty [scoped, project:nixos]
│  └─ 🪟 Ghostty [scoped, project:nixos]
├─ 📋 Workspace 2: Code
│  └─ 🪟 Code [scoped, project:nixos] ⭐ focused
└─ 📋 Workspace 3: Browser
   ├─ 🪟 Firefox [global]
   └─ 🪟 YouTube [global, PWA]

📺 Output: rdp1 (1920x1080)
└─ 📋 Workspace 4: Media
   └─ 🪟 YouTube [global, PWA]

👻 Hidden (project != nixos):
├─ 🪟 Ghostty [scoped, project:stacks, WS1]
└─ 🪟 Code [scoped, project:stacks, WS2]
```

**Features**:
- Collapsible nodes (expand/collapse monitors, workspaces)
- Color coding: green=active project, yellow=other project, gray=hidden, red=focused
- Icons: 📺 monitor, 📋 workspace, 🪟 window, ⭐ focused, 👻 hidden
- Real-time node addition/removal
- Navigate with arrow keys, enter to focus window

**Implementation**: Textual `Tree` widget with custom `TreeNode` rendering

---

### 2. **Table View** (Textual.widgets.DataTable)

**Purpose**: Compact sortable overview

| ID | Class | Title | WS | Monitor | Project | Marks | Float | Hidden | Focused |
|----|-------|-------|----|----|---------|-------|-------|--------|---------|
| 10485763 | Code | nixos - Visual Studio Code | 2 | rdp0 | nixos | project:nixos | No | No | ⭐ Yes |
| 6291458 | Ghostty | ~/repos/nixos | 1 | rdp0 | nixos | project:nixos | No | No | No |
| 14680066 | Firefox | GitHub | 3 | rdp0 | - | - | No | No | No |
| 8388610 | Ghostty | ~/repos/stacks | 1 | rdp0 | stacks | project:stacks | No | 👻 Yes | No |

**Features**:
- Sortable columns (click header)
- Filter by: project, monitor, workspace, hidden/visible
- Color coding same as tree view
- Real-time row updates
- Select row and press Enter to focus window

**Implementation**: Textual `DataTable` with reactive data source

---

### 3. **JSON View** (Text widget with syntax highlighting)

**Purpose**: Export/debug view with i3-compatible JSON

```json
{
  "monitors": [
    {
      "name": "rdp0",
      "active": true,
      "workspaces": [
        {
          "num": 2,
          "name": "2",
          "focused": true,
          "visible": true,
          "windows": [
            {
              "id": 10485763,
              "window": 10485763,
              "window_class": "Code",
              "window_title": "nixos - Visual Studio Code",
              "marks": ["project:nixos"],
              "focused": true,
              "floating": "auto_off",
              "workspace": "2",
              "output": "rdp0",
              "i3pm": {
                "project": "nixos",
                "classification": "scoped",
                "hidden": false,
                "tracked": true
              }
            }
          ]
        }
      ]
    }
  ],
  "hidden_windows": [...]
}
```

**Features**:
- Copy to clipboard
- Export to file
- Strip i3pm extensions for pure i3 JSON
- Validate against i3 schema

---

## Visual Representation Library Comparison

| Feature | Textual Tree | Textual DataTable | ASCII Art | Mermaid |
|---------|--------------|-------------------|-----------|---------|
| **Real-time updates** | ✅ Excellent | ✅ Excellent | ⚠️ Full redraw | ❌ Static |
| **Interactivity** | ✅ Navigate, collapse | ✅ Sort, filter | ❌ None | ❌ None |
| **Performance** | ✅ Fast | ✅ Fast | ⚠️ OK for <100 windows | ❌ External renderer |
| **Code complexity** | ✅ Low (built-in) | ✅ Low (built-in) | ⚠️ Medium (custom) | ❌ High (external dep) |
| **Terminal compatibility** | ✅ All modern | ✅ All modern | ✅ Universal | ❌ Requires image support |
| **Hierarchical view** | ✅ Perfect | ❌ Flat only | ✅ With indentation | ✅ Perfect (but static) |
| **Large datasets** | ✅ Handles 1000s | ✅ Handles 1000s | ⚠️ <100 comfortable | ❌ Slow rendering |

**Recommendation**:
- **TUI**: Use **Textual Tree** + **Textual DataTable** (both views in tabs)
- **CLI**: Use **ASCII Tree** for `--tree` flag, **Table** for default
- **Skip Mermaid**: Too complex, requires external rendering, not real-time

---

## ASCII Tree Implementation (for CLI)

For `i3pm windows --tree` without TUI:

```python
def render_ascii_tree(monitors, active_project=None):
    """Render window state as ASCII tree."""
    lines = []

    for monitor in monitors:
        # Monitor header
        active_mark = " [Active Project: {active_project}]" if active_project else ""
        lines.append(f"📺 {monitor.name} ({monitor.width}x{monitor.height}){active_mark}")

        for ws_idx, ws in enumerate(monitor.workspaces):
            is_last_ws = ws_idx == len(monitor.workspaces) - 1
            ws_prefix = "└─" if is_last_ws else "├─"
            lines.append(f"{ws_prefix} 📋 Workspace {ws.num}: {ws.name}")

            for win_idx, win in enumerate(ws.windows):
                is_last_win = win_idx == len(ws.windows) - 1
                win_indent = "   " if is_last_ws else "│  "
                win_prefix = "└─" if is_last_win else "├─"

                # Window formatting
                project_info = f", project:{win.project}" if win.project else ""
                focus_mark = " ⭐" if win.focused else ""
                hidden_mark = " 👻" if win.hidden else ""

                lines.append(
                    f"{win_indent}{win_prefix} 🪟 {win.window_class} "
                    f"[{win.classification}{project_info}]{focus_mark}{hidden_mark}"
                )

        lines.append("")  # Blank line between monitors

    # Hidden windows section
    hidden = [w for w in all_windows if w.hidden]
    if hidden:
        lines.append("👻 Hidden (not in active project):")
        for win in hidden:
            lines.append(f"├─ 🪟 {win.window_class} [project:{win.project}, WS{win.workspace}]")

    return "\n".join(lines)
```

**Advantages**:
- ✅ Works in any terminal
- ✅ Can be piped/redirected
- ✅ No TUI overhead
- ✅ Good for scripts

---

## Implementation Architecture

### 1. Daemon RPC Enhancement

**New method**: `get_window_tree(include_i3pm=True, include_hidden=True)`

```python
async def _get_window_tree(self, params: Dict[str, Any]) -> Dict[str, Any]:
    """Get complete window tree with i3 JSON compatibility.

    Args:
        params:
            - include_i3pm (bool): Include i3pm extensions (default True)
            - include_hidden (bool): Include hidden windows (default True)
            - strip_i3pm (bool): Remove i3pm extensions for pure i3 JSON (default False)

    Returns:
        {
            "monitors": [
                {
                    "name": str,
                    "active": bool,
                    "width": int,
                    "height": int,
                    "workspaces": [
                        {
                            "num": int,
                            "name": str,
                            "focused": bool,
                            "visible": bool,
                            "windows": [
                                {
                                    # All i3 native fields ...
                                    "id": int,
                                    "window": int,
                                    "window_class": str,
                                    "window_title": str,
                                    "marks": [str],
                                    "focused": bool,
                                    "floating": str,
                                    "workspace": str,
                                    "output": str,
                                    # i3pm extensions (if include_i3pm=True)
                                    "i3pm": {
                                        "project": str | null,
                                        "classification": str,
                                        "hidden": bool,
                                        "tracked": bool,
                                        "app_identifier": str
                                    }
                                }
                            ]
                        }
                    ]
                }
            ],
            "hidden_windows": [...],  # if include_hidden=True
            "active_project": str | null,
            "total_windows": int,
            "total_visible": int,
            "total_hidden": int
        }
    """
```

### 2. TUI Screen: WindowStateScreen

**File**: `home-modules/tools/i3_project_manager/tui/screens/window_state.py`

```python
class WindowStateScreen(Screen):
    """Real-time window state visualization.

    Features:
    - Tab 1: Tree view (hierarchical)
    - Tab 2: Table view (sortable)
    - Tab 3: JSON view (exportable)
    - Real-time updates via event subscription
    - Keyboard shortcuts for filtering
    """

    BINDINGS = [
        Binding("1", "tab_tree", "Tree View"),
        Binding("2", "tab_table", "Table View"),
        Binding("3", "tab_json", "JSON View"),
        Binding("h", "toggle_hidden", "Toggle Hidden"),
        Binding("p", "filter_project", "Filter Project"),
        Binding("m", "filter_monitor", "Filter Monitor"),
        Binding("r", "refresh", "Refresh"),
        Binding("e", "export", "Export JSON"),
    ]

    async def on_mount(self):
        # Subscribe to daemon events
        await self.subscribe_to_events()
        await self.load_initial_state()

    async def subscribe_to_events(self):
        """Subscribe to real-time window events."""
        await self.daemon_client.call("subscribe_events", {"subscribe": True})

        # Start event listener task
        self.event_task = asyncio.create_task(self._listen_for_events())

    async def _listen_for_events(self):
        """Listen for event notifications and update UI."""
        while True:
            # Read event notification from daemon
            event = await self.daemon_client.read_notification()

            # Update appropriate view
            if event["event_type"] == "window":
                await self.update_window(event)
            elif event["event_type"] == "workspace":
                await self.update_workspace(event)
            elif event["event_type"] == "tick":
                # Project switch
                await self.refresh_all()
```

### 3. CLI Enhancement

**New flags for `i3pm windows`**:

```bash
# Current (table view, snapshot)
i3pm windows

# New: Tree view, snapshot
i3pm windows --tree

# New: Table view, live updates
i3pm windows --live

# New: Tree view, live updates
i3pm windows --tree --live

# New: JSON export with i3 compatibility
i3pm windows --json --strip-i3pm > windows.json

# New: Filter options
i3pm windows --tree --project=nixos --monitor=rdp0
```

---

## Performance Considerations

### Event Subscription Overhead

**Current**: Manual refresh only (no overhead)
**Proposed**: WebSocket-style event stream

**Impact**:
- Daemon: +1 client connection per TUI session
- Network: ~100 bytes per event (JSON-RPC notification)
- Frequency: ~10-50 events/minute (normal usage)
- Memory: Negligible (<1MB per subscriber)

**Mitigation**:
- Limit subscribers (e.g., max 5 concurrent)
- Debounce rapid events (100ms window)
- Unsubscribe on TUI exit

### Tree Rendering Performance

**Textual Tree widget**:
- Handles 1000+ nodes efficiently
- Lazy rendering (only visible nodes)
- Diff-based updates (only changed nodes)

**Typical window counts**:
- Small setup: 10-20 windows → instant
- Medium setup: 50-100 windows → <50ms
- Large setup: 200+ windows → <100ms

**Optimization**: Only update changed branches

---

## User Experience Improvements

### 1. **Visual Hierarchy Understanding**

Current: Flat list of windows, hard to understand relationships

Proposed: Clear monitor → workspace → window hierarchy

### 2. **Project Context Visibility**

Current: Must check marks manually to see project association

Proposed: Color-coded tree shows project at a glance

### 3. **Hidden Window Discovery**

Current: No way to see which windows are hidden by project switching

Proposed: Dedicated "Hidden" section shows what's hidden and why

### 4. **Real-time Feedback**

Current: Must manually refresh to see changes

Proposed: Automatic updates when windows open/close/move

### 5. **Export/Import Workflows**

Current: No way to save window state

Proposed: Export JSON compatible with i3-save-tree

---

## Implementation Plan

**Phase 1: Daemon RPC** (30 min)
- [ ] Add `get_window_tree()` method to `ipc_server.py`
- [ ] Extend `_get_windows()` to include output, floating, hidden state
- [ ] Add `strip_i3pm` parameter for pure i3 JSON export

**Phase 2: CLI Tree View** (45 min)
- [ ] Implement `render_ascii_tree()` function
- [ ] Add `--tree` flag to `cmd_windows()`
- [ ] Add `--strip-i3pm` flag for JSON export
- [ ] Test with various window configurations

**Phase 3: TUI Window State Screen** (90 min)
- [ ] Create `WindowStateScreen` class
- [ ] Implement Tree view tab with Textual.widgets.Tree
- [ ] Implement Table view tab with DataTable
- [ ] Implement JSON view tab with Text widget
- [ ] Add keyboard shortcuts and filters

**Phase 4: Real-time Events** (60 min)
- [ ] Implement event subscription in WindowStateScreen
- [ ] Add event listener task
- [ ] Implement incremental tree/table updates
- [ ] Add debouncing for rapid events
- [ ] Test with window creation/destruction/movement

**Phase 5: Integration** (30 min)
- [ ] Add "Windows" tab to existing MonitorScreen
- [ ] Update CLI help text
- [ ] Add to quickstart documentation
- [ ] Test end-to-end workflow

**Total Estimated Time**: 4-5 hours

---

## Testing Scenarios

1. **Static view**: 10 windows across 2 monitors → verify tree structure
2. **Project switch**: Switch projects → verify hidden windows section updates
3. **Window creation**: Open new window → verify it appears in tree instantly
4. **Window destruction**: Close window → verify it disappears from tree
5. **Workspace move**: Move window to different workspace → verify tree updates
6. **Monitor change**: Connect/disconnect monitor → verify tree reorganizes
7. **Export**: Export JSON → verify it's valid i3 JSON (can be imported with i3-msg)
8. **Performance**: 100+ windows → verify <100ms render time

---

## Open Questions

1. **Should we support i3-save-tree format for import?**
   - Could allow users to pre-define window layouts
   - Would need to extend with project context
   - Deferred to future feature

2. **Should we show floating windows in separate section?**
   - Current design: Shows floating inline with tiled (marked with icon)
   - Alternative: Separate "Floating" branch under workspace
   - Decision: Keep inline, use icon/color to distinguish

3. **Should we support filtering in real-time mode?**
   - Yes, keyboard shortcuts to toggle filters
   - Filter persists across updates

---

## Conclusion

**Recommendation**: Implement using **Textual Tree + DataTable** for TUI, **ASCII tree** for CLI

**Benefits**:
- ✅ i3 JSON compatibility (can export/import with native tools)
- ✅ Visual hierarchy makes relationships clear
- ✅ Real-time updates provide immediate feedback
- ✅ Low code complexity (built-in Textual widgets)
- ✅ Excellent performance (handles 1000+ windows)
- ✅ Works in any terminal
- ✅ Extensible (can add more views later)

**Next Step**: Proceed with Phase 1 implementation (Daemon RPC enhancement)
