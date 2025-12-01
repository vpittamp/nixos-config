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

    # Feature 041 T022: Launch correlation metadata
    correlation_matched: bool = False  # True if window was matched via launch notification
    correlation_launch_id: Optional[str] = None  # Launch ID that matched this window
    correlation_confidence: Optional[float] = None  # Correlation confidence (0.0-1.0)
    correlation_confidence_level: Optional[str] = None  # Confidence level: EXACT, HIGH, MEDIUM, LOW
    correlation_signals: Optional[Dict[str, Any]] = None  # Signals used in correlation

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

    # ===== FEATURE 102: UNIFIED EVENT TRACING =====
    # Correlation and causality tracking
    correlation_id: Optional[str] = None        # UUID linking related events in a causality chain
    causality_depth: int = 0                    # Nesting depth in chain (0 = root, 1+ = child)
    trace_id: Optional[str] = None              # Active trace ID if event is part of a trace

    # Command execution events (command::*)
    command_text: Optional[str] = None          # Full Sway command text (e.g., "[con_id=123] move scratchpad")
    command_duration_ms: Optional[float] = None # Execution time in milliseconds
    command_success: Optional[bool] = None      # True if command succeeded
    command_error_msg: Optional[str] = None     # Error message if command failed
    command_batch_count: Optional[int] = None   # Number of commands in batch (for command::batch)
    command_batch_id: Optional[str] = None      # Batch identifier for grouping

    # Enhanced output events (output::*)
    output_event_type: Optional[str] = None     # "connected" | "disconnected" | "profile_changed" | "unspecified"
    output_old_profile: Optional[str] = None    # Previous profile name (for profile_changed)
    output_new_profile: Optional[str] = None    # New profile name (for profile_changed)
    output_changed_props: Optional[Dict[str, Any]] = None  # Properties that changed

    # Feature 102 T043-T045: Output state details
    output_state: Optional[Dict[str, Any]] = None       # Current output state (for connected/profile_changed)
    output_old_state: Optional[Dict[str, Any]] = None   # Previous output state (for disconnected/profile_changed)
    output_changed_properties: Optional[Dict[str, Any]] = None  # Detailed property changes

    def __post_init__(self) -> None:
        """Validate event entry."""
        if self.event_id < 0:
            raise ValueError(f"Invalid event_id: {self.event_id}")
        if not self.event_type:
            raise ValueError("event_type cannot be empty")
        if self.source not in ("i3", "ipc", "daemon", "systemd", "proc", "i3pm", "sway"):
            raise ValueError(f"Invalid source: {self.source} (must be 'i3', 'ipc', 'daemon', 'systemd', 'proc', 'i3pm', or 'sway')")
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

    # Feature 074: Session Management - Focus tracking (T016-T020, US1, US4)
    project_focused_workspace: Dict[str, int] = field(default_factory=dict)  # project → workspace_num (T016, US1)
    workspace_focused_window: Dict[int, int] = field(default_factory=dict)  # workspace_num → window_id (T060, US4)

    # Feature 102 T048: Window blur event tracking - track currently focused window globally
    currently_focused_window: Optional[int] = None  # Currently focused window ID (for blur event generation)

    def __post_init__(self) -> None:
        """Initialize daemon state."""
        import os

        if self.pid == 0:
            self.pid = os.getpid()

    # Feature 074: Session Management - Focus tracking methods (T017-T020, US1)
    def get_focused_workspace(self, project: str) -> Optional[int]:
        """Get focused workspace for a project (T017, US1)"""
        return self.project_focused_workspace.get(project)

    def set_focused_workspace(self, project: str, workspace_num: int) -> None:
        """Set focused workspace for a project (T018, US1)"""
        self.project_focused_workspace[project] = workspace_num

    def get_focused_window(self, workspace_num: int) -> Optional[int]:
        """Get focused window ID for a workspace (T061, US4)"""
        return self.workspace_focused_window.get(workspace_num)

    def set_focused_window(self, workspace_num: int, window_id: int) -> None:
        """Set focused window for a workspace (T062, US4)"""
        self.workspace_focused_window[workspace_num] = window_id

    def to_json(self) -> Dict[str, Any]:
        """Serialize state to JSON-compatible dict for persistence (T019, US1)"""
        return {
            "active_project": self.active_project,
            "project_focused_workspace": self.project_focused_workspace,
            "workspace_focused_window": {
                str(k): v for k, v in self.workspace_focused_window.items()
            },
            "start_time": self.start_time.isoformat(),
            "event_count": self.event_count,
            "error_count": self.error_count,
        }

    @classmethod
    def from_json(cls, data: Dict[str, Any]) -> 'DaemonState':
        """Deserialize state from JSON (T020, US1)"""
        state = cls()
        state.active_project = data.get("active_project")
        state.project_focused_workspace = data.get("project_focused_workspace", {})
        state.workspace_focused_window = {
            int(k): v for k, v in data.get("workspace_focused_window", {}).items()
        }
        state.start_time = datetime.fromisoformat(data["start_time"]) if "start_time" in data else datetime.now()
        state.event_count = data.get("event_count", 0)
        state.error_count = data.get("error_count", 0)
        return state


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


