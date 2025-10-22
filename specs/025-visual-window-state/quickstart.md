# Quick Start: Visual Window State Management

**Feature Branch**: `025-visual-window-state`
**For**: Developers implementing this feature
**Last Updated**: 2025-10-22

## Overview

This feature adds visual window state monitoring, enhanced layout save/restore with flicker prevention, layout diff capabilities, and i3-resurrect compatibility to the i3pm system.

## Prerequisites

```bash
# Ensure you're on the feature branch
git checkout 025-visual-window-state

# Verify daemon is running
i3-project-daemon-status

# Verify i3pm is installed
which i3pm
```

## Architecture Summary

```
┌─────────────────────────────────────────┐
│  i3 Window Manager (Source of Truth)    │
│  - GET_TREE, GET_WORKSPACES, GET_OUTPUTS│
└────────────┬────────────────────────────┘
             │ i3 IPC
             ▼
┌─────────────────────────────────────────┐
│  i3-project-event-daemon                 │
│  - Tracks window events                  │
│  - Broadcasts state changes              │
│  - Provides JSON-RPC IPC                 │
└────────────┬────────────────────────────┘
             │ Unix Socket IPC
             ▼
┌─────────────────────────────────────────┐
│  i3pm CLI/TUI                            │
│  - Window state visualization            │
│  - Layout save/restore                   │
│  - Layout diff                           │
└─────────────────────────────────────────┘
```

## Key Components

### New Modules to Implement

