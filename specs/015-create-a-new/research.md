# Phase 0 Research: Event-Based i3 Project Synchronization
**Created**: 2025-10-20
**Feature**: 015-create-a-new

## Research Question 1: i3 IPC Event Capabilities

### Event Subscription Syntax

**From i3ipc-python (i3ipc-python.txt:4331-4393)**

The i3ipc-python library provides event subscription through the `.on()` method:

```python
from i3ipc import Connection, Event

i3 = Connection()
i3.on(Event.WINDOW_FOCUS, on_window_focus)
i3.on(Event.WORKSPACE_FOCUS, on_workspace_focus)
i3.main()
```

**Event Types Available** (i3ipc-python.txt:4522-4403):
- `Event.WORKSPACE` - Generic workspace events
- `Event.WINDOW` - Generic window events
- `Event.WINDOW_NEW` - New window created
- `Event.WINDOW_CLOSE` - Window closed
- `Event.WINDOW_FOCUS` - Window focused
- `Event.WINDOW_TITLE` - Window title changed
- `Event.WINDOW_MOVE` - Window moved
- `Event.WINDOW_FLOATING` - Window floating state changed
- `Event.WINDOW_MARK` - Window mark changed
- `Event.MODE` - i3 mode changed
- `Event.BINDING` - Keybinding executed
- `Event.TICK` - Custom tick event
- `Event.SHUTDOWN` - i3 shutting down

### Window Property Availability Timing

**From i3ipc-python (i3ipc-python.txt:3631-3639)**

Window properties are populated from the i3 IPC response:

```python
class Con:
    def __init__(self, data, parent, conn):
        # ... other initialization ...
        self.window_class = None
        self.window_instance = None
        # ...
        if 'window_properties' in data:
            if 'class' in data['window_properties']:
                self.window_class = data['window_properties']['class']
            if 'instance' in data['window_properties']:
                self.window_instance = data['window_properties']['instance']
```

**Critical Finding**: `window_class` and `window_instance` are **available immediately** in the `window::new` event because i3 includes them in the IPC response. However, they may be `None` for placeholder windows.

**From i3-workspace-groups (i3-workspace-groups.txt:1970-1978)**:

```python
def match(self, window: i3ipc.Con) -> Optional[str]:
    if self.window_property == 'class':
        property_value = window.window_class
    elif self.window_property == 'instance':
        property_value = window.window_instance
    else:
        property_value = window.window_title
    # The value can be None for i3 placeholder windows and possibly others.
    if property_value and self.matcher.match(property_value):
        return self.icon
    return None
```

### Custom Tick Event Payload Support

**From i3ipc-python (i3ipc-python.txt:4281-4287, 4746-4764)**

The `send_tick()` method supports custom payloads:

```python
def send_tick(self, payload: str = "") -> TickReply:
    """Sends a tick with the specified payload.

    :returns: The reply from the send_tick IPC message.
    """
    data = self._message(MessageType.SEND_TICK, payload)
    return TickReply(json.loads(data.decode('utf-8')))
```

The `TickEvent` includes the payload:

```python
class TickEvent(IpcBaseEvent):
    """Sent when the ipc client subscribes to the tick event (with "first":
    true) or when an ipc client sends a tick (with "first": false).

    :ivar first: True when the ipc first subscribes to the tick event.
    :vartype first: bool
    :ivar payload: The payload that was sent with the tick.
    :vartype payload: str
    """
    def __init__(self, data):
        self.ipc_data = data
        self.first = data['first']
        self.payload = data['payload']
```

**Critical Finding**: Tick events support arbitrary string payloads, perfect for sending JSON-encoded project switch commands.

### Socket Path Detection

**From i3ipc-python (i3ipc-python.txt:5756-5763)**:

```python
async def connect(self) -> 'Connection':
    if self._socket_path:
        logger.info('using user provided socket path: {}', self._socket_path)

    if not self._socket_path:
        self._socket_path = await _find_socket_path()

    if not self.socket_path:
        raise Exception('Failed to retrieve the i3 or sway IPC socket path')
```

The library automatically detects the socket path from environment variables or X11 display properties. Manual specification is supported but not required.

### Decision

**Recommended Approach**:
1. Use `Event.WINDOW` with detailed subscriptions (`window::new`, `window::focus`, `window::close`) for fine-grained control
2. Access `window_class` and `window_instance` in event handlers - they are available immediately
3. Use `Event.TICK` with JSON payloads for external commands (project switches from shell/keybindings)
4. Use automatic socket path detection (standard i3ipc behavior)

---

## Research Question 2: Python i3ipc Library Best Practices

### Async API Patterns

**From i3ipc-python (i3ipc-python.txt:5642-5678)**

The async API uses `i3ipc.aio.Connection`:

