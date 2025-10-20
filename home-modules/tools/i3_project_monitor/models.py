"""Data models for i3 project system monitor tool.

This module defines all dataclasses used by the monitor tool for displaying
daemon state, events, and i3 tree structure.
"""

from dataclasses import dataclass, field
from datetime import datetime
from typing import Any, Dict, List, Optional


@dataclass
class MonitorState:
    """Top-level monitor state for live display mode."""

    # Connection
    daemon_connected: bool
    daemon_uptime_seconds: float
    connection_attempts: int = 0
    last_connection_error: Optional[str] = None

    # Active project
    active_project: Optional[str] = None
    is_global_mode: bool = True

    # Statistics
    total_windows: int = 0
    tracked_windows: int = 0  # Windows with project marks
    total_events_processed: int = 0
    error_count: int = 0

    # System info
    detected_monitors: List['MonitorEntry'] = field(default_factory=list)
    active_workspaces: List[str] = field(default_factory=list)

    # Timestamps
    state_updated_at: datetime = field(default_factory=datetime.now)

    def __post_init__(self) -> None:
        """Validate monitor state."""
        if self.daemon_uptime_seconds < 0:
            raise ValueError(f"Invalid daemon_uptime_seconds: {self.daemon_uptime_seconds}")
        if self.tracked_windows > self.total_windows:
            raise ValueError(f"tracked_windows ({self.tracked_windows}) > total_windows ({self.total_windows})")


@dataclass
class WindowEntry:
    """Window information for display."""

    # Identifiers
    window_id: int
    con_id: int

    # Window properties
    window_class: str
    window_title: str
    window_instance: str

    # Project tracking
    project: Optional[str] = None
    marks: List[str] = field(default_factory=list)

    # Location
    workspace: str = ""
    output: str = ""  # Monitor name
    floating: bool = False

    # State
    focused: bool = False
    visible: bool = True  # Not in scratchpad

    # Timestamps
    created: datetime = field(default_factory=datetime.now)
    last_focus: Optional[datetime] = None

    def __post_init__(self) -> None:
        """Validate window entry."""
        if self.window_id <= 0:
            raise ValueError(f"Invalid window_id: {self.window_id}")
        if self.con_id <= 0:
            raise ValueError(f"Invalid con_id: {self.con_id}")


@dataclass
class MonitorEntry:
    """Monitor/output information for display."""

    # Identifiers
    name: str  # e.g., "eDP-1", "HDMI-1"

    # Properties
    width: int
    height: int
    refresh_rate: float  # Hz
    primary: bool

    # Workspace assignments
    assigned_workspaces: List[int] = field(default_factory=list)  # e.g., [1, 2] for primary
    active_workspace: Optional[int] = None  # Currently visible workspace

    # State
    connected: bool = True
    enabled: bool = True

    def __post_init__(self) -> None:
        """Validate monitor entry."""
        if not self.name:
            raise ValueError("Monitor name cannot be empty")
        if self.width <= 0 or self.height <= 0:
            raise ValueError(f"Invalid resolution: {self.width}x{self.height}")
        if self.refresh_rate <= 0:
            raise ValueError(f"Invalid refresh_rate: {self.refresh_rate}")
        if self.active_workspace is not None and self.active_workspace not in self.assigned_workspaces:
            raise ValueError(f"active_workspace {self.active_workspace} not in assigned_workspaces")


@dataclass
class EventEntry:
    """Event log entry for event stream display."""

    # Event metadata
    event_id: int  # Incremental ID for event ordering
    event_type: str  # "window::new", "window::close", "tick", "workspace::init"
    timestamp: datetime

    # Event payload (varies by type)
    window_id: Optional[int] = None
    window_class: Optional[str] = None
    workspace_name: Optional[str] = None
    project_name: Optional[str] = None
    tick_payload: Optional[str] = None

    # Processing info
    processing_duration_ms: float = 0.0  # Time daemon took to handle event
    error: Optional[str] = None  # If event processing failed

    def __post_init__(self) -> None:
        """Validate event entry."""
        if self.event_id < 0:
            raise ValueError(f"Invalid event_id: {self.event_id}")
        if not self.event_type:
            raise ValueError("event_type cannot be empty")
        if self.processing_duration_ms < 0:
            raise ValueError(f"Invalid processing_duration_ms: {self.processing_duration_ms}")

    @classmethod
    def from_json(cls, data: Dict[str, Any]) -> 'EventEntry':
        """Create EventEntry from JSON-RPC response data.

        Args:
            data: Event data from daemon get_events response

        Returns:
            EventEntry instance
        """
        # Parse ISO timestamp
        timestamp = datetime.fromisoformat(data["timestamp"])

        return cls(
            event_id=data["event_id"],
            event_type=data["event_type"],
            timestamp=timestamp,
            window_id=data.get("window_id"),
            window_class=data.get("window_class"),
            workspace_name=data.get("workspace_name"),
            project_name=data.get("project_name"),
            tick_payload=data.get("tick_payload"),
            processing_duration_ms=data.get("processing_duration_ms", 0.0),
            error=data.get("error"),
        )


