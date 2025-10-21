# Python Development Standards

This guide details the Python development patterns, best practices, and standards for NixOS system tooling as established by the i3-project management system (Features 015, 017, 018).

## Overview

Python 3.11+ is the standard for all system tooling that requires:
- Async I/O for i3 IPC communication
- Terminal UI applications
- Event-driven architectures
- Daemon services
- Testing frameworks

## Language Version & Dependencies

### Python Version

**Required**: Python 3.11+

**Rationale**: Python 3.11 provides:
- Improved async/await performance (2x faster asyncio)
- Better error messages with precise location tracking
- TaskGroups for structured concurrency
- ExceptionGroups for better async error handling

### Standard Library Dependencies

```python
import asyncio          # Async/await patterns
import logging          # Structured logging
from dataclasses import dataclass, field  # Data models
from typing import Optional, List, Dict   # Type hints
from pathlib import Path                   # Path handling
import json                                # JSON serialization
from datetime import datetime              # Timestamps
```

### External Dependencies

**Required Libraries**:
- `i3ipc-python` (sync) / `i3ipc.aio` (async): i3 IPC communication
- `rich`: Terminal UI (tables, live displays, syntax highlighting)
- `pytest`: Testing framework
- `pytest-asyncio`: Async test support

**Optional Libraries**:
- `pydantic`: Advanced data validation (if complex validation needed)
- `click` or `argparse`: CLI argument parsing (argparse preferred for simplicity)

### NixOS Package Declaration

```nix
# home-modules/tools/<tool-name>.nix
{ config, lib, pkgs, ... }:

{
  home.packages = with pkgs; [
    (python311.withPackages (ps: with ps; [
      i3ipc          # i3 IPC library
      rich           # Terminal UI
      pytest         # Testing
      pytest-asyncio # Async tests
    ]))
  ];
}
```

## Project Structure

### Standard Module Layout

```
home-modules/tools/<tool-name>/
├── __init__.py              # Package initialization
├── __main__.py              # CLI entry point
├── models.py                # Data models (Pydantic/dataclasses)
├── daemon_client.py         # IPC client (if communicating with daemon)
├── <service>.py             # Business logic modules
├── displays/                # Terminal UI components (if applicable)
│   ├── __init__.py
│   ├── base.py             # Base display class
│   └── <mode>.py           # Display mode implementations
├── validators/              # State validation (if applicable)
│   ├── __init__.py
│   └── <validator>.py
└── README.md                # Module documentation

tests/<tool-name>/
├── unit/
│   ├── test_models.py
│   ├── test_validators.py
│   └── test_formatters.py
├── integration/
│   ├── test_daemon_client.py
│   └── test_i3_ipc.py
├── scenarios/               # End-to-end workflow tests
│   ├── test_<workflow>.py
│   └── base_scenario.py
└── fixtures/
    ├── mock_daemon.py
    └── sample_data.py
```

### CLI Entry Point Pattern

```python
# __main__.py
"""
Tool Name - Brief description

Usage:
    tool-name [options]
"""
import argparse
import asyncio
import logging
import sys
from pathlib import Path

from . import displays
from .daemon_client import DaemonClient


def parse_args() -> argparse.Namespace:
    """Parse command-line arguments."""
    parser = argparse.ArgumentParser(
        description="Tool description",
        formatter_class=argparse.RawDescriptionHelpFormatter
    )

    parser.add_argument(
        "--mode",
        choices=["live", "events", "history"],
        default="live",
        help="Display mode (default: live)"
    )

    parser.add_argument(
        "--verbose", "-v",
        action="store_true",
        help="Enable verbose logging"
    )

    return parser.parse_args()


async def main() -> int:
    """Main entry point."""
    args = parse_args()

    # Configure logging
    logging.basicConfig(
        level=logging.DEBUG if args.verbose else logging.INFO,
        format="%(asctime)s - %(name)s - %(levelname)s - %(message)s"
    )

    logger = logging.getLogger(__name__)

    try:
        # Initialize display mode
        display_class = displays.get_display_class(args.mode)
        display = display_class()

        # Run display
        await display.run()

        return 0

    except KeyboardInterrupt:
        logger.info("Interrupted by user")
        return 0

    except Exception as e:
        logger.error(f"Error: {e}", exc_info=args.verbose)
        return 1


def cli_main():
    """Synchronous wrapper for CLI."""
    sys.exit(asyncio.run(main()))


if __name__ == "__main__":
    cli_main()
```

