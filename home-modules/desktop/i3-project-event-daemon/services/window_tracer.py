"""Window Tracer - Per-window state change tracking for debugging.

Feature 101: Provides detailed tracing of individual windows to understand
their behavior relative to project management configuration.

Usage:
    # Start tracing a window
    i3pm trace start --class ghostty
    i3pm trace start --id 42
    i3pm trace start --title "Scratchpad Terminal"

    # View trace
    i3pm trace show <trace_id>

    # Stop and export
    i3pm trace stop <trace_id>
    i3pm trace export <trace_id> > window-trace.json
"""

import asyncio
import json
import logging
import re
import time
from dataclasses import dataclass, field, asdict
from datetime import datetime
from enum import Enum
from pathlib import Path
from typing import Any, Dict, List, Optional, Set
from collections import deque

logger = logging.getLogger(__name__)


class TraceEventType(str, Enum):
    """Types of events that can be traced."""
    # Lifecycle
    WINDOW_NEW = "window::new"
    WINDOW_CLOSE = "window::close"

    # Focus
    WINDOW_FOCUS = "window::focus"
    WINDOW_BLUR = "window::blur"

    # Position/State
    WINDOW_MOVE = "window::move"
    WINDOW_FLOATING = "window::floating_changed"
    WINDOW_FULLSCREEN = "window::fullscreen_changed"
    WINDOW_URGENT = "window::urgent"

    # Marks
    MARK_ADDED = "mark::added"
    MARK_REMOVED = "mark::removed"

    # Project/Visibility
    PROJECT_SWITCH = "project::switch"
    VISIBILITY_HIDDEN = "visibility::hidden"
    VISIBILITY_SHOWN = "visibility::shown"
    SCRATCHPAD_MOVE = "scratchpad::move"
    SCRATCHPAD_SHOW = "scratchpad::show"

    # Environment
    ENV_DETECTED = "env::detected"
    ENV_CHANGED = "env::changed"

    # Feature 101 Enhancement: Command execution tracing
    # These events track the actual Sway IPC commands being built and executed
    COMMAND_QUEUED = "command::queued"      # Command added to batch
    COMMAND_EXECUTED = "command::executed"  # Command sent to Sway
    COMMAND_RESULT = "command::result"      # Sway response (success/failure)
    COMMAND_BATCH = "command::batch"        # Batch of commands for a window

    # Feature 101 Enhancement: State source attribution
    # These events track where state information came from
    STATE_SAVED = "state::saved"            # State saved to workspace tracker
    STATE_LOADED = "state::loaded"          # State loaded from workspace tracker
    STATE_CONFLICT = "state::conflict"      # Saved state differs from live state

    # Feature 101 Enhancement: Pre-launch tracing
    # These events track the complete launch lifecycle before window appears
    LAUNCH_INTENT = "launch::intent"              # CLI registered pending trace for app
    LAUNCH_NOTIFICATION = "launch::notification"  # Daemon received notify_launch from wrapper
    LAUNCH_ENV_INJECTED = "launch::env_injected"  # I3PM_* environment variables captured
    LAUNCH_CORRELATED = "launch::correlated"      # Window matched to pending launch

    # Trace control
    TRACE_START = "trace::start"
    TRACE_STOP = "trace::stop"
    TRACE_SNAPSHOT = "trace::snapshot"


