# i3 Event Subscription Contract

**Feature**: Event-Based i3 Project Synchronization
**Contract Type**: i3 IPC Event Specification
**Version**: 1.0.0

## Overview

This contract defines which i3 IPC events the daemon subscribes to and how they are handled. Based on i3 IPC protocol documented in `/etc/nixos/docs/i3-ipc.txt`.

---

## Subscribed Events

The daemon subscribes to the following i3 event types:

1. `window` - Window state changes
2. `workspace` - Workspace state changes
3. `tick` - Custom tick events (used for project switch notifications)
4. `shutdown` - i3 shutdown/restart events

---

## Event: `window`

**Event Type ID**: 0x80000003 (0x3 with highest bit set)

**Subscription**: `["window"]`

### Subtypes

The daemon handles the following `window` event subtypes (indicated by `change` field):

#### 1. `window::new`

**Trigger**: New window is created and managed by i3

**Payload**:
```json
{
  "change": "new",
  "container": {
    "id": 140737329456128,
    "type": "con",
    "window": 94557896564,
    "window_properties": {
      "class": "Code",
      "instance": "code",
      "title": "Visual Studio Code"
    },
    "workspace": "1",
    "marks": [],
    "focused": true
  }
}
```

**Daemon Action**:
1. Check if active project exists
2. Check if `window_properties.class` is in scoped_classes
3. If both true, apply mark: `i3.command(f'[id={window}] mark --add "project:{active_project}"')`
4. Add to in-memory `window_map`

**Timing**: Event fires after window is reparented by i3 (WM_CLASS should be available)

**Performance Target**: <100ms from event receipt to mark applied

---

#### 2. `window::close`

**Trigger**: Window is closed and removed from i3's tree

**Payload**:
```json
{
  "change": "close",
  "container": {
    "id": 140737329456128,
    "window": 94557896564,
    "window_properties": {
      "class": "Code"
    }
  }
}
```

**Daemon Action**:
1. Remove `window_map[container.window]` if exists
2. No other action needed (marks automatically removed by i3)

**Timing**: Event fires before window is fully destroyed

---

#### 3. `window::focus`

**Trigger**: Window receives input focus

**Payload**:
```json
{
  "change": "focus",
  "container": {
    "id": 140737329456128,
    "window": 94557896564,
    "focused": true,
    "marks": ["project:nixos", "editor"]
  }
}
```

**Daemon Action**:
1. Update `window_map[container.window].last_focus = datetime.now()`
2. Optionally notify subscribers of focus change (for external tools)

**Performance Target**: <50ms

---

#### 4. `window::mark`

**Trigger**: Marks are added or removed from a window (via `mark` command or GUI action)

**Payload**:
```json
{
  "change": "mark",
  "container": {
    "id": 140737329456128,
    "window": 94557896564,
    "marks": ["project:nixos", "editor", "active"]
  }
}
```

**Daemon Action**:
1. Extract project marks (starting with `project:`)
2. If project mark found: Update or add `window_map[container.window]`
3. If project mark removed: Remove from `window_map[container.window]`
4. Validate project name matches existing project config

**Use Case**: Detects manual mark changes by user (e.g., `i3-msg 'mark project:nixos'`)

---

#### 5. `window::move`

**Trigger**: Window moved to different workspace or output

**Payload**:
```json
{
  "change": "move",
  "container": {
    "id": 140737329456128,
    "window": 94557896564,
    "workspace": "2",
    "marks": ["project:nixos"]
  }
}
```

**Daemon Action**:
1. Update `window_map[container.window].workspace = container.workspace`
2. Update `window_map[container.window].output = container.output` (if changed)
3. No visibility changes needed (marks preserved during move)

**Use Case**: Track window location for workspace-based queries

---

### Ignored Subtypes

The daemon ignores these window event subtypes:

- `window::title` - Title changes (not used for project management)
- `window::fullscreen_mode` - Fullscreen state (not relevant)
- `window::floating` - Float/tile toggle (not relevant)
- `window::urgent` - Urgent flag (not relevant)

---

## Event: `workspace`

**Event Type ID**: 0x80000000 (0x0 with highest bit set)

**Subscription**: `["workspace"]`

### Subtypes

#### 1. `workspace::init`

**Trigger**: New workspace created

