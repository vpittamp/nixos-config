"""Data models for i3 project event daemon.

This module defines all dataclasses used for runtime state management,
configuration, and event processing.
"""

from dataclasses import dataclass, field
from datetime import datetime
from pathlib import Path
from typing import Any, Dict, List, Optional, Set
import i3ipc


@dataclass
class WindowInfo:
    """Information about a tracked window."""

    # Window identity
    window_id: int  # X11 window ID (from i3)
    con_id: int  # i3 container ID (internal to i3)

    # Window properties
    window_class: str  # WM_CLASS property (e.g., "Code", "ghostty")
    window_title: str  # Window title (may change dynamically)
    window_instance: str  # WM_CLASS instance

    # Application identification (US4)
    app_identifier: str  # Identified application (may differ from class for PWAs/terminal apps)

    # Project association
    project: Optional[str] = None  # Associated project name (from mark)
    marks: List[str] = field(default_factory=list)  # All i3 marks on this window

    # Position
    workspace: str = ""  # Current workspace name
    output: str = ""  # Current monitor/output name
    is_floating: bool = False  # Floating vs. tiled

    # Timestamps
    created: datetime = field(default_factory=datetime.now)
    last_focus: Optional[datetime] = None

    def __post_init__(self) -> None:
        """Validate window information."""
        if self.window_id <= 0:
            raise ValueError(f"Invalid window_id: {self.window_id}")
        if self.con_id <= 0:
            raise ValueError(f"Invalid con_id: {self.con_id}")


@dataclass
class ProjectConfig:
    """Configuration for a single project."""

    # Identity
    name: str  # Unique project identifier (e.g., "nixos")
    display_name: str  # Human-readable name (e.g., "NixOS")
    icon: str  # Nerd Font icon or emoji

    # Directory
    directory: Path  # Project root directory

    # Metadata
    created: datetime = field(default_factory=datetime.now)
    last_active: Optional[datetime] = None

    def __post_init__(self) -> None:
        """Validate project configuration."""
        if not self.name:
            raise ValueError("Project name cannot be empty")
        if not self.name.replace("-", "").replace("_", "").isalnum():
            raise ValueError(f"Invalid project name: {self.name}")
        if len(self.name) > 64:
            raise ValueError(f"Project name too long: {self.name}")
        if not self.directory.is_absolute():
            raise ValueError(f"Project directory must be absolute: {self.directory}")
        if len(self.icon) != 1:
            raise ValueError(f"Icon must be single character: {self.icon}")


@dataclass
class ActiveProjectState:
    """Active project persistence."""

    project_name: Optional[str]  # Active project name (None = global mode)
    activated_at: datetime  # When project was activated
    previous_project: Optional[str] = None  # Previous project (for quick switching)


@dataclass
class ApplicationClassification:
    """Classification of window classes for project scoping."""

    scoped_classes: Set[str]  # Classes that belong to projects
    global_classes: Set[str]  # Classes that are always global

    def __post_init__(self) -> None:
        """Validate no overlap between scoped and global classes."""
        overlap = self.scoped_classes & self.global_classes
        if overlap:
            raise ValueError(f"Classes cannot be both scoped and global: {overlap}")


@dataclass
class IdentificationRule:
    """Rule for identifying applications from window properties."""

    # Priority 1-4 matching criteria
    wm_instance: Optional[str] = None  # Match WM_CLASS instance
    wm_class: Optional[str] = None  # Match WM_CLASS class
    title_pattern: Optional[str] = None  # Regex pattern for window title
    process_name: Optional[str] = None  # Match process name from /proc

    # Output
    identifier: str = ""  # Application identifier to use

    def __post_init__(self) -> None:
        """Validate at least one matching criterion is provided."""
        if not any([self.wm_instance, self.wm_class, self.title_pattern, self.process_name]):
            raise ValueError("At least one matching criterion must be provided")
        if not self.identifier:
            raise ValueError("Identifier cannot be empty")


@dataclass
class EventQueueEntry:
    """Single event in processing queue."""

    event_type: str  # 'window', 'workspace', 'tick', 'shutdown'
    event_subtype: str  # 'new', 'focus', 'close', 'mark', 'init', 'empty', etc.
    payload: Dict[str, Any]  # Event-specific data from i3
    received_at: datetime = field(default_factory=datetime.now)
    processing_status: str = "pending"  # 'pending', 'processing', 'completed', 'error'
    error_message: Optional[str] = None  # Error details if processing failed


@dataclass
class WorkspaceInfo:
    """Information about an i3 workspace."""

    # Identity
    name: str  # Workspace name (e.g., "1", "1:code")
    num: int  # Workspace number (or -1 for named workspaces)

    # Position
    output: str  # Monitor/output name
    rect_x: int = 0  # X position
    rect_y: int = 0  # Y position
    rect_width: int = 0  # Width
    rect_height: int = 0  # Height

    # State
    visible: bool = False  # Currently visible on any output
    focused: bool = False  # Currently focused
    urgent: bool = False  # Has urgent window

    # Windows
    window_ids: List[int] = field(default_factory=list)  # Windows on this workspace


@dataclass
class DaemonState:
    """Runtime state of the event listener daemon."""

    # Connection state
    conn: Optional[i3ipc.Connection] = None  # Active i3 IPC connection
    socket_path: str = ""  # i3 socket path (from $I3SOCK or auto-detected)
    is_connected: bool = False  # Connection status
    last_heartbeat: datetime = field(default_factory=datetime.now)

    # Runtime state
    pid: int = 0  # Daemon process ID
    start_time: datetime = field(default_factory=datetime.now)
    event_count: int = 0  # Total events processed
    error_count: int = 0  # Total errors encountered

    # Project state
    active_project: Optional[str] = None  # Currently active project name
    window_map: Dict[int, WindowInfo] = field(default_factory=dict)  # window_id → WindowInfo
    workspace_map: Dict[str, WorkspaceInfo] = field(
        default_factory=dict
    )  # workspace_name → WorkspaceInfo

    # Subscription state
    subscribed_events: List[str] = field(
        default_factory=lambda: ["window", "workspace", "tick", "shutdown"]
    )
    subscription_time: datetime = field(default_factory=datetime.now)

    # Configuration
    projects: Dict[str, ProjectConfig] = field(default_factory=dict)  # project_name → ProjectConfig
    scoped_classes: Set[str] = field(default_factory=set)  # Window classes that are project-scoped
    global_classes: Set[str] = field(default_factory=set)  # Window classes that are always global

    def __post_init__(self) -> None:
        """Initialize daemon state."""
        import os

        if self.pid == 0:
            self.pid = os.getpid()