1. **i3_project_manager/visualization/** - Tree/table views for window state
2. **i3_project_manager/core/swallow_matcher.py** - Enhanced window matching
3. **i3_project_manager/core/layout_diff.py** - Diff computation
4. **i3_project_manager/schemas/** - JSON schemas for validation

### Existing Modules to Extend

1. **i3_project_manager/core/layout.py** - Add unmapping/remapping
2. **i3_project_manager/core/models.py** - Add Pydantic validation
3. **i3_project_manager/core/daemon_client.py** - Add window state queries
4. **i3_project_manager/tui/screens/monitor.py** - Add tree view tab

## Development Workflow

### Step 1: Set Up Development Environment

```bash
# Install dependencies
cd /etc/nixos
sudo nixos-rebuild switch --flake .#<your-target>

# Verify Python dependencies
python3 -c "import i3ipc.aio, textual, psutil, pydantic; print('OK')"
```

### Step 2: Implement Data Models

**File**: `home-modules/tools/i3_project_manager/models/layout.py`

```python
from pydantic import BaseModel, Field
from typing import List, Optional
from datetime import datetime

class SwallowCriteria(BaseModel):
    """Window matching criteria."""
    window_class: Optional[str] = None
    instance: Optional[str] = None
    title: Optional[str] = None
    window_role: Optional[str] = None

    def matches(self, window) -> bool:
        # Implementation in data-model.md
        pass

# Add WindowState, LayoutWindow, WorkspaceLayout, SavedLayout
# See data-model.md for complete definitions
```

### Step 3: Implement Window State Visualization

**File**: `home-modules/tools/i3_project_manager/visualization/tree_view.py`

```python
from textual.widgets import Tree
from textual.app import ComposeResult
import i3ipc.aio

class WindowTreeView(Tree):
    """Hierarchical window state visualization."""

    async def update_from_i3(self):
        """Query i3 and update tree structure."""
        async with i3ipc.aio.Connection() as i3:
            tree = await i3.get_tree()
            workspaces = await i3.get_workspaces()
            outputs = await i3.get_outputs()

            # Build tree: outputs → workspaces → windows
            self.clear()
            for output in outputs:
                output_node = self.root.add(f"📺 {output.name}")
                for ws in [w for w in workspaces if w.output == output.name]:
                    ws_node = output_node.add(f"🖥️  WS{ws.num}: {ws.name}")
                    # Add windows from tree
                    for window in find_workspace_windows(tree, ws.name):
                        ws_node.add(f"  {window.window_class}: {window.name}")
```

**CLI Command**: `home-modules/tools/i3_project_manager/cli/commands.py`

```python
@click.command('windows')
@click.option('--tree', is_flag=True, help='Hierarchical tree view')
@click.option('--table', is_flag=True, help='Sortable table view')
@click.option('--live', is_flag=True, help='Real-time updates')
@click.option('--json', is_flag=True, help='JSON output')
async def windows_command(tree, table, live, json):
    """View current window state."""
    if live:
        from i3_project_manager.visualization import WindowMonitorApp
        app = WindowMonitorApp()
        await app.run_async()
    elif tree:
        # Print ASCII tree
        await print_window_tree()
    elif table:
        # Print table
        await print_window_table()
    elif json:
        # Print JSON
        await print_window_json()
```

### Step 4: Implement Layout Save with Unmapping

**File**: `home-modules/tools/i3_project_manager/core/layout.py`

```python
import subprocess
from pathlib import Path

async def save_layout_with_discovery(project: Project, layout_name: str) -> SavedLayout:
    """Save current layout with launch command discovery."""
    async with i3ipc.aio.Connection() as i3:
        tree = await i3.get_tree()
        workspaces = await i3.get_workspaces()
        outputs = await i3.get_outputs()

        workspace_layouts = []
        for ws in workspaces:
            windows = find_workspace_windows(tree, ws.name)
            layout_windows = []

            for window in windows:
                # Discover launch command via psutil
                launch_cmd = await discover_launch_command(window.pid)

                # Create swallow criteria
                swallows = [SwallowCriteria(
                    window_class=f"^{window.window_class}$",
                    instance=f"^{window.window_instance}$"
                )]

                layout_windows.append(LayoutWindow(
                    swallows=swallows,
                    launch_command=launch_cmd.command if launch_cmd else None,
                    working_directory=launch_cmd.working_directory if launch_cmd else None,
                    geometry=WindowGeometry(...),
                    floating=window.floating == 'user_on',
                    border='pixel',
                    layout='splith'
                ))

            workspace_layouts.append(WorkspaceLayout(
                number=ws.num,
                output=ws.output,
                layout='splith',
                windows=layout_windows,
                saved_at=datetime.now(),
                window_count=len(layout_windows)
            ))

        saved_layout = SavedLayout(
            version="1.0",
            project=project.name,
            layout_name=layout_name,
            saved_at=datetime.now(),
            monitor_count=len(outputs),
            monitor_config={o.name: MonitorInfo(...) for o in outputs},
            workspaces=workspace_layouts,
            total_windows=sum(len(ws.windows) for ws in workspace_layouts)
        )

        # Write to file
        layout_path = project_layouts_dir(project) / f"{layout_name}.json"
        layout_path.write_text(saved_layout.model_dump_json(indent=2))

        return saved_layout

async def restore_layout_with_unmapping(project: Project, layout_name: str):
    """Restore layout with flicker prevention."""
    # Load layout
    layout_path = project_layouts_dir(project) / f"{layout_name}.json"
    saved_layout = SavedLayout.model_validate_json(layout_path.read_text())

    async with i3ipc.aio.Connection() as i3:
        for ws_layout in saved_layout.workspaces:
            # 1. Get existing windows on workspace
            await i3.command(f'workspace {ws_layout.number}')
            existing_windows = await get_workspace_window_ids(i3, ws_layout.number)

            # 2. Unmap windows
            for window_id in existing_windows:
                subprocess.run(['xdotool', 'windowunmap', str(window_id)])

            try:
                # 3. Generate append_layout JSON
                append_json = generate_append_layout_json(ws_layout)
                temp_file = Path(f"/tmp/i3pm-layout-{ws_layout.number}.json")
                temp_file.write_text(json.dumps(append_json))

                # 4. Apply layout
                await i3.command(f'append_layout {temp_file}')

                # 5. Launch applications
                for window in ws_layout.windows:
                    if window.launch_command:
                        await launch_application(window)

                # 6. Wait for swallow (timeout 30s)
                await wait_for_swallow(i3, timeout=30)

            finally:
                # 7. Remap all windows (even on error)
                all_windows = await get_workspace_window_ids(i3, ws_layout.number)
                for window_id in all_windows:
                    subprocess.run(['xdotool', 'windowmap', str(window_id)])
```

### Step 5: Implement Layout Diff

**File**: `home-modules/tools/i3_project_manager/core/layout_diff.py`

```python
async def compute_layout_diff(project: Project, layout_name: str) -> WindowDiff:
    """Compute diff between current state and saved layout."""
    # Load saved layout
    layout_path = project_layouts_dir(project) / f"{layout_name}.json"
    saved_layout = SavedLayout.model_validate_json(layout_path.read_text())

    # Get current state
    async with i3ipc.aio.Connection() as i3:
        tree = await i3.get_tree()
        current_windows = extract_all_windows(tree)

    # Match windows
    matches = []
    for curr_win in current_windows:
        for ws_layout in saved_layout.workspaces:
            for saved_win in ws_layout.windows:
                if any(criteria.matches(curr_win) for criteria in saved_win.swallows):
                    matches.append((curr_win, saved_win))
                    break

    # Categorize
    matched_current = {m[0] for m in matches}
    matched_saved = {m[1] for m in matches}

    added = [w for w in current_windows if w not in matched_current]
    removed = [w for all_ws in saved_layout.workspaces for w in all_ws.windows if w not in matched_saved]

    moved = []
    kept = []
    for curr_win, saved_win in matches:
        if (curr_win.workspace != saved_win.workspace or
            curr_win.output != get_output_for_workspace(saved_layout, saved_win)):
            moved.append((curr_win, saved_win))
        else:
            kept.append((curr_win, saved_win))

    return WindowDiff(
        layout_name=layout_name,
        current_windows=len(current_windows),
        saved_windows=sum(ws.window_count for ws in saved_layout.workspaces),
        added=added,
        removed=removed,
        moved=moved,
        kept=kept
    )
```

## Testing Strategy

### Unit Tests

```bash
# Test data models
pytest tests/unit/test_models.py -v

# Test swallow matching
pytest tests/unit/test_swallow_matcher.py -v

# Test diff computation
pytest tests/unit/test_layout_diff.py -v
```

### Integration Tests

```bash
# Test daemon communication
pytest tests/integration/test_daemon_client.py -v

# Test layout save/restore
pytest tests/integration/test_layout_operations.py -v
```

### Manual Testing

```bash
# 1. Save current layout
i3pm layout save dev-setup

# 2. Move windows around
# (manually rearrange windows in i3)

# 3. View diff
i3pm layout diff dev-setup

# 4. Restore layout
i3pm layout restore dev-setup

# 5. View window state tree
i3pm windows --tree --live
```

## Debugging Tips

### Check Daemon Status

```bash
i3-project-daemon-status
i3-project-daemon-events --limit=20
```

### Validate Layout JSON

```bash
# Check layout file syntax
python3 -c "import json; print(json.load(open('~/.config/i3pm/projects/nixos/layouts/dev-setup.json')))"

# Validate against schema
python3 -c "from i3_project_manager.models.layout import SavedLayout; SavedLayout.model_validate_json(open('...').read())"
```

### Monitor Window Events

```bash
# Watch window events in real-time
i3-msg -t subscribe -m '["window"]' | jq .
```

## Common Issues

### Issue: Windows not swallowed during restore

**Cause**: Swallow criteria too strict or application not launching

**Fix**:
```bash
# Check swallow criteria in layout JSON
cat ~/.config/i3pm/projects/<project>/layouts/<layout>.json | jq '.workspaces[].windows[].swallows'

# Test window matching manually
i3pm windows --json | jq '.[] | select(.window_class == "Ghostty")'
```

### Issue: Visual flicker during restore

**Cause**: xdotool not unmapping windows

**Fix**:
```bash
# Verify xdotool is installed
which xdotool

# Test unmapping manually
xdotool search --class Ghostty windowunmap
xdotool search --class Ghostty windowmap
```

### Issue: Launch command not discovered

**Cause**: Process PID not available or process tree incomplete

**Fix**:
```bash
# Check window PID
i3-msg -t get_tree | jq '.nodes[].nodes[].nodes[] | select(.window_properties.class == "Ghostty") | .pid'

# Check process tree
ps -fp <PID>
```

## Performance Targets

- **Real-time updates**: <100ms from i3 event to TUI update
- **Tree rendering**: <100ms for 100 windows
- **Layout save**: <2s for 20 windows
- **Layout restore**: <30s for 20 windows
- **Layout diff**: <500ms for 50 windows

## File Locations

```
~/.config/i3pm/
├── projects/
│   └── <project-name>/
│       └── layouts/
│           ├── dev-setup.json
│           ├── minimal.json
│           └── full-screen.json
└── swallow_criteria.json

/etc/nixos/
├── home-modules/tools/i3_project_manager/
│   ├── visualization/
│   │   ├── tree_view.py
│   │   └── table_view.py
│   ├── core/
│   │   ├── layout.py (extend)
│   │   ├── models.py (extend)
│   │   ├── swallow_matcher.py (new)
│   │   └── layout_diff.py (new)
│   └── schemas/
│       ├── saved_layout.json
│       └── swallow_criteria.json
└── specs/025-visual-window-state/
    ├── spec.md
    ├── plan.md
    ├── research.md
    ├── data-model.md
    ├── quickstart.md
    └── contracts/
```

## Next Steps

1. Review [data-model.md](./data-model.md) for entity definitions
2. Review [research.md](./research.md) for technology decisions
3. Implement data models with Pydantic validation
4. Implement window state visualization
5. Extend layout save/restore with unmapping
6. Implement layout diff
7. Add i3-resurrect import/export

## Resources

- [i3 User's Guide](https://i3wm.org/docs/userguide.html) - i3 window manager documentation
- [i3 IPC Documentation](https://i3wm.org/docs/ipc.html) - i3 IPC protocol reference
- [Textual Documentation](https://textual.textualize.io/) - Terminal UI framework
- [Pydantic Documentation](https://docs.pydantic.dev/) - Data validation library
- [psutil Documentation](https://psutil.readthedocs.io/) - Process utilities

---

**Questions?** Check the spec, plan, or research docs, or test interactively with `i3pm windows --live`
