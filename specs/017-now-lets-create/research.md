# Research: i3 Project System Monitor

**Branch**: `017-now-lets-create` | **Date**: 2025-10-20

## Research Summary

This document captures technology decisions, best practices, and implementation patterns for the i3 project system monitor tool. All research questions from the Technical Context have been resolved.

## Technology Decisions

### 1. Terminal UI Framework

**Decision**: Use `rich` Python library (not `textual`)

**Rationale**:
- Rich provides immediate terminal output with tables, live displays, and syntax highlighting
- Lightweight and simple API for non-interactive display modes
- No complex TUI event loop required for monitoring use case
- Excellent performance for streaming event displays
- Well-documented live rendering and table formatting
- Already proven in similar monitoring tools (htop-style displays)

**Alternatives Considered**:
- **textual**: Full TUI framework with widgets - rejected as too complex for simple display-only monitoring
- **blessed**: Lower-level terminal library - rejected due to more manual formatting work
- **curses**: Standard library - rejected due to complexity and poor Rich table formatting

**Implementation Pattern**:
```python
from rich.console import Console
from rich.table import Table
from rich.live import Live
from rich.layout import Layout

# Live updating display
console = Console()
with Live(generate_table(), refresh_per_second=4) as live:
    while True:
        live.update(generate_table())
```

### 2. Daemon Communication

**Decision**: Reuse existing JSON-RPC over Unix socket pattern from i3-project-daemon-status/events

**Rationale**:
- Daemon already implements JSON-RPC server at `$XDG_RUNTIME_DIR/i3-project-daemon/ipc.sock`
- Existing CLI tools (i3-project-daemon-status, i3-project-daemon-events) demonstrate the pattern
- Simple nc-based communication works reliably
- No additional dependencies required for IPC
- Consistent with existing codebase architecture

**Existing Methods Available**:
- `get_status` - returns daemon uptime, connection status, events processed, active project
- `get_events` - returns recent events (currently stub, needs implementation)
- `get_active_project` - returns current active project name
- `get_projects` - returns all projects with window counts
- `get_windows` - returns tracked windows with filter support

**Methods to Add** (Phase 1 Design):
- `list_monitors` - return detected monitors with workspace assignments
- `subscribe_events` - enable event streaming notifications
- Event storage in daemon - add circular buffer for last 500 events

**Connection Pattern**:
```python
import socket
import json

def send_request(method, params=None):
    request = {"jsonrpc": "2.0", "method": method, "id": 1}
    if params:
        request["params"] = params

    sock_path = f"{os.environ['XDG_RUNTIME_DIR']}/i3-project-daemon/ipc.sock"
    sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    sock.connect(sock_path)
    sock.sendall(json.dumps(request).encode() + b'\n')
    response = sock.recv(4096)
    sock.close()
    return json.loads(response)["result"]
```

### 3. Event Streaming Architecture

**Decision**: Use asyncio with JSON-RPC notifications for real-time event streaming

**Rationale**:
- Daemon already uses asyncio for i3 IPC connection
- JSON-RPC 2.0 supports notifications (no id field, no response expected)
- Allows daemon to push events to subscribed clients without polling
- Monitor tool can maintain persistent connection for live updates
- Fits existing daemon architecture with minimal changes

**Implementation Pattern**:
```python
# Daemon side: broadcast notification to subscribed clients
async def broadcast_event(self, event_type, event_data):
    notification = {
        "jsonrpc": "2.0",
        "method": "event",
        "params": {
            "type": event_type,
            "timestamp": datetime.now().isoformat(),
            "data": event_data
        }
    }
    for writer in self.subscribed_clients:
        writer.write(json.dumps(notification).encode() + b'\n')
        await writer.drain()

# Monitor tool side: subscribe and read stream
async def subscribe_events():
    # Send subscribe request
    send_request("subscribe_events")
    # Keep connection open and read notifications
    while True:
        data = await reader.readline()
        notification = json.loads(data.decode())
        if notification.get("method") == "event":
            yield notification["params"]
```