**Payload**:
```json
{
  "change": "init",
  "current": {
    "id": 140737329456200,
    "name": "5",
    "num": 5,
    "output": "DP-1",
    "visible": true,
    "focused": true
  }
}
```

**Daemon Action**:
1. Add to `workspace_map`
2. Apply project-scoped window visibility rules if project active

**Use Case**: Ensures new workspaces respect active project context

---

#### 2. `workspace::empty`

**Trigger**: Workspace becomes empty (last window closed)

**Payload**:
```json
{
  "change": "empty",
  "current": {
    "name": "5",
    "num": 5
  }
}
```

**Daemon Action**:
1. Remove from `workspace_map` (i3 will destroy workspace)
2. Clean up any stale workspace references

---

#### 3. `workspace::focus`

**Trigger**: User switches to different workspace

**Payload**:
```json
{
  "change": "focus",
  "current": {
    "name": "2",
    "num": 2,
    "focused": true
  },
  "old": {
    "name": "1",
    "num": 1,
    "focused": false
  }
}
```

**Daemon Action**:
1. Update workspace focus tracking
2. Optionally trigger window visibility updates (if project-scoped windows need show/hide)

**Use Case**: Context-aware status bar updates, workspace-based project hints

---

#### 4. `workspace::move`

**Trigger**: Workspace moved to different output (monitor)

**Payload**:
```json
{
  "change": "move",
  "current": {
    "name": "3",
    "num": 3,
    "output": "HDMI-1"
  },
  "old": {
    "output": "DP-1"
  }
}
```

**Daemon Action**:
1. Update `workspace_map[workspace.name].output`
2. Optionally trigger workspace reassignment logic

**Use Case**: Multi-monitor support (replaces manual Win+Shift+M trigger)

---

### Ignored Subtypes

- `workspace::rename` - Not used for project management

---

## Event: `tick`

**Event Type ID**: 0x8000000A (0xA with highest bit set)

**Subscription**: `["tick"]`

**Purpose**: Custom events sent via `i3-msg` for project switch notifications.

### Payload Format

```json
{
  "first": true,
  "payload": "project:nixos"
}
```

**Payload Patterns**:
- `project:PROJECT_NAME` - Switch to specified project
- `project:none` - Clear active project (global mode)
- `project:reload` - Reload project configurations

### Daemon Action

```python
def on_tick(i3, event):
    payload = event.payload

    if payload.startswith('project:'):
        project_name = payload.split(':', 1)[1]

        if project_name == 'none':
            # Clear active project
            clear_active_project()
        elif project_name == 'reload':
            # Reload configs
            reload_project_configs()
        else:
            # Switch to project
            switch_to_project(project_name)
```

### Sending Tick Events

**From CLI**:
```bash
i3-msg 'exec --no-startup-id i3-msg -t send_tick "project:nixos"'
```

**From i3 config**:
```
bindsym $mod+p exec --no-startup-id rofi -show project && i3-msg -t send_tick "project:$(cat ~/.config/i3/active-project.json | jq -r '.project_name')"
```

**Performance Target**: <200ms from tick event to window visibility updated

---

## Event: `shutdown`

**Event Type ID**: 0x80000009 (0x9 with highest bit set)

**Subscription**: `["shutdown"]`

**Purpose**: Detect i3 shutdown or restart for graceful daemon reconnection.

### Payload

```json
{
  "change": "restart"  // or "exit"
}
```

**Change Types**:
- `restart`: i3 is restarting (daemon should reconnect)
- `exit`: i3 is exiting (daemon should terminate)

### Daemon Action

```python
def on_shutdown(i3, event):
    if event.change == 'restart':
        logger.info("i3 restarting, preparing for reconnection...")
        # auto_reconnect will handle reconnection
        # State will be rebuilt from marks after reconnection
    elif event.change == 'exit':
        logger.info("i3 exiting, terminating daemon...")
        # Graceful shutdown
        sys.exit(0)
```

---

## Event Handling Patterns

### Async Event Handler Pattern

