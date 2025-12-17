"""Pydantic data models for eBPF AI Agent Monitor.

This module defines the core data structures used throughout the daemon:
- ProcessState: Enum for process state machine
- EBPFEvent: ctypes structure for kernel→userspace event transfer
- MonitoredProcess: Tracked AI process with state management
- BadgeState: Badge file format for eww panel integration
- OTELSessionData: Enrichment data from OTEL monitor
- DaemonState: Top-level daemon state container
"""

import ctypes
import time
from enum import Enum
from pathlib import Path
from typing import Optional

from pydantic import BaseModel, Field, ConfigDict


# =============================================================================
# Syscall Constants (matching BPF C program)
# =============================================================================

SYSCALL_READ = 0
SYSCALL_POLL = 1
SYSCALL_SELECT = 2
SYSCALL_EXIT = 3
SYSCALL_READ_EXIT = 4  # sys_exit_read event


# =============================================================================
# ctypes Structure for BPF Event
# =============================================================================


class EBPFEvent(ctypes.Structure):
    """Raw eBPF event structure from kernel perf buffer.

    This structure must match the `ebpf_event_t` defined in the BPF C program.
    Uses ctypes for direct memory mapping from perf buffer.

    Attributes:
        pid: Process ID that triggered the event.
        tgid: Thread group ID (usually same as PID for main thread).
        fd: File descriptor (0 = stdin).
        syscall: Syscall type identifier (see SYSCALL_* constants).
        timestamp: Kernel timestamp in nanoseconds since boot.
        comm: Process name (null-terminated, max 16 chars).
    """

    _fields_ = [
        ("pid", ctypes.c_uint32),
        ("tgid", ctypes.c_uint32),
        ("fd", ctypes.c_uint32),
        ("syscall", ctypes.c_uint8),
        ("timestamp", ctypes.c_uint64),
        ("comm", ctypes.c_char * 16),
    ]

    def get_comm(self) -> str:
        """Get process name as decoded string."""
        return self.comm.decode("utf-8", errors="replace").rstrip("\x00")


# =============================================================================
# Process State Enum
# =============================================================================


class ProcessState(str, Enum):
    """State machine states for monitored AI processes.

    State Transitions:
        UNKNOWN → WORKING: Process detected via eBPF event
        WORKING → WAITING: sys_enter_read(fd=0) + threshold timeout
        WAITING → WORKING: sys_exit_read (user resumed interaction)
        WORKING → EXITED: Process terminated
        WAITING → EXITED: Process terminated while waiting
    """

    UNKNOWN = "unknown"
    WORKING = "working"
    WAITING = "waiting"
    EXITED = "exited"


# =============================================================================
# Monitored Process Model
# =============================================================================


class MonitoredProcess(BaseModel):
    """Tracked AI process with state management.

    Represents an AI process (Claude Code, Codex CLI) being monitored.
    Maintained in daemon memory, rebuilt on service restart.

    Attributes:
        pid: Process ID (must be > 0).
        comm: Process name (e.g., "claude", "codex").
        window_id: Sway container ID for the terminal window.
        project_name: Project from I3PM_PROJECT_NAME env var.
        state: Current state in the state machine.
        last_state_change: Unix timestamp of last state transition.
        read_entry_time: Timestamp when process entered read syscall (0 if not in read).
        parent_chain: PID chain from process up to init (for window resolution).
        session_started: Unix timestamp when session was first detected.
    """

    model_config = ConfigDict(
        validate_assignment=True,
        extra="forbid",
    )

    pid: int = Field(..., gt=0, description="Process ID")
    comm: str = Field(..., max_length=16, description="Process name")
    window_id: int = Field(..., gt=0, description="Sway container ID")
    project_name: str = Field(default="", description="Project name from environment")
    state: ProcessState = Field(default=ProcessState.UNKNOWN, description="Current state")
    last_state_change: float = Field(
        default_factory=time.time,
        gt=0,
        description="Unix timestamp of last state change",
    )
    read_entry_time: float = Field(
        default=0.0,
        ge=0,
        description="Timestamp when entered read syscall (0 if not in read)",
    )
    parent_chain: list[int] = Field(
        ...,
        min_length=1,
        description="PID chain: [self, parent, grandparent, ...]",
    )
    session_started: float = Field(
        default_factory=time.time,
        gt=0,
        description="Unix timestamp when session began",
    )

    def transition_to(self, new_state: ProcessState) -> bool:
        """Transition to a new state with timestamp update.

        Args:
            new_state: Target state to transition to.

        Returns:
            True if state changed, False if already in target state.
        """
        if self.state != new_state:
            self.state = new_state
            self.last_state_change = time.time()
            return True
        return False

    def enter_read(self) -> None:
        """Record entry into read syscall."""
        self.read_entry_time = time.time()

    def exit_read(self) -> None:
        """Record exit from read syscall."""
        self.read_entry_time = 0.0

    def is_waiting_timeout(self, threshold_ms: int) -> bool:
        """Check if process has been in read syscall longer than threshold.

        Args:
            threshold_ms: Threshold in milliseconds.

        Returns:
            True if in read syscall for longer than threshold.
        """
        if self.read_entry_time == 0:
            return False
        elapsed_ms = (time.time() - self.read_entry_time) * 1000
        return elapsed_ms >= threshold_ms

    def time_in_state(self) -> float:
        """Get time in current state in seconds."""
        return time.time() - self.last_state_change


