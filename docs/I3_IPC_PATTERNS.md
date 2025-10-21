# i3 IPC Integration Patterns

This guide provides patterns and best practices for integrating with i3 window manager's IPC (Inter-Process Communication) API, as established by the i3-project management system.

## Core Principle

**i3's IPC API is the authoritative source of truth for all window management state.**

Custom state tracking (daemons, databases, configuration files) MUST be validated against i3 IPC data. When discrepancies occur, i3 IPC data is always correct.

## i3 IPC Message Types

### Query Messages (GET_*)

These messages query i3's current state:

| Message Type | Purpose | Returns |
|--------------|---------|---------|
| `GET_WORKSPACES` | Query all workspaces | Workspace list with names, visible status, output assignments |
| `GET_OUTPUTS` | Query monitor/output configuration | Output list with names, active status, dimensions, assigned workspaces |
| `GET_TREE` | Query window tree structure | Complete window hierarchy with containers, marks, focus |
| `GET_MARKS` | Query all window marks | List of all marks in current session |
| `GET_BAR_CONFIG` | Query bar configuration | Bar configuration details |
| `GET_VERSION` | Query i3 version | i3 version information |
| `GET_BINDING_MODES` | Query binding modes | List of all binding modes |
| `GET_CONFIG` | Query current config | Raw i3 configuration |

### Command Messages

| Message Type | Purpose | Example |
|--------------|---------|---------|
| `COMMAND` | Execute i3 commands | `mark project:nixos`, `workspace 1`, `move container to workspace 2` |
| `SUBSCRIBE` | Subscribe to events | Subscribe to `window`, `workspace`, `output`, `binding` events |

## Connection Patterns

### Basic Async Connection

```python
import i3ipc.aio

async def query_workspaces():
    """Query i3 workspaces (recommended pattern)."""
    async with i3ipc.aio.Connection() as i3:
        workspaces = await i3.get_workspaces()
        return workspaces
```

**Why async context manager?**
- Automatically connects to i3 IPC socket
- Ensures connection is closed after use
- Handles connection errors gracefully

### Persistent Connection (For Event Listeners)

```python
import i3ipc.aio
import asyncio

class I3EventListener:
    """Long-running i3 event listener."""

    def __init__(self):
        self.i3 = None

    async def connect(self):
        """Connect to i3 IPC socket."""
        self.i3 = await i3ipc.aio.Connection().connect()

    async def subscribe_to_events(self):
        """Subscribe to i3 events."""
        # Window events
        self.i3.on(i3ipc.Event.WINDOW, self.handle_window_event)

        # Workspace events
        self.i3.on(i3ipc.Event.WORKSPACE, self.handle_workspace_event)

        # Output events (monitor connect/disconnect)
        self.i3.on(i3ipc.Event.OUTPUT, self.handle_output_event)

        # Tick events (custom events via i3-msg -t subscribe)
        self.i3.on(i3ipc.Event.TICK, self.handle_tick_event)

    async def handle_window_event(self, i3, event):
        """Handle window events."""
        print(f"Window {event.change}: {event.container.window_class}")

    async def handle_workspace_event(self, i3, event):
        """Handle workspace events."""
        print(f"Workspace {event.change}: {event.current.name}")

    async def handle_output_event(self, i3, event):
        """Handle output/monitor events."""
        print(f"Output {event.change}")

    async def handle_tick_event(self, i3, event):
        """Handle custom tick events."""
        print(f"Tick: {event.payload}")

    async def run(self):
        """Run event loop."""
        await self.i3.main()

# Usage
listener = I3EventListener()
await listener.connect()
await listener.subscribe_to_events()
await listener.run()
```

## State Query Patterns

### Workspace State

```python
async def get_workspace_assignments():
    """Get current workspace-to-output assignments."""
    async with i3ipc.aio.Connection() as i3:
        workspaces = await i3.get_workspaces()

        assignments = {}
        for ws in workspaces:
            assignments[ws.num] = {
                "name": ws.name,
                "output": ws.output,
                "visible": ws.visible,
                "focused": ws.focused,
                "urgent": ws.urgent
            }

        return assignments

# Example output:
# {
#     1: {"name": "1", "output": "HDMI-1", "visible": True, "focused": True, "urgent": False},
#     2: {"name": "2", "output": "HDMI-1", "visible": False, "focused": False, "urgent": False},
#     3: {"name": "3", "output": "DP-1", "visible": True, "focused": False, "urgent": False}
# }
```

### Output/Monitor State

