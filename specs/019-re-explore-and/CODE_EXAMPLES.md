# Code Examples: Layout Save/Restore Implementation

**Date**: 2025-10-20
**Context**: Implementation examples for custom layout save/restore using i3ipc

---

## Table of Contents

1. [Data Models](#data-models)
2. [Capture Layout](#capture-layout)
3. [Restore Layout](#restore-layout)
4. [Window Matching](#window-matching)
5. [Daemon Integration](#daemon-integration)
6. [CLI Commands](#cli-commands)
7. [Testing](#testing)

---

## Data Models

### Add to `home-modules/desktop/i3-project-event-daemon/models.py`

```python
from dataclasses import dataclass, field
from datetime import datetime
from pathlib import Path
from typing import List, Optional

@dataclass
class LayoutWindow:
    """Window specification in a saved layout."""

    # Identity (for matching)
    window_class: str  # WM_CLASS class
    window_instance: str  # WM_CLASS instance
    app_identifier: str  # Application identifier (from app classification)

    # Position
    workspace: str  # Workspace name (e.g., "1", "2:code")
    output: str  # Monitor/output name (e.g., "eDP-1", "HDMI-1")

    # Project association
    project: Optional[str] = None  # Project name if project-scoped
    marks: List[str] = field(default_factory=list)  # All i3 marks

    # Optional: Process info for relaunching
    cmdline: Optional[List[str]] = None  # Command line arguments
    cwd: Optional[Path] = None  # Working directory

    def __post_init__(self) -> None:
        """Validate window specification."""
        if not self.window_class:
            raise ValueError("window_class cannot be empty")
        if not self.workspace:
            raise ValueError("workspace cannot be empty")


@dataclass
class WorkspaceLayout:
    """Layout for a single workspace."""

    workspace_name: str  # Workspace name
    output: str  # Monitor this workspace is on
    windows: List[LayoutWindow] = field(default_factory=list)

    def __post_init__(self) -> None:
        """Validate workspace layout."""
        if not self.workspace_name:
            raise ValueError("workspace_name cannot be empty")


@dataclass
class ProjectLayout:
    """Complete layout for a project."""

    # Identity
    project_name: str  # Project this layout belongs to

    # Metadata
    created: datetime  # When layout was saved
    monitor_count: int  # Number of monitors when saved (for compatibility check)

    # Layout data
    workspaces: List[WorkspaceLayout] = field(default_factory=list)

    def __post_init__(self) -> None:
        """Validate project layout."""
        if not self.project_name:
            raise ValueError("project_name cannot be empty")
        if self.monitor_count < 1:
            raise ValueError(f"Invalid monitor_count: {self.monitor_count}")

    @property
    def window_count(self) -> int:
        """Total number of windows in this layout."""
        return sum(len(ws.windows) for ws in self.workspaces)
```

---

## Capture Layout

### Implementation in new file: `home-modules/desktop/i3-project-event-daemon/layout.py`

```python
"""Layout save/restore functionality for i3 project management."""

import logging
from datetime import datetime
from typing import List, Optional
from i3ipc.aio import Connection
from pathlib import Path

from .models import ProjectLayout, WorkspaceLayout, LayoutWindow
from .state import StateManager

logger = logging.getLogger(__name__)


async def capture_project_layout(
    project: str,
    i3: Connection,
    state: StateManager
) -> ProjectLayout:
    """Capture current layout for a project.

    Args:
        project: Project name to capture layout for
        i3: i3 IPC connection
        state: Daemon state manager

    Returns:
        ProjectLayout object with current window positions

    Raises:
        ValueError: If project not found or has no windows
    """
    # Get all windows for this project
    windows = await state.get_windows_by_project(project)

    if not windows:
        raise ValueError(f"Project {project} has no windows to save")

    # Get current monitor count
    outputs = await i3.get_outputs()
    active_outputs = [o for o in outputs if o.active]
    monitor_count = len(active_outputs)

    logger.info(f"Capturing layout for project {project} ({len(windows)} windows, {monitor_count} monitors)")

    # Group windows by workspace
    workspace_dict = {}

    for window_info in windows:
        ws_name = window_info.workspace
        if not ws_name:
            logger.warning(f"Window {window_info.window_id} has no workspace, skipping")
            continue

        if ws_name not in workspace_dict:
            workspace_dict[ws_name] = []

        # Create layout window spec
        layout_window = LayoutWindow(
            window_class=window_info.window_class,
            window_instance=window_info.window_instance,
            app_identifier=window_info.app_identifier,
            workspace=window_info.workspace,
            output=window_info.output,
            project=window_info.project,
            marks=window_info.marks.copy(),
        )

        workspace_dict[ws_name].append(layout_window)

    # Create workspace layouts
    workspace_layouts = []

    for ws_name, ws_windows in sorted(workspace_dict.items()):
        # Get output for this workspace
        tree = await i3.get_tree()
        ws_containers = tree.find_named(ws_name)

        if not ws_containers:
            logger.warning(f"Workspace {ws_name} not found in tree, using primary output")
            output_name = active_outputs[0].name if active_outputs else "primary"
        else:
            ws_con = ws_containers[0]
            output_name = ws_con.ipc_data.get("output", "primary")

        workspace_layouts.append(WorkspaceLayout(
            workspace_name=ws_name,
            output=output_name,
            windows=ws_windows,
        ))

    # Create project layout
    layout = ProjectLayout(
        project_name=project,
        created=datetime.now(),
        monitor_count=monitor_count,
        workspaces=workspace_layouts,
    )

    logger.info(
        f"Captured layout: {len(workspace_layouts)} workspaces, "
        f"{layout.window_count} windows"
    )

    return layout


async def save_project_layout(
    project: str,
    output_file: Path,
    i3: Connection,
    state: StateManager
) -> dict:
    """Capture and save project layout to file.

    Args:
        project: Project name
        output_file: Path to save layout JSON
        i3: i3 IPC connection
        state: Daemon state manager

    Returns:
        Status dict with success/error info
    """
    try:
        # Capture layout
        layout = await capture_project_layout(project, i3, state)

        # Convert to JSON
        import json
        from dataclasses import asdict

        layout_dict = asdict(layout)

        # Convert datetime to ISO string
        layout_dict["created"] = layout_dict["created"].isoformat()

        # Convert Path objects to strings
        for ws in layout_dict["workspaces"]:
            for window in ws["windows"]:
                if window.get("cwd"):
                    window["cwd"] = str(window["cwd"])

        # Ensure output directory exists
        output_file.parent.mkdir(parents=True, exist_ok=True)

        # Save to file
        output_file.write_text(json.dumps(layout_dict, indent=2))

        logger.info(f"Saved layout to {output_file}")

        return {
            "success": True,
            "project": project,
            "file": str(output_file),
            "workspace_count": len(layout.workspaces),
            "window_count": layout.window_count,
        }

    except Exception as e:
        logger.error(f"Failed to save layout: {e}", exc_info=True)
        return {
            "success": False,
            "error": str(e),
        }
```

---

## Restore Layout

### Add to `layout.py`

```python
async def restore_project_layout(
    layout: ProjectLayout,
    i3: Connection,
    state: StateManager
) -> dict:
    """Restore a saved project layout.

    Args:
        layout: ProjectLayout object to restore
        i3: i3 IPC connection
        state: Daemon state manager

    Returns:
        Status dict with success/error info
    """
    # Check monitor compatibility
    outputs = await i3.get_outputs()
    active_outputs = [o for o in outputs if o.active]
    current_monitor_count = len(active_outputs)

    if current_monitor_count < layout.monitor_count:
        logger.warning(
            f"Layout saved for {layout.monitor_count} monitors, "
            f"you have {current_monitor_count}. "
            f"Some windows may not restore correctly."
        )

    logger.info(
        f"Restoring layout for project {layout.project_name}: "
        f"{len(layout.workspaces)} workspaces, {layout.window_count} windows"
    )

    # Track restoration results
    moved_count = 0
    skipped_count = 0
    errors = []

    # Restore each workspace
    for ws_layout in layout.workspaces:
        result = await restore_workspace(ws_layout, i3, state)
        moved_count += result["moved"]
        skipped_count += result["skipped"]
        errors.extend(result["errors"])

    logger.info(
        f"Layout restoration complete: "
        f"{moved_count} windows moved, {skipped_count} skipped"
    )

    return {
        "success": len(errors) == 0,
        "project": layout.project_name,
        "moved": moved_count,
        "skipped": skipped_count,
        "errors": errors,
    }


async def restore_workspace(
    ws_layout: WorkspaceLayout,
    i3: Connection,
    state: StateManager
) -> dict:
    """Restore windows in a single workspace.

    Args:
        ws_layout: WorkspaceLayout to restore
        i3: i3 IPC connection
        state: Daemon state manager

    Returns:
        Dict with moved/skipped counts and errors
    """
    moved_count = 0
    skipped_count = 0
    errors = []

    logger.debug(f"Restoring workspace {ws_layout.workspace_name} ({len(ws_layout.windows)} windows)")

    for window_spec in ws_layout.windows:
        try:
            # Find existing window
            existing_window = await find_matching_window(window_spec, i3, state)

            if existing_window:
                # Get current workspace
                tree = await i3.get_tree()
                container = tree.find_by_id(existing_window.con_id)

                if not container:
                    logger.warning(f"Container {existing_window.con_id} not found in tree")
                    skipped_count += 1
                    continue

                current_ws = container.workspace()
                current_ws_name = current_ws.name if current_ws else None

                if current_ws_name != ws_layout.workspace_name:
                    # Move to correct workspace
                    await i3.command(
                        f'[con_id={container.id}] '
                        f'move to workspace {ws_layout.workspace_name}'
                    )

                    logger.debug(
                        f"Moved {window_spec.window_class} "
                        f"from {current_ws_name} to {ws_layout.workspace_name}"
                    )
                    moved_count += 1
                else:
                    logger.debug(f"Window {window_spec.window_class} already on correct workspace")

            else:
                logger.warning(
                    f"Window not found: {window_spec.window_class} "
                    f"(marks: {window_spec.marks})"
                )
                skipped_count += 1

        except Exception as e:
            error_msg = f"Failed to restore {window_spec.window_class}: {e}"
            logger.error(error_msg)
            errors.append(error_msg)
            skipped_count += 1

    return {
        "moved": moved_count,
        "skipped": skipped_count,
        "errors": errors,
    }


async def load_project_layout(layout_file: Path) -> ProjectLayout:
    """Load project layout from JSON file.

    Args:
        layout_file: Path to layout JSON file

    Returns:
        ProjectLayout object

    Raises:
        FileNotFoundError: If layout file doesn't exist
        ValueError: If layout file is invalid
    """
    if not layout_file.exists():
        raise FileNotFoundError(f"Layout file not found: {layout_file}")

    import json
    from datetime import datetime

    try:
        layout_dict = json.loads(layout_file.read_text())

        # Convert ISO string to datetime
        layout_dict["created"] = datetime.fromisoformat(layout_dict["created"])

        # Convert dict to dataclass
        workspaces = [
            WorkspaceLayout(
                workspace_name=ws["workspace_name"],
                output=ws["output"],
                windows=[
                    LayoutWindow(**window)
                    for window in ws["windows"]
                ]
            )
            for ws in layout_dict["workspaces"]
        ]

        return ProjectLayout(
            project_name=layout_dict["project_name"],
            created=layout_dict["created"],
            monitor_count=layout_dict["monitor_count"],
            workspaces=workspaces,
        )

    except Exception as e:
        raise ValueError(f"Invalid layout file: {e}")
```

---

## Window Matching

### Add to `layout.py`

```python
async def find_matching_window(
    window_spec: LayoutWindow,
    i3: Connection,
    state: StateManager
) -> Optional["WindowInfo"]:
    """Find existing window that matches layout specification.

    Matching priority:
    1. Project mark + window class
    2. All marks + window class
    3. Window class + instance

    Args:
        window_spec: LayoutWindow specification to match
        i3: i3 IPC connection
        state: Daemon state manager

    Returns:
        WindowInfo if found, None otherwise
    """
    # Priority 1: Match by project mark + window class
    if window_spec.project:
        project_mark = f"project:{window_spec.project}"
        tree = await i3.get_tree()
        marked_windows = tree.find_marked(project_mark)

        for container in marked_windows:
            if container.window_class == window_spec.window_class:
                # Found match by project mark and class
                window_info = await state.get_window(container.window)
                if window_info:
                    logger.debug(
                        f"Matched window by project mark: "
                        f"{window_spec.window_class} (mark={project_mark})"
                    )
                    return window_info

    # Priority 2: Match by any mark + window class
    tree = await i3.get_tree()
    for mark in window_spec.marks:
        if not mark:
            continue

        marked_windows = tree.find_marked(mark)
        for container in marked_windows:
            if container.window_class == window_spec.window_class:
                window_info = await state.get_window(container.window)
                if window_info:
                    logger.debug(
                        f"Matched window by mark: "
                        f"{window_spec.window_class} (mark={mark})"
                    )
                    return window_info

    # Priority 3: Match by window class + instance
    # (Less reliable, may match wrong window if multiple instances)
    all_windows = await state.state.window_map.values()
    for window_info in all_windows:
        if (window_info.window_class == window_spec.window_class and
            window_info.window_instance == window_spec.window_instance):
            logger.debug(
                f"Matched window by class+instance: "
                f"{window_spec.window_class}/{window_spec.window_instance}"
            )
            return window_info

    # No match found
    return None
```

---

## Daemon Integration

### Add to `home-modules/desktop/i3-project-event-daemon/ipc_server.py`

```python
# Import layout functions
from .layout import save_project_layout, load_project_layout, restore_project_layout

# Add to IPCServer class methods:

async def handle_save_layout(self, params: dict) -> dict:
    """Handle save_layout IPC command.

    Args:
        params: {
            "project": str,  # Project name
            "output_file": str  # Optional output path
        }

    Returns:
        Status dict with success/error info
    """
    project = params.get("project")
    if not project:
        return {"success": False, "error": "Missing 'project' parameter"}

    # Default output file
    output_file_str = params.get("output_file")
    if output_file_str:
        output_file = Path(output_file_str)
    else:
        # Default: ~/.config/i3/layouts/{project}.json
        config_dir = Path.home() / ".config" / "i3" / "layouts"
        output_file = config_dir / f"{project}.json"

    return await save_project_layout(
        project=project,
        output_file=output_file,
        i3=self.daemon.i3,
        state=self.daemon.state,
    )


async def handle_restore_layout(self, params: dict) -> dict:
    """Handle restore_layout IPC command.

    Args:
        params: {
            "project": str,  # Project name
            "layout_file": str  # Optional layout file path
        }

    Returns:
        Status dict with success/error info
    """
    project = params.get("project")
    if not project:
        return {"success": False, "error": "Missing 'project' parameter"}

    # Default layout file
    layout_file_str = params.get("layout_file")
    if layout_file_str:
        layout_file = Path(layout_file_str)
    else:
        # Default: ~/.config/i3/layouts/{project}.json
        config_dir = Path.home() / ".config" / "i3" / "layouts"
        layout_file = config_dir / f"{project}.json"

    try:
        # Load layout from file
        layout = await load_project_layout(layout_file)

        # Restore layout
        return await restore_project_layout(
            layout=layout,
            i3=self.daemon.i3,
            state=self.daemon.state,
        )

    except FileNotFoundError as e:
        return {"success": False, "error": str(e)}
    except ValueError as e:
        return {"success": False, "error": f"Invalid layout file: {e}"}


async def handle_list_layouts(self, params: dict) -> dict:
    """Handle list_layouts IPC command.

    Returns:
        List of saved layouts with metadata
    """
    layouts_dir = Path.home() / ".config" / "i3" / "layouts"

    if not layouts_dir.exists():
        return {"success": True, "layouts": []}

    layouts = []

    for layout_file in layouts_dir.glob("*.json"):
        try:
            import json
            layout_dict = json.loads(layout_file.read_text())

            layouts.append({
                "project": layout_dict["project_name"],
                "file": str(layout_file),
                "created": layout_dict["created"],
                "workspace_count": len(layout_dict["workspaces"]),
                "window_count": sum(len(ws["windows"]) for ws in layout_dict["workspaces"]),
                "monitor_count": layout_dict["monitor_count"],
            })

        except Exception as e:
            logger.warning(f"Failed to parse layout {layout_file}: {e}")

    return {
        "success": True,
        "layouts": sorted(layouts, key=lambda x: x["created"], reverse=True),
    }
```

**Update method dispatch**:

```python
# In IPCServer.__init__ or handle_request method:
self.handlers = {
    # ... existing handlers ...
    "save_layout": self.handle_save_layout,
    "restore_layout": self.handle_restore_layout,
    "list_layouts": self.handle_list_layouts,
}
```

---

## CLI Commands

### Create `home-modules/desktop/i3-project-event-daemon/cli/i3-project-layout-save`

```python
#!/usr/bin/env python3
"""Save current i3 project layout."""

import argparse
import asyncio
import json
import sys
from pathlib import Path

# Assuming daemon_client utility exists
from i3_project_monitor.daemon_client import DaemonClient


async def main():
    parser = argparse.ArgumentParser(
        description="Save current window layout for an i3 project"
    )
    parser.add_argument(
        "project",
        help="Project name to save layout for"
    )
    parser.add_argument(
        "-o", "--output",
        type=Path,
        help="Output file path (default: ~/.config/i3/layouts/{project}.json)"
    )
    parser.add_argument(
        "--daemon-socket",
        type=Path,
        help="Daemon IPC socket path (default: $XDG_RUNTIME_DIR/i3-project-daemon/ipc.sock)"
    )

    args = parser.parse_args()

    # Connect to daemon
    client = DaemonClient(socket_path=args.daemon_socket)

    try:
        # Call save_layout
        response = await client.call_method(
            "save_layout",
            {
                "project": args.project,
                "output_file": str(args.output) if args.output else None,
            }
        )

        if response.get("success"):
            print(f"✓ Layout saved for project: {args.project}")
            print(f"  File: {response['file']}")
            print(f"  Workspaces: {response['workspace_count']}")
            print(f"  Windows: {response['window_count']}")
            sys.exit(0)
        else:
            print(f"✗ Failed to save layout: {response.get('error')}", file=sys.stderr)
            sys.exit(1)

    except Exception as e:
        print(f"✗ Error: {e}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    asyncio.run(main())
```

### Create `home-modules/desktop/i3-project-event-daemon/cli/i3-project-layout-restore`

```python
#!/usr/bin/env python3
"""Restore saved i3 project layout."""

import argparse
import asyncio
import sys
from pathlib import Path

from i3_project_monitor.daemon_client import DaemonClient


async def main():
    parser = argparse.ArgumentParser(
        description="Restore saved window layout for an i3 project"
    )
    parser.add_argument(
        "project",
        help="Project name to restore layout for"
    )
    parser.add_argument(
        "-f", "--file",
        type=Path,
        help="Layout file path (default: ~/.config/i3/layouts/{project}.json)"
    )
    parser.add_argument(
        "--daemon-socket",
        type=Path,
        help="Daemon IPC socket path"
    )

    args = parser.parse_args()

    # Connect to daemon
    client = DaemonClient(socket_path=args.daemon_socket)

    try:
        # Call restore_layout
        response = await client.call_method(
            "restore_layout",
            {
                "project": args.project,
                "layout_file": str(args.file) if args.file else None,
            }
        )

        if response.get("success"):
            print(f"✓ Layout restored for project: {args.project}")
            print(f"  Moved: {response['moved']} windows")
            print(f"  Skipped: {response['skipped']} windows")

            if response.get("errors"):
                print(f"\nErrors:")
                for error in response["errors"]:
                    print(f"  - {error}")
            sys.exit(0)
        else:
            print(f"✗ Failed to restore layout: {response.get('error')}", file=sys.stderr)
            sys.exit(1)

    except Exception as e:
        print(f"✗ Error: {e}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    asyncio.run(main())
```

### Create `home-modules/desktop/i3-project-event-daemon/cli/i3-project-layout-list`

```python
#!/usr/bin/env python3
"""List saved i3 project layouts."""

import argparse
import asyncio
import sys
from pathlib import Path

from i3_project_monitor.daemon_client import DaemonClient


async def main():
    parser = argparse.ArgumentParser(
        description="List saved i3 project layouts"
    )
    parser.add_argument(
        "--daemon-socket",
        type=Path,
        help="Daemon IPC socket path"
    )

    args = parser.parse_args()

    # Connect to daemon
    client = DaemonClient(socket_path=args.daemon_socket)

    try:
        # Call list_layouts
        response = await client.call_method("list_layouts", {})

        if response.get("success"):
            layouts = response.get("layouts", [])

            if not layouts:
                print("No saved layouts found")
                sys.exit(0)

            print(f"Saved layouts ({len(layouts)}):\n")

            for layout in layouts:
                print(f"  {layout['project']}")
                print(f"    File: {layout['file']}")
                print(f"    Created: {layout['created']}")
                print(f"    Workspaces: {layout['workspace_count']}")
                print(f"    Windows: {layout['window_count']}")
                print(f"    Monitors: {layout['monitor_count']}")
                print()

            sys.exit(0)
        else:
            print(f"✗ Failed to list layouts: {response.get('error')}", file=sys.stderr)
            sys.exit(1)

    except Exception as e:
        print(f"✗ Error: {e}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    asyncio.run(main())
```

---

## Testing

### Test Script: `test_layout_save_restore.py`

```python
#!/usr/bin/env python3
"""Test layout save/restore functionality."""

import asyncio
import json
from pathlib import Path
import tempfile
from i3ipc.aio import Connection

# Import layout functions (adjust path as needed)
import sys
sys.path.insert(0, str(Path(__file__).parent))

from layout import (
    capture_project_layout,
    save_project_layout,
    load_project_layout,
    restore_project_layout,
)


async def test_capture_and_save():
    """Test capturing and saving layout."""
    print("Test: Capture and save layout")

    # Mock state manager (simplified)
    class MockState:
        async def get_windows_by_project(self, project):
            from models import WindowInfo
            from datetime import datetime

            return [
                WindowInfo(
                    window_id=12345,
                    con_id=67890,
                    window_class="Code",
                    window_instance="code",
                    window_title="Test",
                    app_identifier="code",
                    project="nixos",
                    marks=["project:nixos"],
                    workspace="1",
                    output="eDP-1",
                    created=datetime.now(),
                ),
                WindowInfo(
                    window_id=12346,
                    con_id=67891,
                    window_class="org.kde.ghostty",
                    window_instance="ghostty",
                    window_title="Terminal",
                    app_identifier="ghostty",
                    project="nixos",
                    marks=["project:nixos"],
                    workspace="2",
                    output="HDMI-1",
                    created=datetime.now(),
                ),
            ]

    state = MockState()
    i3 = await Connection().connect()

    # Capture layout
    layout = await capture_project_layout("nixos", i3, state)

    print(f"✓ Captured layout: {len(layout.workspaces)} workspaces, {layout.window_count} windows")

    # Save to temp file
    with tempfile.NamedTemporaryFile(mode='w', suffix='.json', delete=False) as f:
        temp_file = Path(f.name)

    result = await save_project_layout("nixos", temp_file, i3, state)

    if result["success"]:
        print(f"✓ Saved to {temp_file}")

        # Verify file contents
        layout_dict = json.loads(temp_file.read_text())
        assert layout_dict["project_name"] == "nixos"
        assert len(layout_dict["workspaces"]) == 2

        print("✓ File contents valid")
    else:
        print(f"✗ Save failed: {result['error']}")

    temp_file.unlink()


async def test_load_and_restore():
    """Test loading and restoring layout."""
    print("\nTest: Load and restore layout")

    # Create test layout file
    test_layout = {
        "project_name": "nixos",
        "created": "2025-10-20T10:30:00",
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
                        "marks": ["project:nixos"],
                        "cmdline": None,
                        "cwd": None,
                    }
                ]
            }
        ]
    }

    with tempfile.NamedTemporaryFile(mode='w', suffix='.json', delete=False) as f:
        temp_file = Path(f.name)
        f.write(json.dumps(test_layout, indent=2))

    # Load layout
    layout = await load_project_layout(temp_file)

    print(f"✓ Loaded layout: {layout.project_name}")
    print(f"  Workspaces: {len(layout.workspaces)}")
    print(f"  Windows: {layout.window_count}")

    temp_file.unlink()


async def main():
    """Run all tests."""
    await test_capture_and_save()
    await test_load_and_restore()

    print("\n✓ All tests passed")


if __name__ == "__main__":
    asyncio.run(main())
```

---

## Next Steps

1. **Add data models** to `models.py`
2. **Create `layout.py`** with capture/restore functions
3. **Update `ipc_server.py`** with new handlers
4. **Create CLI scripts** for save/restore/list
5. **Test with real daemon** and i3 windows
6. **Add to NixOS configuration** to install CLI commands
7. **Document in quickstart guide**

---

**Last Updated**: 2025-10-20