# =============================================================================
# Badge State Model (matches existing JSON schema)
# =============================================================================


class BadgeState(BaseModel):
    """Badge file format for eww panel integration.

    This model matches the existing badge file format at:
    $XDG_RUNTIME_DIR/i3pm-badges/<window_id>.json

    Must maintain backward compatibility with existing eww consumers.

    Attributes:
        window_id: Sway container ID for the window.
        state: Current state ("working" or "stopped").
        source: AI agent type identifier.
        project: Project name from environment.
        count: Notification count (increments on repeated completions).
        timestamp: Unix timestamp when badge was last updated.
        needs_attention: True when AI completed and user hasn't focused window.
        session_started: Unix timestamp when AI session began.
    """

    model_config = ConfigDict(
        validate_assignment=True,
        extra="forbid",
    )

    window_id: int = Field(..., gt=0, description="Sway container ID")
    state: str = Field(
        ...,
        pattern="^(working|stopped)$",
        description="Current state: 'working' or 'stopped'",
    )
    source: str = Field(
        ...,
        pattern="^(claude-code|codex|generic)$",
        description="AI agent type identifier",
    )
    project: str = Field(default="", description="Project name from environment")
    count: int = Field(
        default=1,
        ge=1,
        le=9999,
        description="Notification count",
    )
    timestamp: float = Field(
        default_factory=time.time,
        ge=0,
        description="Unix timestamp when badge was last updated",
    )
    needs_attention: bool = Field(
        default=False,
        description="True when AI completed and user hasn't focused window",
    )
    session_started: float = Field(
        default_factory=time.time,
        ge=0,
        description="Unix timestamp when AI session began",
    )
    # Feature 119/123: OTEL enrichment fields
    otel_session_id: Optional[str] = Field(
        default=None,
        description="Session ID from OTEL telemetry for correlation",
    )
    input_tokens: int = Field(
        default=0,
        ge=0,
        description="Input token count from OTEL metrics",
    )
    output_tokens: int = Field(
        default=0,
        ge=0,
        description="Output token count from OTEL metrics",
    )
    cache_tokens: int = Field(
        default=0,
        ge=0,
        description="Cache token count from OTEL metrics",
    )

    @classmethod
    def from_monitored_process(cls, process: MonitoredProcess) -> "BadgeState":
        """Create badge state from a monitored process.

        Args:
            process: MonitoredProcess instance.

        Returns:
            BadgeState for writing to file.
        """
        # Map process comm to source identifier
        source_map = {
            "claude": "claude-code",
            "codex": "codex",
        }
        source = source_map.get(process.comm, "generic")

        # Map ProcessState to badge state string
        state = "stopped" if process.state == ProcessState.WAITING else "working"

        return cls(
            window_id=process.window_id,
            state=state,
            source=source,
            project=process.project_name,
            timestamp=time.time(),
            needs_attention=process.state == ProcessState.WAITING,
            session_started=process.session_started,
        )


# =============================================================================
# OTEL Session Data Model (Feature 123 enrichment)
# =============================================================================