```python
async def get_monitor_configuration():
    """Get current monitor/output configuration."""
    async with i3ipc.aio.Connection() as i3:
        outputs = await i3.get_outputs()

        monitors = []
        for output in outputs:
            if not output.active:
                continue  # Skip inactive outputs

            monitors.append({
                "name": output.name,
                "active": output.active,
                "primary": output.primary,
                "current_workspace": output.current_workspace,
                "rect": {
                    "x": output.rect.x,
                    "y": output.rect.y,
                    "width": output.rect.width,
                    "height": output.rect.height
                }
            })

        return monitors
```

### Window Tree Traversal

```python
async def find_windows_with_mark(mark: str):
    """Find all windows with specific mark."""
    async with i3ipc.aio.Connection() as i3:
        tree = await i3.get_tree()

        windows = []
        def traverse(node):
            # Check if this is a window container
            if node.window:
                if mark in (node.marks or []):
                    windows.append({
                        "id": node.window,
                        "class": node.window_class,
                        "title": node.name,
                        "workspace": node.workspace().num,
                        "marks": node.marks,
                        "floating": node.floating == "user_on"
                    })

            # Traverse children
            for child in node.nodes:
                traverse(child)

            # Traverse floating nodes
            for child in node.floating_nodes:
                traverse(child)

        traverse(tree)
        return windows
```

### Get All Window Marks

```python
async def get_all_marks():
    """Get all window marks in current session."""
    async with i3ipc.aio.Connection() as i3:
        marks = await i3.get_marks()
        return marks

# Returns: ["project:nixos", "project:stacks", "visible", "_NET_WM_STATE_HIDDEN"]
```

## Command Execution Patterns

### Mark Windows

```python
async def mark_window(window_id: int, mark: str):
    """Mark a window with a specific mark."""
    async with i3ipc.aio.Connection() as i3:
        # Build command: [con_id=<id>] mark project:nixos
        command = f'[con_id="{window_id}"] mark "{mark}"'
        result = await i3.command(command)

        # Check if command succeeded
        if result[0].success:
            return True
        else:
            raise RuntimeError(f"Failed to mark window: {result[0].error}")
```

### Unmark Windows

```python
async def unmark_window(window_id: int, mark: str):
    """Remove mark from window."""
    async with i3ipc.aio.Connection() as i3:
        command = f'[con_id="{window_id}"] unmark "{mark}"'
        result = await i3.command(command)
        return result[0].success
```

### Move Windows

```python
async def move_window_to_workspace(window_id: int, workspace_num: int):
    """Move window to specific workspace."""
    async with i3ipc.aio.Connection() as i3:
        command = f'[con_id="{window_id}"] move container to workspace number {workspace_num}'
        result = await i3.command(command)
        return result[0].success
```

### Show/Hide Windows with Marks

```python
async def show_windows_with_mark(mark: str):
    """Show (unmark as hidden) all windows with specific mark."""
    async with i3ipc.aio.Connection() as i3:
        # Remove the hidden mark from all windows with project mark
        command = f'[con_mark="{mark}"] unmark "_NET_WM_STATE_HIDDEN"'
        await i3.command(command)

async def hide_windows_with_mark(mark: str):
    """Hide (mark as hidden) all windows with specific mark."""
    async with i3ipc.aio.Connection() as i3:
        # Add the hidden mark to all windows with project mark
        command = f'[con_mark="{mark}"] mark "_NET_WM_STATE_HIDDEN"'
        await i3.command(command)
```

## Event-Driven Architecture

### Window Event Types

```python
from i3ipc import Event

# Window event types (event.change values)
WINDOW_NEW = "new"          # New window created
WINDOW_CLOSE = "close"      # Window closed
WINDOW_FOCUS = "focus"      # Window focused
WINDOW_TITLE = "title"      # Window title changed
WINDOW_FULLSCREEN = "fullscreen_mode"  # Fullscreen toggled
WINDOW_MOVE = "move"        # Window moved
WINDOW_FLOATING = "floating"  # Floating state changed
WINDOW_URGENT = "urgent"    # Urgent flag changed
WINDOW_MARK = "mark"        # Mark added/removed

async def handle_window_event(i3, event):
    """Handle all window event types."""
    window_id = event.container.id
    window_class = event.container.window_class

    if event.change == "new":
        # New window created - mark it if needed
        await mark_window_for_project(window_id, window_class)

    elif event.change == "close":
        # Window closed - clean up tracking
        remove_from_tracking(window_id)

    elif event.change == "focus":
        # Window focused - update active state
        update_focus_state(window_id)

    elif event.change == "mark":
        # Mark changed - validate state
        validate_window_marks(window_id)
```

### Workspace Event Types

