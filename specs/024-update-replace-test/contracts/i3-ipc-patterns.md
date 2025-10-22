# i3 IPC Message Patterns for Dynamic Window Rules Engine

**Feature**: 024-update-replace-test
**Created**: 2025-10-22
**Version**: 1.0
**Constitution Principle**: XI (i3 IPC Alignment)

---

## Overview

This document defines all i3 IPC message types used by the dynamic window rules engine. Each message type includes its purpose, request/response format, Python implementation patterns, and performance expectations. All patterns follow Constitution Principle XI: **i3 IPC is the authoritative source of truth for all window and workspace state**.

**Key Design Principles**:
1. Query i3 IPC for authoritative state (never cache)
2. Use event subscriptions for real-time updates (not polling)
3. Validate all state changes with GET_TREE queries
4. Handle i3 IPC failures gracefully with retries

**Reference Documentation**: `/etc/nixos/docs/i3-ipc.txt` (official i3 IPC specification)

---

## Message Types

### 1. GET_TREE (Type: 4)

**Purpose**: Retrieve complete window tree hierarchy for window property extraction and state validation.

**Use Cases in Window Rules Engine**:
- Extract window properties (class, title, instance, role, type) on `window::new` events
- Bulk window extraction on daemon startup for state restoration
- Validate window workspace assignment after rule application
- Traverse tree to find parent workspace for new windows

**Request Format**:
```json
{
  "type": 4,
  "payload": ""
}
```

**Response Structure** (relevant fields only):
```json
{
  "id": 94281592451312,
  "type": "con|workspace|output|root",
  "name": "Window title or workspace name",
  "window": 2097153,
  "window_class": "Code",
  "window_instance": "code",
  "window_role": "browser-window",
  "window_type": "normal",
  "marks": ["project:nixos", "visible"],
  "nodes": [],
  "floating_nodes": []
}
```

**Key Response Fields**:

| Field | Type | Description | Fallback |
|-------|------|-------------|----------|
| `id` | int | Container ID (unique, persistent) | N/A (always present) |
| `window` | int/null | X11 window ID (null for containers without windows) | `None` |
| `window_class` | str/null | Window class (WM_CLASS) | `"unknown"` |
| `window_instance` | str/null | Window instance (WM_CLASS instance) | `""` |
| `name` | str | Window title (_NET_WM_NAME) or workspace name | `""` |
| `window_role` | str/null | Window role (WM_WINDOW_ROLE) | `""` |
| `window_type` | str/null | Window type (_NET_WM_WINDOW_TYPE) | `"normal"` |
| `marks` | list[str] | i3 marks applied to this window | `[]` |
| `type` | str | Node type: "con", "workspace", "output", "root" | N/A (always present) |
| `nodes` | list | Child containers | `[]` |
| `floating_nodes` | list | Floating child containers | `[]` |

**Python Implementation** (using i3ipc.aio):

```python
import i3ipc.aio as i3ipc
from typing import Optional, List
from dataclasses import dataclass

@dataclass(frozen=True)
class WindowProperties:
    """Immutable snapshot of window properties extracted from i3 tree."""
    con_id: int
    window_id: Optional[int]
    window_class: str  # "unknown" if null
    window_instance: str  # "" if null
    window_title: str  # "" if null
    window_role: str  # "" if null
    window_type: str  # "normal" default
    workspace: int
    marks: List[str]
    transient_for: Optional[int]

async def extract_window_properties(
    container: i3ipc.Con
) -> WindowProperties:
    """Extract properties from i3 container object.

    Args:
        container: i3ipc.aio.Con object from window::new event or GET_TREE

    Returns:
        WindowProperties with all fields populated (null-safe)
    """
    # Find parent workspace by traversing up tree
    workspace_node = container.workspace()
    workspace_num = int(workspace_node.name) if workspace_node else 0

    return WindowProperties(
        con_id=container.id,
        window_id=container.window,
        window_class=container.window_class or "unknown",
        window_instance=container.window_instance or "",
        window_title=container.name or "",
        window_role=getattr(container, "window_role", ""),
        window_type=getattr(container, "window_type", "normal"),
        workspace=workspace_num,
        marks=list(container.marks) if container.marks else [],
        transient_for=getattr(container, "transient_for", None),
    )

async def extract_all_windows(
    conn: i3ipc.Connection
) -> List[WindowProperties]:
    """Bulk extract all windows from GET_TREE (daemon startup).

    Args:
        conn: i3 async connection

    Returns:
        List of WindowProperties for all windows in tree
    """
    tree = await conn.get_tree()
    windows = []

    def traverse(node, workspace_name=None):
        # Track workspace as we descend
        if node.type == "workspace":
            workspace_name = node.name

        # Extract window if this is a window container
        if node.window:
            # Create mock container with workspace reference
            node._workspace_name = workspace_name
            props = extract_window_properties_sync(node, workspace_name)
            windows.append(props)

        # Recurse into children
        for child in node.nodes + node.floating_nodes:
            traverse(child, workspace_name)

    traverse(tree)
    return windows
```

