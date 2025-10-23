"""
Mock i3 IPC connection for testing

Feature 030: Production Readiness
Task T020: Mock i3 fixtures

Provides mock implementations of i3ipc classes for isolated testing
without requiring a running i3 instance.
"""

from typing import List, Dict, Any, Optional, Callable
from dataclasses import dataclass, field
from unittest.mock import Mock


@dataclass
class MockI3Window:
    """Mock i3 window node"""
    id: int
    name: str
    window_class: str
    window_instance: str
    window_role: str = ""
    window_type: str = "normal"
    window: int = 0  # X window ID
    focused: bool = False
    urgent: bool = False
    marks: List[str] = field(default_factory=list)
    rect: Dict[str, int] = field(default_factory=lambda: {"x": 0, "y": 0, "width": 800, "height": 600})
    floating: str = "auto_off"
    scratchpad_state: str = "none"

    # Parent references
    workspace: Optional[str] = None
    output: Optional[str] = None

    def __post_init__(self):
        if self.window == 0:
            self.window = self.id * 100  # Generate fake X window ID


@dataclass
class MockI3Workspace:
    """Mock i3 workspace node"""
    num: int
    name: str
    visible: bool = False
    focused: bool = False
    urgent: bool = False
    output: str = "HDMI-0"
    windows: List[MockI3Window] = field(default_factory=list)

    def __post_init__(self):
        # Set parent references for windows
        for window in self.windows:
            window.workspace = self.name
            window.output = self.output


@dataclass
class MockI3Output:
    """Mock i3 output (monitor) node"""
    name: str
    active: bool = True
    primary: bool = False
    current_workspace: Optional[str] = None
    rect: Dict[str, int] = field(default_factory=lambda: {"x": 0, "y": 0, "width": 1920, "height": 1080})
    workspaces: List[MockI3Workspace] = field(default_factory=list)


class MockI3Tree:
    """
    Mock i3 tree structure

    Provides a simplified tree that mimics i3ipc.Con structure
    for testing layout capture and window queries.
    """

    def __init__(self, outputs: List[MockI3Output] = None):
        self.outputs = outputs or []
        self._focused_window: Optional[MockI3Window] = None

    def find_focused(self) -> Optional[MockI3Window]:
        """Find focused window"""
        if self._focused_window:
            return self._focused_window

        # Find first focused window
        for output in self.outputs:
            for workspace in output.workspaces:
                for window in workspace.windows:
                    if window.focused:
                        return window
        return None

    def find_by_id(self, window_id: int) -> Optional[MockI3Window]:
        """Find window by ID"""
        for output in self.outputs:
            for workspace in output.workspaces:
                for window in workspace.windows:
                    if window.id == window_id:
                        return window
        return None

    def find_marked(self, mark: str) -> List[MockI3Window]:
        """Find windows with specific mark"""
        results = []
        for output in self.outputs:
            for workspace in output.workspaces:
                for window in workspace.windows:
                    if mark in window.marks:
                        results.append(window)
        return results

    def workspaces(self) -> List[MockI3Workspace]:
        """Get all workspaces"""
        result = []
        for output in self.outputs:
            result.extend(output.workspaces)
        return result

    def leaves(self) -> List[MockI3Window]:
        """Get all window nodes (leaves)"""
        result = []
        for output in self.outputs:
            for workspace in output.workspaces:
                result.extend(workspace.windows)
        return result


