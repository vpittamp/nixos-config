"""Mock i3 IPC connection for testing."""

from typing import List, Dict, Any, Optional
from dataclasses import dataclass, field
from unittest.mock import AsyncMock


@dataclass
class MockRect:
    """Mock i3 Rect object."""
    x: int = 0
    y: int = 0
    width: int = 1920
    height: int = 1080


@dataclass
class MockWindowProperties:
    """Mock i3 window properties."""
    class_: str = "Test"
    instance: str = "test"
    title: str = "Test Window"
    role: str = "browser"
    window_type: str = "normal"


@dataclass
class MockCon:
    """Mock i3 container/window object."""
    id: int = 12345
    name: str = "Test Window"
    type: str = "con"
    window: Optional[int] = 67890
    window_class: str = "Test"
    window_properties: MockWindowProperties = field(default_factory=MockWindowProperties)
    rect: MockRect = field(default_factory=MockRect)
    marks: List[str] = field(default_factory=list)
    workspace: int = 1
    
    def ipc_data(self) -> Dict[str, Any]:
        """Return i3 IPC compatible dict."""
        return {
            "id": self.id,
            "name": self.name,
            "type": self.type,
            "window": self.window,
            "window_properties": {
                "class": self.window_properties.class_,
                "instance": self.window_properties.instance,
                "title": self.window_properties.title,
                "role": self.window_properties.role,
                "window_type": self.window_properties.window_type,
            },
            "rect": {
                "x": self.rect.x,
                "y": self.rect.y,
                "width": self.rect.width,
                "height": self.rect.height,
            },
            "marks": self.marks,
        }


@dataclass
class MockOutput:
    """Mock i3 output object."""
    name: str = "DP-1"
    active: bool = True
    primary: bool = True
    rect: MockRect = field(default_factory=MockRect)
    
    def ipc_data(self) -> Dict[str, Any]:
        """Return i3 IPC compatible dict."""
        return {
            "name": self.name,
            "active": self.active,
            "primary": self.primary,
            "rect": {
                "x": self.rect.x,
                "y": self.rect.y,
                "width": self.rect.width,
                "height": self.rect.height,
            },
        }


@dataclass
class MockWorkspace:
    """Mock i3 workspace object."""
    num: int = 1
    name: str = "1"
    output: str = "DP-1"
    focused: bool = False
    visible: bool = True
    
    def ipc_data(self) -> Dict[str, Any]:
        """Return i3 IPC compatible dict."""
        return {
            "num": self.num,
            "name": self.name,
            "output": self.output,
            "focused": self.focused,
            "visible": self.visible,
        }


class MockI3Connection:
    """Mock i3ipc.aio.Connection for testing."""
    
    def __init__(self):
        self.windows: List[MockCon] = []
        self.outputs: List[MockOutput] = [MockOutput()]
        self.workspaces: List[MockWorkspace] = [MockWorkspace(num=i, name=str(i)) for i in range(1, 10)]
        self.marks: List[str] = []
        self.command_history: List[str] = []
        self.event_handlers: Dict[str, List] = {}
        
    async def get_tree(self) -> MockCon:
        """Mock GET_TREE command."""
        root = MockCon(type="root", window=None)
        # Return mock tree structure
        return root
    
    async def get_outputs(self) -> List[MockOutput]:
        """Mock GET_OUTPUTS command."""
        return self.outputs
    
    async def get_workspaces(self) -> List[MockWorkspace]:
        """Mock GET_WORKSPACES command."""
        return self.workspaces
    
    async def get_marks(self) -> List[str]:
        """Mock GET_MARKS command."""
        return self.marks
    
    async def command(self, cmd: str) -> List[Dict[str, Any]]:
        """Mock RUN_COMMAND."""
        self.command_history.append(cmd)
        return [{"success": True}]
    
    def on(self, event: str, handler):
        """Register event handler."""
        if event not in self.event_handlers:
            self.event_handlers[event] = []
        self.event_handlers[event].append(handler)
    
    async def main(self):
        """Mock event loop main."""
        pass
    
    async def __aenter__(self):
        """Async context manager entry."""
        return self
    
    async def __aexit__(self, exc_type, exc_val, exc_tb):
        """Async context manager exit."""
        pass


def create_mock_i3_connection(**kwargs) -> MockI3Connection:
    """Factory function to create mock i3 connection with custom state."""
    conn = MockI3Connection()
    
    # Apply overrides
    if "outputs" in kwargs:
        conn.outputs = kwargs["outputs"]
    if "workspaces" in kwargs:
        conn.workspaces = kwargs["workspaces"]
    if "windows" in kwargs:
        conn.windows = kwargs["windows"]
    if "marks" in kwargs:
        conn.marks = kwargs["marks"]
    
    return conn