**Performance Expectations**:
- Single GET_TREE query: 5-30ms (depends on window count)
- 50 windows: ~10-15ms
- 200 windows: ~30-50ms
- Scales linearly with window count
- Tree traversal overhead: ~0.5ms per window (in-memory Python objects)

**Error Handling**:
```python
async def safe_get_tree(conn: i3ipc.Connection) -> Optional[i3ipc.Con]:
    """Query GET_TREE with timeout and error handling."""
    try:
        tree = await asyncio.wait_for(conn.get_tree(), timeout=2.0)
        return tree
    except asyncio.TimeoutError:
        logger.error("GET_TREE query timed out after 2s")
        return None
    except Exception as e:
        logger.error(f"GET_TREE query failed: {e}")
        return None
```

---

### 2. GET_WORKSPACES (Type: 1)

**Purpose**: Query current workspace list and their assignments to outputs (monitors).

**Use Cases in Window Rules Engine**:
- Validate target workspace exists before moving window
- Check if workspace is on active output (multi-monitor support)
- Determine current focused workspace before rule application
- Workspace-to-output mapping for monitor distribution

**Request Format**:
```json
{
  "type": 1,
  "payload": ""
}
```

**Response Structure** (array of workspace objects):
```json
[
  {
    "num": 1,
    "name": "1",
    "visible": true,
    "focused": true,
    "rect": {"x": 0, "y": 0, "width": 1920, "height": 1080},
    "output": "DP-1",
    "urgent": false
  },
  {
    "num": 2,
    "name": "2",
    "visible": false,
    "focused": false,
    "rect": {"x": 0, "y": 0, "width": 1920, "height": 1080},
    "output": "DP-1",
    "urgent": false
  }
]
```

**Key Response Fields**:

| Field | Type | Description |
|-------|------|-------------|
| `num` | int | Workspace number (1-9) |
| `name` | str | Workspace name (usually same as num) |
| `visible` | bool | Whether workspace is currently visible on any output |
| `focused` | bool | Whether workspace is currently focused |
| `output` | str | Output name (monitor) this workspace is assigned to |
| `urgent` | bool | Whether any window on workspace has urgent flag |

**Python Implementation**:

```python
async def validate_target_workspace(
    conn: i3ipc.Connection,
    workspace: int
) -> tuple[bool, Optional[str]]:
    """Validate workspace exists and is on active output.

    Args:
        conn: i3 async connection
        workspace: Target workspace number (1-9)

    Returns:
        (is_valid, output_name) tuple
        - is_valid: True if workspace on active output
        - output_name: Name of assigned output or None
    """
    # Query i3 for current state (Constitution Principle XI)
    workspaces = await conn.get_workspaces()
    outputs = await conn.get_outputs()

    active_outputs = {o.name for o in outputs if o.active}

    # Find target workspace
    target_ws = next((ws for ws in workspaces if ws.num == workspace), None)

    if not target_ws:
        # Workspace doesn't exist yet, will be created by i3
        # Check workspace distribution rules based on monitor count
        return True, _get_default_output_for_workspace(workspace, outputs)

    # Workspace exists, check if on active output
    if target_ws.output in active_outputs:
        return True, target_ws.output
    else:
        logger.warning(
            f"Workspace {workspace} assigned to inactive output {target_ws.output}"
        )
        return False, None

async def get_focused_workspace(conn: i3ipc.Connection) -> Optional[int]:
    """Get currently focused workspace number."""
    workspaces = await conn.get_workspaces()
    focused = next((ws for ws in workspaces if ws.focused), None)
    return focused.num if focused else None
```