# ============================================================================
# Feature 039: Diagnostic & Optimization Models
# ============================================================================
# Pydantic models for diagnostic tooling, window identity, and state validation.
# These models provide complete introspection of the window management system.


class WindowIdentity(BaseModel):
    """Complete window identification and context (Feature 039: T005)."""

    # X11/i3 Properties
    window_id: int = Field(..., description="i3 window container ID")
    window_class: str = Field(..., description="WM_CLASS class field (full)")
    window_class_normalized: str = Field(..., description="Normalized class for matching")
    window_instance: Optional[str] = Field(None, description="WM_CLASS instance field")
    window_title: str = Field(..., description="Window title/name")
    window_pid: int = Field(..., description="Process ID of window")

    # Workspace Context
    workspace_number: int = Field(..., description="Current workspace number")
    workspace_name: str = Field(..., description="Current workspace name")
    output_name: str = Field(..., description="Monitor/output name (e.g., 'HDMI-1')")

    # Window State
    is_floating: bool = Field(False, description="Floating vs tiled")
    is_focused: bool = Field(False, description="Currently focused")
    is_hidden: bool = Field(False, description="In scratchpad")

    # I3PM Context
    i3pm_env: Optional["I3PMEnvironment"] = Field(None, description="I3PM environment variables")
    i3pm_marks: List[str] = Field(default_factory=list, description="i3 marks on window")

    # Matching Info (diagnostic)
    matched_app: Optional[str] = Field(None, description="Matched app name from registry")
    match_type: Optional[str] = Field(None, description="Match type: exact, instance, normalized, none")

    # Timestamps
    created_at: datetime = Field(default_factory=datetime.now, description="Window creation time")
    last_seen_at: datetime = Field(default_factory=datetime.now, description="Last state update time")

    model_config = {
        "json_schema_extra": {
            "example": {
                "window_id": 14680068,
                "window_class": "com.mitchellh.ghostty",
                "window_class_normalized": "ghostty",
                "window_instance": "ghostty",
                "window_title": "vpittamp@hetzner: ~",
                "window_pid": 823199,
                "workspace_number": 2,
                "workspace_name": "2:code",
                "output_name": "HDMI-1",
                "is_floating": False,
                "is_focused": True,
                "is_hidden": False,
                "matched_app": "terminal",
                "match_type": "instance"
            }
        }
    }