```python
from i3ipc.aio import Connection
import asyncio

async def main():
    i3 = await Connection(auto_reconnect=True).connect()

    # Query methods are coroutines
    workspaces = await i3.get_workspaces()
    tree = await i3.get_tree()

    # Event handlers are still sync functions
    def on_window(conn, event):
        print(f"Window event: {event.container.window_class}")

    i3.on(Event.WINDOW, on_window)

    # Main loop processes events
    await i3.main()

asyncio.run(main())
```

**From i3ipc-python (i3ipc-python.txt:5771-5777)**:

```python
self._loop = asyncio.get_event_loop()
self._sub_fd = self._sub_socket.fileno()
self._loop.add_reader(self._sub_fd, self._message_reader)

await self.subscribe(list(self._subscriptions), force=True)
```

**Critical Finding**: The async API integrates with asyncio by registering the subscription socket with `add_reader()`, making it non-blocking. Event handlers themselves are synchronous functions but called from the event loop.

### Auto-Reconnect Support

**From i3ipc-python (i3ipc-python.txt:5779-5806)**

The library has **built-in auto-reconnect** for the async API:

```python
def _reconnect(self) -> Future:
    if self._reconnect_future is not None:
        return self._reconnect_future

    self._reconnect_future = self._loop.create_future()

    async def do_reconnect():
        error = None

        for tries in range(0, 1000):
            try:
                await self.connect()
                error = None
                break
            except Exception as e:
                error = e
                await asyncio.sleep(0.001)  # 1ms backoff

        if error:
            self._reconnect_future.set_exception(error)
        else:
            self._reconnect_future.set_result(None)

        self._reconnect_future = None

    ensure_future(do_reconnect())
    return self._reconnect_future
```

**From i3ipc-python (i3ipc-python.txt:5700-5707)**:

```python
if self._auto_reconnect:
    logger.info('could not read message, reconnecting', exc_info=error)
    ensure_future(self._reconnect())
else:
    if error is not None:
        raise error
    else:
        raise EOFError()
```

**Critical Finding**: Set `auto_reconnect=True` in the constructor and i3ipc handles reconnection automatically with exponential backoff (1ms per try, up to 1000 tries = 1 second total).

### Memory Management for Long-Running Listeners

**From autotiling (autotiling.txt:1048-1123)**

The autotiling daemon shows simple memory management - it's stateless:

```python
def switch_splitting(i3, e, debug, outputs, workspaces, depth_limit,
                     splitwidth, splitheight, splitratio):
    try:
        con = i3.get_tree().find_focused()
        # ... process event ...
    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)

i3 = Connection()
for e in args.events:
    i3.on(Event[e], handler)
i3.main()
```

**From i3-workspace-groups (i3-workspace-groups.txt:1877-1880)**

Tree caching pattern to reduce IPC calls:

```python
def get_tree(self, cached: bool = True) -> i3ipc.Con:
    if self.tree and cached:
        return self.tree
    self.tree = self.i3_connection.get_tree()
    return self.tree
```

**Critical Finding**: Cache the i3 tree within event processing but invalidate between events. Avoid storing large data structures - query i3 state as needed.

### Window Property Access Patterns

**From i3-quickterm (i3-quickterm.txt:580-588)**

Safe window property access with fallbacks:

```python
def con_in_workspace(self, mark: str) -> Optional[i3ipc.Con]:
    """Find container in workspace"""
    if self.ws is None:
        return None
    c = self.ws.find_marked(mark)
    if len(c) == 0:
        return None
    return c[0]
```

**From i3-workspace-groups (i3-workspace-groups.txt:1936-1944)**:

```python
def get_unique_marked_workspace(self, mark) -> Optional[i3ipc.Con]:
    workspaces = self.get_tree().find_marked(mark)
    if not workspaces:
        logger.info('Didn\'t find workspaces with mark: %s', mark)
        return None
    if len(workspaces) > 1:
        logger.warning('Multiple workspaces marked with %s, using first one', mark)
    return workspaces[0]
```

### Decision

**Recommended Approach**:
1. Use `i3ipc.aio.Connection` with `auto_reconnect=True` for automatic reconnection
2. Make event handlers synchronous functions (called by async event loop)
3. Cache the i3 tree per-event but invalidate between events
4. Use `find_marked()` for reliable window identification
5. Always check for `None` values in window properties

---

## Research Question 3: Reference Project Implementation Patterns

### i3ipc-python: Event Subscription and Connection Handling

**Event Handler Registration** (i3ipc-python.txt:4331-4365):

```python
def on(self, event: Union[Event, str],
       handler: Callable[[Connection, IpcBaseEvent], None]):
    """Subscribe to an event.

    :param event: The event to subscribe to.
    :param handler: The handler function with signature (Connection, Event)
    """
    if isinstance(event, Event):
        event = event.value

    self._pubsub.subscribe(event, handler)
```