class OTELSessionData(BaseModel):
    """Enrichment data from OTEL monitor pipe.

    This model represents session data received from the otel-ai-monitor service
    via its named pipe. Used to enrich badge files with token metrics and
    session correlation data.

    The eBPF daemon is authoritative for state detection (working/waiting).
    OTEL provides supplementary information like token counts.

    Attributes:
        session_id: Unique session identifier for correlation.
        tool: AI tool identifier ("claude-code" or "codex").
        state: OTEL's view of state (used for logging, not authoritative).
        project: Project name if available.
        window_id: Sway container ID if resolved.
        input_tokens: Total input tokens for session.
        output_tokens: Total output tokens for session.
        cache_tokens: Total cache tokens for session.
    """

    model_config = ConfigDict(
        validate_assignment=True,
        extra="ignore",  # Allow extra fields from OTEL JSON
    )

    session_id: str = Field(..., description="Unique session identifier")
    tool: str = Field(
        ...,
        description="AI tool identifier (claude-code, codex)",
    )
    state: str = Field(
        default="unknown",
        description="OTEL's view of state (idle, working, completed)",
    )
    project: Optional[str] = Field(
        default=None,
        description="Project name if available",
    )
    window_id: Optional[int] = Field(
        default=None,
        description="Sway container ID if resolved",
    )
    input_tokens: int = Field(
        default=0,
        ge=0,
        description="Total input tokens for session",
    )
    output_tokens: int = Field(
        default=0,
        ge=0,
        description="Total output tokens for session",
    )
    cache_tokens: int = Field(
        default=0,
        ge=0,
        description="Total cache tokens for session",
    )


# =============================================================================
# Daemon State Model
# =============================================================================


class DaemonState(BaseModel):
    """Top-level daemon state container.

    Maintains all tracked processes and daemon configuration.
    Reconstructed on service startup by scanning /proc and existing badge files.

    Attributes:
        tracked_processes: Mapping of PID to MonitoredProcess.
        target_user_uid: UID for badge file ownership.
        target_user_name: Username for notifications.
        badge_directory: Path to badge file directory.
        wait_threshold_ms: Milliseconds before WAITING state transition.
        target_process_names: Set of process names to monitor.
    """

    model_config = ConfigDict(
        validate_assignment=True,
        arbitrary_types_allowed=True,
    )

    tracked_processes: dict[int, MonitoredProcess] = Field(
        default_factory=dict,
        description="PID → MonitoredProcess mapping",
    )
    target_user_uid: int = Field(..., ge=0, description="UID for badge file ownership")
    target_user_name: str = Field(..., description="Username for notifications")
    badge_directory: Path = Field(..., description="Path to badge file directory")
    wait_threshold_ms: int = Field(
        default=1000,
        gt=0,
        description="Milliseconds before WAITING state",
    )
    target_process_names: set[str] = Field(
        default_factory=lambda: {"claude", "codex"},
        description="Process names to monitor",
    )

    def get_process(self, pid: int) -> Optional[MonitoredProcess]:
        """Get tracked process by PID.

        Args:
            pid: Process ID.

        Returns:
            MonitoredProcess if tracked, None otherwise.
        """
        return self.tracked_processes.get(pid)

    def add_process(self, process: MonitoredProcess) -> None:
        """Add a process to tracking.

        Args:
            process: MonitoredProcess to track.
        """
        self.tracked_processes[process.pid] = process

    def remove_process(self, pid: int) -> Optional[MonitoredProcess]:
        """Remove a process from tracking.

        Args:
            pid: Process ID to remove.

        Returns:
            Removed MonitoredProcess if found, None otherwise.
        """
        return self.tracked_processes.pop(pid, None)

    def is_target_process(self, comm: str) -> bool:
        """Check if process name is a monitoring target.

        Args:
            comm: Process name.

        Returns:
            True if process should be monitored.
        """
        return comm in self.target_process_names

    def get_processes_in_state(self, state: ProcessState) -> list[MonitoredProcess]:
        """Get all processes in a specific state.

        Args:
            state: ProcessState to filter by.

        Returns:
            List of processes in the given state.
        """
        return [p for p in self.tracked_processes.values() if p.state == state]