**Performance Expectations**:
- GET_WORKSPACES query: 2-3ms
- Response size: ~200 bytes per workspace (typically 1-9 workspaces = ~2 KB)
- Negligible overhead for window rule validation

---

### 3. GET_OUTPUTS (Type: 3)

**Purpose**: Query monitor/output configuration for multi-monitor workspace distribution.

**Use Cases in Window Rules Engine**:
- Detect monitor connect/disconnect events
- Validate workspace is on active output before window assignment
- Count active monitors for workspace distribution rules
- Identify primary monitor for fallback workspace assignment

**Request Format**:
```json
{
  "type": 3,
  "payload": ""
}
```

**Response Structure** (array of output objects):
```json
[
  {
    "name": "DP-1",
    "active": true,
    "primary": true,
    "current_workspace": "1",
    "rect": {"x": 0, "y": 0, "width": 1920, "height": 1080}
  },
  {
    "name": "HDMI-1",
    "active": true,
    "primary": false,
    "current_workspace": "3",
    "rect": {"x": 1920, "y": 0, "width": 1920, "height": 1080}
  }
]
```

**Key Response Fields**:

| Field | Type | Description |
|-------|------|-------------|
| `name` | str | Output identifier (e.g., "DP-1", "HDMI-1", "eDP-1") |
| `active` | bool | Whether output is currently connected and active |
| `primary` | bool | Whether this is the primary output |
| `current_workspace` | str | Name of workspace currently shown on this output |
| `rect` | dict | Output dimensions and position |

**Python Implementation**:

```python
from dataclasses import dataclass
from typing import List

@dataclass
class MonitorConfig:
    """Monitor configuration from GET_OUTPUTS."""
    name: str
    active: bool
    primary: bool
    current_workspace: str
    width: int
    height: int
    x: int
    y: int

async def get_monitor_configs(
    conn: i3ipc.Connection
) -> List[MonitorConfig]:
    """Query active monitor configuration.

    Returns:
        List of MonitorConfig for active outputs only
    """
    outputs = await conn.get_outputs()

    monitors = []
    for output in outputs:
        if output.active:
            monitors.append(MonitorConfig(
                name=output.name,
                active=output.active,
                primary=output.primary,
                current_workspace=output.current_workspace,
                width=output.rect.width,
                height=output.rect.height,
                x=output.rect.x,
                y=output.rect.y,
            ))

    return monitors

async def get_workspace_distribution_rule(
    conn: i3ipc.Connection
) -> dict[int, str]:
    """Get workspace-to-output mapping based on monitor count.

    Distribution rules:
    - 1 monitor: WS 1-9 on primary
    - 2 monitors: WS 1-2 on primary, WS 3-9 on secondary
    - 3+ monitors: WS 1-2 on primary, WS 3-5 on secondary, WS 6-9 on tertiary

    Returns:
        Dict mapping workspace number to output name
    """
    monitors = await get_monitor_configs(conn)
    monitor_count = len(monitors)

    # Sort: primary first, then by x position
    monitors.sort(key=lambda m: (not m.primary, m.x))

    workspace_map = {}

    if monitor_count == 1:
        # All workspaces on primary
        for ws in range(1, 10):
            workspace_map[ws] = monitors[0].name
    elif monitor_count == 2:
        # WS 1-2 on primary, WS 3-9 on secondary
        for ws in range(1, 3):
            workspace_map[ws] = monitors[0].name
        for ws in range(3, 10):
            workspace_map[ws] = monitors[1].name
    else:
        # WS 1-2 on primary, WS 3-5 on secondary, WS 6-9 on tertiary
        for ws in range(1, 3):
            workspace_map[ws] = monitors[0].name
        for ws in range(3, 6):
            workspace_map[ws] = monitors[1].name
        for ws in range(6, 10):
            workspace_map[ws] = monitors[2].name if len(monitors) > 2 else monitors[1].name

    return workspace_map
```

