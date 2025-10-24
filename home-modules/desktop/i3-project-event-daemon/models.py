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


# ============================================================================
# Monitor Configuration Models (Feature 033)
# ============================================================================
# Pydantic models for declarative workspace-to-monitor mapping configuration.
# These models provide runtime validation for the JSON configuration file at
# ~/.config/i3/workspace-monitor-mapping.json

from enum import Enum
from pydantic import BaseModel, Field, field_validator


class MonitorRole(str, Enum):
    """Monitor role assignment."""
    PRIMARY = "primary"
    SECONDARY = "secondary"
    TERTIARY = "tertiary"


class MonitorDistribution(BaseModel):
    """Workspace distribution for a specific monitor role."""
    primary: List[int] = Field(default_factory=list, description="Workspaces on primary monitor")
    secondary: List[int] = Field(default_factory=list, description="Workspaces on secondary monitor")
    tertiary: List[int] = Field(default_factory=list, description="Workspaces on tertiary monitor")

    @field_validator("primary", "secondary", "tertiary")
    @classmethod
    def validate_workspace_numbers(cls, v: List[int]) -> List[int]:
        """Ensure workspace numbers are positive integers."""
        for ws_num in v:
            if ws_num <= 0:
                raise ValueError(f"Workspace number must be positive: {ws_num}")
        return v


class DistributionRules(BaseModel):
    """Distribution rules for different monitor counts."""
    one_monitor: MonitorDistribution = Field(
        alias="1_monitor",
        description="Distribution for 1-monitor setup"
    )
    two_monitors: MonitorDistribution = Field(
        alias="2_monitors",
        description="Distribution for 2-monitor setup"
    )
    three_monitors: MonitorDistribution = Field(
        alias="3_monitors",
        description="Distribution for 3+ monitor setup"
    )

    model_config = {"populate_by_name": True}


class WorkspaceMonitorConfig(BaseModel):
    """Root configuration model for workspace-to-monitor mapping."""

    version: str = Field(default="1.0", description="Configuration version")

    distribution: DistributionRules = Field(
        description="Default workspace distribution rules by monitor count"
    )

    workspace_preferences: Dict[int, MonitorRole] = Field(
        default_factory=dict,
        description="Explicit workspace-to-role assignments (overrides distribution)"
    )

    output_preferences: Dict[MonitorRole, List[str]] = Field(
        default_factory=dict,
        description="Preferred output names for each role (with fallbacks)"
    )

    debounce_ms: int = Field(
        default=1000,
        ge=0,
        le=5000,
        description="Debounce delay for monitor change events (ms)"
    )

    enable_auto_reassign: bool = Field(
        default=True,
        description="Automatically reassign workspaces on monitor changes"
    )

    @field_validator("workspace_preferences")
    @classmethod
    def validate_workspace_preferences(cls, v: Dict[int, MonitorRole]) -> Dict[int, MonitorRole]:
        """Ensure workspace numbers in preferences are positive integers."""
        for ws_num in v.keys():
            if ws_num <= 0:
                raise ValueError(f"Workspace number must be positive: {ws_num}")
        return v

    model_config = {
        "use_enum_values": True,
        "json_schema_extra": {
            "example": {
                "version": "1.0",
                "distribution": {
                    "1_monitor": {"primary": [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]},
                    "2_monitors": {"primary": [1, 2], "secondary": [3, 4, 5, 6, 7, 8, 9, 10]},
                    "3_monitors": {"primary": [1, 2], "secondary": [3, 4, 5], "tertiary": [6, 7, 8, 9, 10]},
                },
                "workspace_preferences": {18: "secondary", 42: "tertiary"},
                "output_preferences": {
                    "primary": ["rdp0", "DP-1", "eDP-1"],
                    "secondary": ["rdp1", "HDMI-1"],
                    "tertiary": ["rdp2", "HDMI-2"],
                },
                "debounce_ms": 1000,
                "enable_auto_reassign": True,
            }
        }
    }


class OutputRect(BaseModel):
    """Output geometry (position and size)."""
    x: int
    y: int
    width: int
    height: int