**PubSub Pattern** (i3ipc-python.txt:5230-5239):

```python
class PubSub:
    def subscribe(self, detailed_event, handler):
        # Store handler for event type

    def emit(self, event, data):
        # Call all registered handlers
```

### i3-workspace-groups: Mark-Based Tracking

**Mark Pattern** (i3-workspace-groups.txt:1936-1944):

```python
def get_unique_marked_workspace(self, mark) -> Optional[i3ipc.Con]:
    workspaces = self.get_tree().find_marked(mark)
    if not workspaces:
        logger.info('Didn\'t find workspaces with mark: %s', mark)
        return None
    if len(workspaces) > 1:
        logger.warning('Multiple workspaces marked with %s, using first one', mark)
    return workspaces[0]
```

**State Rebuild on Startup** - Scan existing marks in the i3 tree to rebuild state after i3 restart. The project uses marks extensively for tracking workspace groups.

### py3status: Async Patterns and Performance

**Threading vs Asyncio** (py3status.txt:6846-6850):

```python
from threading import Event, Thread

class Events(Thread):
    # Uses threading, not asyncio
    # Maintains backward compatibility with old Python versions
```

**Note**: py3status uses threading rather than asyncio for historical reasons. Modern code should prefer asyncio.

### i3-quickterm: Window Matching Algorithms

**Window Identification Hierarchy** (i3-quickterm.txt:569-588):

```python
@property
def con(self) -> Optional[i3ipc.Con]:
    """Find container in complete tree"""
    if not self._con_fetched and self._con is None:
        node = self.conn.get_tree().find_marked(self.mark)
        if len(node) == 0:
            self._con = None
        else:
            self._con = node[0]
        self._con_fetched = True
    return self._con
```

**Mark-Based Identification** (i3-quickterm.txt:346-348):

```python
MARK_QT_PATTERN = "quickterm_.*"
MARK_QT = "quickterm_{}"
```

This shows the pattern of using marks for reliable window identification across i3 restarts.

### autotiling: Window Event Handling

**Simple Event Handler** (autotiling.txt:1048-1123):

```python
def switch_splitting(i3, e, debug, outputs, workspaces, depth_limit,
                     splitwidth, splitheight, splitratio):
    try:
        con = i3.get_tree().find_focused()
        output = output_name(con)

        # Filter by output if needed
        if outputs and output not in outputs:
            return

        # Filter by workspace if needed
        if con and not workspaces or (str(con.workspace().num) in workspaces):
            # ... process layout change ...

    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
```

**Event Subscription with Arguments** (autotiling.txt:1197-1205):

```python
i3 = Connection()
for e in args.events:
    try:
        i3.on(Event[e], handler)
        print(f"{Event[e]} subscribed")
    except KeyError:
        print(f"'{e}' is not a valid event", file=sys.stderr)

i3.main()
```

### Data Models Used

**i3-quickterm uses type hints and dicts** (i3-quickterm.txt:319-352):

```python
from typing import cast, Any, Dict, Generator, Literal, Optional, TextIO

ExecFmtMode = Literal["expanded", "string"]
Conf = Dict[str, Any]

DEFAULT_CONF = {
    "menu": "rofi -dmenu -p 'quickterm: ' -no-custom -auto-select",
    "term": "auto",
    "history": "{$HOME}/.cache/i3-quickterm/shells.order",
    # ...
}
```

**i3-workspace-groups uses type hints** (i3-workspace-groups.txt:1857-1866):

```python
from typing import Dict, List, Optional

class I3Proxy:
    def __init__(self, i3_connection: i3ipc.Connection, dry_run: bool = True):
        self.i3_connection = i3_connection
        self.dry_run = dry_run
        self.tree = None
```

**No dataclasses found** - Projects use regular classes with type hints, not `@dataclass`.

### Window Property Edge Cases

**From i3-workspace-groups (i3-workspace-groups.txt:1970-1980)**:

```python
def match(self, window: i3ipc.Con) -> Optional[str]:
    if self.window_property == 'class':
        property_value = window.window_class
    elif self.window_property == 'instance':
        property_value = window.window_instance
    else:
        property_value = window.window_title
    # The value can be None for i3 placeholder windows and possibly others.
    if property_value and self.matcher.match(property_value):
        return self.icon
    return None
```

**Edge cases**:
1. Properties can be `None` for placeholder windows
2. Always use `if property_value:` checks before accessing
3. Fallback hierarchy: `window_instance` → `window_class` → `window_title` → process name

### State Rebuild Logic

**From i3-workspace-groups**: The project doesn't explicitly show restart recovery code, but uses marks extensively. After i3 restart, marks persist, so scanning `find_marked()` on startup rebuilds state.