class I3PMEnvironment(BaseModel):
    """I3PM environment variables from /proc/{pid}/environ (Feature 039: T006)."""

    # Application Identity
    app_id: str = Field(..., description="Unique instance ID: {app}-{project}-{pid}-{timestamp}")
    app_name: str = Field(..., description="Registry application name (e.g., 'vscode', 'terminal')")

    # Workspace Assignment (Feature 039)
    target_workspace: Optional[int] = Field(None, description="Direct workspace assignment from launcher (1-10)")

    # Project Context
    project_name: Optional[str] = Field(None, description="Active project name (e.g., 'nixos', 'stacks')")
    project_dir: Optional[str] = Field(None, description="Project directory path")
    project_display_name: Optional[str] = Field(None, description="Human-readable project name")
    project_icon: Optional[str] = Field(None, description="Project icon emoji")

    # Scope
    scope: str = Field(..., description="Application scope: 'scoped' or 'global'")
    active: bool = Field(True, description="True if project was active at launch")

    # Launch Context
    launch_time: int = Field(..., description="Unix timestamp of launch")
    launcher_pid: int = Field(..., description="Wrapper script PID")

    model_config = {
        "json_schema_extra": {
            "example": {
                "app_id": "terminal-stacks-823199-1730000000",
                "app_name": "terminal",
                "project_name": "stacks",
                "project_dir": "/home/vpittamp/projects/stacks",
                "project_display_name": "Stacks",
                "project_icon": "📚",
                "scope": "scoped",
                "active": True,
                "launch_time": 1730000000,
                "launcher_pid": 823150
            }
        }
    }


class WorkspaceRule(BaseModel):
    """Workspace assignment rule for an application (Feature 039: T007)."""

    # Application Matching
    app_identifier: str = Field(..., description="App name or window class pattern")
    matching_strategy: str = Field("normalized", description="Match strategy: exact, instance, normalized, regex")
    aliases: List[str] = Field(default_factory=list, description="Alternative class names that match")

    # Assignment
    target_workspace: int = Field(..., description="Workspace number to assign (1-10)")
    fallback_behavior: str = Field("current", description="Fallback if workspace unavailable: current, create, error")

    # Metadata
    app_name: str = Field(..., description="Application name from registry")
    description: Optional[str] = Field(None, description="Human-readable description")

    model_config = {
        "json_schema_extra": {
            "example": {
                "app_identifier": "ghostty",
                "matching_strategy": "normalized",
                "aliases": ["com.mitchellh.ghostty", "Ghostty"],
                "target_workspace": 3,
                "fallback_behavior": "current",
                "app_name": "lazygit",
                "description": "Git TUI in terminal on workspace 3"
            }
        }
    }


class EventSubscription(BaseModel):
    """i3 IPC event subscription status (Feature 039: T008)."""

    subscription_type: str = Field(..., description="Event type: window, workspace, output, tick, binding")
    is_active: bool = Field(..., description="True if subscription is currently active")
    event_count: int = Field(0, description="Total events received since daemon start")
    last_event_time: Optional[datetime] = Field(None, description="Timestamp of most recent event")
    last_event_change: Optional[str] = Field(None, description="Last event change type (e.g., 'new', 'focus')")

    model_config = {
        "json_schema_extra": {
            "example": {
                "subscription_type": "window",
                "is_active": True,
                "event_count": 1234,
                "last_event_time": "2025-10-26T12:34:56",
                "last_event_change": "new"
            }
        }
    }


class WindowEvent(BaseModel):
    """Captured i3 window event for diagnostics (Feature 039: T009)."""

    # Event Metadata
    event_type: str = Field(..., description="Event type: window, workspace, output, tick")
    event_change: str = Field(..., description="Change type: new, close, focus, move, etc.")
    timestamp: datetime = Field(default_factory=datetime.now, description="Event capture time")

    # Window Context
    window_id: Optional[int] = Field(None, description="Window container ID (if window event)")
    window_class: Optional[str] = Field(None, description="Window class at event time")
    window_title: Optional[str] = Field(None, description="Window title at event time")

    # Processing Info
    handler_duration_ms: Optional[float] = Field(None, description="Handler execution time in milliseconds")
    workspace_assigned: Optional[int] = Field(None, description="Workspace assigned (if applicable)")
    marks_applied: List[str] = Field(default_factory=list, description="Marks applied to window")

    # Error Tracking
    error: Optional[str] = Field(None, description="Error message if processing failed")
    stack_trace: Optional[str] = Field(None, description="Stack trace for debugging")

    model_config = {
        "json_schema_extra": {
            "example": {
                "event_type": "window",
                "event_change": "new",
                "timestamp": "2025-10-26T12:34:56.789",
                "window_id": 14680068,
                "window_class": "com.mitchellh.ghostty",
                "window_title": "vpittamp@hetzner: ~",
                "handler_duration_ms": 45.2,
                "workspace_assigned": 3,
                "marks_applied": ["project:stacks", "app:terminal"],
                "error": None
            }
        }
    }