class MonitorConfig(BaseModel):
    """Represents a physical monitor/output."""

    name: str = Field(description="Output name from i3 IPC (e.g., rdp0, DP-1)")
    active: bool = Field(description="Whether output is currently active")
    primary: bool = Field(description="Whether this is the xrandr primary output")
    role: Optional[MonitorRole] = Field(None, description="Assigned role (primary/secondary/tertiary)")
    rect: OutputRect = Field(description="Output position and size")
    current_workspace: Optional[str] = Field(None, description="Workspace currently visible on this output")

    # Additional i3 output fields
    make: Optional[str] = Field(None, description="Monitor manufacturer")
    model: Optional[str] = Field(None, description="Monitor model")
    serial: Optional[str] = Field(None, description="Monitor serial number")

    @classmethod
    def from_i3_output(cls, output: Any) -> "MonitorConfig":
        """Create MonitorConfig from i3ipc Output object."""
        return cls(
            name=output.name,
            active=output.active,
            primary=output.primary,
            rect=OutputRect(
                x=output.rect.x,
                y=output.rect.y,
                width=output.rect.width,
                height=output.rect.height,
            ),
            current_workspace=output.current_workspace,
            make=output.make,
            model=output.model,
            serial=output.serial,
        )


class WorkspaceAssignment(BaseModel):
    """Represents the assignment of a workspace to an output."""

    workspace_num: int = Field(description="Workspace number")
    output_name: Optional[str] = Field(None, description="Current output name (from i3 IPC)")
    target_role: Optional[MonitorRole] = Field(None, description="Target role (from config)")
    target_output: Optional[str] = Field(None, description="Resolved target output name")
    source: str = Field(description="Assignment source: 'default', 'explicit', 'runtime'")
    visible: bool = Field(description="Whether workspace is visible on an active output")
    window_count: int = Field(default=0, description="Number of windows on this workspace")

    @classmethod
    def from_i3_workspace(cls, workspace: Any, target_role: Optional[MonitorRole] = None) -> "WorkspaceAssignment":
        """Create WorkspaceAssignment from i3ipc Workspace object."""
        return cls(
            workspace_num=workspace.num,
            output_name=workspace.output,
            target_role=target_role,
            source="runtime",  # Will be updated by assignment logic
            visible=workspace.visible,
        )


class MonitorSystemState(BaseModel):
    """Complete monitor and workspace state."""

    monitors: List[MonitorConfig] = Field(description="All detected monitors")
    workspaces: List[WorkspaceAssignment] = Field(description="All workspace assignments")
    active_monitor_count: int = Field(description="Number of active monitors")
    primary_output: Optional[str] = Field(None, description="Primary output name")
    last_updated: float = Field(description="Timestamp of last state update (Unix epoch)")

    @property
    def active_monitors(self) -> List[MonitorConfig]:
        """Get only active monitors."""
        return [m for m in self.monitors if m.active]

    @property
    def orphaned_workspaces(self) -> List[WorkspaceAssignment]:
        """Get workspaces on inactive outputs."""
        active_output_names = {m.name for m in self.active_monitors}
        return [ws for ws in self.workspaces if ws.output_name not in active_output_names]


class ValidationIssue(BaseModel):
    """Single validation issue."""
    severity: str = Field(description="Severity: 'error' or 'warning'")
    field: str = Field(description="Field path (e.g., 'distribution.2_monitors.primary')")
    message: str = Field(description="Human-readable error message")


class ConfigValidationResult(BaseModel):
    """Result of configuration validation."""
    valid: bool = Field(description="Whether configuration is valid")
    issues: List[ValidationIssue] = Field(default_factory=list, description="Validation issues")
    config: Optional[WorkspaceMonitorConfig] = Field(None, description="Parsed config if valid")

    @property
    def errors(self) -> List[ValidationIssue]:
        """Get only error-level issues."""
        return [issue for issue in self.issues if issue.severity == "error"]

    @property
    def warnings(self) -> List[ValidationIssue]:
        """Get only warning-level issues."""
        return [issue for issue in self.issues if issue.severity == "warning"]