**Performance Expectations**:
- GET_OUTPUTS query: 2-3ms
- Response size: ~300 bytes per output (typically 1-3 outputs = ~1 KB)
- Negligible overhead

---

### 4. GET_MARKS (Type: 7)

**Purpose**: Retrieve all i3 marks currently applied to windows.

**Use Cases in Window Rules Engine**:
- State restoration: Validate project marks after daemon restart
- Conflict detection: Check if window already has project mark
- Debugging: List all marked windows for diagnostics

**Request Format**:
```json
{
  "type": 7,
  "payload": ""
}
```

**Response Structure** (array of mark strings):
```json
[
  "project:nixos",
  "project:stacks",
  "visible",
  "terminal",
  "pwa-youtube"
]
```

**Python Implementation**:

```python
async def get_project_marks(conn: i3ipc.Connection) -> set[str]:
    """Get all project-related marks from i3.

    Returns:
        Set of project mark strings (e.g., {"project:nixos", "project:stacks"})
    """
    marks = await conn.get_marks()
    project_marks = {mark for mark in marks if mark.startswith("project:")}
    return project_marks

async def validate_active_project_state(
    conn: i3ipc.Connection,
    expected_project: Optional[str]
) -> tuple[bool, Optional[str]]:
    """Validate active project state against i3 marks.

    Args:
        conn: i3 connection
        expected_project: Expected active project from filesystem state

    Returns:
        (is_valid, actual_project) tuple
        - is_valid: True if filesystem matches i3 state
        - actual_project: Actual active project from i3 marks
    """
    project_marks = await get_project_marks(conn)
    project_names = {mark.split(":", 1)[1] for mark in project_marks}

    if len(project_names) > 1:
        # Invalid state: multiple projects active
        logger.error(f"Multiple active projects detected: {project_names}")
        return False, None
    elif len(project_names) == 1:
        actual_project = next(iter(project_names))
        if expected_project and expected_project != actual_project:
            logger.warning(
                f"Active project mismatch: expected={expected_project}, "
                f"actual={actual_project}. Using i3 state (authoritative)."
            )
            return False, actual_project
        return True, actual_project
    else:
        # No project marks
        if expected_project:
            logger.warning(
                f"Filesystem indicates active project '{expected_project}', "
                f"but no project marks found in i3."
            )
            return False, None
        return True, None
```

**Performance Expectations**:
- GET_MARKS query: 2-3ms
- Response size: ~20 bytes per mark (typically 10-50 marks = ~1 KB)
- Very fast, suitable for frequent queries

---

### 5. COMMAND (Type: 0)

**Purpose**: Execute i3 commands to modify window state (move, mark, layout, floating).

**Use Cases in Window Rules Engine**:
- Move window to workspace after rule match
- Apply marks to windows for tracking
- Set window floating state
- Set container layout mode
- Focus workspace after window assignment

**Request Format**:
```json
{
  "type": 0,
  "payload": "[con_id=\"12345\"] move container to workspace number 2"
}
```

**Response Structure** (array of command results):
```json
[
  {
    "success": true,
    "error": null
  }
]
```

**Common Commands**:

| Command | Purpose | Example |
|---------|---------|---------|
| Move to workspace | Assign window to workspace | `[con_id="12345"] move container to workspace number 2` |
| Mark window | Add mark for tracking | `[id=67890] mark --add "project:nixos"` |
| Float window | Set floating state | `[con_id="12345"] floating enable` |
| Tile window | Disable floating | `[con_id="12345"] floating disable` |
| Set layout | Change container layout | `[con_id="12345"] layout tabbed` |
| Focus workspace | Switch workspace view | `workspace number 2` |

**Python Implementation**:

```python
async def move_window_to_workspace(
    conn: i3ipc.Connection,
    container_id: int,
    workspace: int,
    focus: bool = False
) -> bool:
    """Move window to target workspace with optional focus.

    Args:
        conn: i3 async connection
        container_id: Container ID from i3 tree
        workspace: Target workspace number (1-9)
        focus: If True, switch focus to workspace after move

    Returns:
        True if successful, False on error
    """
    # Move window to workspace (no focus change)
    result = await conn.command(
        f'[con_id="{container_id}"] move container to workspace number {workspace}'
    )

    if not result or not result[0].success:
        logger.error(
            f"Failed to move window {container_id} to workspace {workspace}: "
            f"{result[0].error if result else 'no response'}"
        )
        return False

    logger.info(f"Moved window {container_id} to workspace {workspace}")

    # Optional: Focus workspace if requested
    if focus:
        focus_result = await conn.command(f'workspace number {workspace}')
        if focus_result and focus_result[0].success:
            logger.info(f"Focused workspace {workspace}")
        else:
            logger.warning(f"Failed to focus workspace {workspace}")

    return True

async def mark_window(
    conn: i3ipc.Connection,
    window_id: int,
    mark: str
) -> bool:
    """Add mark to window.

    Args:
        conn: i3 connection
        window_id: X11 window ID
        mark: Mark string (alphanumeric, underscore, hyphen only)

    Returns:
        True if successful
    """
    result = await conn.command(f'[id={window_id}] mark --add "{mark}"')

    if result and result[0].success:
        logger.info(f"Marked window {window_id} with '{mark}'")
        return True
    else:
        logger.error(f"Failed to mark window {window_id}: {result[0].error if result else 'no response'}")
        return False

async def set_window_floating(
    conn: i3ipc.Connection,
    container_id: int,
    enable: bool
) -> bool:
    """Set window floating state."""
    state = "enable" if enable else "disable"
    result = await conn.command(f'[con_id="{container_id}"] floating {state}')
    return result and result[0].success

async def set_container_layout(
    conn: i3ipc.Connection,
    container_id: int,
    mode: str
) -> bool:
    """Set container layout mode.

    Args:
        mode: "tabbed", "stacked", "splitv", "splith"
    """
    result = await conn.command(f'[con_id="{container_id}"] layout {mode}')
    return result and result[0].success
```

**Performance Expectations**:
- Single COMMAND execution: 5-10ms
- Batch commands (multiple in one call): 10-20ms
- Focus command (workspace switch): 10-15ms
- Critical: Commands execute sequentially (i3 processes one at a time)

**Error Handling**:
```python
async def safe_command(
    conn: i3ipc.Connection,
    command: str,
    timeout: float = 2.0
) -> Optional[bool]:
    """Execute i3 command with timeout and error handling."""
    try:
        result = await asyncio.wait_for(conn.command(command), timeout=timeout)
        if result and result[0].success:
            return True
        else:
            logger.error(f"Command failed: {command} -> {result[0].error if result else 'no response'}")
            return False
    except asyncio.TimeoutError:
        logger.error(f"Command timed out after {timeout}s: {command}")
        return None
    except Exception as e:
        logger.error(f"Command exception: {command} -> {e}")
        return None
```

---

### 6. SUBSCRIBE (Type: 2)

**Purpose**: Subscribe to i3 events for real-time window and workspace state updates.

**Use Cases in Window Rules Engine**:
- `window::new`: Detect new windows for rule application
- `window::title`: Re-evaluate rules when window title changes
- `window::close`: Clean up window tracking on window close
- `output`: Detect monitor connect/disconnect for workspace redistribution
- `workspace::focus`: Track current workspace for focus control

**Request Format**:
```json
{
  "type": 2,
  "payload": "[\"window\", \"output\", \"workspace\"]"
}
```

**Event Payloads**:

#### window::new Event
```json
{
  "change": "new",
  "container": {
    "id": 12345,
    "window": 67890,
    "window_class": "Code",
    "name": "main.py - VS Code",
    "type": "con",
    "marks": []
  }
}
```

