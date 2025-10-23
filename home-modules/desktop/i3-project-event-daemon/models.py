"""Data models for i3 project event daemon.

This module defines all dataclasses used for runtime state management,
configuration, and event processing.
"""

from dataclasses import dataclass, field
from datetime import datetime
from pathlib import Path
from typing import Any, Dict, List, Optional, Set
import i3ipc

# Import shared Project model from i3pm
try:
    from i3_project_manager.core.models import Project
except ImportError:
    # Fallback for development/testing without i3pm installed
    Project = None  # type: ignore


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


# Feature 030: Standalone Project model (remove i3_project_manager dependency)
@dataclass
class Project:
    """Project configuration for workspace/window management."""

    name: str  # Unique project identifier
    display_name: str  # Human-readable name
    icon: str  # Unicode emoji or icon
    directory: Path  # Project directory
    scoped_classes: Set[str] = field(default_factory=set)  # App classes scoped to this project

    def __post_init__(self) -> None:
        """Validate project configuration."""
        if not self.name:
            raise ValueError("Project name cannot be empty")
        if not self.directory.exists():
            raise ValueError(f"Project directory does not exist: {self.directory}")


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
class EventEntry:
    """Unified event log entry for all system events.

    Covers three event categories:
    - i3 events (window::*, workspace::*, output, tick)
    - IPC events (project::*, query::*, config::*, rules::*)
    - Daemon events (daemon::*)
    """

    # ===== METADATA (Always present) =====
    event_id: int                       # Incremental ID for event ordering
    event_type: str                     # "window::new", "project::switch", "query::status", etc.
    timestamp: datetime                 # When event occurred
    source: str                         # "i3" | "ipc" | "daemon"
    processing_duration_ms: float = 0.0 # Time daemon took to handle event
    error: Optional[str] = None         # Error message if processing failed

    # ===== SOURCE CONTEXT (Optional) =====
    client_pid: Optional[int] = None    # PID of client that triggered (for IPC events)

    # ===== WINDOW EVENTS (window::*) =====
    window_id: Optional[int] = None
    window_class: Optional[str] = None
    window_title: Optional[str] = None
    window_instance: Optional[str] = None
    workspace_name: Optional[str] = None

    # ===== PROJECT EVENTS (project::*) =====
    project_name: Optional[str] = None          # Project name
    project_directory: Optional[str] = None     # Project directory path
    old_project: Optional[str] = None           # Previous project (for switch/clear)
    new_project: Optional[str] = None           # New project (for switch)
    windows_affected: Optional[int] = None      # Number of windows shown/hidden

    # ===== TICK EVENTS (tick) =====
    tick_payload: Optional[str] = None          # Raw tick payload

    # ===== OUTPUT EVENTS (output) =====
    output_name: Optional[str] = None           # Monitor name
    output_count: Optional[int] = None          # Total active monitors

    # ===== QUERY EVENTS (query::*) =====
    query_method: Optional[str] = None          # IPC method called
    query_params: Optional[Dict[str, Any]] = None  # Request parameters
    query_result_count: Optional[int] = None    # Number of results returned

    # ===== CONFIG EVENTS (config::*, rules::*) =====
    config_type: Optional[str] = None           # "app_classification" | "window_rules"
    rules_added: Optional[int] = None           # Number of rules added
    rules_removed: Optional[int] = None         # Number of rules removed

    # ===== DAEMON EVENTS (daemon::*) =====
    daemon_version: Optional[str] = None        # Daemon version
    i3_socket: Optional[str] = None             # i3 socket path

    # ===== SYSTEMD EVENTS (systemd::*) =====
    # Feature 029: Linux System Log Integration - User Story 1
    systemd_unit: Optional[str] = None          # Service unit name (e.g., "app-firefox-123.service")
    systemd_message: Optional[str] = None       # systemd message (e.g., "Started Firefox Web Browser")
    systemd_pid: Optional[int] = None           # Process ID from journal _PID field
    journal_cursor: Optional[str] = None        # Journal cursor for event position (for pagination)

    # ===== PROCESS EVENTS (process::*) =====
    # Feature 029: Linux System Log Integration - User Story 2
    process_pid: Optional[int] = None           # Process ID
    process_name: Optional[str] = None          # Command name from /proc/{pid}/comm
    process_cmdline: Optional[str] = None       # Full command line (sanitized, truncated to 500 chars)
    process_parent_pid: Optional[int] = None    # Parent process ID from /proc/{pid}/stat
    process_start_time: Optional[int] = None    # Process start time from /proc/{pid}/stat (for correlation)

    def __post_init__(self) -> None:
        """Validate event entry."""
        if self.event_id < 0:
            raise ValueError(f"Invalid event_id: {self.event_id}")
        if not self.event_type:
            raise ValueError("event_type cannot be empty")
        if self.source not in ("i3", "ipc", "daemon", "systemd", "proc"):
            raise ValueError(f"Invalid source: {self.source} (must be 'i3', 'ipc', 'daemon', 'systemd', or 'proc')")
        if self.processing_duration_ms < 0:
            raise ValueError(f"Invalid processing_duration_ms: {self.processing_duration_ms}")

        # Feature 029: Validate systemd events must have systemd_unit
        if self.source == "systemd" and not self.systemd_unit:
            raise ValueError("systemd events must have systemd_unit")

        # Feature 029: Validate proc events must have process_pid and process_name
        if self.source == "proc":
            if not self.process_pid or not self.process_name:
                raise ValueError("proc events must have process_pid and process_name")