@dataclass
class WindowState:
    """Snapshot of window state at a point in time."""
    window_id: int
    app_id: Optional[str] = None
    window_class: Optional[str] = None
    title: Optional[str] = None
    pid: Optional[int] = None

    # Position
    workspace_num: Optional[int] = None
    workspace_name: Optional[str] = None
    output: Optional[str] = None

    # State flags
    focused: bool = False
    floating: bool = False
    fullscreen: bool = False
    urgent: bool = False
    hidden: bool = False  # In scratchpad or hidden by project switch

    # Geometry
    x: int = 0
    y: int = 0
    width: int = 0
    height: int = 0

    # Project context
    marks: List[str] = field(default_factory=list)
    project_name: Optional[str] = None
    scope: Optional[str] = None  # "scoped" | "global" | None

    # Environment (from /proc/<pid>/environ)
    env_vars: Dict[str, str] = field(default_factory=dict)

    def to_dict(self) -> Dict[str, Any]:
        return asdict(self)

    @classmethod
    def from_container(cls, container, env_vars: Optional[Dict[str, str]] = None) -> "WindowState":
        """Create WindowState from i3ipc Container."""
        # Get workspace info
        workspace = container.workspace()
        workspace_num = workspace.num if workspace else None
        workspace_name = workspace.name if workspace else None

        # Get output
        output = None
        if workspace:
            parent = workspace.parent
            while parent:
                if parent.type == "output":
                    output = parent.name
                    break
                parent = parent.parent

        # Parse marks for project info
        marks = list(container.marks) if container.marks else []
        project_name = None
        scope = None
        for mark in marks:
            if mark.startswith("scoped:"):
                scope = "scoped"
                # Extract project from scoped:PROJECT:WINDOW_ID
                parts = mark.split(":")
                if len(parts) >= 2:
                    # Handle qualified names with colons (account/repo:branch)
                    project_name = ":".join(parts[1:-1]) if len(parts) > 2 else parts[1]
            elif mark.startswith("global:"):
                scope = "global"

        # Geometry
        rect = container.rect or container.window_rect
        x = rect.x if rect else 0
        y = rect.y if rect else 0
        width = rect.width if rect else 0
        height = rect.height if rect else 0

        return cls(
            window_id=container.id,
            app_id=getattr(container, 'app_id', None),
            window_class=getattr(container, 'window_class', None) or getattr(container, 'app_id', None),
            title=container.name,
            pid=container.pid,
            workspace_num=workspace_num,
            workspace_name=workspace_name,
            output=output,
            focused=container.focused,
            floating=container.type == "floating_con" or (hasattr(container, 'floating') and container.floating),
            fullscreen=getattr(container, 'fullscreen_mode', 0) > 0,
            urgent=getattr(container, 'urgent', False),
            hidden=workspace_name == "__i3_scratch" if workspace_name else False,
            x=x,
            y=y,
            width=width,
            height=height,
            marks=marks,
            project_name=project_name,
            scope=scope,
            env_vars=env_vars or {},
        )


@dataclass
class TraceEvent:
    """A single event in a window's trace timeline."""
    timestamp: float
    event_type: TraceEventType
    description: str

    # State before and after (for comparison)
    state_before: Optional[WindowState] = None
    state_after: Optional[WindowState] = None

    # Additional context
    context: Dict[str, Any] = field(default_factory=dict)

    # Computed diff
    changes: Dict[str, Any] = field(default_factory=dict)

    # Feature 101 Enhancement: Causality and timing
    caused_by: Optional[str] = None  # ID of event that triggered this one
    delta_ms: Optional[float] = None  # Time since previous event (set by WindowTrace)

    # Feature 101 Phase 3: Enhanced causality tracking
    event_id: str = field(default_factory=lambda: f"evt-{int(time.time()*1000000) % 10000000:07d}")
    correlation_id: Optional[str] = None  # Groups related events (e.g., all from one project switch)
    causality_depth: int = 0  # Nesting depth in causality chain (0 = root event)

    def __post_init__(self):
        """Compute state diff if both states provided."""
        if self.state_before and self.state_after:
            self.changes = self._compute_diff()

    def _compute_diff(self) -> Dict[str, Any]:
        """Compute what changed between before and after states."""
        if not self.state_before or not self.state_after:
            return {}

        changes = {}
        before = self.state_before.to_dict()
        after = self.state_after.to_dict()

        for key in set(before.keys()) | set(after.keys()):
            if before.get(key) != after.get(key):
                changes[key] = {
                    "before": before.get(key),
                    "after": after.get(key),
                }

        return changes

    def to_dict(self) -> Dict[str, Any]:
        result = {
            "timestamp": self.timestamp,
            "time_iso": datetime.fromtimestamp(self.timestamp).isoformat(),
            "event_type": self.event_type.value,
            "description": self.description,
            "state_before": self.state_before.to_dict() if self.state_before else None,
            "state_after": self.state_after.to_dict() if self.state_after else None,
            "context": self.context,
            "changes": self.changes,
        }
        # Feature 101 Enhancement: Include timing and causality
        if self.delta_ms is not None:
            result["delta_ms"] = self.delta_ms
        if self.caused_by:
            result["caused_by"] = self.caused_by
        # Feature 101 Phase 3: Enhanced causality tracking
        result["event_id"] = self.event_id
        if self.correlation_id:
            result["correlation_id"] = self.correlation_id
        if self.causality_depth > 0:
            result["causality_depth"] = self.causality_depth
        return result

    def format_summary(self) -> str:
        """Format as a one-line summary for display."""
        ts = datetime.fromtimestamp(self.timestamp).strftime("%H:%M:%S.%f")[:-3]

        # Feature 101 Enhancement: Show delta timing
        delta_str = ""
        if self.delta_ms is not None:
            if self.delta_ms < 1:
                delta_str = f" (+<1ms)"
            elif self.delta_ms < 1000:
                delta_str = f" (+{self.delta_ms:.0f}ms)"
            else:
                delta_str = f" (+{self.delta_ms/1000:.1f}s)"

        change_summary = ""
        if self.changes:
            change_parts = []
            for key, val in list(self.changes.items())[:3]:
                change_parts.append(f"{key}: {val['before']} → {val['after']}")
            change_summary = f" [{', '.join(change_parts)}]"
        return f"[{ts}]{delta_str} {self.event_type.value}: {self.description}{change_summary}"