class StateMismatch(BaseModel):
    """Specific state inconsistency between daemon and i3 (Feature 039: T010)."""

    window_id: int = Field(..., description="Window with mismatch")
    property_name: str = Field(..., description="Property that doesn't match (e.g., 'workspace', 'marks')")
    daemon_value: str = Field(..., description="Value in daemon state")
    i3_value: str = Field(..., description="Value in i3 IPC state (authoritative)")
    severity: str = Field(..., description="Severity: critical, warning, info")

    model_config = {
        "json_schema_extra": {
            "example": {
                "window_id": 14680068,
                "property_name": "workspace",
                "daemon_value": "3",
                "i3_value": "5",
                "severity": "warning"
            }
        }
    }


class StateValidation(BaseModel):
    """State consistency validation results (Feature 039: T010)."""

    # Validation Metadata
    validated_at: datetime = Field(default_factory=datetime.now, description="Validation timestamp")
    total_windows_checked: int = Field(0, description="Total windows validated")

    # Consistency Metrics
    windows_consistent: int = Field(0, description="Windows matching i3 state")
    windows_inconsistent: int = Field(0, description="Windows with state drift")
    mismatches: List[StateMismatch] = Field(default_factory=list, description="Detailed mismatches")

    # Overall Status
    is_consistent: bool = Field(True, description="True if all state matches")
    consistency_percentage: float = Field(100.0, description="Percentage of windows consistent")

    model_config = {
        "json_schema_extra": {
            "example": {
                "validated_at": "2025-10-26T12:34:56",
                "total_windows_checked": 23,
                "windows_consistent": 21,
                "windows_inconsistent": 2,
                "is_consistent": False,
                "consistency_percentage": 91.3
            }
        }
    }


class OutputInfo(BaseModel):
    """Monitor/output information from i3 IPC (Feature 039: T011)."""
    name: str = Field(..., description="Output name (e.g., 'HDMI-1')")
    active: bool = Field(..., description="Output is active")
    current_workspace: Optional[str] = Field(None, description="Workspace currently on this output")


class WorkspaceInfo(BaseModel):
    """Workspace information from i3 IPC (Feature 039: T011)."""
    num: int = Field(..., description="Workspace number")
    name: str = Field(..., description="Workspace name with icon")
    visible: bool = Field(..., description="Currently visible on an output")
    focused: bool = Field(..., description="Currently focused")
    output: str = Field(..., description="Output name this workspace is on")


class I3IPCState(BaseModel):
    """i3 IPC authoritative state snapshot (Feature 039: T011)."""

    # Outputs/Monitors
    outputs: List[OutputInfo] = Field(default_factory=list, description="Connected outputs")
    active_output_count: int = Field(0, description="Number of active monitors")

    # Workspaces
    workspaces: List[WorkspaceInfo] = Field(default_factory=list, description="All workspaces")
    visible_workspace_count: int = Field(0, description="Number of visible workspaces")
    focused_workspace: Optional[str] = Field(None, description="Currently focused workspace name")

    # Windows
    total_windows: int = Field(0, description="Total window count from tree")
    marks: List[str] = Field(default_factory=list, description="All marks in current session")

    # Capture Time
    captured_at: datetime = Field(default_factory=datetime.now, description="State capture timestamp")