@dataclass
class EventCorrelation:
    """Correlation between a parent event and related child events.

    Feature 029: Linux System Log Integration - User Story 3
    Used to show relationships like:
    - GUI window creation → backend process spawns
    - Process spawn → subprocess spawns
    """

    # Correlation metadata
    correlation_id: int                     # Unique correlation ID
    created_at: datetime                    # When correlation was detected
    confidence_score: float                 # 0.0-1.0 confidence in correlation accuracy

    # Event relationships
    parent_event_id: int                    # Parent event (e.g., window::new)
    child_event_ids: List[int]              # Child events (e.g., process::start[])
    correlation_type: str                   # "window_to_process" | "process_to_subprocess"

    # Timing information
    time_delta_ms: float                    # Time between parent and first child event
    detection_window_ms: float = 5000.0     # Time window used for detection (default 5s)

    # Correlation factors (for debugging)
    timing_factor: float = 0.0              # 0.0-1.0 score for timing proximity
    hierarchy_factor: float = 0.0           # 0.0-1.0 score for process hierarchy match
    name_similarity: float = 0.0            # 0.0-1.0 score for name similarity
    workspace_match: bool = False           # Whether events happened in same workspace

    def __post_init__(self) -> None:
        """Validate correlation."""
        if not 0.0 <= self.confidence_score <= 1.0:
            raise ValueError(f"confidence_score must be 0.0-1.0, got {self.confidence_score}")
        if self.time_delta_ms < 0:
            raise ValueError(f"time_delta_ms cannot be negative: {self.time_delta_ms}")
        if self.correlation_type not in ("window_to_process", "process_to_subprocess"):
            raise ValueError(f"Invalid correlation_type: {self.correlation_type}")
        if not self.child_event_ids:
            raise ValueError("child_event_ids cannot be empty")


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
    projects: Dict[str, "Project"] = field(default_factory=dict)  # project_name → Project (from i3pm)
    scoped_classes: Set[str] = field(default_factory=set)  # Window classes that are project-scoped
    global_classes: Set[str] = field(default_factory=set)  # Window classes that are always global

    def __post_init__(self) -> None:
        """Initialize daemon state."""
        import os

        if self.pid == 0:
            self.pid = os.getpid()