#### window::title Event
```json
{
  "change": "title",
  "container": {
    "id": 12345,
    "window": 67890,
    "window_class": "Code",
    "name": "file.py - VS Code",
    "type": "con"
  }
}
```

#### output Event
```json
{
  "change": "unspecified"
}
```

#### workspace::focus Event
```json
{
  "change": "focus",
  "current": {
    "num": 2,
    "name": "2",
    "visible": true,
    "focused": true,
    "output": "DP-1"
  },
  "old": {
    "num": 1,
    "name": "1",
    "visible": false,
    "focused": false,
    "output": "DP-1"
  }
}
```

**Python Implementation**:

```python
async def subscribe_to_events(
    conn: i3ipc.Connection,
    state_manager,
    app_classification,
    window_rules
):
    """Subscribe to i3 events and register handlers.

    Args:
        conn: i3 async connection
        state_manager: StateManager instance
        app_classification: AppClassification instance
        window_rules: List of WindowRule objects
    """
    # Register event handlers
    conn.on("window::new", lambda conn, event: on_window_new(
        conn, event, state_manager, app_classification, window_rules
    ))

    conn.on("window::title", lambda conn, event: on_window_title(
        conn, event, state_manager, window_rules
    ))

    conn.on("window::close", lambda conn, event: on_window_close(
        conn, event, state_manager
    ))

    conn.on("output", lambda conn, event: on_output(
        conn, event, state_manager
    ))

    conn.on("workspace::focus", lambda conn, event: on_workspace_focus(
        conn, event, state_manager
    ))

    # Start event loop
    await conn.main()

async def on_window_new(
    conn: i3ipc.Connection,
    event,
    state_manager,
    app_classification,
    window_rules
):
    """Handle window::new events."""
    container = event.container

    # Extract window properties
    props = await extract_window_properties(container)

    # Classify window using rules
    matched_rule = find_matching_rule(props, window_rules)

    if matched_rule:
        # Apply rule actions
        for action in matched_rule.actions:
            if action.type == "workspace":
                await move_window_to_workspace(
                    conn, props.con_id, action.target, matched_rule.focus
                )
            elif action.type == "mark":
                await mark_window(conn, props.window_id, action.value)
            elif action.type == "float":
                await set_window_floating(conn, props.con_id, action.enable)
            elif action.type == "layout":
                await set_container_layout(conn, props.con_id, action.mode)

    # Track window in state manager
    await state_manager.add_window(props)

async def on_output(
    conn: i3ipc.Connection,
    event,
    state_manager
):
    """Handle output events (monitor connect/disconnect)."""
    logger.info("Output configuration changed, reassigning workspaces")

    # Query new monitor configuration
    monitors = await get_monitor_configs(conn)

    # Redistribute workspaces based on monitor count
    workspace_map = await get_workspace_distribution_rule(conn)

    # Apply workspace-to-output assignments
    for ws_num, output_name in workspace_map.items():
        await conn.command(f'workspace {ws_num} output {output_name}')

    logger.info(f"Reassigned workspaces for {len(monitors)} monitors")
```

**Performance Expectations**:
- Event subscription overhead: < 1ms (one-time setup)
- Event delivery latency: 5-20ms (from i3 to daemon)
- Event processing: 20-100ms (depends on actions)
- Total window::new latency: 25-120ms (SC-001 target: < 500ms)

---

## Event Subscription Patterns

### Pattern 1: Event-Driven Architecture (RECOMMENDED)

**Implementation**: Subscribe to i3 events and react in real-time.

**Benefits**:
- Low latency (< 100ms)
- No polling overhead
- Scales to thousands of windows
- Aligns with Constitution Principle XI

**Example**:
```python
async def main():
    conn = await i3ipc.Connection().connect()

    # Subscribe to events
    conn.on("window::new", handle_window_new)
    conn.on("output", handle_output_change)

    # Start event loop (blocks until connection closes)
    await conn.main()
```

### Pattern 2: Polling (NOT RECOMMENDED)

**Implementation**: Periodically query GET_TREE/GET_WORKSPACES.

**Drawbacks**:
- High latency (polling interval + query time)
- Wasted CPU on unnecessary queries
- Misses rapid state changes
- Violates event-driven design