class DiagnosticReport(BaseModel):
    """Comprehensive system diagnostic report (Feature 039: T012)."""

    # Report Metadata
    generated_at: datetime = Field(default_factory=datetime.now, description="Report generation time")
    daemon_version: str = Field(..., description="Daemon version string")
    uptime_seconds: float = Field(..., description="Daemon uptime in seconds")

    # Connection Status
    i3_ipc_connected: bool = Field(..., description="i3 IPC connection active")
    json_rpc_server_running: bool = Field(..., description="JSON-RPC IPC server active")

    # Event Subscriptions
    event_subscriptions: List[EventSubscription] = Field(default_factory=list, description="All event subscriptions")
    total_events_processed: int = Field(0, description="Sum of all event counts")

    # Window Tracking
    tracked_windows: List[WindowIdentity] = Field(default_factory=list, description="All tracked windows")
    total_windows: int = Field(0, description="Total window count")

    # Recent Events
    recent_events: List[WindowEvent] = Field(default_factory=list, description="Last N events (circular buffer)")
    event_buffer_size: int = Field(500, description="Max events in buffer")

    # State Validation
    state_validation: Optional[StateValidation] = Field(None, description="Consistency check results")

    # i3 IPC State
    i3_ipc_state: Optional[I3IPCState] = Field(None, description="i3 authoritative state snapshot")

    # Health Status
    overall_status: str = Field("unknown", description="Overall health: healthy, warning, critical, unknown")
    health_issues: List[str] = Field(default_factory=list, description="List of detected issues")

    model_config = {
        "json_schema_extra": {
            "example": {
                "generated_at": "2025-10-26T12:34:56",
                "daemon_version": "1.4.0",
                "uptime_seconds": 3600.5,
                "i3_ipc_connected": True,
                "json_rpc_server_running": True,
                "total_events_processed": 1350,
                "total_windows": 23,
                "overall_status": "warning",
                "health_issues": ["State drift detected for 2 windows"]
            }
        }
    }


# ============================================================================
# Feature 041: IPC Launch Context Models
# ============================================================================
# Pydantic models for launch notification and window-to-launch correlation.
# These models enable multi-instance app tracking via pre-launch IPC notifications.

import time


class PendingLaunch(BaseModel):
    """
    Represents an application launch awaiting correlation with a new window.

    A pending launch is created when the launcher wrapper notifies the daemon
    that an application is about to start. The daemon uses this context to
    correlate the next matching window to the correct project.

    Feature 041: IPC Launch Context - T004
    """

    # Core identification
    app_name: str = Field(
        ...,
        description="Application name from registry (e.g., 'vscode', 'terminal')"
    )
    project_name: str = Field(
        ...,
        description="Project name for this launch (e.g., 'nixos', 'stacks')"
    )
    project_directory: Path = Field(
        ...,
        description="Absolute path to project directory"
    )

    # Launch metadata
    launcher_pid: int = Field(
        ...,
        gt=0,
        description="Process ID of the launcher wrapper script"
    )
    workspace_number: int = Field(
        ...,
        ge=1,
        le=70,
        description="Target workspace number for the application"
    )
    timestamp: float = Field(
        ...,
        description="Unix timestamp (seconds.microseconds) when launch notification sent"
    )

    # Correlation context
    expected_class: str = Field(
        ...,
        description="Window class expected for this application (from app registry)"
    )

    # State tracking
    matched: bool = Field(
        default=False,
        description="True if this launch has been matched to a window"
    )

    # Feature 101: Pre-launch tracing integration
    trace_id: Optional[str] = Field(
        default=None,
        description="Associated trace ID if pre-launch tracing is active for this app"
    )

    @field_validator('project_directory')
    @classmethod
    def validate_directory_exists(cls, v: Path) -> Path:
        """Validate project directory exists (optional - may be created later)."""
        # Note: Not enforcing existence to support project creation workflows
        return v.resolve()  # Normalize to absolute path

    @field_validator('timestamp')
    @classmethod
    def validate_timestamp_recent(cls, v: float) -> float:
        """Validate timestamp is not in the future (allows small clock skew)."""
        now = time.time()
        if v > now + 1.0:  # Allow 1 second clock skew
            raise ValueError(f"Launch timestamp {v} is in the future (now={now})")
        return v

    def age(self, current_time: float) -> float:
        """Calculate age of this pending launch in seconds."""
        return current_time - self.timestamp

    def is_expired(self, current_time: float, timeout: float = 5.0) -> bool:
        """Check if this launch has exceeded the correlation timeout."""
        return self.age(current_time) > timeout

    def __str__(self) -> str:
        return (
            f"PendingLaunch(app={self.app_name}, project={self.project_name}, "
            f"workspace={self.workspace_number}, age={self.age(time.time()):.2f}s)"
        )

    model_config = {
        # Allow Path objects in JSON serialization
        "json_encoders": {
            Path: str
        }
    }