## Async/Await Patterns

### i3 IPC Communication

**Always use async/await** for i3 IPC to prevent blocking:

```python
import i3ipc.aio

async def query_i3_state():
    """Query i3 window manager state."""
    async with i3ipc.aio.Connection() as i3:
        # Query workspaces
        workspaces = await i3.get_workspaces()

        # Query outputs
        outputs = await i3.get_outputs()

        # Query window tree
        tree = await i3.get_tree()

        return {
            "workspaces": workspaces,
            "outputs": outputs,
            "tree": tree
        }
```

### Event Subscription Pattern

```python
import i3ipc.aio
import asyncio
from typing import Callable

class EventListener:
    """Listen to i3 IPC events."""

    def __init__(self):
        self.i3 = None
        self.handlers = {}

    async def connect(self):
        """Connect to i3 IPC socket."""
        self.i3 = await i3ipc.aio.Connection().connect()

    async def subscribe(self, event_type: str, handler: Callable):
        """Subscribe to event type with handler."""
        if event_type == "window":
            self.i3.on(i3ipc.Event.WINDOW, handler)
        elif event_type == "workspace":
            self.i3.on(i3ipc.Event.WORKSPACE, handler)
        elif event_type == "output":
            self.i3.on(i3ipc.Event.OUTPUT, handler)

    async def run(self):
        """Run event loop."""
        await self.i3.main()

# Usage
async def handle_window_event(i3, event):
    """Handle window events."""
    print(f"Window event: {event.change}")

listener = EventListener()
await listener.connect()
await listener.subscribe("window", handle_window_event)
await listener.run()
```

### Daemon Client Pattern

```python
import asyncio
import json
from pathlib import Path
from typing import Dict, Any, Optional

class DaemonClient:
    """JSON-RPC client for daemon communication."""

    def __init__(self, socket_path: Path):
        self.socket_path = socket_path
        self.reader = None
        self.writer = None
        self.request_id = 0

    async def connect(self):
        """Connect to daemon socket."""
        self.reader, self.writer = await asyncio.open_unix_connection(
            str(self.socket_path)
        )

    async def disconnect(self):
        """Disconnect from daemon."""
        if self.writer:
            self.writer.close()
            await self.writer.wait_closed()

    async def call(self, method: str, params: Optional[Dict] = None) -> Any:
        """Call JSON-RPC method."""
        self.request_id += 1

        request = {
            "jsonrpc": "2.0",
            "method": method,
            "params": params or {},
            "id": self.request_id
        }

        # Send request
        self.writer.write(json.dumps(request).encode() + b"\n")
        await self.writer.drain()

        # Read response
        response_data = await self.reader.readline()
        response = json.loads(response_data.decode())

        if "error" in response:
            raise RuntimeError(response["error"]["message"])

        return response.get("result")

    async def __aenter__(self):
        await self.connect()
        return self

    async def __aexit__(self, exc_type, exc_val, exc_tb):
        await self.disconnect()

# Usage
async with DaemonClient(Path.home() / ".cache/i3-project/daemon.sock") as client:
    state = await client.call("get_state")
    print(f"Active project: {state['active_project']}")
```

### Auto-Reconnection Pattern