```python
# Workspace event types (event.change values)
WORKSPACE_FOCUS = "focus"   # Workspace focused
WORKSPACE_INIT = "init"     # Workspace created
WORKSPACE_EMPTY = "empty"   # Workspace became empty
WORKSPACE_URGENT = "urgent" # Workspace urgent flag changed
WORKSPACE_RENAME = "rename" # Workspace renamed
WORKSPACE_MOVE = "move"     # Workspace moved to different output

async def handle_workspace_event(i3, event):
    """Handle workspace events."""
    if event.change == "focus":
        ws_num = event.current.num
        ws_name = event.current.name
        output = event.current.output
        print(f"Switched to workspace {ws_num} ({ws_name}) on {output}")

    elif event.change == "move":
        # Workspace moved to different monitor
        ws_num = event.current.num
        new_output = event.current.output
        print(f"Workspace {ws_num} moved to {new_output}")
```

### Output Event Types

```python
# Output event types (event.change values)
OUTPUT_UNSPECIFIED = "unspecified"  # Output changed (connect/disconnect/resolution)

async def handle_output_event(i3, event):
    """Handle monitor connect/disconnect events."""
    # Query new output configuration
    outputs = await i3.get_outputs()
    active_outputs = [o for o in outputs if o.active]

    print(f"Output change detected: {len(active_outputs)} active monitors")

    # Update workspace assignments based on new configuration
    await reassign_workspaces(active_outputs)
```

### Tick Events (Custom Events)

```python
# Tick events are custom events triggered by i3-msg
# Usage: i3-msg -t command tick <payload>

async def send_tick_event(payload: str):
    """Send custom tick event to i3."""
    async with i3ipc.aio.Connection() as i3:
        await i3.command(f'exec i3-msg -t command tick "{payload}"')

async def handle_tick_event(i3, event):
    """Handle custom tick events."""
    payload = event.payload

    # Parse payload (can be JSON string)
    try:
        import json
        data = json.loads(payload)

        if data.get("type") == "project_switch":
            # Handle project switch
            project_name = data.get("project")
            await switch_project(project_name)

    except json.JSONDecodeError:
        # Plain text payload
        print(f"Tick: {payload}")
```

## State Validation Patterns

### Validate Workspace Assignments

```python
async def validate_workspace_assignments(expected: Dict[int, str]):
    """Validate workspace-to-output assignments against expected."""
    async with i3ipc.aio.Connection() as i3:
        workspaces = await i3.get_workspaces()

        discrepancies = []
        for ws in workspaces:
            expected_output = expected.get(ws.num)
            if expected_output and ws.output != expected_output:
                discrepancies.append({
                    "workspace": ws.num,
                    "expected_output": expected_output,
                    "actual_output": ws.output
                })

        return discrepancies

# Usage
expected = {1: "HDMI-1", 2: "HDMI-1", 3: "DP-1"}
issues = await validate_workspace_assignments(expected)
if issues:
    print(f"Found {len(issues)} workspace assignment discrepancies")
    # i3 state is authoritative - update expectations
```

### Validate Window Marks

```python
async def validate_window_marks(daemon_windows: List[Dict]):
    """Validate daemon's window tracking against i3's actual marks."""
    async with i3ipc.aio.Connection() as i3:
        tree = await i3.get_tree()

        # Build map of window_id -> actual marks from i3
        actual_marks = {}
        def traverse(node):
            if node.window:
                actual_marks[node.window] = set(node.marks or [])
            for child in node.nodes + node.floating_nodes:
                traverse(child)
        traverse(tree)

        # Compare daemon state to i3 state
        discrepancies = []
        for daemon_window in daemon_windows:
            window_id = daemon_window["window_id"]
            expected_marks = set(daemon_window.get("marks", []))
            actual = actual_marks.get(window_id, set())

            if expected_marks != actual:
                discrepancies.append({
                    "window_id": window_id,
                    "expected_marks": expected_marks,
                    "actual_marks": actual,
                    "missing_marks": expected_marks - actual,
                    "extra_marks": actual - expected_marks
                })

        return discrepancies
```

## Performance Patterns

### Batch Commands

```python
async def batch_mark_windows(window_marks: List[tuple[int, str]]):
    """Mark multiple windows in single connection."""
    async with i3ipc.aio.Connection() as i3:
        # Build combined command
        commands = [f'[con_id="{wid}"] mark "{mark}"'
                    for wid, mark in window_marks]

        # Execute as single command (separated by semicolons)
        combined = "; ".join(commands)
        results = await i3.command(combined)

        # Check results
        for i, result in enumerate(results):
            if not result.success:
                print(f"Command {i} failed: {result.error}")
```

### Cache i3 State Queries