### 4. Reconnection Strategy

**Decision**: Exponential backoff with 5 retry attempts (1s, 2s, 4s, 8s, 16s), then exit

**Rationale**:
- Matches systemd service restart behavior (RestartSec = 5s in daemon)
- Prevents tight reconnection loops that waste resources
- 5 retries gives ~30 seconds total wait time (reasonable for daemon restart)
- Clear exit after max retries prevents indefinite hanging
- User can manually restart monitor after fixing daemon issues

**Implementation Pattern**:
```python
async def connect_with_retry(max_retries=5):
    for attempt in range(max_retries):
        try:
            return await connect_to_daemon()
        except ConnectionError as e:
            if attempt >= max_retries - 1:
                raise
            delay = 2 ** attempt  # 1, 2, 4, 8, 16
            console.print(f"[yellow]Connection lost, retrying in {delay}s (attempt {attempt+1}/{max_retries})...[/yellow]")
            await asyncio.sleep(delay)
```

### 5. i3 Tree Inspection

**Decision**: Use `i3ipc.aio` library directly (same as daemon), no additional abstractions

**Rationale**:
- Daemon already uses `i3ipc` for async i3 IPC communication
- Library provides complete tree traversal and query capabilities
- No need for daemon mediation - monitor can query i3 directly for tree view
- Reduces daemon complexity and IPC overhead for tree inspection
- Allows richer tree displays with full node properties

**Implementation Pattern**:
```python
from i3ipc import aio

async def get_tree():
    conn = await aio.Connection().connect()
    tree = await conn.get_tree()
    await conn.disconnect()
    return tree

def render_tree_node(node, indent=0):
    # Recursive tree rendering with Rich
    table.add_row(
        "  " * indent + node.type,
        str(node.id),
        ", ".join(node.marks),
        node.window_class or ""
    )
    for child in node.nodes:
        render_tree_node(child, indent + 1)
```

### 6. Display Mode Selection

**Decision**: Command-line flags with separate processes per mode (not single TUI with tabs)

**Rationale**:
- Simpler implementation - each mode is independent script/function
- Allows running multiple modes simultaneously in different terminals
- Matches tmux/terminal multiplexer workflow (common for developers)
- No complex TUI state management or tab switching logic
- Each mode can optimize for its specific display needs
- Easier testing - each mode is isolated

**CLI Design**:
```bash
i3-project-monitor --mode=live      # Default: live state display
i3-project-monitor --mode=events    # Live event stream
i3-project-monitor --mode=history   # Historical event viewer
i3-project-monitor --mode=tree      # i3 tree inspector
```

## Best Practices Integration

### From Existing Daemon Code

**Pattern**: Python asyncio daemon with systemd integration
- Use `asyncio.run()` for main entry point
- Implement graceful shutdown with signal handlers
- Use structured logging with `logging` module
- Dataclasses for model definitions (see `models.py`)

**Pattern**: StateManager for data queries
- Centralize state access through StateManager class
- Use async methods for all state operations
- Maintain in-memory state with thread-safe access

**Pattern**: Configuration loading
- JSON config files in `~/.config/i3/`
- Use `pathlib.Path` for file operations
- Validate configs with type hints and dataclasses

### From Existing CLI Tools

**Pattern**: Bash wrappers for user-facing commands
- Python module for core logic
- Bash script for argument parsing and user experience
- Support both text and JSON output formats
- Color output with ANSI codes (fallback for no Rich in bash)

**Pattern**: Error handling and user messaging
- Clear error messages with actionable guidance
- Check daemon connection before queries
- Provide helpful hints for common issues
- Exit codes: 0 = success, 1 = error, 2 = daemon not running

### NixOS Integration

**Pattern**: Home-manager module for Python tools
- Create Python package with setup.py or pyproject.toml
- Install via `home.packages` with `python3.withPackages`
- Add dependencies: rich, i3ipc
- Create CLI wrapper scripts with `writeShellScriptBin`
- Add to development package profile (not minimal/essential)