```python
import asyncio
from typing import Optional

class ResilientConnection:
    """Connection with automatic reconnection."""

    def __init__(self, socket_path: Path, max_retries: int = 5):
        self.socket_path = socket_path
        self.max_retries = max_retries
        self.retry_delays = [1, 2, 4, 8, 16]  # Exponential backoff
        self.client = None

    async def connect_with_retry(self) -> bool:
        """Connect with exponential backoff retry."""
        for attempt in range(self.max_retries):
            try:
                self.client = DaemonClient(self.socket_path)
                await self.client.connect()
                return True

            except Exception as e:
                if attempt < self.max_retries - 1:
                    delay = self.retry_delays[attempt]
                    print(f"Connection failed, retrying in {delay}s...")
                    await asyncio.sleep(delay)
                else:
                    print(f"Connection failed after {self.max_retries} attempts")
                    return False

        return False
```

## Data Models & Validation

### Dataclass Pattern (Preferred for Simple Models)

```python
from dataclasses import dataclass, field
from typing import Optional, List
from datetime import datetime

@dataclass
class WindowEntry:
    """Represents a tracked window."""
    window_id: int
    window_class: str
    window_title: str
    workspace: int
    project: Optional[str] = None
    marks: List[str] = field(default_factory=list)
    floating: bool = False

    def __post_init__(self):
        """Validate after initialization."""
        if self.window_id <= 0:
            raise ValueError("window_id must be positive")

        if not self.window_class:
            raise ValueError("window_class cannot be empty")

@dataclass
class EventEntry:
    """Represents a system event."""
    event_type: str
    timestamp: datetime
    window_id: Optional[int] = None
    project_name: Optional[str] = None
    payload: dict = field(default_factory=dict)

    def to_dict(self) -> dict:
        """Convert to dictionary for serialization."""
        return {
            "event_type": self.event_type,
            "timestamp": self.timestamp.isoformat(),
            "window_id": self.window_id,
            "project_name": self.project_name,
            "payload": self.payload
        }
```

### Pydantic Pattern (For Complex Validation)

```python
from pydantic import BaseModel, Field, validator
from typing import Optional, List
from datetime import datetime

class MonitorState(BaseModel):
    """Current system monitoring state."""
    active_project: Optional[str] = None
    daemon_uptime: float = Field(gt=0, description="Daemon uptime in seconds")
    tracked_windows: List[WindowEntry] = Field(default_factory=list)
    event_count: int = Field(ge=0, description="Total events processed")

    @validator("active_project")
    def validate_project_name(cls, v):
        """Validate project name format."""
        if v and (v.startswith("-") or "/" in v):
            raise ValueError("Invalid project name format")
        return v

    class Config:
        validate_assignment = True  # Validate on attribute assignment
```

## Terminal UI with Rich

### Basic Table Display

```python
from rich.console import Console
from rich.table import Table
from rich.live import Live
from rich.layout import Layout
from rich.panel import Panel
import asyncio

class LiveDisplay:
    """Live updating terminal display."""

    def __init__(self):
        self.console = Console()

    def create_window_table(self, windows: List[WindowEntry]) -> Table:
        """Create table of tracked windows."""
        table = Table(title="Tracked Windows", show_header=True)

        table.add_column("ID", style="cyan")
        table.add_column("Class", style="green")
        table.add_column("Title", style="white")
        table.add_column("Workspace", style="yellow")
        table.add_column("Project", style="magenta")

        for window in windows:
            table.add_row(
                str(window.window_id),
                window.window_class,
                window.window_title[:40],  # Truncate long titles
                str(window.workspace),
                window.project or "-"
            )

        return table

    async def run(self):
        """Run live display loop."""
        with Live(self.create_layout(), refresh_per_second=4) as live:
            while True:
                # Update data
                windows = await self.fetch_windows()

                # Update display
                live.update(self.create_window_table(windows))

                await asyncio.sleep(0.25)
```

### Event Stream Display