class LaunchWindowInfo(BaseModel):
    """
    Information about a newly created window for correlation.

    Extracted from i3 window::new event container properties. Used to
    find the best matching pending launch based on application class,
    timing, and workspace location.

    Feature 041: IPC Launch Context - T005

    Note: Named LaunchWindowInfo to avoid conflict with existing WindowInfo dataclass.
    """

    # Window identity
    window_id: int = Field(
        ...,
        description="i3 window/container ID (unique)"
    )
    window_class: str = Field(
        ...,
        description="X11 window class (e.g., 'Code', 'Alacritty')"
    )

    # Process context
    window_pid: Optional[int] = Field(
        None,
        description="Process ID of window's owning process (may be None for some windows)"
    )

    # Location context
    workspace_number: int = Field(
        ...,
        ge=1,
        le=70,
        description="Workspace number where window appeared"
    )

    # Timing
    timestamp: float = Field(
        ...,
        description="Unix timestamp when window::new event received"
    )

    def __str__(self) -> str:
        return (
            f"LaunchWindowInfo(id={self.window_id}, class={self.window_class}, "
            f"workspace={self.workspace_number}, pid={self.window_pid})"
        )


class ConfidenceLevel(str, Enum):
    """Correlation confidence levels (from FR-015)."""
    EXACT = "EXACT"      # 1.0
    HIGH = "HIGH"        # 0.8+
    MEDIUM = "MEDIUM"    # 0.6+
    LOW = "LOW"          # 0.3+
    NONE = "NONE"        # 0.0


class CorrelationResult(BaseModel):
    """
    Result of correlating a window to a pending launch.

    Indicates whether a match was found and the confidence level. Used
    to decide if the window should be assigned to the launch's project.

    Feature 041: IPC Launch Context - T006
    """

    # Match outcome
    matched: bool = Field(
        ...,
        description="True if a pending launch was matched to the window"
    )

    # Matched launch details (if matched=True)
    project_name: Optional[str] = Field(
        None,
        description="Project name from matched launch (None if no match)"
    )
    app_name: Optional[str] = Field(
        None,
        description="Application name from matched launch (None if no match)"
    )

    # Correlation quality
    confidence: float = Field(
        ...,
        ge=0.0,
        le=1.0,
        description="Correlation confidence score (0.0 to 1.0)"
    )
    confidence_level: ConfidenceLevel = Field(
        ...,
        description="Categorical confidence level"
    )

    # Correlation signals used
    signals_used: dict = Field(
        default_factory=dict,
        description="Signals that contributed to correlation (for debugging)"
    )

    @classmethod
    def no_match(cls, window_class: str, reason: str) -> "CorrelationResult":
        """Factory method for failed correlation."""
        return cls(
            matched=False,
            project_name=None,
            app_name=None,
            confidence=0.0,
            confidence_level=ConfidenceLevel.NONE,
            signals_used={
                "window_class": window_class,
                "failure_reason": reason
            }
        )

    @classmethod
    def from_launch(
        cls,
        launch: PendingLaunch,
        confidence: float,
        signals: dict
    ) -> "CorrelationResult":
        """Factory method for successful correlation."""
        # Determine confidence level
        if confidence >= 1.0:
            level = ConfidenceLevel.EXACT
        elif confidence >= 0.8:
            level = ConfidenceLevel.HIGH
        elif confidence >= 0.6:
            level = ConfidenceLevel.MEDIUM
        elif confidence >= 0.3:
            level = ConfidenceLevel.LOW
        else:
            level = ConfidenceLevel.NONE

        return cls(
            matched=True,
            project_name=launch.project_name,
            app_name=launch.app_name,
            confidence=confidence,
            confidence_level=level,
            signals_used=signals
        )

    def should_assign_project(self) -> bool:
        """
        Determine if confidence is sufficient for project assignment.

        Threshold: MEDIUM (0.6) or higher (from FR-016).
        """
        return self.confidence >= 0.6

    def __str__(self) -> str:
        if self.matched:
            return (
                f"CorrelationResult(matched={self.matched}, "
                f"project={self.project_name}, confidence={self.confidence:.2f} [{self.confidence_level}])"
            )
        else:
            reason = self.signals_used.get("failure_reason", "unknown")
            return f"CorrelationResult(matched=False, reason={reason})"