@dataclass
class CausalityContext:
    """Active causality context for grouping related events.

    Feature 101 Phase 3: When a high-level operation (e.g., project switch)
    triggers multiple lower-level events, this context groups them together.
    """
    correlation_id: str
    root_event_type: TraceEventType
    root_description: str
    started_at: float
    depth: int = 0
    parent_correlation_id: Optional[str] = None


@dataclass
class TimingBreakdown:
    """Breakdown of time spent in a category of events.

    Feature 101 Phase 3: Used by compute_timing() to analyze performance.
    """
    category: str
    total_ms: float
    event_count: int
    avg_ms: float
    min_ms: float
    max_ms: float


@dataclass
class TraceTiming:
    """Complete timing analysis for a trace.

    Feature 101 Phase 3: Comprehensive timing breakdown for performance analysis.
    """
    total_duration_ms: float
    by_category: Dict[str, TimingBreakdown]
    slow_operations: List["TraceEvent"]  # Events exceeding threshold
    causality_chains: Dict[str, float]  # correlation_id -> total_ms


@dataclass
class WindowTrace:
    """Complete trace for a single window."""
    trace_id: str
    window_id: int
    matcher: Dict[str, str]  # How we matched this window
    started_at: float
    stopped_at: Optional[float] = None

    # Timeline of events
    events: List[TraceEvent] = field(default_factory=list)

    # Current known state
    current_state: Optional[WindowState] = None

    # Max events to keep (prevent memory bloat)
    max_events: int = 1000

    @property
    def is_active(self) -> bool:
        return self.stopped_at is None

    @property
    def duration_seconds(self) -> float:
        end = self.stopped_at or time.time()
        return end - self.started_at

    def add_event(self, event: TraceEvent) -> None:
        """Add event to timeline, maintaining max size."""
        # Feature 101 Enhancement: Compute delta from previous event
        if self.events:
            prev_timestamp = self.events[-1].timestamp
            event.delta_ms = (event.timestamp - prev_timestamp) * 1000

        self.events.append(event)
        if len(self.events) > self.max_events:
            # Remove oldest events (keep most recent)
            self.events = self.events[-self.max_events:]

        # Update current state
        if event.state_after:
            self.current_state = event.state_after

    def to_dict(self) -> Dict[str, Any]:
        return {
            "trace_id": self.trace_id,
            "window_id": self.window_id,
            "matcher": self.matcher,
            "started_at": self.started_at,
            "started_at_iso": datetime.fromtimestamp(self.started_at).isoformat(),
            "stopped_at": self.stopped_at,
            "stopped_at_iso": datetime.fromtimestamp(self.stopped_at).isoformat() if self.stopped_at else None,
            "duration_seconds": self.duration_seconds,
            "is_active": self.is_active,
            "event_count": len(self.events),
            "current_state": self.current_state.to_dict() if self.current_state else None,
            "events": [e.to_dict() for e in self.events],
        }

    # =========================================================================
    # Feature 101 Phase 3: Timing Analysis Methods
    # =========================================================================

    def compute_timing(self, slow_threshold_ms: float = 100.0) -> TraceTiming:
        """Compute timing breakdown by event category.

        Args:
            slow_threshold_ms: Threshold for flagging slow operations

        Returns:
            TraceTiming with breakdown by category, slow operations, and causality chains
        """
        if not self.events:
            return TraceTiming(
                total_duration_ms=0.0,
                by_category={},
                slow_operations=[],
                causality_chains={},
            )

        # Group events by category (extract from event_type)
        by_category: Dict[str, List[TraceEvent]] = {}
        for event in self.events:
            category = event.event_type.value.split("::")[0]
            by_category.setdefault(category, []).append(event)

        # Compute statistics per category
        breakdowns: Dict[str, TimingBreakdown] = {}
        for category, events in by_category.items():
            deltas = [e.delta_ms for e in events if e.delta_ms is not None]
            if deltas:
                breakdowns[category] = TimingBreakdown(
                    category=category,
                    total_ms=sum(deltas),
                    event_count=len(deltas),
                    avg_ms=sum(deltas) / len(deltas),
                    min_ms=min(deltas),
                    max_ms=max(deltas),
                )

        # Find slow operations
        slow_operations = [
            e for e in self.events
            if e.delta_ms is not None and e.delta_ms > slow_threshold_ms
        ]

        # Compute causality chain durations
        causality_chains: Dict[str, float] = {}
        chain_events: Dict[str, List[TraceEvent]] = {}
        for event in self.events:
            if event.correlation_id:
                chain_events.setdefault(event.correlation_id, []).append(event)

        for corr_id, events in chain_events.items():
            if len(events) >= 2:
                duration = (events[-1].timestamp - events[0].timestamp) * 1000
                causality_chains[corr_id] = duration

        return TraceTiming(
            total_duration_ms=self.duration_seconds * 1000,
            by_category=breakdowns,
            slow_operations=slow_operations,
            causality_chains=causality_chains,
        )

    def get_slowest_operations(self, limit: int = 10) -> List[TraceEvent]:
        """Get the N slowest operations by delta_ms.

        Args:
            limit: Maximum number of events to return

        Returns:
            List of TraceEvents sorted by delta_ms descending
        """
        events_with_timing = [e for e in self.events if e.delta_ms is not None]
        events_with_timing.sort(key=lambda e: e.delta_ms or 0, reverse=True)
        return events_with_timing[:limit]

    def get_events_by_category(self, category: str) -> List[TraceEvent]:
        """Get all events in a category.

        Args:
            category: Event category (e.g., 'command', 'window', 'launch')

        Returns:
            List of TraceEvents in that category
        """
        return [e for e in self.events if e.event_type.value.startswith(f"{category}::")]

    def get_events_by_correlation(self, correlation_id: str) -> List[TraceEvent]:
        """Get all events in a causality chain.

        Args:
            correlation_id: The correlation ID to filter by

        Returns:
            List of TraceEvents with that correlation_id
        """
        return [e for e in self.events if e.correlation_id == correlation_id]

    def format_timeline(self, limit: int = 50, include_timing: bool = True) -> str:
        """Format trace as human-readable timeline.

        Feature 101 Phase 3: Enhanced with timing summary and causality visualization.

        Args:
            limit: Maximum number of events to show
            include_timing: Whether to include timing summary section
        """
        lines = [
            f"═══ Window Trace: {self.trace_id} ═══",
            f"Window ID: {self.window_id}",
            f"Matcher: {self.matcher}",
            f"Duration: {self.duration_seconds:.2f}s",
            f"Events: {len(self.events)}",
            f"Status: {'ACTIVE' if self.is_active else 'STOPPED'}",
        ]

        # Feature 101 Phase 3: Add timing summary
        if include_timing and self.events:
            timing = self.compute_timing()
            lines.extend([
                "",
                "─── Timing Summary ───",
                f"Total Duration: {timing.total_duration_ms:.0f}ms",
                "",
                "By Category:",
            ])
            for cat, breakdown in sorted(timing.by_category.items()):
                lines.append(
                    f"  {cat:12s} {breakdown.total_ms:7.0f}ms "
                    f"({breakdown.event_count} events, avg {breakdown.avg_ms:.1f}ms)"
                )

            # Show slow operations
            if timing.slow_operations:
                lines.extend([
                    "",
                    "Slow Operations (>100ms):",
                ])
                for event in timing.slow_operations[:5]:
                    ts = datetime.fromtimestamp(event.timestamp).strftime("%H:%M:%S.%f")[:-3]
                    lines.append(f"  [{ts}] {event.event_type.value} ({event.delta_ms:.0f}ms)")

            # Show causality chains
            if timing.causality_chains:
                lines.extend([
                    "",
                    "Causality Chains:",
                ])
                for corr_id, duration in sorted(
                    timing.causality_chains.items(),
                    key=lambda x: x[1],
                    reverse=True,
                )[:3]:
                    chain_events = self.get_events_by_correlation(corr_id)
                    if chain_events:
                        root = chain_events[0]
                        lines.append(
                            f"  {corr_id} ({duration:.0f}ms) - {root.event_type.value}: {root.description[:40]}"
                        )

        lines.extend([
            "",
            "─── Timeline ───",
        ])

        events_to_show = self.events[-limit:] if len(self.events) > limit else self.events
        if len(self.events) > limit:
            lines.append(f"(showing last {limit} of {len(self.events)} events)")

        for event in events_to_show:
            # Add indentation for events in causality chains
            prefix = "  " * event.causality_depth if event.causality_depth > 0 else ""
            lines.append(f"{prefix}{event.format_summary()}")

        if self.current_state:
            lines.extend([
                "",
                "─── Current State ───",
                f"  Class: {self.current_state.window_class}",
                f"  Title: {self.current_state.title}",
                f"  Workspace: {self.current_state.workspace_num} ({self.current_state.workspace_name})",
                f"  Output: {self.current_state.output}",
                f"  Floating: {self.current_state.floating}",
                f"  Hidden: {self.current_state.hidden}",
                f"  Marks: {self.current_state.marks}",
                f"  Project: {self.current_state.project_name} ({self.current_state.scope})",
            ])

        return "\n".join(lines)