```python
import asyncio
from datetime import datetime, timedelta

class I3StateCache:
    """Cache i3 state queries to reduce IPC calls."""

    def __init__(self, ttl_seconds: int = 1):
        self.ttl = timedelta(seconds=ttl_seconds)
        self.cache = {}

    async def get_workspaces(self):
        """Get workspaces with caching."""
        cache_key = "workspaces"

        if cache_key in self.cache:
            cached_time, cached_data = self.cache[cache_key]
            if datetime.now() - cached_time < self.ttl:
                return cached_data

        # Cache miss or expired - query i3
        async with i3ipc.aio.Connection() as i3:
            workspaces = await i3.get_workspaces()

        self.cache[cache_key] = (datetime.now(), workspaces)
        return workspaces

# Usage (for high-frequency queries)
cache = I3StateCache(ttl_seconds=0.5)
workspaces = await cache.get_workspaces()  # May use cached data
```

## Error Handling Patterns

### Handle Connection Failures

```python
import logging

logger = logging.getLogger(__name__)

async def safe_i3_query():
    """Query i3 with error handling."""
    try:
        async with i3ipc.aio.Connection() as i3:
            return await i3.get_workspaces()

    except FileNotFoundError:
        logger.error("i3 IPC socket not found - is i3 running?")
        return None

    except PermissionError:
        logger.error("Permission denied accessing i3 IPC socket")
        return None

    except Exception as e:
        logger.error(f"Unexpected error querying i3: {e}", exc_info=True)
        return None
```

### Validate Command Results

```python
async def safe_mark_window(window_id: int, mark: str):
    """Mark window with validation."""
    async with i3ipc.aio.Connection() as i3:
        command = f'[con_id="{window_id}"] mark "{mark}"'
        results = await i3.command(command)

        if not results:
            raise RuntimeError("No result from i3 command")

        result = results[0]
        if not result.success:
            # Parse error message
            error_msg = result.error or "Unknown error"

            if "not found" in error_msg.lower():
                raise ValueError(f"Window {window_id} not found")
            else:
                raise RuntimeError(f"Failed to mark window: {error_msg}")

        return True
```

## Testing Patterns

### Mock i3 Connection

```python
# tests/fixtures/mock_i3.py
class MockI3Connection:
    """Mock i3 IPC connection for testing."""

    def __init__(self):
        self.workspaces = []
        self.outputs = []
        self.tree = None
        self.commands_executed = []

    async def get_workspaces(self):
        return self.workspaces

    async def get_outputs(self):
        return self.outputs

    async def get_tree(self):
        return self.tree

    async def command(self, cmd: str):
        self.commands_executed.append(cmd)
        # Return mock success result
        return [type('Result', (), {'success': True, 'error': None})]

# Usage in tests
@pytest.fixture
def mock_i3():
    connection = MockI3Connection()
    # Set up mock data
    connection.workspaces = [
        type('Workspace', (), {
            'num': 1,
            'name': '1',
            'output': 'HDMI-1',
            'visible': True,
            'focused': True
        })
    ]
    return connection
```

## Best Practices Summary

1. **Always use i3 IPC as source of truth**: Query i3 to validate custom state, not vice versa
2. **Use async/await for all IPC calls**: Prevents blocking and improves performance
3. **Use context managers for connections**: Ensures proper cleanup
4. **Subscribe to events instead of polling**: More efficient and lower latency
5. **Validate command results**: Check `result.success` and handle errors
6. **Handle connection failures gracefully**: i3 socket may not be available
7. **Batch commands when possible**: Reduces IPC round-trips
8. **Cache infrequent queries**: Reduces IPC overhead for rarely-changing data
9. **Use window IDs, not titles/classes for targeting**: IDs are unique and stable
10. **Test with mock i3 connection**: Enables testing without running i3

## Common Patterns Reference

### Window Management
- Find windows: `GET_TREE` + traverse
- Mark window: `COMMAND` with `[con_id="<id>"] mark "<mark>"`
- Show/hide windows: `COMMAND` with mark manipulation
- Move window: `COMMAND` with `move container to workspace`

### Workspace Management
- Get assignments: `GET_WORKSPACES` + check `output` field
- Switch workspace: `COMMAND` with `workspace <num>`
- Move workspace: `COMMAND` with `move workspace to output`

### Monitor Management
- Get configuration: `GET_OUTPUTS`
- Detect changes: Subscribe to `output` events
- Validate assignments: Compare `GET_WORKSPACES` output to expected

### Event Handling
- Window events: Subscribe to `window` events, handle `new`/`close`/`mark`
- Workspace events: Subscribe to `workspace` events, handle `focus`/`move`
- Output events: Subscribe to `output` events, handle monitor changes
- Custom events: Use `tick` events with JSON payloads

## See Also

- [Python Development Standards](./PYTHON_DEVELOPMENT.md) - Async patterns and testing
- [Constitution](../.specify/memory/constitution.md) - i3 IPC Alignment (Principle XI)
- [Feature 015 Quickstart](../specs/015-create-a-new/quickstart.md) - Event-driven daemon examples
- [i3 IPC Documentation](https://i3wm.org/docs/ipc.html) - Official i3 IPC spec