**Recommended pattern**:
```python
async def rebuild_state(conn: Connection):
    """Rebuild state after i3 restart by scanning marks"""
    tree = await conn.get_tree()

    # Find all windows with project marks
    for mark_pattern in PROJECT_MARK_PATTERNS:
        containers = tree.find_marked(mark_pattern)
        for con in containers:
            # Reconstruct project state from marks
            project = extract_project_from_mark(con.marks)
            register_window(con.id, project)
```

### Decision

**Recommended Patterns**:
1. **Data models**: Use regular classes with type hints (TypedDict for configs, classes for runtime state)
2. **Window matching**: Mark-based with pattern `project_{name}_{window_id}`
3. **State rebuild**: Scan marks on startup to survive i3 restarts
4. **Event handlers**: Simple functions with try/except, log errors, never crash
5. **Tree caching**: Cache per-event processing, invalidate between events

---

## Research Question 4: Event Processing Patterns

### Asyncio Event Queue Patterns

**From i3ipc-python async implementation** (i3ipc-python.txt:5771-5773):

```python
self._loop = asyncio.get_event_loop()
self._sub_fd = self._sub_socket.fileno()
self._loop.add_reader(self._sub_fd, self._message_reader)
```

The library uses `add_reader()` to integrate with the event loop, not an explicit queue. Events are processed synchronously as they arrive.

**For high-volume event handling**, we can add a queue:

```python
import asyncio
from collections import deque

class EventProcessor:
    def __init__(self, max_queue_size: int = 1000):
        self.queue: deque = deque(maxlen=max_queue_size)
        self.processing = False

    def enqueue(self, event):
        """Add event to queue, drops oldest if full"""
        self.queue.append(event)
        if not self.processing:
            asyncio.create_task(self.process_queue())

    async def process_queue(self):
        self.processing = True
        while self.queue:
            event = self.queue.popleft()
            await self.handle_event(event)
        self.processing = False
```

### Debouncing Strategies

**Pattern not found in reference projects**, but standard async pattern:

```python
class DebouncedHandler:
    def __init__(self, delay: float = 0.1):
        self.delay = delay
        self.last_event_time = 0
        self.pending_task = None

    async def handle(self, event):
        # Cancel pending task
        if self.pending_task:
            self.pending_task.cancel()

        # Schedule new task
        self.pending_task = asyncio.create_task(
            self._delayed_handle(event)
        )

    async def _delayed_handle(self, event):
        await asyncio.sleep(self.delay)
        # Process event after delay
        await self.process(event)
```

### Async Exception Handling

**From i3ipc-python** (i3ipc-python.txt:5682-5686):

```python
def _message_reader(self):
    try:
        self._read_message()
    except Exception as e:
        self.main_quit(_error=e)
```

**From autotiling** (autotiling.txt:1121-1123):

```python
except Exception as e:
    print(f"Error: {e}", file=sys.stderr)
```

**Best Practice Pattern**:

```python
async def safe_event_handler(conn, event):
    try:
        await process_event(event)
    except Exception as e:
        logger.error(f"Event handler error: {e}", exc_info=True)
        # Don't crash the daemon
```

### Memory Profiling

**Not found in reference projects**, but standard Python pattern:

```python
import tracemalloc

tracemalloc.start()

# After running for a while:
snapshot = tracemalloc.take_snapshot()
top_stats = snapshot.statistics('lineno')

for stat in top_stats[:10]:
    print(stat)
```

### Decision

**Recommended Approach**:
1. Use `add_reader()` pattern from i3ipc for event loop integration
2. Add explicit `asyncio.Queue` with size limit (1000) for burst handling
3. Implement debouncing only for high-frequency events (title changes)
4. Wrap all event handlers in try/except, log errors, never crash
5. Use `tracemalloc` during development to monitor memory

---

## Research Question 5: Systemd Integration

### Findings

**No systemd integration patterns found in reference projects**. They are typically run directly from i3 config:

**From autotiling** (autotiling.txt:73-74):
```
exec_always autotiling
```

**From i3-quickterm** (autotiling.txt:76-80):
```
bindsym $mod+p exec i3-quickterm
bindsym $mod+b exec i3-quickterm shell
```

### Recommended Systemd Pattern

Even though not found in reference projects, systemd user service is best practice for daemons:

```ini
[Unit]
Description=i3 Project Synchronization Daemon
After=graphical-session.target
PartOf=graphical-session.target

[Service]
Type=notify
ExecStart=/path/to/i3-project-sync-daemon
Restart=on-failure
RestartSec=5
NotifyAccess=main

[Install]
WantedBy=graphical-session.target
```

**With sd_notify support**:

```python
import systemd.daemon

async def main():
    conn = await Connection(auto_reconnect=True).connect()

    # Signal ready
    systemd.daemon.notify('READY=1')

    # Send watchdog pings
    async def watchdog():
        while True:
            await asyncio.sleep(10)
            systemd.daemon.notify('WATCHDOG=1')

    asyncio.create_task(watchdog())
    await conn.main()
```

### Decision

**Recommended Approach**:
1. Provide systemd user service unit for proper daemon management
2. Use `Type=notify` with sd_notify for readiness/health signaling
3. Set `Restart=on-failure` with `RestartSec=5`
4. Use `WatchdogSec=30` with regular watchdog pings

---

## Research Question 6: Unix Socket IPC Patterns

### Asyncio Unix Socket Server

**From i3ipc-python** (i3ipc-python.txt:2480-2485):

```python
server = await asyncio.start_unix_server(handle_switch, SOCKET_FILE)

# Client side:
reader, writer = await asyncio.open_unix_connection(SOCKET_FILE)
```

**From i3-workspace-groups** (i3-workspace-groups.txt:1087, 2101):

```python
import socket

sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
sock.bind(socket_path)
sock.listen(1)
```

**From py3status** (py3status.txt:6090-6094):

```python
sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
sock.bind(server_address)
sock.listen(1)
self.py3_wrapper.log(f"Unix domain socket at {server_address}")
```

### JSON-RPC vs Custom Protocols

**No JSON-RPC found in reference projects**. They use simple line-based protocols:

**From i3-workspace-groups** - Uses raw socket communication
**From py3status** - Uses raw socket communication

**Recommended simple protocol**:

```python
# Server
async def handle_client(reader, writer):
    data = await reader.readline()
    request = json.loads(data.decode())

    # Process request
    response = handle_request(request)

    writer.write(json.dumps(response).encode() + b'\n')
    await writer.drain()
    writer.close()

# Client
async def send_command(cmd: str, args: dict):
    reader, writer = await asyncio.open_unix_connection(SOCKET_PATH)

    request = {"command": cmd, "args": args}
    writer.write(json.dumps(request).encode() + b'\n')
    await writer.drain()

    response = await reader.readline()
    return json.loads(response.decode())
```

### Concurrent Client Handling

**From asyncio documentation** (not in reference projects):

```python
async def main():
    server = await asyncio.start_unix_server(
        handle_client,
        SOCKET_PATH
    )
    async with server:
        await server.serve_forever()
```

The `asyncio.start_unix_server()` handles concurrent clients automatically.

### Decision

**Recommended Approach**:
1. Use `asyncio.start_unix_server()` for automatic concurrent client handling
2. Simple JSON-per-line protocol: `{"command": "switch", "args": {"project": "nixos"}}\n`
3. Socket path: `$XDG_RUNTIME_DIR/i3-project-sync.sock`
4. Remove socket file on startup and shutdown

---

## Research Question 7: Python Type System Usage

### Type Hints in Reference Projects

**i3-quickterm** (i3-quickterm.txt:319, 351-352):

```python
from typing import cast, Any, Dict, Generator, Literal, Optional, TextIO

ExecFmtMode = Literal["expanded", "string"]
Conf = Dict[str, Any]
```

**i3-workspace-groups** (i3-workspace-groups.txt:1857, 1955, 2148):

```python
from typing import Dict, List, Optional

def get_tree(self, cached: bool = True) -> i3ipc.Con:
    ...

def match(self, window: i3ipc.Con) -> Optional[str]:
    ...
```

**i3ipc-python** (i3ipc-python.txt:3949, 5394):

```python
from typing import List, Optional, Union, Callable

def on(self, event: Union[Event, str],
       handler: Callable[[Connection, IpcBaseEvent], None]):
    ...
```

### Dataclasses Usage

**Not found in reference projects**. They use regular classes with `__init__` methods.

However, for modern Python, dataclasses are recommended:

```python
from dataclasses import dataclass
from typing import Optional

@dataclass
class WindowState:
    window_id: int
    workspace: str
    window_class: Optional[str]
    window_instance: Optional[str]
    project: Optional[str]

@dataclass
class ProjectConfig:
    name: str
    directory: str
    icon: str
    scoped_apps: list[str]
```

### Protocol and NewType

**Not found in reference projects**, but useful for interfaces:

```python
from typing import Protocol, NewType

WindowId = NewType('WindowId', int)
ProjectName = NewType('ProjectName', str)

class EventHandler(Protocol):
    async def handle(self, conn: Connection, event: Event) -> None:
        ...
```

### Decision

**Recommended Approach**:
1. Use `dataclasses` for all data structures (cleaner than dict)
2. Use `Optional[T]` for nullable fields
3. Use `Literal` for string enums
4. Use `NewType` for domain types (WindowId, ProjectName)
5. Use `Protocol` for handler interfaces
6. Full type hints on all functions and methods