class WindowTracer:
    """Manages window traces and captures state changes.

    This class is designed to be integrated with the i3 event handlers
    to capture window state changes in real-time.
    """

    def __init__(self, max_traces: int = 10):
        """Initialize tracer.

        Args:
            max_traces: Maximum number of concurrent traces to allow.
        """
        self.max_traces = max_traces
        self._traces: Dict[str, WindowTrace] = {}  # trace_id -> WindowTrace
        self._window_traces: Dict[int, Set[str]] = {}  # window_id -> set of trace_ids
        self._matchers: Dict[str, Dict[str, str]] = {}  # trace_id -> matcher config
        self._trace_counter = 0
        self._lock = asyncio.Lock()

        # Feature 101: Pre-launch tracing - traces waiting for app launch
        self._pending_app_traces: Dict[str, str] = {}  # app_name -> trace_id
        self._pending_trace_timeout: float = 30.0  # seconds

    def _generate_trace_id(self) -> str:
        """Generate unique trace ID."""
        self._trace_counter += 1
        return f"trace-{int(time.time())}-{self._trace_counter}"

    def _read_process_environ(self, pid: int) -> Dict[str, str]:
        """Read I3PM_* environment variables from process."""
        env_vars = {}
        try:
            environ_path = Path(f"/proc/{pid}/environ")
            if environ_path.exists():
                content = environ_path.read_bytes()
                for entry in content.split(b'\0'):
                    if entry.startswith(b'I3PM_'):
                        try:
                            key, _, value = entry.partition(b'=')
                            env_vars[key.decode()] = value.decode()
                        except (ValueError, UnicodeDecodeError):
                            pass
        except (PermissionError, FileNotFoundError, ProcessLookupError):
            pass
        return env_vars

    def _matches_window(self, container, matcher: Dict[str, str]) -> bool:
        """Check if a window matches the given matcher criteria."""
        if "id" in matcher:
            if container.id != int(matcher["id"]):
                return False

        if "class" in matcher:
            window_class = getattr(container, 'app_id', None) or getattr(container, 'window_class', None) or ""
            pattern = matcher["class"]
            if not re.search(pattern, window_class, re.IGNORECASE):
                return False

        if "title" in matcher:
            title = container.name or ""
            pattern = matcher["title"]
            if not re.search(pattern, title, re.IGNORECASE):
                return False

        if "pid" in matcher:
            if container.pid != int(matcher["pid"]):
                return False

        if "app_id" in matcher:
            app_id = getattr(container, 'app_id', None) or ""
            pattern = matcher["app_id"]
            if not re.search(pattern, app_id, re.IGNORECASE):
                return False

        return True

    async def start_trace(
        self,
        matcher: Dict[str, str],
        window_id: Optional[int] = None,
        initial_container=None,
    ) -> str:
        """Start tracing a window.

        Args:
            matcher: Dict with matching criteria (id, class, title, pid, app_id)
            window_id: Optional specific window ID to trace
            initial_container: Optional i3ipc container for initial state

        Returns:
            trace_id: Unique identifier for this trace

        Raises:
            ValueError: If max traces reached or invalid matcher
        """
        async with self._lock:
            if len(self._traces) >= self.max_traces:
                raise ValueError(f"Maximum traces ({self.max_traces}) reached. Stop a trace first.")

            if not matcher:
                raise ValueError("Matcher must specify at least one criterion (id, class, title, pid, app_id)")

            trace_id = self._generate_trace_id()

            # If window_id provided directly, use it
            if window_id is None and "id" in matcher:
                window_id = int(matcher["id"])

            if window_id is None:
                # We'll discover the window when events come in
                window_id = 0  # Placeholder

            trace = WindowTrace(
                trace_id=trace_id,
                window_id=window_id,
                matcher=matcher,
                started_at=time.time(),
            )

            # Add initial state if container provided
            if initial_container:
                env_vars = self._read_process_environ(initial_container.pid) if initial_container.pid else {}
                initial_state = WindowState.from_container(initial_container, env_vars)
                trace.current_state = initial_state
                trace.window_id = initial_container.id

                trace.add_event(TraceEvent(
                    timestamp=time.time(),
                    event_type=TraceEventType.TRACE_START,
                    description=f"Trace started for window {initial_container.id}",
                    state_after=initial_state,
                    context={"matcher": matcher},
                ))
            else:
                trace.add_event(TraceEvent(
                    timestamp=time.time(),
                    event_type=TraceEventType.TRACE_START,
                    description=f"Trace started, waiting for matching window",
                    context={"matcher": matcher},
                ))

            self._traces[trace_id] = trace
            self._matchers[trace_id] = matcher

            # Feature 101 fix: Use trace.window_id since it may have been updated
            # from initial_container.id (line 490). The parameter window_id could
            # still be 0 even when a valid container was provided.
            effective_window_id = trace.window_id
            if effective_window_id > 0:
                if effective_window_id not in self._window_traces:
                    self._window_traces[effective_window_id] = set()
                self._window_traces[effective_window_id].add(trace_id)
                logger.debug(
                    f"[Feature 101] Added trace {trace_id} to _window_traces[{effective_window_id}]"
                )

            logger.info(
                f"[WindowTracer] Started trace {trace_id} with matcher {matcher}, "
                f"window_id={effective_window_id}"
            )
            return trace_id

    async def stop_trace(self, trace_id: str) -> Optional[WindowTrace]:
        """Stop a trace and return final state.

        Args:
            trace_id: ID of trace to stop

        Returns:
            The stopped WindowTrace, or None if not found
        """
        async with self._lock:
            trace = self._traces.get(trace_id)
            if not trace:
                return None

            trace.stopped_at = time.time()
            trace.add_event(TraceEvent(
                timestamp=time.time(),
                event_type=TraceEventType.TRACE_STOP,
                description="Trace stopped",
                state_before=trace.current_state,
            ))

            # Remove from window mapping
            if trace.window_id in self._window_traces:
                self._window_traces[trace.window_id].discard(trace_id)
                if not self._window_traces[trace.window_id]:
                    del self._window_traces[trace.window_id]

            # Remove from matchers
            self._matchers.pop(trace_id, None)

            logger.info(f"[WindowTracer] Stopped trace {trace_id} ({len(trace.events)} events)")
            return trace

    async def record_event(
        self,
        container,
        event_type: TraceEventType,
        description: str,
        context: Optional[Dict[str, Any]] = None,
    ) -> List[str]:
        """Record an event for any matching traces.

        Args:
            container: i3ipc container that triggered the event
            event_type: Type of event
            description: Human-readable description
            context: Additional context data

        Returns:
            List of trace_ids that recorded this event
        """
        if not container:
            return []

        affected_traces = []

        async with self._lock:
            # Find traces that match this window
            matching_trace_ids = set()

            # Check direct window_id mapping
            if container.id in self._window_traces:
                matching_trace_ids.update(self._window_traces[container.id])

            # Check matchers for traces waiting for a window
            for trace_id, matcher in list(self._matchers.items()):
                trace = self._traces.get(trace_id)
                if not trace or not trace.is_active:
                    continue

                if trace.window_id == 0 and self._matches_window(container, matcher):
                    # This trace was waiting for a matching window
                    trace.window_id = container.id
                    if container.id not in self._window_traces:
                        self._window_traces[container.id] = set()
                    self._window_traces[container.id].add(trace_id)
                    matching_trace_ids.add(trace_id)
                    logger.info(f"[WindowTracer] Trace {trace_id} matched window {container.id}")
                elif self._matches_window(container, matcher):
                    matching_trace_ids.add(trace_id)

            # Record event in all matching traces
            for trace_id in matching_trace_ids:
                trace = self._traces.get(trace_id)
                if not trace or not trace.is_active:
                    continue

                # Get environment variables
                env_vars = self._read_process_environ(container.pid) if container.pid else {}

                # Create state snapshot
                new_state = WindowState.from_container(container, env_vars)

                trace.add_event(TraceEvent(
                    timestamp=time.time(),
                    event_type=event_type,
                    description=description,
                    state_before=trace.current_state,
                    state_after=new_state,
                    context=context or {},
                ))

                affected_traces.append(trace_id)

        return affected_traces

    async def get_trace(self, trace_id: str) -> Optional[WindowTrace]:
        """Get a trace by ID."""
        return self._traces.get(trace_id)

    async def list_traces(self) -> List[Dict[str, Any]]:
        """List all traces (active and stopped)."""
        return [
            {
                "trace_id": t.trace_id,
                "window_id": t.window_id,
                "matcher": t.matcher,
                "is_active": t.is_active,
                "event_count": len(t.events),
                "duration_seconds": t.duration_seconds,
                "started_at": datetime.fromtimestamp(t.started_at).isoformat(),
            }
            for t in self._traces.values()
        ]

    async def clear_stopped_traces(self) -> int:
        """Remove all stopped traces. Returns count removed."""
        async with self._lock:
            stopped = [tid for tid, t in self._traces.items() if not t.is_active]
            for tid in stopped:
                del self._traces[tid]
            return len(stopped)

    async def broadcast_event(
        self,
        event_type: TraceEventType,
        description: str,
        context: Optional[Dict[str, Any]] = None,
    ) -> List[str]:
        """Broadcast an event to all active traces.

        Feature 101: Used for global events like project::switch that affect
        all traced windows regardless of which specific window triggered them.

        Args:
            event_type: Type of event (e.g., PROJECT_SWITCH)
            description: Human-readable description
            context: Additional context data

        Returns:
            List of trace_ids that recorded this event
        """
        affected_traces = []

        async with self._lock:
            for trace_id, trace in self._traces.items():
                if not trace.is_active:
                    continue

                # Record event without state change (global event)
                trace.add_event(TraceEvent(
                    timestamp=time.time(),
                    event_type=event_type,
                    description=description,
                    state_before=trace.current_state,
                    state_after=trace.current_state,  # No state change for broadcast events
                    context=context or {},
                ))

                affected_traces.append(trace_id)

        if affected_traces:
            logger.debug(f"[WindowTracer] Broadcast {event_type.value} to {len(affected_traces)} traces")

        return affected_traces

    async def record_window_event(
        self,
        window_id: int,
        event_type: TraceEventType,
        description: str,
        context: Optional[Dict[str, Any]] = None,
    ) -> List[str]:
        """Record an event for traces watching a specific window ID.

        Feature 101 Enhancement: For events that don't have a container available
        (e.g., command execution) but know the window ID they affect.

        Args:
            window_id: The window ID this event affects
            event_type: Type of event
            description: Human-readable description
            context: Additional context data

        Returns:
            List of trace_ids that recorded this event
        """
        affected_traces = []

        async with self._lock:
            # Find traces watching this window
            trace_ids = self._window_traces.get(window_id, set())
            logger.debug(f"[WindowTracer] record_window_event for window {window_id}: found {len(trace_ids)} traces (all traces: {list(self._window_traces.keys())})")

            for trace_id in trace_ids:
                trace = self._traces.get(trace_id)
                if not trace or not trace.is_active:
                    continue

                trace.add_event(TraceEvent(
                    timestamp=time.time(),
                    event_type=event_type,
                    description=description,
                    state_before=trace.current_state,
                    state_after=trace.current_state,  # No state change
                    context=context or {},
                ))

                affected_traces.append(trace_id)

        if affected_traces:
            logger.debug(f"[WindowTracer] Recorded {event_type.value} for window {window_id} in {len(affected_traces)} traces")

        return affected_traces

    async def take_snapshot(self, trace_id: str, container) -> bool:
        """Take a manual snapshot of window state.

        Useful for capturing state at specific points in time.
        """
        trace = self._traces.get(trace_id)
        if not trace or not trace.is_active:
            return False

        env_vars = self._read_process_environ(container.pid) if container.pid else {}
        new_state = WindowState.from_container(container, env_vars)

        trace.add_event(TraceEvent(
            timestamp=time.time(),
            event_type=TraceEventType.TRACE_SNAPSHOT,
            description="Manual snapshot",
            state_before=trace.current_state,
            state_after=new_state,
        ))

        return True

    # =========================================================================
    # Feature 101: Pre-launch tracing methods
    # =========================================================================

    async def start_app_trace(
        self,
        app_name: str,
        timeout: float = 30.0,
    ) -> str:
        """Start tracing for next launch of an app.

        Creates a pending trace that activates when the app launches.
        The trace automatically expires after the timeout if no launch occurs.

        Args:
            app_name: Application registry name (e.g., "terminal", "code")
            timeout: Seconds before pending trace expires without launch

        Returns:
            trace_id for the pending trace

        Raises:
            ValueError: If max traces reached
        """
        async with self._lock:
            if len(self._traces) >= self.max_traces:
                raise ValueError(f"Maximum traces ({self.max_traces}) reached")

            trace_id = self._generate_trace_id()

            # Create trace with app_name matcher (window_id=0 until launch)
            trace = WindowTrace(
                trace_id=trace_id,
                window_id=0,  # Unknown until launch
                matcher={"app_name": app_name},
                started_at=time.time(),
            )

            trace.add_event(TraceEvent(
                timestamp=time.time(),
                event_type=TraceEventType.LAUNCH_INTENT,
                description=f"Waiting for launch of app '{app_name}'",
                context={
                    "app_name": app_name,
                    "timeout": timeout,
                },
            ))

            self._traces[trace_id] = trace
            self._matchers[trace_id] = {"app_name": app_name}
            self._pending_app_traces[app_name] = trace_id

            # Schedule timeout cleanup
            asyncio.create_task(
                self._pending_trace_timeout_handler(trace_id, app_name, timeout)
            )

            logger.info(f"[WindowTracer] Started app trace {trace_id} for '{app_name}' (timeout={timeout}s)")
            return trace_id

    async def _pending_trace_timeout_handler(
        self,
        trace_id: str,
        app_name: str,
        timeout: float,
    ) -> None:
        """Handle timeout for pending traces.

        Auto-stops the trace if no launch occurs within the timeout period.
        """
        await asyncio.sleep(timeout)

        async with self._lock:
            # Check if trace is still pending (not yet correlated with a window)
            if app_name in self._pending_app_traces:
                if self._pending_app_traces[app_name] == trace_id:
                    del self._pending_app_traces[app_name]
                    trace = self._traces.get(trace_id)
                    if trace and trace.is_active and trace.window_id == 0:
                        trace.add_event(TraceEvent(
                            timestamp=time.time(),
                            event_type=TraceEventType.TRACE_STOP,
                            description=f"Pending trace expired after {timeout}s (no launch detected)",
                            context={"timeout": timeout, "reason": "expired"},
                        ))
                        trace.stopped_at = time.time()
                        logger.warning(f"[WindowTracer] Trace {trace_id} expired (no launch for '{app_name}')")

    async def get_pending_trace_for_app(self, app_name: str) -> Optional[str]:
        """Get pending trace ID for an app if one exists.

        Args:
            app_name: Application registry name

        Returns:
            trace_id if a pending trace exists, None otherwise
        """
        return self._pending_app_traces.get(app_name)

    async def record_launch_notification(
        self,
        trace_id: str,
        app_name: str,
        project_name: Optional[str],
        workspace_number: Optional[int],
        expected_class: Optional[str],
        launcher_pid: Optional[int],
        env_vars: Dict[str, str],
    ) -> None:
        """Record launch notification events for a trace.

        Called when daemon receives notify_launch for a traced app.

        Args:
            trace_id: The pending trace ID
            app_name: App name from launch notification
            project_name: Project name if in project context
            workspace_number: Target workspace number
            expected_class: Expected window class for matching
            launcher_pid: PID of the launcher wrapper script
            env_vars: All environment variables being set
        """
        trace = self._traces.get(trace_id)
        if not trace or not trace.is_active:
            return

        # Record notification received
        trace.add_event(TraceEvent(
            timestamp=time.time(),
            event_type=TraceEventType.LAUNCH_NOTIFICATION,
            description=f"Launch notification received for '{app_name}'",
            context={
                "app_name": app_name,
                "project_name": project_name,
                "workspace_number": workspace_number,
                "expected_class": expected_class,
                "launcher_pid": launcher_pid,
            },
        ))

        # Record I3PM_* environment variables
        i3pm_vars = {k: v for k, v in env_vars.items() if k.startswith("I3PM_")}
        trace.add_event(TraceEvent(
            timestamp=time.time(),
            event_type=TraceEventType.LAUNCH_ENV_INJECTED,
            description=f"Environment variables injected ({len(i3pm_vars)} I3PM_* vars)",
            context={"env_vars": i3pm_vars},
        ))

        logger.debug(f"[WindowTracer] Recorded launch notification for trace {trace_id}")

    async def record_launch_correlation(
        self,
        trace_id: str,
        window_id: int,
        container,
        correlation_confidence: float,
    ) -> None:
        """Record window correlation event.

        Called when window::new correlates a window to a pending launch.
        This "activates" the trace by associating it with the actual window.

        Args:
            trace_id: The pending trace ID
            window_id: The newly created window's ID
            container: The i3ipc container object
            correlation_confidence: Match confidence (0.0-1.0)
        """
        async with self._lock:
            trace = self._traces.get(trace_id)
            if not trace or not trace.is_active:
                return

            # Update trace with actual window ID
            trace.window_id = window_id

            # Add to window_traces mapping for future events
            if window_id not in self._window_traces:
                self._window_traces[window_id] = set()
            self._window_traces[window_id].add(trace_id)

            # Remove from pending (launch has occurred)
            app_name = trace.matcher.get("app_name")
            if app_name and app_name in self._pending_app_traces:
                del self._pending_app_traces[app_name]

            # Capture window state
            env_vars = self._read_process_environ(container.pid) if container.pid else {}
            state = WindowState.from_container(container, env_vars)
            trace.current_state = state

            trace.add_event(TraceEvent(
                timestamp=time.time(),
                event_type=TraceEventType.LAUNCH_CORRELATED,
                description=f"Window {window_id} correlated with confidence {correlation_confidence:.2f}",
                state_after=state,
                context={
                    "window_id": window_id,
                    "correlation_confidence": correlation_confidence,
                    "window_class": state.window_class,
                    "window_pid": container.pid,
                    "time_to_correlate_ms": (time.time() - trace.started_at) * 1000,
                },
            ))

            logger.info(f"[WindowTracer] Trace {trace_id} matched window {window_id}")


# Global tracer instance (initialized by daemon)
_tracer: Optional[WindowTracer] = None


def get_tracer() -> Optional[WindowTracer]:
    """Get the global WindowTracer instance."""
    return _tracer


def init_tracer(max_traces: int = 10) -> WindowTracer:
    """Initialize the global WindowTracer."""
    global _tracer
    _tracer = WindowTracer(max_traces=max_traces)
    logger.info(f"[WindowTracer] Initialized with max_traces={max_traces}")
    return _tracer