## Open Source Code Review

### Rich Library Examples

**Reviewed**: https://github.com/Textualize/rich (GitHub examples)

**Key Learnings**:
- Use `rich.live.Live` for auto-updating displays
- `rich.layout.Layout` for split-screen views (useful for multi-panel display)
- `rich.table.Table` with `show_header=True` for data grids
- `rich.syntax.Syntax` for syntax highlighting (useful for JSON event display)
- `rich.panel.Panel` for grouped content sections

**Applicable Patterns**:
```python
# Multi-panel layout (e.g., status + windows + monitors)
layout = Layout()
layout.split_column(
    Layout(name="status", size=5),
    Layout(name="windows"),
    Layout(name="monitors", size=8)
)
layout["status"].update(status_panel)
layout["windows"].update(windows_table)
layout["monitors"].update(monitors_table)
```

### i3ipc-python Examples

**Reviewed**: https://github.com/altdesktop/i3ipc-python (documentation and examples)

**Key Learnings**:
- `Connection().get_tree()` returns full window tree
- `Container.marks` provides all marks including `project:*`
- Tree traversal with `nodes` and `floating_nodes` attributes
- `find_focused()` helper for current focus
- `workspace()` method on containers to get workspace name

**Applicable Patterns**:
```python
# Find windows with project marks
tree = await conn.get_tree()
for node in tree.descendants():
    if node.window:
        project_marks = [m for m in node.marks if m.startswith("project:")]
        if project_marks:
            print(f"{node.window_class}: {project_marks[0]}")
```

## Implementation Risks and Mitigations

### Risk: Event Flooding

**Problem**: High event rates (100+ events/sec) could freeze terminal UI

**Mitigation**:
- Buffer events in circular queue (collections.deque with maxlen=500)
- Update display at fixed rate (4 FPS using Rich Live refresh_per_second=4)
- Implement event filtering by type in daemon query
- Consider rate limiting display updates if performance issues occur

### Risk: Daemon Connection Loss During Display

**Problem**: Monitor tool crashes or hangs if daemon stops mid-operation

**Mitigation**:
- Wrap all IPC calls in try/except ConnectionError
- Display connection status prominently in UI
- Implement auto-reconnect with exponential backoff
- Graceful degradation - show last known state during reconnection

### Risk: Large Window/Event Counts

**Problem**: 100+ windows or 500 events may exceed terminal height

**Mitigation**:
- Use Rich table pagination or scrolling (terminal native scrollback)
- Limit initial display to 20-50 items with "..." indicator
- Add --limit flag for history mode to cap event count
- Consider filtering options (e.g., --project=nixos)

## Phase 1 Design Tasks

Based on this research, Phase 1 will generate:

1. **data-model.md**: Define data models for:
   - MonitorState (connection status, active project, uptime)
   - WindowEntry (window details for display)
   - EventEntry (event log structure)
   - MonitorEntry (monitor/output information)

2. **contracts/**: Define extended daemon JSON-RPC API:
   - `list_monitors` request/response schema
   - `subscribe_events` request/notification schema
   - Event circular buffer storage requirements
   - Update `get_events` to return stored events

3. **quickstart.md**: User guide covering:
   - Installing monitor tool (NixOS home-manager)
   - Running different display modes
   - Interpreting display output
   - Common troubleshooting scenarios

## References

- Rich library documentation: https://rich.readthedocs.io/
- i3ipc-python documentation: https://i3ipc-python.readthedocs.io/
- Existing daemon code: `/etc/nixos/home-modules/desktop/i3-project-event-daemon/`
- Existing CLI tools: `/etc/nixos/scripts/i3-project-daemon-*`
- Feature 015 specification: `/etc/nixos/specs/015-create-a-new/spec.md`
- NixOS Constitution: `/etc/nixos/.specify/memory/constitution.md`

---

**Research Status**: ✅ Complete - All unknowns from Technical Context resolved