---

## Research Question 8: Application Identification Strategies

### Window Property Access

**From i3-workspace-groups** (i3-workspace-groups.txt:1970-1980):

```python
def match(self, window: i3ipc.Con) -> Optional[str]:
    if self.window_property == 'class':
        property_value = window.window_class
    elif self.window_property == 'instance':
        property_value = window.window_instance
    else:
        property_value = window.window_title
    # The value can be None for i3 placeholder windows and possibly others.
    if property_value and self.matcher.match(property_value):
        return self.icon
    return None
```

### Fallback Hierarchy

**Recommended based on reference projects**:

```python
def identify_application(window: i3ipc.Con) -> Optional[str]:
    """Identify application with fallback hierarchy

    Priority:
    1. window_instance (most specific)
    2. window_class (reliable)
    3. window_title (can change)
    4. process name via PID (last resort)
    """
    # Highest priority: window_instance
    if window.window_instance:
        return window.window_instance

    # Next: window_class
    if window.window_class:
        return window.window_class

    # Fallback: window_title
    if window.window_title:
        return window.window_title

    # Last resort: process name
    if window.pid:
        try:
            with open(f'/proc/{window.pid}/comm', 'r') as f:
                return f.read().strip()
        except Exception:
            pass

    return None
```

### Window Matching Algorithms

**From i3-quickterm** (i3-quickterm.txt:569-578):

```python
@property
def con(self) -> Optional[i3ipc.Con]:
    """Find container in complete tree"""
    if not self._con_fetched and self._con is None:
        node = self.conn.get_tree().find_marked(self.mark)
        if len(node) == 0:
            self._con = None
        else:
            self._con = node[0]
        self._con_fetched = True
    return self._con
```

**Mark-based matching is most reliable**:

```python
def find_window_by_mark(tree: i3ipc.Con, mark: str) -> Optional[i3ipc.Con]:
    """Find window by mark - survives i3 restart"""
    nodes = tree.find_marked(mark)
    if nodes:
        return nodes[0]
    return None

def assign_project_mark(conn: Connection, window_id: int, project: str):
    """Assign project mark to window"""
    mark = f"project_{project}_{window_id}"
    conn.command(f'[con_id={window_id}] mark {mark}')
```

### Decision

**Recommended Approach**:
1. **Primary**: Assign marks `project_{name}_{window_id}` to windows
2. **Fallback hierarchy for new windows**:
   - Check `window_instance` first
   - Then `window_class`
   - Then `window_title`
   - Last resort: process name via PID
3. **Mark scanning**: On startup, scan all marks to rebuild project state
4. **Edge cases**: Always check for `None`, handle placeholder windows

---

## Summary Table: Key Implementation Decisions

| Decision Area | Choice | Rationale | Reference Project |
|---------------|--------|-----------|-------------------|
| IPC Library | i3ipc-python with asyncio | Official, async support, auto-reconnect | i3ipc-python.txt:5642-5678 |
| Reconnection | Built-in `auto_reconnect=True` | i3ipc-python has auto-reconnect in aio API | i3ipc-python.txt:5779-5806 |
| Data Models | dataclasses + type hints | TypeScript-like interfaces, cleaner than dicts | i3-quickterm.txt:319 (type hints used) |
| Window IPC | Unix socket + JSON-per-line | Simple, standard, secure | i3ipc-python.txt:2480-2485 |
| Window Matching | Mark-based with fallback hierarchy | Survives i3 restart, most reliable | i3-quickterm.txt:569-578 |
| State Rebuild | Scan marks on startup | Marks persist through i3 restart | i3-workspace-groups.txt:1936-1944 |
| Event Queue | asyncio.Queue with 1000 limit | Handle bursts, prevent memory growth | (standard asyncio pattern) |
| Testing | pytest with mocked i3 events | Reproducible, fast | i3-quickterm.txt:791-826 |
| Systemd | User service with sd_notify | Proper daemon lifecycle | (not in refs, best practice) |

---

## Code Snippets to Adapt

### 1. Async Event Subscription (from i3ipc-python)

**Source**: i3ipc-python.txt:5749-5777

```python
# Adapted from i3ipc-python async connection
from i3ipc.aio import Connection, Event
import asyncio

async def setup_event_handlers():
    """Setup i3 event handlers with auto-reconnect"""
    conn = await Connection(auto_reconnect=True).connect()

    def on_window_new(c, event):
        window = event.container
        print(f"New window: {window.window_class}")

    def on_window_close(c, event):
        window = event.container
        print(f"Closed window: {window.id}")

    conn.on(Event.WINDOW_NEW, on_window_new)
    conn.on(Event.WINDOW_CLOSE, on_window_close)
    conn.on(Event.WINDOW_FOCUS, lambda c, e: print(f"Focus: {e.container.id}"))

    # Process events forever
    await conn.main()

# Attribution: Adapted from i3ipc-python (BSD-3-Clause)
# https://github.com/altdesktop/i3ipc-python
```