class LaunchRegistryStats(BaseModel):
    """
    Statistics about the launch registry for diagnostics.

    Provides insight into pending launches, match rates, and expiration
    for debugging and system monitoring.

    Feature 041: IPC Launch Context - T007
    """

    # Current state
    total_pending: int = Field(
        ...,
        ge=0,
        description="Number of pending launches awaiting correlation"
    )
    unmatched_pending: int = Field(
        ...,
        ge=0,
        description="Number of pending launches not yet matched"
    )

    # Historical counters (since daemon start)
    total_notifications: int = Field(
        default=0,
        ge=0,
        description="Total launch notifications received"
    )
    total_matched: int = Field(
        default=0,
        ge=0,
        description="Total successful correlations"
    )
    total_expired: int = Field(
        default=0,
        ge=0,
        description="Total launches that expired without matching"
    )
    total_failed_correlation: int = Field(
        default=0,
        ge=0,
        description="Total windows that appeared without matching launch"
    )

    # Computed metrics
    @property
    def match_rate(self) -> float:
        """Percentage of notifications that resulted in successful matches."""
        if self.total_notifications == 0:
            return 0.0
        return (self.total_matched / self.total_notifications) * 100

    @property
    def expiration_rate(self) -> float:
        """Percentage of notifications that expired without matching."""
        if self.total_notifications == 0:
            return 0.0
        return (self.total_expired / self.total_notifications) * 100

    def __str__(self) -> str:
        return (
            f"LaunchRegistryStats(pending={self.total_pending}, "
            f"matched={self.total_matched}, expired={self.total_expired}, "
            f"match_rate={self.match_rate:.1f}%)"
        )


# ============================================================================
# Workspace Mode Models (Feature 042)
# ============================================================================

@dataclass
class WorkspaceModeState:
    """State for workspace mode navigation (Feature 042) + project switching."""

    active: bool = False
    mode_type: str = "goto"  # "goto" or "move"
    accumulated_digits: str = ""  # For workspace numbers
    accumulated_chars: str = ""  # For project letters (NEW)
    input_type: Optional[str] = None  # "workspace" or "project" (NEW)
    entered_at: Optional[datetime] = None
    output_cache: Dict[str, str] = field(default_factory=dict)  # Monitor mappings

    def reset(self) -> None:
        """Reset state to inactive."""
        self.active = False
        self.mode_type = "goto"
        self.accumulated_digits = ""
        self.accumulated_chars = ""  # NEW
        self.input_type = None  # NEW
        self.entered_at = None

    def to_dict(self) -> Dict[str, Any]:
        """Convert to dictionary for IPC."""
        return {
            "active": self.active,
            "mode_type": self.mode_type,
            "accumulated_digits": self.accumulated_digits,
            "accumulated_chars": self.accumulated_chars,  # NEW
            "input_type": self.input_type,  # NEW
            "entered_at": self.entered_at.isoformat() if self.entered_at else None,
        }


@dataclass
class WorkspaceSwitch:
    """Record of a workspace switch (Feature 042 - US4)."""

    workspace_number: int
    output_name: str
    mode_type: str  # "goto" or "move"
    timestamp: datetime = field(default_factory=datetime.now)

    def to_dict(self) -> Dict[str, Any]:
        """Convert to dictionary for IPC."""
        return {
            "workspace_number": self.workspace_number,
            "output_name": self.output_name,
            "mode_type": self.mode_type,
            "timestamp": self.timestamp.isoformat(),
        }


@dataclass
class WorkspaceModeEvent:
    """Event broadcast for workspace mode state changes (Feature 042 - US3)."""

    event_type: str  # "digit", "execute", "cancel", "enter", "exit"
    state: WorkspaceModeState
    timestamp: datetime = field(default_factory=datetime.now)

    def model_dump(self) -> Dict[str, Any]:
        """Convert to dictionary for IPC (Pydantic-compatible name)."""
        return {
            "event_type": self.event_type,
            "state": self.state.to_dict(),
            "timestamp": self.timestamp.isoformat(),
        }
