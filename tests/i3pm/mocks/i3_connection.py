"""Mock i3 IPC connection for isolated testing.

Provides mock i3 window tree and workspace management without requiring i3.
"""

from typing import List, Dict, Any, Optional
from dataclasses import dataclass, field


@dataclass
class MockWindow:
    """Mock i3 window node."""
    name: str
    window_class: str
    window_id: int
    workspace: str = "1"
    marks: List[str] = field(default_factory=list)
    geometry: Dict[str, int] = field(default_factory=lambda: {"width": 1920, "height": 1080, "x": 0, "y": 0})

    def to_i3_dict(self) -> Dict[str, Any]:
        """Convert to i3 IPC format."""
        return {
            "name": self.name,
            "window": self.window_id,
            "window_properties": {"class": self.window_class},
            "marks": self.marks,
            "rect": self.geometry,
            "nodes": [],
            "floating_nodes": []
        }


@dataclass
class MockWorkspace:
    """Mock i3 workspace."""
    name: str
    num: int
    output: str = "primary"
    visible: bool = True
    focused: bool = False
    windows: List[MockWindow] = field(default_factory=list)

    def to_i3_dict(self) -> Dict[str, Any]:
        """Convert to i3 IPC format."""
        return {
            "name": self.name,
            "num": self.num,
            "output": self.output,
            "visible": self.visible,
            "focused": self.focused,
            "type": "workspace",
            "nodes": [w.to_i3_dict() for w in self.windows],
            "floating_nodes": []
        }


@dataclass
class MockOutput:
    """Mock i3 output/monitor."""
    name: str
    active: bool = True
    primary: bool = False
    current_workspace: Optional[str] = None
    rect: Dict[str, int] = field(default_factory=lambda: {"width": 1920, "height": 1080, "x": 0, "y": 0})

    def to_i3_dict(self) -> Dict[str, Any]:
        """Convert to i3 IPC format."""
        return {
            "name": self.name,
            "active": self.active,
            "primary": self.primary,
            "current_workspace": self.current_workspace,
            "rect": self.rect
        }


class MockI3Connection:
    """Mock i3 IPC connection."""

    def __init__(self):
        """Initialize mock i3 connection."""
        self.workspaces: List[MockWorkspace] = []
        self.outputs: List[MockOutput] = []
        self.commands_executed: List[str] = []
        self.subscribed_events: List[str] = []

        # Setup default state
        self._setup_default_state()

    def _setup_default_state(self):
        """Setup default workspace and output configuration."""
        # Default outputs
        self.outputs = [
            MockOutput(name="primary", active=True, primary=True, current_workspace="1"),
            MockOutput(name="HDMI-1", active=True, primary=False, current_workspace="3")
        ]

        # Default workspaces
        self.workspaces = [
            MockWorkspace(name="1", num=1, output="primary", visible=True, focused=True),
            MockWorkspace(name="2", num=2, output="primary", visible=False),
            MockWorkspace(name="3", num=3, output="HDMI-1", visible=True),
        ]

    async def command(self, cmd: str) -> List[Dict[str, Any]]:
        """Execute i3 command.

        Args:
            cmd: i3 command string

        Returns:
            List of command results
        """
        self.commands_executed.append(cmd)

        # Parse and handle common commands
        if cmd.startswith("exec"):
            return [{"success": True}]
        elif cmd.startswith("workspace"):
            return [{"success": True}]
        elif cmd.startswith("["):
            # Criteria command (e.g., [class="Code"] move to workspace 1)
            return [{"success": True}]
        else:
            return [{"success": True}]

    async def get_tree(self) -> Any:
        """Get window tree.

        Returns:
            Mock i3 tree structure
        """
        # Simple mock tree class
        class MockTree:
            def __init__(self, workspaces):
                self.workspaces = workspaces

            def find_classed(self, window_class: str) -> List[Any]:
                """Find windows by class."""
                results = []
                for ws in self.workspaces:
                    for window in ws.windows:
                        if window.window_class == window_class:
                            results.append(window)
                return results

            def find_marked(self, mark: str) -> List[Any]:
                """Find windows by mark."""
                results = []
                for ws in self.workspaces:
                    for window in ws.windows:
                        if mark in window.marks:
                            results.append(window)
                return results

        return MockTree(self.workspaces)

    async def get_workspaces(self) -> List[Dict[str, Any]]:
        """Get workspace list.

        Returns:
            List of workspace dicts
        """
        return [ws.to_i3_dict() for ws in self.workspaces]

    async def get_outputs(self) -> List[Dict[str, Any]]:
        """Get output list.

        Returns:
            List of output dicts
        """
        return [output.to_i3_dict() for output in self.outputs]

    async def subscribe(self, events: List[str]) -> None:
        """Subscribe to i3 events.

        Args:
            events: Event types to subscribe to
        """
        self.subscribed_events.extend(events)

    def add_window(self, workspace_num: int, window: MockWindow) -> None:
        """Add window to workspace.

        Args:
            workspace_num: Workspace number
            window: Window to add
        """
        for ws in self.workspaces:
            if ws.num == workspace_num:
                ws.windows.append(window)
                break

    def remove_window(self, window_id: int) -> None:
        """Remove window by ID.

        Args:
            window_id: Window ID to remove
        """
        for ws in self.workspaces:
            ws.windows = [w for w in ws.windows if w.window_id != window_id]

    def clear_commands(self) -> None:
        """Clear captured commands."""
        self.commands_executed.clear()

    def get_commands_by_prefix(self, prefix: str) -> List[str]:
        """Get commands starting with prefix.

        Args:
            prefix: Command prefix to filter by

        Returns:
            List of matching commands
        """
        return [cmd for cmd in self.commands_executed if cmd.startswith(prefix)]