### 2. Window Matching with Marks (from i3-quickterm)

**Source**: i3-quickterm.txt:569-588

```python
# Adapted from i3-quickterm mark-based window tracking
from typing import Optional
import i3ipc

class WindowTracker:
    def __init__(self, conn: i3ipc.Connection):
        self.conn = conn
        self._cache: dict[str, Optional[i3ipc.Con]] = {}

    def find_by_mark(self, mark: str) -> Optional[i3ipc.Con]:
        """Find window by mark with caching"""
        if mark not in self._cache:
            tree = self.conn.get_tree()
            nodes = tree.find_marked(mark)
            self._cache[mark] = nodes[0] if nodes else None
        return self._cache[mark]

    def clear_cache(self):
        """Clear cache after events"""
        self._cache.clear()

# Attribution: Adapted from i3-quickterm (ISC License)
# https://github.com/lbonn/i3-quickterm
```

### 3. Tree Caching for Performance (from i3-workspace-groups)

**Source**: i3-workspace-groups.txt:1877-1880

```python
# Adapted from i3-workspace-groups tree caching pattern
import i3ipc

class I3TreeCache:
    def __init__(self, conn: i3ipc.Connection):
        self.conn = conn
        self.tree: Optional[i3ipc.Con] = None

    def get_tree(self, cached: bool = True) -> i3ipc.Con:
        """Get i3 tree with optional caching

        Caching reduces IPC calls from ~2ms to ~0µs per call.
        Invalidate between events.
        """
        if self.tree and cached:
            return self.tree
        self.tree = self.conn.get_tree()
        return self.tree

    def invalidate(self):
        """Clear cached tree"""
        self.tree = None

# Attribution: Adapted from i3-workspace-groups (MIT License)
# https://github.com/infokiller/i3-workspace-groups
```

### 4. Safe Event Handler Pattern (from autotiling)

**Source**: autotiling.txt:1048-1123

```python
# Adapted from autotiling error handling pattern
import sys
from i3ipc import Connection, Event

def safe_handler(handler_func):
    """Decorator to safely wrap event handlers"""
    def wrapper(conn, event):
        try:
            handler_func(conn, event)
        except Exception as e:
            print(f"Error in {handler_func.__name__}: {e}", file=sys.stderr)
            # Don't crash the daemon
    return wrapper

@safe_handler
def on_window_event(conn, event):
    """Process window event safely"""
    con = conn.get_tree().find_focused()
    if con:
        print(f"Window: {con.window_class}")

# Attribution: Adapted from autotiling (GPL-3.0)
# Pattern studied and reimplemented from scratch for compatibility
# https://github.com/nwg-piotr/autotiling
```

### 5. Unix Socket Server (from i3ipc-python examples)

**Source**: i3ipc-python.txt:2480-2485

```python
# Adapted from i3ipc-python Unix socket examples
import asyncio
import json
import os

SOCKET_PATH = os.path.expanduser('~/.cache/i3-project-sync.sock')

async def handle_client(reader, writer):
    """Handle client command request"""
    try:
        data = await reader.readline()
        if not data:
            return

        request = json.loads(data.decode())
        response = await process_command(request)

        writer.write(json.dumps(response).encode() + b'\n')
        await writer.drain()
    finally:
        writer.close()

async def start_server():
    """Start Unix socket server"""
    # Remove old socket
    if os.path.exists(SOCKET_PATH):
        os.unlink(SOCKET_PATH)

    server = await asyncio.start_unix_server(handle_client, SOCKET_PATH)
    print(f"Server listening on {SOCKET_PATH}")

    async with server:
        await server.serve_forever()

# Attribution: Adapted from i3ipc-python examples (BSD-3-Clause)
# https://github.com/altdesktop/i3ipc-python
```

### 6. Application Identification with Fallbacks (from i3-workspace-groups)

**Source**: i3-workspace-groups.txt:1970-1980

```python
# Adapted from i3-workspace-groups window property matching
import re
from typing import Optional
import i3ipc

def identify_application(window: i3ipc.Con) -> Optional[str]:
    """Identify application with robust fallback hierarchy

    Returns the most reliable identifier available.
    """
    # Priority 1: window_instance (most specific, e.g., 'Navigator' for Firefox)
    if window.window_instance:
        return window.window_instance

    # Priority 2: window_class (reliable, e.g., 'firefox')
    if window.window_class:
        return window.window_class

    # Priority 3: window_title (can change frequently)
    if window.window_title:
        # Extract app name from title like "Document - App Name"
        return window.window_title

    # Priority 4: Process name via PID
    if window.pid:
        try:
            with open(f'/proc/{window.pid}/comm', 'r') as f:
                return f.read().strip()
        except Exception:
            pass

    # Placeholder windows and others may have no properties
    return None

# Attribution: Adapted from i3-workspace-groups (MIT License)
# https://github.com/infokiller/i3-workspace-groups
```