```python
from rich.console import Console
from rich.syntax import Syntax
from rich.panel import Panel
from collections import deque

class EventStreamDisplay:
    """Display live event stream."""

    def __init__(self, max_events: int = 100):
        self.console = Console()
        self.events = deque(maxlen=max_events)

    def display_event(self, event: EventEntry):
        """Display single event."""
        # Format timestamp
        timestamp = event.timestamp.strftime("%H:%M:%S.%f")[:-3]

        # Color by event type
        color_map = {
            "window": "cyan",
            "workspace": "green",
            "tick": "yellow",
            "output": "magenta"
        }
        color = color_map.get(event.event_type, "white")

        # Format event
        event_str = f"[{timestamp}] [{color}]{event.event_type}[/{color}]"

        if event.window_id:
            event_str += f" window={event.window_id}"

        if event.project_name:
            event_str += f" project={event.project_name}"

        self.console.print(event_str)

    async def run(self):
        """Run event stream display."""
        async for event in self.event_source():
            self.events.append(event)
            self.display_event(event)
```

## Testing Patterns

### Unit Test Pattern

```python
import pytest
from datetime import datetime
from ..models import WindowEntry, EventEntry

class TestWindowEntry:
    """Test WindowEntry model."""

    def test_valid_window(self):
        """Test creating valid window entry."""
        window = WindowEntry(
            window_id=12345,
            window_class="Alacritty",
            window_title="Terminal",
            workspace=1,
            project="nixos"
        )

        assert window.window_id == 12345
        assert window.project == "nixos"

    def test_invalid_window_id(self):
        """Test window with invalid ID raises error."""
        with pytest.raises(ValueError, match="window_id must be positive"):
            WindowEntry(
                window_id=0,
                window_class="Test",
                window_title="Test",
                workspace=1
            )
```

### Async Test Pattern

```python
import pytest
import asyncio
from ..daemon_client import DaemonClient

@pytest.mark.asyncio
async def test_daemon_connection(mock_daemon_socket):
    """Test connecting to daemon."""
    client = DaemonClient(mock_daemon_socket)

    await client.connect()

    try:
        state = await client.call("get_state")
        assert "active_project" in state
    finally:
        await client.disconnect()

@pytest.mark.asyncio
async def test_auto_reconnection():
    """Test automatic reconnection on failure."""
    connection = ResilientConnection(Path("/tmp/test.sock"))

    # Should retry and eventually succeed
    connected = await connection.connect_with_retry()
    assert connected
```

### Mock Pattern for i3 IPC

```python
# tests/fixtures/mock_i3.py
import asyncio
from typing import List, Dict

class MockI3Connection:
    """Mock i3 IPC connection for testing."""

    def __init__(self):
        self.workspaces = []
        self.outputs = []
        self.tree = None

    async def get_workspaces(self) -> List[Dict]:
        """Return mock workspaces."""
        return self.workspaces

    async def get_outputs(self) -> List[Dict]:
        """Return mock outputs."""
        return self.outputs

    async def get_tree(self) -> Dict:
        """Return mock tree."""
        return self.tree

    def set_mock_data(self, workspaces, outputs, tree):
        """Set mock data for testing."""
        self.workspaces = workspaces
        self.outputs = outputs
        self.tree = tree

# Usage in tests
@pytest.fixture
def mock_i3():
    """Provide mock i3 connection."""
    connection = MockI3Connection()
    connection.set_mock_data(
        workspaces=[{"num": 1, "name": "1", "visible": True}],
        outputs=[{"name": "HDMI-1", "active": True}],
        tree={"nodes": []}
    )
    return connection
```

## Error Handling

### Graceful Error Pattern

```python
import logging

logger = logging.getLogger(__name__)

async def safe_operation():
    """Perform operation with graceful error handling."""
    try:
        result = await risky_operation()
        return result

    except ConnectionError as e:
        logger.error(f"Connection failed: {e}")
        logger.info("Attempting reconnection...")
        # Auto-reconnect logic

    except ValueError as e:
        logger.error(f"Invalid data: {e}")
        # Return safe default
        return None

    except Exception as e:
        logger.error(f"Unexpected error: {e}", exc_info=True)
        raise  # Re-raise unexpected errors
```