**When to Use**: Never. Use event subscriptions instead.

---

## Performance Summary

| Message Type | Latency | Use Frequency | Notes |
|--------------|---------|--------------|-------|
| GET_TREE | 5-30ms | Per event + startup | Scales with window count |
| GET_WORKSPACES | 2-3ms | Per rule validation | Very fast |
| GET_OUTPUTS | 2-3ms | Per monitor change | Very fast |
| GET_MARKS | 2-3ms | On daemon restart | Very fast |
| COMMAND | 5-15ms | Per action | Sequential execution |
| SUBSCRIBE | < 1ms | Once on startup | One-time setup |

**Total Window Rule Application Latency**:
- Best case (cached, no validation): 20-50ms
- Average case (with validation): 30-80ms
- Worst case (multiple actions + focus): 50-120ms
- **Target (SC-001)**: < 500ms (80-90% margin)

---

## Error Handling Patterns

### Pattern 1: Retry with Exponential Backoff

```python
async def retry_command(
    conn: i3ipc.Connection,
    command: str,
    max_retries: int = 3
) -> bool:
    """Retry i3 command with exponential backoff."""
    for attempt in range(max_retries):
        result = await safe_command(conn, command)
        if result is True:
            return True

        if result is False:
            # Command failed, retry
            wait_time = 2 ** attempt * 0.1  # 0.1s, 0.2s, 0.4s
            logger.warning(f"Command failed, retrying in {wait_time}s (attempt {attempt+1}/{max_retries})")
            await asyncio.sleep(wait_time)
        else:
            # Timeout or exception, abort
            logger.error(f"Command fatal error, aborting retries")
            return False

    logger.error(f"Command failed after {max_retries} retries")
    return False
```

### Pattern 2: Validate After State Changes

```python
async def move_window_with_validation(
    conn: i3ipc.Connection,
    container_id: int,
    workspace: int
) -> bool:
    """Move window and validate result with GET_TREE query."""
    # Execute move command
    success = await move_window_to_workspace(conn, container_id, workspace, focus=False)
    if not success:
        return False

    # Validate with GET_TREE (Constitution Principle XI: i3 IPC is authoritative)
    await asyncio.sleep(0.05)  # Allow i3 to process command
    tree = await conn.get_tree()
    window_node = find_container_by_id(tree, container_id)

    if window_node:
        actual_ws = window_node.workspace()
        if actual_ws and int(actual_ws.name) == workspace:
            logger.info(f"Window {container_id} successfully moved to workspace {workspace}")
            return True
        else:
            logger.error(
                f"Window {container_id} move validation failed: "
                f"expected WS {workspace}, actual WS {actual_ws.name if actual_ws else 'unknown'}"
            )
            return False
    else:
        logger.error(f"Window {container_id} not found in tree after move")
        return False
```

---

## Integration with Existing Codebase

### Location: `home-modules/desktop/i3-project-event-daemon/`

**Files to Modify**:
- `handlers.py`: Add window rule evaluation in `on_window_new()`
- `daemon.py`: Load window rules on startup
- `state_manager.py`: Track window-to-rule associations

**New Files to Create**:
- `window_rules.py`: Rule loading, matching, and application logic
- `rule_actions.py`: Action execution (workspace, mark, float, layout)
- `tree_traversal.py`: Window property extraction from GET_TREE

**Configuration File**: `~/.config/i3/window-rules.json`

---

## References

- Official i3 IPC specification: `/etc/nixos/docs/i3-ipc.txt`
- i3 IPC integration patterns: `/etc/nixos/docs/I3_IPC_PATTERNS.md`
- Python development standards: `/etc/nixos/docs/PYTHON_DEVELOPMENT.md`
- Feature specification: `/etc/nixos/specs/024-update-replace-test/spec.md`
- Data model: `/etc/nixos/specs/024-update-replace-test/data-model.md`
- Research findings: `/etc/nixos/specs/024-update-replace-test/research.md`

---

**Document Version**: 1.0
**Last Updated**: 2025-10-22
**Author**: Claude Code