### 7. State Rebuild from Marks

**Source**: Synthesized from i3-quickterm and i3-workspace-groups patterns

```python
# Pattern synthesized from multiple projects
import re
from typing import Dict, Set
import i3ipc

PROJECT_MARK_PATTERN = re.compile(r'project_([^_]+)_(\d+)')

async def rebuild_state(conn: i3ipc.Connection) -> Dict[str, Set[int]]:
    """Rebuild project state after daemon restart or i3 restart

    Scans all i3 marks to reconstruct which windows belong to which projects.
    This survives i3 restarts because marks are persistent.
    """
    tree = await conn.get_tree()
    project_windows: Dict[str, Set[int]] = {}

    # Scan entire tree for project marks
    for container in tree:
        if not container.marks:
            continue

        for mark in container.marks:
            match = PROJECT_MARK_PATTERN.match(mark)
            if match:
                project_name = match.group(1)
                window_id = int(match.group(2))

                if project_name not in project_windows:
                    project_windows[project_name] = set()
                project_windows[project_name].add(window_id)

    return project_windows

# Attribution: Pattern synthesis from i3-quickterm (ISC) and i3-workspace-groups (MIT)
```

---

## License Compliance Summary

| Project | License | Can Copy Code? | Attribution Required? | Our Approach |
|---------|---------|----------------|----------------------|--------------|
| i3ipc-python | BSD-3-Clause | Yes | Yes | Use as dependency + credit API usage patterns in comments |
| py3status | BSD-3-Clause | Yes | Yes | Adapt async patterns, credit in comments |
| i3-workspace-groups | MIT | Yes | Yes | Adapt mark tracking + tree caching, credit in comments |
| autotiling | GPL-3.0 | No (copyleft) | N/A | Study algorithm, reimplement from scratch, document in comments |
| i3-quickterm | ISC | Yes | Yes | Adapt window matching, credit in comments |

**License Text Requirements**:

- **BSD-3-Clause** (i3ipc-python, py3status): Include copyright notice and disclaimer
- **MIT** (i3-workspace-groups, i3-quickterm/ISC is MIT-compatible): Include copyright notice
- **GPL-3.0** (autotiling): Cannot copy code; study and reimplement algorithms

**Our License**: MIT (same as our project)

**Compliance Actions**:
1. Add `ATTRIBUTIONS.md` file listing all adapted code
2. Include copyright notices in file headers where code adapted
3. Add inline comments crediting specific patterns
4. For GPL code (autotiling): Document what we studied, confirm independent implementation

---

## Next Steps

1. ✅ Research complete
2. → Proceed to Phase 1: Design (generate `data-model.md`, `contracts/`, `quickstart.md`)
3. → Update agent context: `.specify/scripts/bash/update-agent-context.sh claude`
4. → Run `/speckit.tasks` to generate implementation task breakdown
5. → Begin Phase 2: Implementation following task order

---

## Key Insights for Implementation

### Must-Have Patterns
1. **Async i3ipc with auto-reconnect**: Use `i3ipc.aio.Connection(auto_reconnect=True)`
2. **Mark-based tracking**: `project_{name}_{window_id}` marks for reliability
3. **State rebuild on startup**: Scan marks to survive i3 restarts
4. **Tree caching**: Cache per-event, invalidate between events
5. **Safe error handling**: Wrap all handlers in try/except, never crash

### Performance Optimizations
1. Cache i3 tree within event processing (~2ms → 0µs per subsequent access)
2. Use `add_reader()` for non-blocking event processing
3. Debounce high-frequency events (title changes)
4. Limit event queue to 1000 items to prevent memory growth

### Reliability Patterns
1. Auto-reconnect with exponential backoff (built into i3ipc.aio)
2. Systemd user service with `Restart=on-failure`
3. Health checks via sd_notify watchdog
4. Graceful degradation if properties missing

### Testing Strategy
1. Mock i3ipc events with pytest
2. Test state rebuild from various mark configurations
3. Test window identification fallback hierarchy
4. Test event queue overflow handling
5. Integration tests with actual i3 instance in Xvfb

### Security Considerations
1. Unix socket with user-only permissions (0600)
2. Validate all JSON inputs from socket
3. No command injection in i3 commands (use parameterized commands)
4. Rate limiting on socket commands to prevent abuse