### Exit Codes

```python
import sys

class ExitCode:
    """Standard exit codes."""
    SUCCESS = 0
    GENERAL_ERROR = 1
    CONNECTION_ERROR = 2
    VALIDATION_ERROR = 3
    CONFIGURATION_ERROR = 4

# Usage
if not await connect_to_daemon():
    logger.error("Failed to connect to daemon")
    sys.exit(ExitCode.CONNECTION_ERROR)
```

## Logging Standards

### Logger Configuration

```python
import logging
from pathlib import Path

def setup_logging(verbose: bool = False, log_file: Path = None):
    """Configure application logging."""
    level = logging.DEBUG if verbose else logging.INFO

    # Create formatter
    formatter = logging.Formatter(
        "%(asctime)s - %(name)s - %(levelname)s - %(message)s",
        datefmt="%Y-%m-%d %H:%M:%S"
    )

    # Console handler
    console_handler = logging.StreamHandler()
    console_handler.setLevel(level)
    console_handler.setFormatter(formatter)

    handlers = [console_handler]

    # File handler (optional)
    if log_file:
        file_handler = logging.FileHandler(log_file)
        file_handler.setLevel(logging.DEBUG)
        file_handler.setFormatter(formatter)
        handlers.append(file_handler)

    # Configure root logger
    logging.basicConfig(
        level=level,
        handlers=handlers
    )
```

### Logging Best Practices

```python
logger = logging.getLogger(__name__)

# Use appropriate log levels
logger.debug(f"Processing window ID {window_id}")  # Detailed debug info
logger.info(f"Switched to project {project_name}")  # General info
logger.warning(f"Window {window_id} not found")    # Recoverable issue
logger.error(f"Failed to connect: {error}")         # Error occurred
logger.critical(f"Daemon crashed: {error}")         # Critical failure

# Use structured logging for important events
logger.info(
    "Project switched",
    extra={
        "old_project": old_project,
        "new_project": new_project,
        "window_count": len(windows)
    }
)
```

## Performance Considerations

### Circular Buffer for Events

```python
from collections import deque
from typing import Generic, TypeVar

T = TypeVar('T')

class CircularBuffer(Generic[T]):
    """Fixed-size circular buffer for event storage."""

    def __init__(self, max_size: int = 500):
        self.buffer = deque(maxlen=max_size)

    def append(self, item: T):
        """Add item to buffer (oldest item dropped if full)."""
        self.buffer.append(item)

    def get_recent(self, count: int) -> List[T]:
        """Get most recent N items."""
        return list(self.buffer)[-count:]

    def __len__(self) -> int:
        return len(self.buffer)
```

### Async Task Management

```python
import asyncio
from typing import List

async def run_concurrent_tasks(tasks: List[asyncio.Task]):
    """Run tasks concurrently with proper error handling."""
    try:
        results = await asyncio.gather(*tasks, return_exceptions=True)

        # Check for exceptions
        for i, result in enumerate(results):
            if isinstance(result, Exception):
                logger.error(f"Task {i} failed: {result}")

        return results

    except asyncio.CancelledError:
        logger.info("Tasks cancelled")
        # Cancel all tasks
        for task in tasks:
            task.cancel()
        raise
```

## See Also

- [i3 IPC Patterns](./I3_IPC_PATTERNS.md) - i3 integration guidance
- [Constitution](../.specify/memory/constitution.md) - Python Development Standards (Principle X)
- [Feature 017 Quickstart](../specs/017-now-lets-create/quickstart.md) - Monitor tool examples
- [Feature 018 Quickstart](../specs/018-create-a-new/quickstart.md) - Testing framework examples