```python
from i3ipc.aio import Connection
from i3ipc import Event

async def on_window_new(i3, event):
    """Handle new window events."""
    try:
        window = event.container
        active_project = get_active_project()

        if active_project and is_scoped_class(window.window_class):
            mark = f"project:{active_project}"
            await i3.command(f'[id={window.window}] mark --add "{mark}"')
            logger.info(f"Marked window {window.window} with {mark}")

    except Exception as e:
        logger.error(f"Error in window_new handler: {e}")
        # Don't crash daemon on handler errors

async def main():
    i3 = await Connection(auto_reconnect=True).connect()

    # Subscribe to events
    i3.on(Event.WINDOW_NEW, on_window_new)
    i3.on(Event.WINDOW_CLOSE, on_window_close)
    i3.on(Event.WINDOW_MARK, on_window_mark)
    i3.on(Event.WINDOW_FOCUS, on_window_focus)
    i3.on(Event.WINDOW_MOVE, on_window_move)
    i3.on(Event.WORKSPACE_INIT, on_workspace_init)
    i3.on(Event.WORKSPACE_EMPTY, on_workspace_empty)
    i3.on(Event.WORKSPACE_FOCUS, on_workspace_focus)
    i3.on(Event.WORKSPACE_MOVE, on_workspace_move)
    i3.on(Event.TICK, on_tick)
    i3.on(Event.SHUTDOWN, on_shutdown)

    logger.info("Event subscriptions registered")

    # Run event loop (blocks forever)
    await i3.main()
```

### Error Handling

**Principle**: Event handler errors must not crash the daemon.

```python
def safe_handler(handler_func):
    """Decorator to catch and log handler exceptions."""
    async def wrapper(i3, event):
        try:
            await handler_func(i3, event)
        except Exception as e:
            logger.error(f"Handler {handler_func.__name__} failed: {e}")
            # Increment error counter for monitoring
            state.error_count += 1
    return wrapper

@safe_handler
async def on_window_new(i3, event):
    # Handler implementation
    pass
```

---

## Performance Targets

| Event Type | Processing Latency Target | Typical Latency |
|------------|---------------------------|-----------------|
| window::new + mark | <100ms | 10-50ms |
| window::close | <10ms | <5ms |
| window::focus | <50ms | 1-10ms |
| window::mark | <20ms | 5-15ms |
| workspace::* | <50ms | 5-20ms |
| tick (project switch) | <200ms | 50-150ms |

**Overall Target**: 95% of events processed within 100ms (FR-028)

---

## Event Ordering Guarantees

Per i3 documentation:

1. **Events are delivered in order** they occur
2. **Events never interrupt each other** (sequential delivery)
3. **Caveat**: Once subscribed, request/reply ordering is not guaranteed
   - Solution: Use separate connection for commands if strict ordering needed
   - For daemon: Not an issue (events drive commands, not vice versa)

---

## Testing Event Handlers

### Manual Event Triggering

```bash
# Trigger window::new
code /tmp/test.txt

# Trigger window::close
i3-msg '[class="Code"] kill'

# Trigger window::mark
i3-msg '[class="Code"] mark project:nixos'

# Trigger workspace::focus
i3-msg 'workspace 2'

# Trigger tick event
i3-msg -t send_tick "project:nixos"

# Trigger shutdown event (caution: restarts i3)
i3-msg restart
```

### Event Monitoring

```bash
# Monitor events with i3-msg (for debugging)
i3-msg -t subscribe -m '["window","workspace","tick","shutdown"]'

# View daemon event log
journalctl --user -u i3-project-event-listener -f

# Query recent events via CLI
i3-project-daemon-events --limit=50
```

### Simulated Event Testing

```python
# test_event_handlers.py
import pytest
from unittest.mock import Mock
from i3ipc import Event

@pytest.fixture
def mock_connection():
    conn = Mock()
    conn.command = Mock(return_value=[{"success": True}])
    return conn

@pytest.mark.asyncio
async def test_window_new_handler(mock_connection):
    """Test window::new event handler."""
    event = Mock()
    event.change = "new"
    event.container = Mock(
        window=12345,
        window_class="Code",
        marks=[]
    )

    # Set active project
    set_active_project("nixos")

    # Call handler
    await on_window_new(mock_connection, event)

    # Verify mark was applied
    mock_connection.command.assert_called_with(
        '[id=12345] mark --add "project:nixos"'
    )
```

---

## Versioning

**i3 IPC Protocol Version**: Compatible with i3 v4.20+

**Compatibility**: Event structure is stable across i3 versions. Daemon should gracefully handle unknown event subtypes (ignore with warning).

**Future Events**: If i3 adds new event subtypes, daemon should:
1. Log unknown subtype for investigation
2. Continue processing other events
3. Upgrade daemon to handle new subtypes if relevant
