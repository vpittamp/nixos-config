"""Mock i3 IPC fixtures for testing event subscriptions (Feature 039: T014)."""

from typing import Any, Callable, Dict, List, Optional
from dataclasses import dataclass, field
from datetime import datetime
import asyncio


@dataclass
class MockI3Event:
    """Mock i3 event for testing."""
    event_type: str  # "window", "workspace", "output", "tick"
    change: str  # "new", "close", "focus", etc.
    container: Optional[Any] = None
    current: Optional[Any] = None
    old: Optional[Any] = None


@dataclass
class MockI3Container:
    """Mock i3 container (window) for testing."""
    id: int
    window: int  # X11 window ID
    name: str  # Window title
    window_class: str = ""
    window_instance: str = ""
    pid: int = -1
    focused: bool = False
    floating: str = "auto_off"  # "user_on", "auto_on", or "user_off", "auto_off"
    workspace: Optional[str] = None
    marks: List[str] = field(default_factory=list)
    rect: Dict[str, int] = field(default_factory=lambda: {"x": 0, "y": 0, "width": 800, "height": 600})


@dataclass
class MockI3Workspace:
    """Mock i3 workspace for testing."""
    num: int
    name: str
    visible: bool = False
    focused: bool = False
    urgent: bool = False
    output: str = "HDMI-1"
    rect: Dict[str, int] = field(default_factory=lambda: {"x": 0, "y": 0, "width": 1920, "height": 1080})


@dataclass
class MockI3Output:
    """Mock i3 output (monitor) for testing."""
    name: str
    active: bool = True
    primary: bool = False
    current_workspace: Optional[str] = None
    rect: Dict[str, int] = field(default_factory=lambda: {"x": 0, "y": 0, "width": 1920, "height": 1080})


class MockI3Connection:
    """Mock i3ipc.Connection for testing without real i3."""

    def __init__(self):
        """Initialize mock connection."""
        self._event_handlers: Dict[str, List[Callable]] = {}
        self._subscriptions: List[str] = []
        self._windows: Dict[int, MockI3Container] = {}
        self._workspaces: Dict[int, MockI3Workspace] = {}
        self._outputs: Dict[str, MockI3Output] = {}
        self._marks: List[str] = []

    def on(self, event_type: str, handler: Callable) -> None:
        """Register event handler."""
        if event_type not in self._event_handlers:
            self._event_handlers[event_type] = []
        self._event_handlers[event_type].append(handler)

    async def subscribe(self, events: List[str]) -> None:
        """Subscribe to event types."""
        self._subscriptions.extend(events)

    async def emit_event(self, event: MockI3Event) -> None:
        """Emit a mock event to registered handlers."""
        event_type_str = f"{event.event_type}::{event.change}"
        if event_type_str in self._event_handlers:
            for handler in self._event_handlers[event_type_str]:
                if asyncio.iscoroutinefunction(handler):
                    await handler(event=event, container=event.container)
                else:
                    handler(event=event, container=event.container)

    def get_tree(self) -> Any:
        """Get window tree (mock)."""
        # Return simple mock tree structure
        return type('Tree', (), {
            'find_focused': lambda: list(self._windows.values())[0] if self._windows else None,
            'descendents': lambda: list(self._windows.values())
        })()

    def get_workspaces(self) -> List[MockI3Workspace]:
        """Get all workspaces."""
        return list(self._workspaces.values())

    def get_outputs(self) -> List[MockI3Output]:
        """Get all outputs."""
        return list(self._outputs.values())

    def get_marks(self) -> List[str]:
        """Get all marks."""
        return self._marks

    def command(self, cmd: str) -> List[Any]:
        """Execute i3 command (mock)."""
        # Parse simple commands for testing
        if "mark" in cmd:
            # Extract mark name
            parts = cmd.split()
            if len(parts) >= 2:
                mark_name = parts[-1]
                if mark_name not in self._marks:
                    self._marks.append(mark_name)
        return [{"success": True}]

    # Test helper methods

    def add_window(self, container: MockI3Container) -> None:
        """Add a mock window."""
        self._windows[container.id] = container

    def add_workspace(self, workspace: MockI3Workspace) -> None:
        """Add a mock workspace."""
        self._workspaces[workspace.num] = workspace

    def add_output(self, output: MockI3Output) -> None:
        """Add a mock output."""
        self._outputs[output.name] = output

    def reset(self) -> None:
        """Reset mock connection state."""
        self._windows.clear()
        self._workspaces.clear()
        self._outputs.clear()
        self._marks.clear()
        self._event_handlers.clear()
        self._subscriptions.clear()


# Fixture factory functions

def create_ghost_window(window_id: int = 14680068, pid: int = 823199) -> MockI3Container:
    """Create Ghostty terminal window fixture."""
    return MockI3Container(
        id=window_id,
        window=window_id,
        name="vpittamp@hetzner: ~",
        window_class="com.mitchellh.ghostty",
        window_instance="ghostty",
        pid=pid,
        workspace="2:code"
    )


def create_vscode_window(window_id: int = 37748739, pid: int = 823199) -> MockI3Container:
    """Create VS Code window fixture (shared PID)."""
    return MockI3Container(
        id=window_id,
        window=window_id,
        name="stacks - nixos - Visual Studio Code",
        window_class="Code",
        window_instance="code",
        pid=pid,
        workspace="2:code"
    )


def create_firefox_window(window_id: int = 12345678) -> MockI3Container:
    """Create Firefox browser window fixture."""
    return MockI3Container(
        id=window_id,
        window=window_id,
        name="Mozilla Firefox",
        window_class="firefox",
        window_instance="Navigator",
        pid=100001,
        workspace="1:web"
    )


def create_workspace(num: int, name: str, output: str = "HDMI-1", visible: bool = False) -> MockI3Workspace:
    """Create workspace fixture."""
    return MockI3Workspace(
        num=num,
        name=name,
        visible=visible,
        output=output
    )


def create_output(name: str = "HDMI-1", active: bool = True, primary: bool = True) -> MockI3Output:
    """Create output (monitor) fixture."""
    return MockI3Output(
        name=name,
        active=active,
        primary=primary
    )