@dataclass
class EventSubscription:
    """Active event subscription state."""

    # Subscription filter
    event_types: List[str] = field(default_factory=list)  # Empty list = all types

    # Buffer configuration
    buffer_size: int = 100  # Local buffer for smooth display updates

    # State
    subscribed_at: datetime = field(default_factory=datetime.now)
    events_received: int = 0
    last_event_at: Optional[datetime] = None

    # Connection
    connection_active: bool = False
    reconnect_attempts: int = 0

    def __post_init__(self) -> None:
        """Validate subscription."""
        if self.buffer_size <= 0:
            raise ValueError(f"Invalid buffer_size: {self.buffer_size}")


@dataclass
class TreeNode:
    """i3 window tree node for tree inspection mode."""

    # Node identity
    id: int
    type: str  # "root", "output", "workspace", "con", "floating_con"

    # Hierarchy
    parent_id: Optional[int]
    child_ids: List[int] = field(default_factory=list)

    # Properties
    name: str = ""
    marks: List[str] = field(default_factory=list)
    focused: bool = False
    visible: bool = True

    # Container-specific (if type == "con")
    window_id: Optional[int] = None
    window_class: Optional[str] = None
    window_title: Optional[str] = None
    window_role: Optional[str] = None

    # Workspace-specific (if type == "workspace")
    workspace_num: Optional[int] = None
    workspace_output: Optional[str] = None

    # Layout
    layout: str = "splith"  # "splith", "splitv", "tabbed", "stacked"
    border: str = "normal"  # "normal", "pixel", "none"
    floating: str = "auto_off"  # "auto_off", "auto_on", "user_off", "user_on"

    # Geometry
    rect: Dict[str, int] = field(default_factory=lambda: {"x": 0, "y": 0, "width": 0, "height": 0})

    def __post_init__(self) -> None:
        """Validate tree node."""
        if self.id < 0:
            raise ValueError(f"Invalid id: {self.id}")
        valid_types = {"root", "output", "workspace", "con", "floating_con", "dockarea"}
        if self.type not in valid_types:
            raise ValueError(f"Invalid type: {self.type}, must be one of {valid_types}")

    @classmethod
    def from_i3_container(cls, container: Any) -> 'TreeNode':
        """Create TreeNode from i3ipc Container object.

        Args:
            container: i3ipc Container instance

        Returns:
            TreeNode instance
        """
        return cls(
            id=container.id,
            type=container.type,
            parent_id=container.parent.id if container.parent else None,
            child_ids=[child.id for child in container.nodes + container.floating_nodes],
            name=container.name or "",
            marks=container.marks or [],
            focused=container.focused,
            visible=not container.ipc_data.get("urgent", False),  # Simplified visibility check
            window_id=container.window,
            window_class=container.window_class,
            window_title=container.name,
            window_role=container.window_role,
            workspace_num=container.num if container.type == "workspace" else None,
            workspace_output=container.ipc_data.get("output") if container.type == "workspace" else None,
            layout=container.layout,
            border=container.border,
            floating=container.floating or "auto_off",
            rect={
                "x": container.rect.x,
                "y": container.rect.y,
                "width": container.rect.width,
                "height": container.rect.height,
            }
        )


@dataclass
class ConnectionState:
    """Connection state for daemon client."""

    # Connection status
    connected: bool = False
    socket_path: str = ""

    # Retry state
    connection_attempts: int = 0
    max_retries: int = 5
    retry_delay_seconds: float = 1.0  # Exponential backoff base

    # Errors
    last_error: Optional[str] = None
    last_success_at: Optional[datetime] = None
    last_failure_at: Optional[datetime] = None

    def should_retry(self) -> bool:
        """Check if reconnection should be attempted.

        Returns:
            True if retry attempts remain
        """
        return self.connection_attempts < self.max_retries

    def get_retry_delay(self) -> float:
        """Calculate exponential backoff delay.

        Returns:
            Delay in seconds (capped at 16s)
        """
        delay = self.retry_delay_seconds * (2 ** self.connection_attempts)
        return min(delay, 16.0)  # Cap at 16 seconds