class MockI3Connection:
    """
    Mock i3ipc.Connection for testing

    Simulates i3 IPC without requiring running i3 instance.
    Allows testing of event handling, queries, and commands.
    """

    def __init__(self, tree: Optional[MockI3Tree] = None):
        self.tree = tree or MockI3Tree()
        self.event_handlers: Dict[str, List[Callable]] = {}
        self.command_log: List[str] = []
        self._connected = True

    def get_tree(self) -> MockI3Tree:
        """Get window tree"""
        return self.tree

    def get_workspaces(self) -> List[Dict[str, Any]]:
        """Get workspace list"""
        return [
            {
                "num": ws.num,
                "name": ws.name,
                "visible": ws.visible,
                "focused": ws.focused,
                "urgent": ws.urgent,
                "output": ws.output,
            }
            for ws in self.tree.workspaces()
        ]

    def get_outputs(self) -> List[Dict[str, Any]]:
        """Get output list"""
        return [
            {
                "name": output.name,
                "active": output.active,
                "primary": output.primary,
                "current_workspace": output.current_workspace,
                "rect": output.rect,
            }
            for output in self.tree.outputs
        ]

    def command(self, cmd: str) -> List[Dict[str, Any]]:
        """Execute i3 command"""
        self.command_log.append(cmd)
        return [{"success": True}]

    def on(self, event_type: str, handler: Callable) -> None:
        """Register event handler"""
        if event_type not in self.event_handlers:
            self.event_handlers[event_type] = []
        self.event_handlers[event_type].append(handler)

    def main(self) -> None:
        """Start event loop (no-op for mock)"""
        pass

    def main_quit(self) -> None:
        """Stop event loop (no-op for mock)"""
        pass

    def trigger_event(self, event_type: str, event_data: Dict[str, Any]) -> None:
        """
        Trigger event handlers for testing

        Args:
            event_type: Event type (e.g., "window::new", "workspace::focus")
            event_data: Event data to pass to handlers
        """
        handlers = self.event_handlers.get(event_type, [])
        for handler in handlers:
            handler(self, event_data)

    @property
    def connected(self) -> bool:
        """Connection status"""
        return self._connected

    def disconnect(self) -> None:
        """Disconnect"""
        self._connected = False


def create_mock_window(
    window_id: int,
    name: str,
    window_class: str,
    workspace: str = "1",
    output: str = "HDMI-0",
    focused: bool = False,
    marks: List[str] = None,
    **kwargs
) -> MockI3Window:
    """
    Helper to create mock window with sensible defaults

    Args:
        window_id: Window ID
        name: Window title
        window_class: Window class (WM_CLASS)
        workspace: Workspace name
        output: Output name
        focused: Whether window is focused
        marks: Window marks
        **kwargs: Additional window properties

    Returns:
        MockI3Window instance
    """
    return MockI3Window(
        id=window_id,
        name=name,
        window_class=window_class,
        window_instance=kwargs.get("window_instance", window_class.lower()),
        workspace=workspace,
        output=output,
        focused=focused,
        marks=marks or [],
        **{k: v for k, v in kwargs.items() if k != "window_instance"}
    )


def create_simple_tree() -> MockI3Tree:
    """Create simple tree with 1 output, 2 workspaces, 3 windows"""
    output = MockI3Output(
        name="HDMI-0",
        primary=True,
        current_workspace="1",
        workspaces=[
            MockI3Workspace(
                num=1,
                name="1",
                visible=True,
                focused=True,
                output="HDMI-0",
                windows=[
                    create_mock_window(1, "Terminal 1", "Ghostty", focused=True),
                    create_mock_window(2, "VS Code", "Code"),
                ]
            ),
            MockI3Workspace(
                num=2,
                name="2",
                visible=False,
                focused=False,
                output="HDMI-0",
                windows=[
                    create_mock_window(3, "Firefox", "firefox"),
                ]
            ),
        ]
    )

    return MockI3Tree(outputs=[output])


def create_multi_monitor_tree() -> MockI3Tree:
    """Create tree with 2 outputs, 4 workspaces, 6 windows"""
    output1 = MockI3Output(
        name="HDMI-0",
        primary=True,
        current_workspace="1",
        workspaces=[
            MockI3Workspace(
                num=1,
                name="1",
                visible=True,
                focused=True,
                output="HDMI-0",
                windows=[
                    create_mock_window(1, "Terminal", "Ghostty", focused=True, marks=["project:nixos"]),
                    create_mock_window(2, "VS Code", "Code", marks=["project:nixos"]),
                ]
            ),
            MockI3Workspace(
                num=2,
                name="2",
                visible=False,
                output="HDMI-0",
                windows=[
                    create_mock_window(3, "Firefox", "firefox"),
                ]
            ),
        ]
    )

    output2 = MockI3Output(
        name="DP-0",
        primary=False,
        current_workspace="3",
        workspaces=[
            MockI3Workspace(
                num=3,
                name="3",
                visible=True,
                output="DP-0",
                windows=[
                    create_mock_window(4, "Slack", "Slack"),
                    create_mock_window(5, "Discord", "discord"),
                ]
            ),
            MockI3Workspace(
                num=4,
                name="4",
                visible=False,
                output="DP-0",
                windows=[
                    create_mock_window(6, "Spotify", "spotify"),
                ]
            ),
        ]
    )

    return MockI3Tree(outputs=[output1, output2])
