"""
Monitoring Panel Data Backend Script

Queries i3pm daemon for window/workspace/project state and outputs JSON for Eww consumption.

Usage:
    python3 -m i3_project_manager.cli.monitoring_data                   # Windows view (default)
    python3 -m i3_project_manager.cli.monitoring_data --mode projects   # Projects view
    python3 -m i3_project_manager.cli.monitoring_data --mode apps       # Apps view
    python3 -m i3_project_manager.cli.monitoring_data --mode events     # Events view
    python3 -m i3_project_manager.cli.monitoring_data --mode health     # Health view
    python3 -m i3_project_manager.cli.monitoring_data --mode traces     # Window traces view (Feature 101)
    python3 -m i3_project_manager.cli.monitoring_data --listen          # Stream mode (deflisten)

Output: Single-line JSON to stdout (see contracts/eww-defpoll.md)

Performance: <50ms execution time for typical workload (20-30 windows)

Stream Mode (--listen):
    - Subscribes to Sway window/workspace/output events
    - Outputs JSON on every state change (<100ms latency)
    - Includes heartbeat every 5s to detect stale connections
    - Automatic reconnection with exponential backoff
    - Graceful shutdown on SIGTERM/SIGPIPE
"""

import argparse
import asyncio
import json
import logging
import os
import re
import signal
import subprocess
import sys
import time
from collections import deque
from pathlib import Path
from typing import Any, Dict, List, Optional, Literal

# Pydantic for data validation (Feature 092)
from pydantic import BaseModel, Field

# Import daemon client from core module
from i3_project_manager.core.daemon_client import DaemonClient, DaemonError

# Feature 097: Import models and utilities for project hierarchy
from i3_project_manager.models.project_config import (
    ProjectConfig,
    SourceType,
    ProjectStatus,
    GitMetadata,
    RepositoryWithWorktrees,
    PanelProjectsData,
)
from i3_project_manager.services.git_utils import (
    detect_orphaned_worktrees,
    get_bare_repository_path,
    format_relative_time,
)

# Import i3ipc for event subscriptions in listen mode
try:
    from i3ipc.aio import Connection as I3Connection
except ImportError:
    I3Connection = None  # Gracefully handle missing i3ipc in one-shot mode

# Feature 095 Enhancement: Animated spinner frames for "working" state badges
# Braille dot spinner: elegant, modern, 10 frames cycling every 120ms
SPINNER_FRAMES = ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"]
SPINNER_INTERVAL_MS = 120  # milliseconds per frame


def get_spinner_frame() -> str:
    """Get current spinner frame based on time.

    Uses millisecond precision to determine which frame to show.
    Frame changes every SPINNER_INTERVAL_MS milliseconds.
    """
    ms = int(time.time() * 1000)
    idx = (ms // SPINNER_INTERVAL_MS) % len(SPINNER_FRAMES)
    return SPINNER_FRAMES[idx]


# Feature 095: File-based badge state directory
# Badge state files are written by claude-hooks scripts and read by this script
# Format: $XDG_RUNTIME_DIR/i3pm-badges/<window_id>.json
BADGE_STATE_DIR = Path(os.environ.get("XDG_RUNTIME_DIR", f"/run/user/{os.getuid()}")) / "i3pm-badges"

# Feature 107: inotify watcher for immediate badge detection (<15ms latency)
# Uses subprocess inotifywait to avoid adding Python dependencies
INOTIFYWAIT_CMD = "inotifywait"  # Requires inotify-tools package


def load_badge_state_from_files() -> Dict[str, Any]:
    """Load badge state from filesystem.

    Feature 095: File-based badge tracking without daemon dependency.
    Reads JSON files from $XDG_RUNTIME_DIR/i3pm-badges/<window_id>.json

    Returns:
        Dict mapping window_id (string) to badge metadata
    """
    badge_state: Dict[str, Any] = {}

    if not BADGE_STATE_DIR.exists():
        return badge_state

    for badge_file in BADGE_STATE_DIR.glob("*.json"):
        try:
            with open(badge_file, "r") as f:
                badge_data = json.load(f)
                window_id = badge_file.stem  # filename without .json extension
                badge_state[window_id] = badge_data
                logger.debug(f"Feature 095: Loaded badge for window {window_id}: {badge_data.get('state', 'unknown')}")
        except (json.JSONDecodeError, IOError) as e:
            logger.warning(f"Feature 095: Failed to read badge file {badge_file}: {e}")
            continue

    return badge_state


async def create_badge_watcher() -> Optional[asyncio.subprocess.Process]:
    """Create inotify watcher subprocess for badge directory.

    Feature 107: Uses inotifywait for immediate badge file detection (<15ms latency).
    Falls back to polling if inotifywait is not available.

    Returns:
        Subprocess process if inotifywait available, None otherwise.
    """
    import shutil

    # Check if inotifywait is available
    if not shutil.which(INOTIFYWAIT_CMD):
        logger.warning("Feature 107: inotifywait not found, falling back to polling")
        return None

    # Ensure badge directory exists before watching
    BADGE_STATE_DIR.mkdir(parents=True, exist_ok=True)

    try:
        # inotifywait in monitor mode (-m) outputs events as they happen
        # -e create,modify,delete watches for file changes
        # -q quiet mode (no startup message)
        # --format outputs just the event type and filename
        process = await asyncio.create_subprocess_exec(
            INOTIFYWAIT_CMD,
            "-m",           # Monitor mode (continuous)
            "-q",           # Quiet (no initial watching message)
            "-e", "create,modify,delete,moved_to",
            "--format", "%e %f",  # Event type and filename
            str(BADGE_STATE_DIR),
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.DEVNULL,
        )
        logger.info(f"Feature 107: Started inotify watcher on {BADGE_STATE_DIR} (pid={process.pid})")
        return process
    except Exception as e:
        logger.warning(f"Feature 107: Failed to start inotify watcher: {e}")
        return None


async def read_inotify_events(
    process: asyncio.subprocess.Process,
    on_badge_change: asyncio.Event,
) -> None:
    """Read inotify events from subprocess and signal badge changes.

    Feature 107: Runs as background task, sets event when badge files change.

    Args:
        process: inotifywait subprocess
        on_badge_change: Event to set when badge file changes detected
    """
    if process.stdout is None:
        return

    try:
        while True:
            line = await process.stdout.readline()
            if not line:
                # EOF - process terminated
                logger.warning("Feature 107: inotifywait process terminated")
                break

            # Parse event line: "EVENT_TYPE filename"
            event_line = line.decode().strip()
            if event_line:
                logger.debug(f"Feature 107: inotify event: {event_line}")
                # Signal that badge files changed
                on_badge_change.set()

    except asyncio.CancelledError:
        logger.debug("Feature 107: inotify reader cancelled")
        raise
    except Exception as e:
        logger.warning(f"Feature 107: Error reading inotify events: {e}")


# Icon resolution - loads from application-registry.json and pwa-registry.json
# Uses XDG icon theme lookup for icon names (like "firefox" -> /usr/share/icons/.../firefox.png)
_icon_registry: Optional[Dict[str, str]] = None
_icon_cache: Dict[str, str] = {}
APP_REGISTRY_PATH = Path.home() / ".config/i3/application-registry.json"
PWA_REGISTRY_PATH = Path.home() / ".config/i3/pwa-registry.json"

# Icon search directories for manual fallback
ICON_SEARCH_DIRS = [
    Path.home() / ".local/share/icons",
    Path.home() / ".icons",
    Path("/usr/share/icons"),
    Path("/usr/share/pixmaps"),
]
ICON_EXTENSIONS = (".svg", ".png", ".xpm")

# Try to import XDG icon theme lookup
try:
    from xdg.IconTheme import getIconPath
except ImportError:
    getIconPath = None


# Service Registry for Health Monitoring (Feature 088)
# Defines all monitored systemd services categorized by functional role
SERVICE_REGISTRY = {
    "core": [
        {
            "name": "i3-project-daemon",
            "display_name": "i3 Project Daemon",
            "is_user_service": False,
            "socket_activated": True,
            "socket_name": "i3-project-daemon.socket",
            "conditional": False,
            "description": "Window management and project context daemon",
        },
        {
            "name": "workspace-preview-daemon",
            "display_name": "Workspace Preview Daemon",
            "is_user_service": True,
            "socket_activated": False,
            "conditional": False,
            "description": "Workspace preview data provider for Eww workspace bar",
        },
        {
            "name": "sway-tree-monitor",
            "display_name": "Sway Tree Monitor",
            "is_user_service": True,
            "socket_activated": False,
            "conditional": False,
            "description": "Real-time Sway tree diff monitoring daemon",
        },
    ],
    "ui": [
        {
            "name": "eww-top-bar",
            "display_name": "Eww Top Bar",
            "is_user_service": True,
            "socket_activated": False,
            "conditional": False,
            "description": "System metrics and status bar",
        },
        {
            "name": "eww-workspace-bar",
            "display_name": "Eww Workspace Bar",
            "is_user_service": True,
            "socket_activated": False,
            "conditional": False,
            "description": "Workspace navigation and project preview bar",
        },
        {
            "name": "eww-monitoring-panel",
            "display_name": "Eww Monitoring Panel",
            "is_user_service": True,
            "socket_activated": False,
            "conditional": False,
            "description": "Window/project/health monitoring panel",
        },
        {
            "name": "eww-quick-panel",
            "display_name": "Eww Quick Panel",
            "is_user_service": True,
            "socket_activated": False,
            "conditional": False,
            "description": "Quick settings panel",
        },
        {
            "name": "swaync",
            "display_name": "SwayNC",
            "is_user_service": True,
            "socket_activated": False,
            "conditional": False,
            "description": "Notification center",
        },
        {
            "name": "sov",
            "display_name": "Sway Overview (sov)",
            "is_user_service": True,
            "socket_activated": False,
            "conditional": False,
            "description": "Workspace overview visualization",
        },
        {
            "name": "elephant",
            "display_name": "Elephant Launcher",
            "is_user_service": True,
            "socket_activated": False,
            "conditional": False,
            "description": "Application launcher (Walker backend)",
        },
    ],
    # T039: Removed i3wsr (legacy service - not installed/used)
    "system": [
        {
            "name": "sway-config-manager",
            "display_name": "Sway Config Manager",
            "is_user_service": True,
            "socket_activated": False,
            "conditional": False,
            "description": "Hot-reloadable Sway configuration manager",
        },
    ],
    "optional": [
        {
            "name": "wayvnc@HEADLESS-1",
            "display_name": "WayVNC (Display 1)",
            "is_user_service": True,
            "socket_activated": False,
            "conditional": True,
            "condition_profiles": ["single", "dual", "triple", "local+1vnc", "local+2vnc"],
            "description": "VNC server for virtual display 1",
        },
        {
            "name": "wayvnc@HEADLESS-2",
            "display_name": "WayVNC (Display 2)",
            "is_user_service": True,
            "socket_activated": False,
            "conditional": True,
            "condition_profiles": ["dual", "triple", "local+2vnc"],
            "description": "VNC server for virtual display 2",
        },
        {
            "name": "wayvnc@HEADLESS-3",
            "display_name": "WayVNC (Display 3)",
            "is_user_service": True,
            "socket_activated": False,
            "conditional": True,
            "condition_profiles": ["triple"],
            "description": "VNC server for virtual display 3 (Hetzner only)",
        },
        {
            "name": "tailscale-rtp-default-sink",
            "display_name": "Tailscale RTP Audio Sink",
            "is_user_service": True,
            "socket_activated": False,
            "conditional": True,
            "condition_profiles": ["single", "dual", "triple"],
            "description": "Set PipeWire default sink to Tailscale RTP (headless only)",
        },
    ],
}


# =============================================================================
# Feature 092: Event Logging - Data Models
# =============================================================================

# Event type literals for Sway IPC events
EventType = Literal[
    "window::new",
    "window::close",
    "window::focus",
    "window::move",
    "window::floating",
    "window::fullscreen_mode",
    "window::title",
    "window::mark",
    "window::urgent",
    "workspace::focus",
    "workspace::init",
    "workspace::empty",
    "workspace::move",
    "workspace::rename",
    "workspace::urgent",
    "workspace::reload",
    "output::unspecified",
    "binding::run",
    "mode::change",
    "shutdown::exit",
    "tick::manual",
]


class SwayEventPayload(BaseModel):
    """
    Raw Sway IPC event payload (varies by event type).

    Common fields:
    - container: Window/workspace/output container data
    - change: Type of change that occurred
    - current: Current state (for workspace/output focus events)
    - old: Previous state (for workspace/output focus events)
    """
    # Window events
    container: Optional[Dict[str, Any]] = None

    # Workspace events
    current: Optional[Dict[str, Any]] = None
    old: Optional[Dict[str, Any]] = None

    # Binding events
    binding: Optional[Dict[str, Any]] = None

    # Mode events
    change: Optional[str] = None
    pango_markup: Optional[bool] = None

    # Raw event data (catch-all)
    raw: Dict[str, Any] = Field(default_factory=dict)


class EventEnrichment(BaseModel):
    """
    i3pm daemon metadata enrichment for window-related events.

    Only populated for window::* events when i3pm daemon is available.
    """
    # Window identification
    window_id: Optional[int] = None
    pid: Optional[int] = None

    # App registry metadata
    app_name: Optional[str] = None  # From I3PM_APP_NAME or app registry
    app_id: Optional[str] = None    # Full app ID with instance suffix
    icon_path: Optional[str] = None  # Resolved icon file path

    # Project association
    project_name: Optional[str] = None  # i3pm project name
    scope: Optional[Literal["scoped", "global"]] = None

    # Workspace context
    workspace_number: Optional[int] = None
    workspace_name: Optional[str] = None
    output_name: Optional[str] = None

    # PWA detection
    is_pwa: bool = False  # True if workspace >= 50

    # Enrichment metadata
    daemon_available: bool = True  # False if i3pm daemon unreachable
    enrichment_latency_ms: Optional[float] = None  # Time to query daemon


class Event(BaseModel):
    """
    Complete event record with timestamp, type, payload, and enrichment.

    This is the primary data structure stored in the event buffer and
    sent to the Eww UI for display.
    """
    # Core event data
    timestamp: float  # Unix timestamp (seconds since epoch)
    timestamp_friendly: str  # Human-friendly relative time ("5s ago")
    event_type: EventType  # Sway event type (e.g., "window::new")
    change_type: Optional[str] = None  # Sub-type for some events

    # Event payload
    payload: SwayEventPayload

    # i3pm enrichment (optional)
    enrichment: Optional[EventEnrichment] = None

    # Display metadata
    icon: str  # Nerd Font icon for event type
    color: str  # Catppuccin Mocha color hex code

    # Feature 102: Event source indicator (T017)
    source: Literal["sway", "i3pm"] = "sway"  # Event source (sway IPC or i3pm internal)

    # Categorization - Feature 102: Added i3pm categories (T017)
    category: Literal["window", "workspace", "output", "binding", "mode", "system",
                      "project", "visibility", "scratchpad", "launch", "state", "command", "trace"]

    # Feature 102 (T028): Trace cross-reference
    trace_id: Optional[str] = None  # Active trace ID if event is part of a trace
    correlation_id: Optional[str] = None  # Causality chain identifier
    causality_depth: int = 0  # Nesting depth in causality chain

    # Feature 102 T066-T067: Cross-reference validity indicators
    trace_evicted: bool = False  # True if trace_id references a trace no longer in buffer
    parent_missing: bool = False  # True if correlation_id set but parent event not in current view

    # Feature 102 T052: Event performance metrics
    processing_duration_ms: float = 0.0  # Event handler processing time (daemon events only)

    # Filtering support
    searchable_text: str  # Concatenated text for search


class EventsViewData(BaseModel):
    """
    Complete response for events view mode.

    Sent from Python backend to Eww frontend via deflisten streaming.
    """
    # Response status
    status: Literal["ok", "error"]
    error: Optional[str] = None

    # Event data
    events: List[Event] = Field(default_factory=list)

    # Feature 102 T053: Events sorted by duration (slowest first) for sort-by-duration UI
    events_by_duration: List[Event] = Field(default_factory=list)

    # Metadata
    event_count: int = 0  # Total events in buffer
    filtered_count: Optional[int] = None  # Count after filtering
    oldest_timestamp: Optional[float] = None
    newest_timestamp: Optional[float] = None

    # Feature 102 T054: Aggregate performance statistics
    avg_duration_ms: float = 0.0  # Average processing time across events
    slow_event_count: int = 0  # Events with duration > 100ms
    critical_event_count: int = 0  # Events with duration > 500ms

    # Feature 102 T064-T065: Burst handling statistics (from daemon EventBuffer)
    burst_active: bool = False  # Currently in burst mode (>100 events/sec)
    burst_collapsed_current: int = 0  # Events collapsed in current burst
    total_bursts: int = 0  # Total burst periods detected
    total_collapsed: int = 0  # Total events collapsed across all bursts

    # System state
    daemon_available: bool = True  # i3pm daemon reachability
    ipc_connected: bool = True  # Sway IPC connection status

    # Timestamps
    timestamp: float  # Query execution time
    timestamp_friendly: str  # Human-friendly time


class EventBuffer:
    """
    Circular buffer for event storage with automatic FIFO eviction.

    Uses Python deque with maxlen for O(1) append and automatic eviction.
    Thread-safe for single-writer scenarios (event loop).
    """

    def __init__(self, max_size: int = 500):
        """
        Initialize event buffer.

        Args:
            max_size: Maximum number of events to retain (default 500)
        """
        self._buffer: deque[Event] = deque(maxlen=max_size)
        self._max_size = max_size

    def append(self, event: Event) -> None:
        """
        Add event to buffer (automatically evicts oldest if full).

        Args:
            event: Event to append
        """
        self._buffer.append(event)

    def get_all(self, refresh_timestamps: bool = False) -> List[Event]:
        """
        Get all buffered events (oldest first, newest last).

        Args:
            refresh_timestamps: If True, recalculate timestamp_friendly for all events

        Returns:
            List of events in chronological order
        """
        events = list(self._buffer)

        if refresh_timestamps:
            # Refresh timestamp_friendly for all events based on current time
            for event in events:
                event.timestamp_friendly = format_friendly_timestamp(event.timestamp)

        return events

    def clear(self) -> None:
        """Clear all events from buffer."""
        self._buffer.clear()

    def size(self) -> int:
        """Get current buffer size."""
        return len(self._buffer)

    @property
    def max_size(self) -> int:
        """Get maximum buffer capacity."""
        return self._max_size

    def get_performance_stats(self) -> Dict[str, Any]:
        """Get aggregate performance statistics for events in buffer.

        Feature 102 T054: Calculate average duration and count slow events.

        Returns:
            Dict with avg_duration_ms, slow_event_count, critical_event_count
        """
        events = list(self._buffer)
        if not events:
            return {
                "avg_duration_ms": 0.0,
                "slow_event_count": 0,
                "critical_event_count": 0,
            }

        # Calculate average duration (only for events with non-zero duration)
        durations = [e.processing_duration_ms for e in events if e.processing_duration_ms > 0]
        avg_duration = sum(durations) / len(durations) if durations else 0.0

        # Count slow events (>100ms) and critical events (>500ms)
        slow_count = sum(1 for e in events if e.processing_duration_ms > 100)
        critical_count = sum(1 for e in events if e.processing_duration_ms > 500)

        return {
            "avg_duration_ms": round(avg_duration, 2),
            "slow_event_count": slow_count,
            "critical_event_count": critical_count,
        }


# Event icon mapping with Nerd Font icons and Catppuccin Mocha colors
# Feature 102: Added i3pm internal events with distinct source indicator
EVENT_ICONS = {
    # Window events (Sway)
    "window::new": {"icon": "󰖲", "color": "#89b4fa", "source": "sway"},  # Blue
    "window::close": {"icon": "󰖶", "color": "#f38ba8", "source": "sway"},  # Red
    "window::focus": {"icon": "󰋁", "color": "#74c7ec", "source": "sway"},  # Sapphire
    "window::blur": {"icon": "󰋀", "color": "#6c7086", "source": "sway"},  # Overlay - Feature 102
    "window::move": {"icon": "󰁔", "color": "#fab387", "source": "sway"},  # Peach
    "window::floating": {"icon": "󰉈", "color": "#f9e2af", "source": "sway"},  # Yellow
    "window::fullscreen_mode": {"icon": "󰊓", "color": "#cba6f7", "source": "sway"},  # Mauve
    "window::title": {"icon": "󰓹", "color": "#a6adc8", "source": "sway"},  # Subtext
    "window::mark": {"icon": "󰃀", "color": "#94e2d5", "source": "sway"},  # Teal
    "window::urgent": {"icon": "󰀪", "color": "#f38ba8", "source": "sway"},  # Red

    # Workspace events (Sway)
    "workspace::focus": {"icon": "󱂬", "color": "#94e2d5", "source": "sway"},  # Teal
    "workspace::init": {"icon": "󰐭", "color": "#a6e3a1", "source": "sway"},  # Green
    "workspace::empty": {"icon": "󰭀", "color": "#6c7086", "source": "sway"},  # Overlay
    "workspace::move": {"icon": "󰁔", "color": "#fab387", "source": "sway"},  # Peach
    "workspace::rename": {"icon": "󰑕", "color": "#89dceb", "source": "sway"},  # Sky
    "workspace::urgent": {"icon": "󰀪", "color": "#f38ba8", "source": "sway"},  # Red
    "workspace::reload": {"icon": "󰑓", "color": "#a6e3a1", "source": "sway"},  # Green

    # Output events (Sway - enhanced with Feature 102)
    "output::unspecified": {"icon": "󰍹", "color": "#cba6f7", "source": "sway"},  # Mauve
    "output::connected": {"icon": "󰍹", "color": "#a6e3a1", "source": "sway"},  # Green - Feature 102
    "output::disconnected": {"icon": "󰍺", "color": "#f38ba8", "source": "sway"},  # Red - Feature 102
    "output::profile_changed": {"icon": "󰄫", "color": "#89dceb", "source": "sway"},  # Sky - Feature 102

    # Binding/mode events (Sway)
    "binding::run": {"icon": "󰌌", "color": "#f9e2af", "source": "sway"},  # Yellow
    "mode::change": {"icon": "󰘧", "color": "#89dceb", "source": "sway"},  # Sky

    # System events (Sway)
    "shutdown::exit": {"icon": "󰚌", "color": "#f38ba8", "source": "sway"},  # Red
    "tick::manual": {"icon": "󰥔", "color": "#6c7086", "source": "sway"},  # Overlay

    # =========================================================================
    # Feature 102: i3pm Internal Events
    # These events are generated by the i3pm daemon, not raw Sway IPC
    # All use Peach (#fab387) or Mauve (#cba6f7) for i3pm distinction
    # =========================================================================

    # Project events (i3pm)
    "project::switch": {"icon": "󰒍", "color": "#fab387", "source": "i3pm"},  # Peach - project switch
    "project::clear": {"icon": "󰆴", "color": "#fab387", "source": "i3pm"},  # Peach - clear project

    # Visibility events (i3pm)
    "visibility::hidden": {"icon": "󰈈", "color": "#cba6f7", "source": "i3pm"},  # Mauve - window hidden
    "visibility::shown": {"icon": "󰈉", "color": "#a6e3a1", "source": "i3pm"},  # Green - window shown
    "scratchpad::move": {"icon": "󰘓", "color": "#cba6f7", "source": "i3pm"},  # Mauve - scratchpad move

    # Command events (i3pm - Feature 102)
    "command::queued": {"icon": "󰒲", "color": "#89dceb", "source": "i3pm"},  # Sky - queued
    "command::executed": {"icon": "󰑮", "color": "#a6e3a1", "source": "i3pm"},  # Green - executed
    "command::result": {"icon": "󰄬", "color": "#94e2d5", "source": "i3pm"},  # Teal - result
    "command::batch": {"icon": "󱁤", "color": "#f9e2af", "source": "i3pm"},  # Yellow - batch

    # Launch events (i3pm)
    "launch::intent": {"icon": "󰐊", "color": "#89b4fa", "source": "i3pm"},  # Blue - intent
    "launch::notification": {"icon": "󰗗", "color": "#89dceb", "source": "i3pm"},  # Sky - notification
    "launch::env_injected": {"icon": "󰆼", "color": "#94e2d5", "source": "i3pm"},  # Teal - env injected
    "launch::correlated": {"icon": "󰄾", "color": "#a6e3a1", "source": "i3pm"},  # Green - correlated

    # State events (i3pm)
    "state::saved": {"icon": "󰆓", "color": "#a6e3a1", "source": "i3pm"},  # Green - saved
    "state::loaded": {"icon": "󰈔", "color": "#89b4fa", "source": "i3pm"},  # Blue - loaded
    "state::conflict": {"icon": "󰆘", "color": "#f38ba8", "source": "i3pm"},  # Red - conflict

    # Mark events (i3pm)
    "mark::added": {"icon": "󰃀", "color": "#94e2d5", "source": "i3pm"},  # Teal - added
    "mark::removed": {"icon": "󰃁", "color": "#6c7086", "source": "i3pm"},  # Overlay - removed

    # Environment events (i3pm)
    "env::detected": {"icon": "󰆼", "color": "#89dceb", "source": "i3pm"},  # Sky - detected
    "env::changed": {"icon": "󰆻", "color": "#f9e2af", "source": "i3pm"},  # Yellow - changed

    # Trace events (i3pm)
    "trace::start": {"icon": "󰙨", "color": "#a6e3a1", "source": "i3pm"},  # Green - start
    "trace::stop": {"icon": "󰙧", "color": "#f38ba8", "source": "i3pm"},  # Red - stop
    "trace::snapshot": {"icon": "󰄄", "color": "#89dceb", "source": "i3pm"},  # Sky - snapshot
}


def _resolve_icon_name(icon_name: str) -> str:
    """Resolve icon name to full file path using XDG lookup."""
    if not icon_name:
        return ""

    # Check cache first
    cache_key = icon_name.lower()
    if cache_key in _icon_cache:
        return _icon_cache[cache_key]

    # If it's already an absolute path, verify it exists
    candidate = Path(icon_name)
    if candidate.is_absolute() and candidate.exists():
        _icon_cache[cache_key] = str(candidate)
        return str(candidate)

    # Try XDG icon theme lookup (resolves names like "firefox")
    if getIconPath:
        themed = getIconPath(icon_name, 48)
        if themed:
            resolved = str(Path(themed))
            _icon_cache[cache_key] = resolved
            return resolved

    # Manual search through icon directories as fallback
    for directory in ICON_SEARCH_DIRS:
        if not directory.exists():
            continue
        for ext in ICON_EXTENSIONS:
            probe = directory / f"{icon_name}{ext}"
            if probe.exists():
                resolved = str(probe)
                _icon_cache[cache_key] = resolved
                return resolved

    # Not found - cache empty string
    _icon_cache[cache_key] = ""
    return ""


def get_icon_registry() -> Dict[str, str]:
    """Get or load the icon registry mapping app names to resolved icon paths."""
    global _icon_registry
    if _icon_registry is not None:
        return _icon_registry

    _icon_registry = {}

    # Load from application-registry.json
    if APP_REGISTRY_PATH.exists():
        try:
            with open(APP_REGISTRY_PATH) as f:
                data = json.load(f)
                for app in data.get("applications", []):
                    name = app.get("name", "").lower()
                    icon = app.get("icon", "")
                    if name and icon:
                        # Resolve icon name to full path
                        _icon_registry[name] = _resolve_icon_name(icon)
        except Exception:
            pass

    # Load from pwa-registry.json
    if PWA_REGISTRY_PATH.exists():
        try:
            with open(PWA_REGISTRY_PATH) as f:
                data = json.load(f)
                for pwa in data.get("pwas", []):
                    # PWAs use ULID-based app_id (e.g., "FFPWA-01JCYF8Z2M")
                    ulid = pwa.get("ulid", "")
                    icon = pwa.get("icon", "")
                    if ulid and icon:
                        _icon_registry[f"ffpwa-{ulid}".lower()] = _resolve_icon_name(icon)
        except Exception:
            pass

    return _icon_registry


def resolve_icon(app_id: str, window_class: str = "") -> str:
    """Resolve icon path for an app_id or window class."""
    registry = get_icon_registry()

    # Try exact app_id match first
    if app_id:
        app_id_lower = app_id.lower()
        if app_id_lower in registry:
            return registry[app_id_lower]

        # Extract base app name (e.g., "terminal-nixos-123456" -> "terminal")
        base_name = app_id.split("-")[0].lower() if "-" in app_id else app_id_lower
        if base_name in registry:
            return registry[base_name]

    # Try window_class as fallback
    if window_class:
        class_lower = window_class.lower()
        if class_lower in registry:
            return registry[class_lower]

    return ""

# Configure logging (stderr only - stdout is for JSON)
logging.basicConfig(
    level=logging.INFO,
    format="[%(asctime)s] %(levelname)s: %(message)s",
    stream=sys.stderr
)
logger = logging.getLogger(__name__)

# Shutdown flag for graceful exit
shutdown_requested = False


def handle_shutdown_signal(signum, frame):
    """Handle SIGTERM/SIGINT for graceful shutdown."""
    global shutdown_requested
    logger.info(f"Received signal {signum}, initiating graceful shutdown")
    shutdown_requested = True


def setup_signal_handlers():
    """Configure signal handlers for graceful shutdown."""
    signal.signal(signal.SIGTERM, handle_shutdown_signal)
    signal.signal(signal.SIGINT, handle_shutdown_signal)
    # Handle broken pipe (Eww closes while we're writing)
    signal.signal(signal.SIGPIPE, signal.SIG_DFL)


def get_window_state_classes(window: Dict[str, Any]) -> str:
    """
    Generate space-separated CSS class string for window states.

    This moves conditional class logic from Yuck to Python for:
    - Better testability (Python unit tests)
    - Cleaner Yuck code (no nested ternaries)
    - No Nix escaping issues with empty strings
    - Separation of concerns (data transformation in backend)

    Args:
        window: Window data from daemon (Sway IPC format)

    Returns:
        Space-separated string of CSS classes (e.g., "window-floating window-hidden")
    """
    classes = []

    if window.get("floating", False):
        classes.append("window-floating")
    if window.get("hidden", False):
        classes.append("window-hidden")
    if window.get("focused", False):
        classes.append("window-focused")
    # UX Enhancement: Activity Pulse Glow for urgent windows
    if window.get("urgent", False):
        classes.append("window-urgent")

    return " ".join(classes)


def escape_pango(text: str) -> str:
    """
    Escape special characters for Pango markup.

    Args:
        text: Raw text string

    Returns:
        Pango-safe string with escaped special chars
    """
    return (text
            .replace("&", "&amp;")
            .replace("<", "&lt;")
            .replace(">", "&gt;")
            .replace('"', "&quot;")
            .replace("'", "&apos;"))


def colorize_json_value(value: Any, indent_level: int = 1) -> str:
    """
    Recursively colorize a JSON value with Pango markup.

    Color scheme (Catppuccin Mocha):
    - Keys: Blue (#89b4fa)
    - Strings: Green (#a6e3a1)
    - Numbers: Peach (#fab387)
    - Booleans: Yellow (#f9e2af)
    - Null: Gray (#6c7086)
    - Punctuation: Subtext (#a6adc8)

    Args:
        value: Python value to colorize (dict, list, str, int, bool, None)
        indent_level: Current indentation level

    Returns:
        Pango markup string
    """
    indent = "  " * indent_level

    if isinstance(value, dict):
        if not value:
            return '<span foreground="#a6adc8">{}</span>'

        lines = ['<span foreground="#a6adc8">{</span>']
        items = list(value.items())
        for i, (key, val) in enumerate(items):
            key_colored = f'<span foreground="#89b4fa">"{escape_pango(key)}"</span>'
            value_colored = colorize_json_value(val, indent_level + 1)
            comma = '<span foreground="#a6adc8">,</span>' if i < len(items) - 1 else ''
            lines.append(f'{indent}{key_colored}<span foreground="#a6adc8">: </span>{value_colored}{comma}')

        lines.append(("  " * (indent_level - 1)) + '<span foreground="#a6adc8">}</span>')
        return '\n'.join(lines)

    elif isinstance(value, list):
        if not value:
            return '<span foreground="#a6adc8">[]</span>'

        lines = ['<span foreground="#a6adc8">[</span>']
        for i, item in enumerate(value):
            value_colored = colorize_json_value(item, indent_level + 1)
            comma = '<span foreground="#a6adc8">,</span>' if i < len(value) - 1 else ''
            lines.append(f'{indent}{value_colored}{comma}')

        lines.append(("  " * (indent_level - 1)) + '<span foreground="#a6adc8">]</span>')
        return '\n'.join(lines)

    elif isinstance(value, str):
        return f'<span foreground="#a6e3a1">"{escape_pango(value)}"</span>'

    elif isinstance(value, bool):
        return f'<span foreground="#f9e2af">{str(value).lower()}</span>'

    elif value is None:
        return '<span foreground="#6c7086">null</span>'

    elif isinstance(value, (int, float)):
        return f'<span foreground="#fab387">{value}</span>'

    else:
        # Fallback for unknown types
        return f'<span foreground="#cdd6f4">{escape_pango(str(value))}</span>'


def colorize_json_pango(data: Dict[str, Any]) -> str:
    """
    Generate Pango markup for syntax-highlighted JSON representation.

    Uses Catppuccin Mocha color scheme for consistent theming with the panel.

    Args:
        data: Dictionary to colorize as JSON

    Returns:
        Pango markup string with syntax highlighting
    """
    return colorize_json_value(data, indent_level=1)


def transform_window(window: Dict[str, Any], badge_state: Optional[Dict[str, Any]] = None) -> Dict[str, Any]:
    """
    Transform daemon window data to Eww-friendly schema.

    Args:
        window: Window data from daemon (Sway IPC format)
        badge_state: Optional dict mapping window IDs (as strings) to badge metadata
                     (Feature 095: Visual Notification Badges)

    Returns:
        WindowInfo dict matching data-model.md specification
    """
    app_id = window.get("app_id", "")
    window_class = window.get("class", "")

    app_name = window_class if window_class else app_id if app_id else "unknown"

    # Use full app_id as display_name (user preference)
    display_name = app_id if app_id else window_class if window_class else "unknown"

    # Resolve icon from app registry
    icon_path = resolve_icon(app_id, window_class)

    # Derive scope from marks - check if any mark starts with "scoped:"
    # Feature 101: Unified mark format - scratchpad terminals also use scoped: prefix
    marks = window.get("marks", [])
    is_scoped_window = any(str(m).startswith("scoped:") for m in marks)
    scope = "scoped" if is_scoped_window else "global"

    # PWA detection - workspaces 50+ are PWAs per CLAUDE.md specification
    # Note: workspace field may be string (including "scratchpad") or int from daemon
    workspace_raw = window.get("workspace", 1)
    try:
        workspace_num = int(workspace_raw) if workspace_raw else 1
    except (ValueError, TypeError):
        # Handle "scratchpad" or other non-numeric workspace values
        workspace_num = 0
    is_pwa = workspace_num >= 50

    # Generate composite state classes (floating, hidden, focused)
    state_classes = get_window_state_classes(window)

    # Get geometry for detail view
    geometry = window.get("geometry", {})

    # Build window data dict
    window_data = {
        "id": window.get("id", 0),
        "pid": window.get("pid", 0),
        "app_id": app_id,
        "app_name": app_name,
        "display_name": display_name,
        "class": window.get("class", ""),
        "instance": window.get("instance", ""),
        # Truncate title to 50 chars for display performance
        "title": window.get("title", "")[:50],
        "full_title": window.get("title", ""),  # Keep full title for detail view
        "project": window.get("project", ""),
        "scope": scope,
        "icon_path": icon_path,
        "workspace": workspace_raw,  # Keep original value ("scratchpad", "1", etc.)
        "workspace_number": workspace_num,  # Numeric workspace for badges
        "output": window.get("output", ""),
        "marks": window.get("marks", []),
        "floating": window.get("floating", False),
        "hidden": window.get("hidden", False),
        "focused": window.get("focused", False),
        "fullscreen": window.get("fullscreen", False),
        "is_pwa": is_pwa,
        "state_classes": state_classes,
        # Geometry for detail view
        "geometry_x": geometry.get("x", 0),
        "geometry_y": geometry.get("y", 0),
        "geometry_width": geometry.get("width", 0),
        "geometry_height": geometry.get("height", 0),
        # Feature 095: Notification badge data (if present)
        # badge_state is dict mapping window ID (string) to {"count": "1", "timestamp": ..., "source": "..."}
        "badge": badge_state.get(str(window.get("id", 0)), {}) if badge_state else {},
    }

    # Generate Pango-markup colorized JSON for hover tooltip
    # Include all fields except redundant/computed ones
    json_data = {
        "id": window_data["id"],
        "pid": window_data["pid"],
        "app_id": window_data["app_id"],
        "class": window_data["class"],
        "instance": window_data["instance"],
        "title": window_data["full_title"],
        "project": window_data["project"],
        "scope": window_data["scope"],
        "workspace": window_data["workspace"],
        "output": window_data["output"],
        "floating": window_data["floating"],
        "focused": window_data["focused"],
        "hidden": window_data["hidden"],
        "fullscreen": window_data["fullscreen"],
        "is_pwa": window_data["is_pwa"],
        "geometry": {
            "x": window_data["geometry_x"],
            "y": window_data["geometry_y"],
            "width": window_data["geometry_width"],
            "height": window_data["geometry_height"]
        },
        "marks": window_data["marks"]
    }

    # Generate colorized JSON (Pango markup)
    window_data["json_repr"] = colorize_json_pango(json_data)

    # Also generate plain JSON for clipboard copy
    window_data["json_plain"] = json.dumps(json_data, indent=2)

    # Base64-encoded JSON for safe shell passing (avoids quoting issues)
    import base64
    window_data["json_base64"] = base64.b64encode(window_data["json_plain"].encode()).decode('ascii')

    return window_data


def transform_workspace(workspace: Dict[str, Any], monitor_name: str, badge_state: Optional[Dict[str, Any]] = None) -> Dict[str, Any]:
    """
    Transform daemon workspace data to Eww-friendly schema.

    Args:
        workspace: Workspace data from daemon
        monitor_name: Parent monitor name
        badge_state: Optional dict mapping window IDs (as strings) to badge metadata
                     (Feature 095: Visual Notification Badges)

    Returns:
        WorkspaceInfo dict matching data-model.md specification
    """
    windows = workspace.get("windows", [])
    transformed_windows = [transform_window(w, badge_state) for w in windows]

    return {
        "number": workspace.get("num", workspace.get("number", 1)),
        "name": workspace.get("name", ""),
        "visible": workspace.get("visible", False),
        "focused": workspace.get("focused", False),
        "monitor": monitor_name,
        "window_count": len(transformed_windows),
        "windows": transformed_windows,
    }


def transform_monitor(output: Dict[str, Any], badge_state: Optional[Dict[str, Any]] = None) -> Dict[str, Any]:
    """
    Transform daemon output/monitor data to Eww-friendly schema.

    Args:
        output: Output data from daemon (contains name, active status, workspaces)
        badge_state: Optional dict mapping window IDs (as strings) to badge metadata
                     (Feature 095: Visual Notification Badges)

    Returns:
        MonitorInfo dict matching data-model.md specification
    """
    monitor_name = output.get("name", "unknown")
    workspaces = output.get("workspaces", [])
    transformed_workspaces = [transform_workspace(ws, monitor_name, badge_state) for ws in workspaces]

    # Determine if monitor has focused workspace
    has_focused = any(ws["focused"] for ws in transformed_workspaces)

    return {
        "name": monitor_name,
        "active": output.get("active", True),
        "focused": has_focused,
        "workspaces": transformed_workspaces,
    }


def validate_and_count(monitors: List[Dict[str, Any]]) -> Dict[str, int]:
    """
    Validate transformed data and compute summary counts.

    Args:
        monitors: List of transformed MonitorInfo dicts

    Returns:
        Dict with keys: monitor_count, workspace_count, window_count
    """
    monitor_count = len(monitors)
    workspace_count = sum(len(m["workspaces"]) for m in monitors)
    window_count = sum(
        ws["window_count"] for m in monitors for ws in m["workspaces"]
    )

    return {
        "monitor_count": monitor_count,
        "workspace_count": workspace_count,
        "window_count": window_count,
    }


def format_friendly_timestamp(timestamp: float) -> str:
    """
    Format Unix timestamp as friendly relative time.

    Args:
        timestamp: Unix timestamp (seconds since epoch)

    Returns:
        Human-friendly string like "Just now", "5 seconds ago", "2 minutes ago"
    """
    now = time.time()
    diff = int(now - timestamp)

    if diff < 5:
        return "Just now"
    elif diff < 60:
        return f"{diff} seconds ago"
    elif diff < 120:
        return "1 minute ago"
    elif diff < 3600:
        minutes = diff // 60
        return f"{minutes} minutes ago"
    elif diff < 7200:
        return "1 hour ago"
    elif diff < 86400:
        hours = diff // 3600
        return f"{hours} hours ago"
    else:
        days = diff // 86400
        return f"{days} day{'s' if days > 1 else ''} ago"


def _format_json_with_syntax_highlighting(data: Dict[str, Any]) -> str:
    """
    Format JSON with syntax highlighting using Pango markup (Feature 094: T021).

    Uses Catppuccin Mocha colors:
    - Keys: Blue (#89b4fa)
    - Strings: Green (#a6e3a1)
    - Numbers: Peach (#fab387)
    - Booleans: Yellow (#f9e2af)
    - Null: Subtext (#a6adc8)

    Args:
        data: Dictionary to format

    Returns:
        Pango markup string with syntax-highlighted JSON
    """
    import re

    # Pretty-print JSON with indentation
    json_str = json.dumps(data, indent=2, ensure_ascii=False)

    # Catppuccin Mocha colors
    COLOR_KEY = "#89b4fa"      # Blue
    COLOR_STRING = "#a6e3a1"   # Green
    COLOR_NUMBER = "#fab387"   # Peach
    COLOR_BOOLEAN = "#f9e2af"  # Yellow
    COLOR_NULL = "#a6adc8"     # Subtext

    # Escape XML special characters first
    json_str = json_str.replace("&", "&amp;")
    json_str = json_str.replace("<", "&lt;")
    json_str = json_str.replace(">", "&gt;")

    # Color JSON keys (property names in quotes before colon)
    json_str = re.sub(
        r'"([^"]+)"\s*:',
        rf'<span foreground="{COLOR_KEY}">"\1"</span>:',
        json_str
    )

    # Color string values (quotes not followed by colon)
    # This matches strings that are not keys
    def color_string_value(match):
        # Check if this string is followed by a colon (would be a key)
        full_text = match.string
        end_pos = match.end()
        # Look ahead to see if there's a colon after whitespace
        remaining = full_text[end_pos:].lstrip()
        if remaining.startswith(':'):
            return match.group(0)  # Don't color keys again
        return f'<span foreground="{COLOR_STRING}">{match.group(0)}</span>'

    json_str = re.sub(r'"[^"]*"', color_string_value, json_str)

    # Color numbers
    json_str = re.sub(
        r'\b(\d+\.?\d*)\b',
        rf'<span foreground="{COLOR_NUMBER}">\1</span>',
        json_str
    )

    # Color booleans
    json_str = re.sub(
        r'\b(true|false)\b',
        rf'<span foreground="{COLOR_BOOLEAN}">\1</span>',
        json_str
    )

    # Color null
    json_str = re.sub(
        r'\bnull\b',
        rf'<span foreground="{COLOR_NULL}">null</span>',
        json_str
    )

    return json_str


def transform_to_project_view(monitors: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
    """
    Transform monitor-based hierarchy to project-based view.

    Groups all windows by their project association, creating a flat structure:
    projects → windows (with workspace/monitor metadata)

    Args:
        monitors: List of MonitorInfo dicts from transform_monitor()

    Returns:
        List of ProjectInfo dicts with structure:
        [
            {
                "name": "nixos",
                "scope": "scoped",
                "window_count": 5,
                "windows": [...]
            },
            {
                "name": "Global Windows",
                "scope": "global",
                "window_count": 3,
                "windows": [...]
            }
        ]
    """
    # Collect all windows from all monitors/workspaces
    all_windows = []
    for monitor in monitors:
        for workspace in monitor["workspaces"]:
            for window in workspace["windows"]:
                # Add monitor and workspace metadata to window
                window_with_meta = window.copy()
                window_with_meta["monitor_name"] = monitor["name"]
                window_with_meta["workspace_name"] = workspace["name"]
                window_with_meta["workspace_number"] = workspace["number"]
                all_windows.append(window_with_meta)

    # Group windows by project
    projects_dict = {}
    global_windows = []

    for window in all_windows:
        if window["scope"] == "scoped" and window["project"]:
            project_name = window["project"]
            if project_name not in projects_dict:
                projects_dict[project_name] = {
                    "name": project_name,
                    "scope": "scoped",
                    "window_count": 0,
                    "windows": []
                }
            projects_dict[project_name]["windows"].append(window)
            projects_dict[project_name]["window_count"] += 1
        else:
            global_windows.append(window)

    # Convert dict to sorted list (alphabetical by project name)
    projects = sorted(projects_dict.values(), key=lambda p: p["name"].lower())

    # Add global windows as a separate "project" at the end
    if global_windows:
        projects.append({
            "name": "Global Windows",
            "scope": "global",
            "window_count": len(global_windows),
            "windows": global_windows
        })

    return projects


async def query_monitoring_data() -> Dict[str, Any]:
    """
    Query i3pm daemon for monitoring panel data.

    Implements contracts/daemon-query.md specification:
    - Connect to daemon via DaemonClient
    - Call get_window_tree() method
    - Transform response to Eww-friendly schema
    - Handle errors gracefully

    Returns:
        MonitoringPanelState dict with status, monitors, counts, timestamp, error

    Error Handling:
        - Daemon unavailable: Return error state with helpful message
        - Timeout: Return error state with timeout message
        - Unexpected errors: Log and return generic error state
    """
    try:
        # Get daemon socket path from environment (defaults to user runtime dir)
        # Feature 085: Support system service socket path via I3PM_DAEMON_SOCKET env var
        import os
        socket_path_str = os.environ.get("I3PM_DAEMON_SOCKET")
        socket_path = Path(socket_path_str) if socket_path_str else None

        # Create daemon client with 2.0s timeout (per contracts/daemon-query.md)
        client = DaemonClient(socket_path=socket_path, timeout=2.0)

        # Connect to daemon
        await client.connect()

        # Query window tree (monitors → workspaces → windows hierarchy)
        tree_data = await client.get_window_tree()

        # UX Enhancement: Query active project for highlighting
        active_project = await client.get_active_project()

        # Feature 095: Load badge state from filesystem (file-based, no daemon)
        # Badge files are written by claude-hooks scripts in $XDG_RUNTIME_DIR/i3pm-badges/
        badge_state = load_badge_state_from_files()
        logger.debug(f"Feature 095: Loaded {len(badge_state)} badges from filesystem")

        # Close connection (stateless pattern per research.md Decision 4)
        await client.close()

        # Transform daemon response to Eww schema
        outputs = tree_data.get("outputs", [])
        monitors = [transform_monitor(output, badge_state) for output in outputs]

        # Validate and compute summary counts
        counts = validate_and_count(monitors)

        # Transform to project-based view (default view)
        projects = transform_to_project_view(monitors)

        # UX Enhancement: Add is_active flag to each project
        for project in projects:
            project["is_active"] = (project.get("name") == active_project)

        # Create flat list of all windows for easy ID lookup in detail view
        all_windows = []
        for project in projects:
            all_windows.extend(project.get("windows", []))

        # UX Enhancement: Extract flat workspaces list for workspace pills
        workspaces = []
        for monitor in monitors:
            for ws in monitor.get("workspaces", []):
                workspaces.append({
                    "name": ws.get("name", ""),
                    "number": ws.get("number", 0),
                    "output": monitor.get("name", ""),
                    "focused": ws.get("focused", False),
                    "urgent": ws.get("urgent", False),
                    "window_count": ws.get("window_count", 0),
                })
        workspaces.sort(key=lambda w: w["number"])

        # Get current timestamp for friendly formatting
        current_timestamp = time.time()
        friendly_time = format_friendly_timestamp(current_timestamp)

        # Feature 095 Enhancement: Check if any badges are in "working" state
        # This is used to trigger more frequent updates for spinner animation
        has_working_badge = any(
            badge.get("state") == "working"
            for badge in badge_state.values()
        ) if badge_state else False

        # Return success state with project-based view
        return {
            "status": "ok",
            "projects": projects,
            "all_windows": all_windows,  # Flat list for detail view lookup
            "workspaces": workspaces,  # UX Enhancement: Flat list for workspace pills
            "active_project": active_project,  # UX Enhancement: For active project highlight
            "project_count": len(projects),
            "monitor_count": counts["monitor_count"],
            "workspace_count": counts["workspace_count"],
            "window_count": counts["window_count"],
            "timestamp": current_timestamp,
            "timestamp_friendly": friendly_time,
            "error": None,
            # Feature 095 Enhancement: Animated spinner frame
            "spinner_frame": get_spinner_frame(),
            "has_working_badge": has_working_badge,
        }

    except DaemonError as e:
        # Expected errors: socket not found, timeout, connection lost
        logger.warning(f"Daemon error: {e}")
        error_timestamp = time.time()
        return {
            "status": "error",
            "projects": [],
            "workspaces": [],  # UX Enhancement: Empty workspaces for error state
            "project_count": 0,
            "monitor_count": 0,
            "workspace_count": 0,
            "window_count": 0,
            "timestamp": error_timestamp,
            "timestamp_friendly": format_friendly_timestamp(error_timestamp),
            "error": str(e),
            "spinner_frame": get_spinner_frame(),
            "has_working_badge": False,
        }

    except Exception as e:
        # Unexpected errors: log for debugging
        logger.error(f"Unexpected error querying daemon: {e}", exc_info=True)
        error_timestamp = time.time()
        return {
            "status": "error",
            "projects": [],
            "workspaces": [],  # UX Enhancement: Empty workspaces for error state
            "project_count": 0,
            "monitor_count": 0,
            "workspace_count": 0,
            "window_count": 0,
            "timestamp": error_timestamp,
            "timestamp_friendly": format_friendly_timestamp(error_timestamp),
            "error": f"Unexpected error: {type(e).__name__}: {e}",
            "spinner_frame": get_spinner_frame(),
            "has_working_badge": False,
        }


def get_projects_hierarchy(projects_dir: Optional[Path] = None) -> PanelProjectsData:
    """
    Build hierarchical project structure for monitoring panel (Feature 097 T035).

    Groups projects by bare_repo_path:
    - Repository projects: First project registered for each bare repo
    - Worktree projects: Nested under their parent repository
    - Standalone projects: Non-git or simple repos
    - Orphaned worktrees: Worktrees with missing parent Repository Project

    Args:
        projects_dir: Directory containing project JSON files (default: ~/.config/i3/projects/)

    Returns:
        PanelProjectsData with repository_projects, standalone_projects, orphaned_worktrees

    Tasks:
        T034: Group projects by bare_repo_path using detect_orphaned_worktrees()
        T035: Return PanelProjectsData structure
        T036: Calculate worktree_count per Repository Project
        T037: Calculate has_dirty aggregation (bubble-up from worktrees to parent)
    """
    projects_dir = projects_dir or Path.home() / ".config/i3/projects"

    if not projects_dir.exists():
        return PanelProjectsData()

    # Load all project configs
    # Pass edit_mode=True context to skip uniqueness/existence validators (they're for creation, not loading)
    load_context = {"edit_mode": True}
    all_projects: List[ProjectConfig] = []
    for project_file in projects_dir.glob("*.json"):
        try:
            with open(project_file, 'r') as f:
                data = json.load(f)
            # Parse with Pydantic model, skip creation-time validators
            project = ProjectConfig.model_validate(data, context=load_context)
            all_projects.append(project)
        except Exception as e:
            logger.warning(f"Feature 097: Skipping invalid project file {project_file}: {e}")
            continue

    # T034: Detect orphaned worktrees using git_utils
    orphaned = detect_orphaned_worktrees(all_projects)
    orphaned_names = {p.name for p in orphaned}

    # Separate projects by source_type
    repository_projects: Dict[str, RepositoryWithWorktrees] = {}  # bare_repo_path -> RepositoryWithWorktrees
    standalone_projects: List[ProjectConfig] = []
    worktree_projects: List[ProjectConfig] = []

    for project in all_projects:
        if project.name in orphaned_names:
            # Skip orphans here, they're already in the orphaned list
            continue

        if project.source_type == SourceType.REPOSITORY:
            # T035: Create RepositoryWithWorktrees container
            if project.bare_repo_path:
                repository_projects[project.bare_repo_path] = RepositoryWithWorktrees(
                    project=project,
                    worktree_count=0,
                    has_dirty=not (project.git_metadata.is_clean if project.git_metadata else True),
                    is_expanded=True,
                    worktrees=[]
                )
        elif project.source_type == SourceType.WORKTREE:
            worktree_projects.append(project)
        else:  # standalone
            standalone_projects.append(project)

    # T036: Nest worktrees under their parent repository and calculate worktree_count
    for worktree in worktree_projects:
        if worktree.bare_repo_path and worktree.bare_repo_path in repository_projects:
            repo_container = repository_projects[worktree.bare_repo_path]
            repo_container.worktrees.append(worktree)
            repo_container.worktree_count = len(repo_container.worktrees)

            # T037: has_dirty bubble-up (if worktree is dirty, parent shows dirty)
            worktree_dirty = not (worktree.git_metadata.is_clean if worktree.git_metadata else True)
            if worktree_dirty:
                repo_container.has_dirty = True
        else:
            # Worktree without matching repository - this shouldn't happen if detect_orphaned_worktrees worked
            # but handle gracefully by adding to orphans
            orphaned.append(worktree)

    # Sort repository projects by name
    sorted_repos = sorted(
        repository_projects.values(),
        key=lambda r: r.project.name
    )

    # Sort worktrees within each repository by name
    for repo in sorted_repos:
        repo.worktrees = sorted(repo.worktrees, key=lambda w: w.name)

    # Sort standalone and orphaned projects by name
    standalone_projects.sort(key=lambda p: p.name)
    orphaned.sort(key=lambda p: p.name)

    return PanelProjectsData(
        repository_projects=sorted_repos,
        standalone_projects=standalone_projects,
        orphaned_worktrees=orphaned,
        active_project=None  # Set by caller after getting active project
    )


def load_discovered_repositories() -> Dict[str, List[Dict[str, Any]]]:
    """Load discovered bare repositories from repos.json.

    Feature 100 T055: Load bare repositories discovered via `i3pm discover`
    and convert them to a format compatible with the Projects tab.

    Returns:
        Dict with "repositories" list (bare repos with worktrees nested)
    """
    repos_file = Path.home() / ".config" / "i3" / "repos.json"

    if not repos_file.exists():
        logger.debug("Feature 100: No repos.json found, skipping bare repo discovery")
        return {"repositories": [], "last_discovery": None}

    try:
        with open(repos_file, "r") as f:
            repos_data = json.load(f)

        repositories = repos_data.get("repositories", [])
        last_discovery = repos_data.get("last_discovery")

        # Convert each discovered repo to project-compatible format
        for repo in repositories:
            # Generate qualified name for the repository
            repo["qualified_name"] = f"{repo['account']}/{repo['name']}"

            # Add source_type for UI display
            repo["source_type"] = "bare_repository"
            repo["source_type_badge"] = "📂"

            # Add display fields
            repo["display_name"] = repo.get("display_name") or repo["name"]
            repo["directory"] = repo["path"]
            repo["directory_display"] = repo["path"].replace(str(Path.home()), "~")

            # Mark worktrees with their qualified names
            for wt in repo.get("worktrees", []):
                wt["qualified_name"] = f"{repo['account']}/{repo['name']}:{wt['branch']}"
                wt["source_type"] = "worktree"
                wt["source_type_badge"] = "🌿"
                wt["parent_repo"] = repo["qualified_name"]
                wt["directory_display"] = wt["path"].replace(str(Path.home()), "~")

        logger.debug(f"Feature 100: Loaded {len(repositories)} discovered bare repositories")
        return {"repositories": repositories, "last_discovery": last_discovery}

    except (json.JSONDecodeError, IOError) as e:
        logger.warning(f"Feature 100: Failed to load repos.json: {e}")
        return {"repositories": [], "last_discovery": None}


async def query_projects_data() -> Dict[str, Any]:
    """
    Query projects view data using bare repository discovery.

    Feature 100: Reads from repos.json (populated by `i3pm discover`) and returns:
    - Hierarchical: repositories with nested worktrees
    - Qualified names: account/repo and account/repo:branch
    - Git status indicators (dirty, ahead/behind)

    Returns repository list with worktrees and current active project.
    """
    current_timestamp = time.time()
    friendly_time = format_friendly_timestamp(current_timestamp)

    try:
        # Feature 100: Load discovered bare repositories from repos.json
        discovered_repos = load_discovered_repositories()
        repositories = discovered_repos.get("repositories", [])
        last_discovery = discovered_repos.get("last_discovery")

        # Get active project (uses qualified name like vpittamp/nixos:main)
        active_project = None
        try:
            result = subprocess.run(
                ["i3pm", "project", "current"],
                capture_output=True,
                text=True,
                timeout=2
            )
            if result.returncode == 0:
                active_project = result.stdout.strip()
        except subprocess.TimeoutExpired:
            pass

        # Enhance repositories with UI fields
        for repo in repositories:
            qualified_name = repo.get("qualified_name", f"{repo['account']}/{repo['name']}")
            repo["is_active"] = (active_project == qualified_name)
            repo["icon"] = "📂"  # Bare repository icon
            repo["display_name"] = repo.get("display_name") or repo["name"]

            # Calculate aggregate stats for the repo
            worktrees = repo.get("worktrees", [])
            repo["worktree_count"] = len(worktrees)
            repo["has_dirty_worktrees"] = any(not wt.get("is_clean", True) for wt in worktrees)

            # Enhance each worktree
            for wt in worktrees:
                wt_qualified = f"{qualified_name}:{wt['branch']}"
                wt["qualified_name"] = wt_qualified
                wt["is_active"] = (active_project == wt_qualified)
                wt["display_name"] = wt["branch"]
                wt["directory_display"] = wt.get("path", "").replace(str(Path.home()), "~")

                # Feature 109: Parse branch number from branch name (e.g., "108-show-worktree" -> "108")
                branch = wt.get("branch", "")
                branch_number = ""
                branch_description = branch
                # Pattern: number-description (e.g., 108-show-worktree-card-detail)
                match = re.match(r'^(\d{2,4})[-_](.+)$', branch)
                if match:
                    branch_number = match.group(1)
                    # Convert description: "show-worktree-card" -> "Show Worktree Card"
                    branch_description = match.group(2).replace('-', ' ').replace('_', ' ').title()
                wt["branch_number"] = branch_number
                wt["branch_description"] = branch_description
                wt["has_branch_number"] = bool(branch_number)

                # Git status indicators
                wt["git_is_dirty"] = not wt.get("is_clean", True)
                wt["git_dirty_indicator"] = "●" if wt["git_is_dirty"] else ""
                wt["git_ahead"] = wt.get("ahead", 0)
                wt["git_behind"] = wt.get("behind", 0)

                # Sync status
                sync_parts = []
                if wt["git_ahead"] > 0:
                    sync_parts.append(f"↑{wt['git_ahead']}")
                if wt["git_behind"] > 0:
                    sync_parts.append(f"↓{wt['git_behind']}")
                wt["git_sync_indicator"] = " ".join(sync_parts)

                # Feature 108 T015-T017: Enhanced status indicators
                # T016: Merge status (skip for main/master branches)
                wt["git_is_merged"] = wt.get("is_merged", False)
                wt["git_merged_indicator"] = "✓" if wt["git_is_merged"] else ""

                # T017: Conflict status
                wt["git_has_conflicts"] = wt.get("has_conflicts", False)
                wt["git_conflict_indicator"] = "⚠" if wt["git_has_conflicts"] else ""

                # Feature 108 T024-T026 (US2): Detailed status for tooltips
                wt["git_staged_count"] = wt.get("staged_count", 0)
                wt["git_modified_count"] = wt.get("modified_count", 0)
                wt["git_untracked_count"] = wt.get("untracked_count", 0)

                # Feature 108 T025: Last commit info
                last_ts = wt.get("last_commit_timestamp", 0)
                wt["git_last_commit_relative"] = format_relative_time(last_ts) if last_ts > 0 else ""
                wt["git_last_commit_message"] = wt.get("last_commit_message", "")[:50]

                # Feature 108 T031: Stale status
                wt["git_is_stale"] = wt.get("is_stale", False)
                wt["git_stale_indicator"] = "💤" if wt["git_is_stale"] else ""

                # Feature 108 T026: Build comprehensive tooltip
                tooltip_parts = []
                tooltip_parts.append(f"Branch: {wt['branch']}")
                tooltip_parts.append(f"Commit: {wt.get('commit', 'unknown')}")
                if wt["git_last_commit_relative"]:
                    tooltip_parts[-1] += f" ({wt['git_last_commit_relative']})"
                if wt["git_last_commit_message"]:
                    tooltip_parts.append(f"Message: {wt['git_last_commit_message']}")

                # Status breakdown
                status_parts = []
                if wt["git_staged_count"] > 0:
                    status_parts.append(f"{wt['git_staged_count']} staged")
                if wt["git_modified_count"] > 0:
                    status_parts.append(f"{wt['git_modified_count']} modified")
                if wt["git_untracked_count"] > 0:
                    status_parts.append(f"{wt['git_untracked_count']} untracked")
                if status_parts:
                    tooltip_parts.append(f"Status: {', '.join(status_parts)}")
                elif wt.get("is_clean", True):
                    tooltip_parts.append("Status: clean")

                # Sync info
                if wt["git_ahead"] > 0 or wt["git_behind"] > 0:
                    sync_desc = []
                    if wt["git_ahead"] > 0:
                        sync_desc.append(f"{wt['git_ahead']} to push")
                    if wt["git_behind"] > 0:
                        sync_desc.append(f"{wt['git_behind']} to pull")
                    tooltip_parts.append(f"Sync: {', '.join(sync_desc)}")

                # Merge/stale/conflict status
                if wt["git_is_merged"]:
                    tooltip_parts.append("Merged: ✓ merged into main")
                if wt["git_is_stale"]:
                    tooltip_parts.append("Stale: no activity in 30+ days")
                if wt["git_has_conflicts"]:
                    tooltip_parts.append("⚠ Has unresolved merge conflicts")

                wt["git_status_tooltip"] = "\\n".join(tooltip_parts)

        # Count totals
        total_worktrees = sum(len(r.get("worktrees", [])) for r in repositories)

        return {
            "status": "ok",
            # Feature 100: Primary data is discovered_repositories
            "discovered_repositories": repositories,
            "last_discovery": last_discovery,
            "repo_count": len(repositories),
            "worktree_count": total_worktrees,
            "active_project": active_project,
            "timestamp": current_timestamp,
            "timestamp_friendly": friendly_time,
            "error": None
        }

    except Exception as e:
        logger.error(f"Error querying projects data: {e}", exc_info=True)
        return {
            "status": "error",
            "discovered_repositories": [],
            "last_discovery": None,
            "repo_count": 0,
            "worktree_count": 0,
            "active_project": None,
            "timestamp": current_timestamp,
            "timestamp_friendly": friendly_time,
            "error": f"Projects query failed: {type(e).__name__}: {e}"
        }


# Feature 111: Import worktree map service for visual graph generation
try:
    from i3_project_manager.services.worktree_map_service import (
        build_worktree_map,
        generate_worktree_map_svg,
        generate_click_overlay_data,
        compute_hierarchical_layout,
    )
    WORKTREE_MAP_AVAILABLE = True
except ImportError as e:
    logger.warning(f"Feature 111: Worktree map service not available: {e}")
    WORKTREE_MAP_AVAILABLE = False


async def query_worktree_map_data() -> Dict[str, Any]:
    """
    Query worktree map data for visual graph rendering.

    Feature 111: Generates SVG visualization of worktree relationships.

    Returns:
        - svg_path: Path to generated SVG file
        - map_data: JSON representation of the worktree map
        - status: ok/error
    """
    current_timestamp = time.time()
    friendly_time = format_friendly_timestamp(current_timestamp)

    try:
        if not WORKTREE_MAP_AVAILABLE:
            return {
                "status": "error",
                "svg_path": None,
                "map_data": None,
                "timestamp": current_timestamp,
                "timestamp_friendly": friendly_time,
                "error": "Worktree map service not available",
            }

        # Load discovered repositories to find active repo
        discovered_repos = load_discovered_repositories()
        repositories = discovered_repos.get("repositories", [])

        if not repositories:
            return {
                "status": "ok",
                "svg_path": None,
                "map_data": {"nodes": [], "edges": [], "repository": None},
                "timestamp": current_timestamp,
                "timestamp_friendly": friendly_time,
                "error": None,
            }

        # Get active project to determine which repo to visualize
        active_project = None
        active_repo = None
        try:
            result = subprocess.run(
                ["i3pm", "project", "current"],
                capture_output=True,
                text=True,
                timeout=2,
            )
            if result.returncode == 0:
                active_project = result.stdout.strip()
                # Parse account/repo from qualified name
                if "/" in active_project:
                    parts = active_project.split("/")
                    if len(parts) >= 2:
                        # Handle account/repo:branch format
                        repo_part = parts[1].split(":")[0] if ":" in parts[1] else parts[1]
                        # Find matching repo
                        for repo in repositories:
                            if repo.get("name") == repo_part or repo.get("qualified_name") == f"{parts[0]}/{repo_part}":
                                active_repo = repo
                                break
        except subprocess.TimeoutExpired:
            pass

        # Default to first repo if no active project
        if not active_repo and repositories:
            active_repo = repositories[0]

        if not active_repo:
            return {
                "status": "ok",
                "svg_path": None,
                "map_data": {"nodes": [], "edges": [], "repository": None},
                "timestamp": current_timestamp,
                "timestamp_friendly": friendly_time,
                "error": None,
            }

        # Build worktree map from repository path
        repo_path = active_repo.get("directory")
        if not repo_path:
            return {
                "status": "error",
                "svg_path": None,
                "map_data": None,
                "timestamp": current_timestamp,
                "timestamp_friendly": friendly_time,
                "error": f"No directory for repository: {active_repo.get('name')}",
            }

        # Build map
        worktree_map = build_worktree_map(repo_path)
        if not worktree_map:
            return {
                "status": "error",
                "svg_path": None,
                "map_data": None,
                "timestamp": current_timestamp,
                "timestamp_friendly": friendly_time,
                "error": f"Failed to build map for: {repo_path}",
            }

        # Generate SVG to cache directory
        svg_dir = Path.home() / ".cache" / "i3pm" / "worktree-maps"
        svg_dir.mkdir(parents=True, exist_ok=True)
        svg_filename = f"{active_repo.get('name', 'repo')}.svg"
        svg_path = str(svg_dir / svg_filename)

        generate_worktree_map_svg(worktree_map, output_path=svg_path)

        # Feature 111 T048: Generate click overlay data for interactive navigation
        overlay_nodes = generate_click_overlay_data(worktree_map)

        return {
            "status": "ok",
            "svg_path": svg_path,
            "map_data": worktree_map.to_svg_data(),
            "overlay_nodes": overlay_nodes,  # Feature 111 US3: Click targets
            "repository": active_repo.get("qualified_name"),
            "timestamp": current_timestamp,
            "timestamp_friendly": friendly_time,
            "error": None,
        }

    except Exception as e:
        logger.error(f"Error querying worktree map data: {e}", exc_info=True)
        return {
            "status": "error",
            "svg_path": None,
            "map_data": None,
            "timestamp": current_timestamp,
            "timestamp_friendly": friendly_time,
            "error": f"Worktree map query failed: {type(e).__name__}: {e}",
        }


async def query_apps_data() -> Dict[str, Any]:
    """
    Query apps view data.

    Returns app registry with configuration and runtime state.
    """
    current_timestamp = time.time()
    friendly_time = format_friendly_timestamp(current_timestamp)

    try:
        # Read application registry JSON file directly (Feature 094)
        # The i3pm apps list --json flag doesn't work, so we read the file directly
        registry_path = Path.home() / ".config/i3/application-registry.json"

        if not registry_path.exists():
            apps = []
        else:
            try:
                with open(registry_path, 'r') as f:
                    registry_data = json.load(f)
                    apps = registry_data.get("applications", [])
            except (json.JSONDecodeError, KeyError) as e:
                logger.warning(f"Failed to parse application registry: {e}")
                apps = []

        # Enhance with runtime state (running instances)
        # Query current windows to match app names
        try:
            client = DaemonClient()
            tree_data = await client.get_window_tree()
            await client.close()

            # Build map of app_name -> window IDs
            app_windows = {}
            for output in tree_data.get("outputs", []):
                for workspace in output.get("workspaces", []):
                    for window in workspace.get("windows", []):
                        app_name = window.get("app_name", "unknown")
                        if app_name not in app_windows:
                            app_windows[app_name] = []
                        app_windows[app_name].append(window.get("id"))

            # Add runtime info to apps
            for app in apps:
                app_name = app.get("name", "")
                app["running_instances"] = len(app_windows.get(app_name, []))
                app["window_ids"] = app_windows.get(app_name, [])

        except Exception as e:
            logger.warning(f"Could not query window state for apps: {e}")
            # Apps will just not have runtime info

        return {
            "status": "ok",
            "apps": apps,
            "app_count": len(apps),
            "timestamp": current_timestamp,
            "timestamp_friendly": friendly_time,
            "error": None
        }

    except Exception as e:
        return {
            "status": "error",
            "apps": [],
            "app_count": 0,
            "timestamp": current_timestamp,
            "timestamp_friendly": friendly_time,
            "error": f"Apps query failed: {type(e).__name__}: {e}"
        }


# Health Monitoring Helper Functions (Feature 088)

def read_monitor_profile() -> str:
    """
    Read current monitor profile from ~/.config/sway/monitor-profile.current.

    Returns:
        Current profile name (e.g., "local-only", "dual", "triple") or "unknown"
    """
    profile_file = Path.home() / ".config/sway/monitor-profile.current"
    try:
        if profile_file.exists():
            return profile_file.read_text().strip()
    except Exception as e:
        logging.warning(f"Failed to read monitor profile: {e}")
    return "unknown"


def get_monitored_services(monitor_profile: str) -> List[Dict[str, Any]]:
    """
    Get list of services to monitor based on current monitor profile.

    Filters conditional services based on their condition_profiles list.

    Args:
        monitor_profile: Current monitor profile name

    Returns:
        Flat list of service definitions to monitor
    """
    services = []

    for category, service_list in SERVICE_REGISTRY.items():
        for service_def in service_list:
            # Include non-conditional services always
            if not service_def.get("conditional", False):
                services.append({**service_def, "category": category})
                continue

            # For conditional services, check if profile matches
            condition_profiles = service_def.get("condition_profiles", [])
            if monitor_profile in condition_profiles:
                services.append({**service_def, "category": category})

    return services


def classify_health_state(
    load_state: str,
    active_state: str,
    sub_state: str,
    unit_file_state: str,
    restart_count: int,
    is_conditional: bool,
    should_be_active: bool
) -> str:
    """
    Classify service health state based on systemd properties.

    Args:
        load_state: Service load state (loaded/not-found/error/masked)
        active_state: Service active state (active/inactive/failed/etc.)
        sub_state: Service sub-state (running/dead/exited/failed/etc.)
        unit_file_state: Service unit file state (enabled/disabled/static/masked)
        restart_count: Number of service restarts (NRestarts)
        is_conditional: Whether service is mode-dependent
        should_be_active: Whether service should be active in current profile

    Returns:
        Health state: healthy/degraded/critical/disabled/unknown
    """
    # Not found or load error
    if load_state in ["not-found", "error"]:
        return "unknown"

    # Intentionally disabled or masked
    if unit_file_state in ["disabled", "masked"]:
        return "disabled"

    # Conditional service not active in current profile
    if is_conditional and not should_be_active:
        return "disabled"

    # Failed state
    if active_state == "failed":
        return "critical"

    # Active and running normally
    if active_state == "active" and sub_state == "running":
        # Check for excessive restarts (degraded health indicator)
        if restart_count >= 3:
            return "degraded"
        return "healthy"

    # Active but not running (e.g., oneshot completed, socket listening)
    if active_state == "active" and sub_state in ["exited", "dead", "listening"]:
        return "healthy"  # Normal for oneshot services and sockets

    # Inactive (not started yet or stopped)
    if active_state == "inactive":
        return "disabled"

    # Activating or deactivating (transient state)
    if active_state in ["activating", "deactivating"]:
        return "degraded"

    # Unknown state
    return "unknown"


def format_uptime(uptime_seconds: int) -> str:
    """
    Convert uptime in seconds to human-friendly format.

    Args:
        uptime_seconds: Uptime in seconds

    Returns:
        Human-friendly string (e.g., "5h 23m", "2d 3h", "45s")
    """
    if uptime_seconds <= 0:
        return "not running"

    if uptime_seconds < 60:
        return f"{uptime_seconds}s"
    elif uptime_seconds < 3600:
        minutes = uptime_seconds // 60
        return f"{minutes}m"
    elif uptime_seconds < 86400:
        hours = uptime_seconds // 3600
        minutes = (uptime_seconds % 3600) // 60
        return f"{hours}h {minutes}m"
    else:
        days = uptime_seconds // 86400
        hours = (uptime_seconds % 86400) // 3600
        return f"{days}d {hours}h"


def get_status_icon(health_state: str) -> str:
    """
    Map health state to status icon for UI display.

    Args:
        health_state: Health state (healthy/degraded/critical/disabled/unknown)

    Returns:
        Status icon (✓/⚠/✗/○/?)
    """
    icon_map = {
        "healthy": "✓",
        "degraded": "⚠",
        "critical": "✗",
        "disabled": "○",
        "unknown": "?"
    }
    return icon_map.get(health_state, "?")


def parse_systemctl_output(stdout: str) -> Dict[str, str]:
    """
    Parse KEY=VALUE format from systemctl show command into dict.

    Args:
        stdout: Output from systemctl show command

    Returns:
        Dictionary of property key-value pairs
    """
    properties = {}
    for line in stdout.strip().split("\n"):
        if "=" in line:
            key, value = line.split("=", 1)
            properties[key] = value
    return properties


def safe_int(value: str, default: int = 0) -> int:
    """
    Safely convert a string to int, handling systemctl's '[not set]' values.

    Args:
        value: String value from systemctl (may be '[not set]')
        default: Default value if conversion fails

    Returns:
        Integer value or default
    """
    if not value or value == "[not set]" or value.strip() == "":
        return default
    try:
        return int(value)
    except ValueError:
        return default


def calculate_uptime(active_enter_timestamp: str) -> int:
    """
    Calculate service uptime in seconds from ActiveEnterTimestamp.

    Args:
        active_enter_timestamp: Timestamp string from systemctl (e.g., "Sat 2025-11-22 10:54:38 EST")

    Returns:
        Uptime in seconds (0 if service not active or timestamp invalid)
    """
    if not active_enter_timestamp or active_enter_timestamp == "":
        return 0

    try:
        # Parse timestamp - format: "Day YYYY-MM-DD HH:MM:SS TZ"
        # Note: This is a simplified parser - may need adjustment for locale variations
        from datetime import datetime
        import re

        # Remove day of week and timezone for simpler parsing
        # Example: "Sat 2025-11-22 10:54:38 EST" -> "2025-11-22 10:54:38"
        match = re.search(r'(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})', active_enter_timestamp)
        if not match:
            return 0

        timestamp_str = match.group(1)
        start_time = datetime.strptime(timestamp_str, "%Y-%m-%d %H:%M:%S")
        current_time = datetime.now()

        uptime_seconds = int((current_time - start_time).total_seconds())
        return max(0, uptime_seconds)  # Ensure non-negative

    except Exception as e:
        logging.warning(f"Failed to parse timestamp '{active_enter_timestamp}': {e}")
        return 0


def query_service_health(
    service_name: str,
    is_user_service: bool,
    socket_name: Optional[str] = None
) -> Dict[str, str]:
    """
    Query systemctl for service properties and return health data.

    Queries: LoadState, ActiveState, SubState, UnitFileState, MainPID, TriggeredBy,
             MemoryCurrent, NRestarts, ActiveEnterTimestamp (Feature 088 US2)

    Args:
        service_name: Service name (e.g., "eww-top-bar.service")
        is_user_service: True for user services (--user flag)
        socket_name: Socket unit name if socket-activated

    Returns:
        Dictionary of systemctl properties
    """
    # Add .service suffix if not present
    if not service_name.endswith(".service"):
        service_name = f"{service_name}.service"

    # Build systemctl command (Feature 088: Added MemoryCurrent, NRestarts, ActiveEnterTimestamp for US2)
    cmd = ["systemctl"]
    if is_user_service:
        cmd.append("--user")

    cmd.extend([
        "show",
        service_name,
        "-p", "LoadState,ActiveState,SubState,UnitFileState,MainPID,TriggeredBy,MemoryCurrent,NRestarts,ActiveEnterTimestamp",
        "--no-pager"
    ])

    try:
        result = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            timeout=2
        )

        properties = parse_systemctl_output(result.stdout)

        # If socket-activated and service is inactive, check socket status
        if socket_name and properties.get("TriggeredBy") == socket_name:
            socket_cmd = ["systemctl"]
            if is_user_service:
                socket_cmd.append("--user")

            socket_cmd.extend([
                "show",
                socket_name,
                "-p", "LoadState,ActiveState,SubState",
                "--no-pager"
            ])

            socket_result = subprocess.run(
                socket_cmd,
                capture_output=True,
                text=True,
                timeout=2
            )

            socket_props = parse_systemctl_output(socket_result.stdout)

            # If socket is active, service is healthy (even if inactive)
            if socket_props.get("ActiveState") == "active":
                properties["_socket_active"] = "true"

        return properties

    except subprocess.TimeoutExpired:
        logging.error(f"Timeout querying {service_name}")
        return {
            "LoadState": "error",
            "ActiveState": "unknown",
            "SubState": "unknown",
            "UnitFileState": "unknown",
            "MainPID": "0",
            "TriggeredBy": ""
        }
    except Exception as e:
        logging.error(f"Error querying {service_name}: {e}")
        return {
            "LoadState": "not-found",
            "ActiveState": "inactive",
            "SubState": "dead",
            "UnitFileState": "not-found",
            "MainPID": "0",
            "TriggeredBy": ""
        }


def build_service_health(
    service_def: Dict[str, Any],
    systemctl_props: Dict[str, str],
    monitor_profile: str
) -> Dict[str, Any]:
    """
    Construct ServiceHealth object from service definition and systemctl properties.

    Args:
        service_def: Service definition from registry (includes category)
        systemctl_props: Properties from systemctl show command
        monitor_profile: Current monitor profile

    Returns:
        ServiceHealth dictionary matching data-model.md schema
    """
    # Extract systemctl properties with defaults
    load_state = systemctl_props.get("LoadState", "unknown")
    active_state = systemctl_props.get("ActiveState", "unknown")
    sub_state = systemctl_props.get("SubState", "unknown")
    unit_file_state = systemctl_props.get("UnitFileState", "unknown")
    main_pid = safe_int(systemctl_props.get("MainPID", "0"), 0)
    restart_count = safe_int(systemctl_props.get("NRestarts", "0"), 0)

    # Feature 088 US2: Calculate uptime and memory usage
    active_enter_timestamp = systemctl_props.get("ActiveEnterTimestamp", "")
    uptime_seconds = calculate_uptime(active_enter_timestamp)
    uptime_friendly = format_uptime(uptime_seconds)

    # Convert memory from bytes to MB (handle [not set] gracefully)
    memory_bytes = safe_int(systemctl_props.get("MemoryCurrent", "0"), 0)
    memory_usage_mb = round(memory_bytes / 1024 / 1024, 1) if memory_bytes > 0 else 0.0

    # Determine if service should be active in current profile
    is_conditional = service_def.get("conditional", False)
    condition_profiles = service_def.get("condition_profiles", [])
    should_be_active = monitor_profile in condition_profiles if is_conditional else True

    # Classify health state
    health_state = classify_health_state(
        load_state=load_state,
        active_state=active_state,
        sub_state=sub_state,
        unit_file_state=unit_file_state,
        restart_count=restart_count,
        is_conditional=is_conditional,
        should_be_active=should_be_active
    )

    # Build ServiceHealth object
    service_health = {
        "service_name": service_def["name"],
        "display_name": service_def["display_name"],
        "category": service_def["category"],
        "description": service_def["description"],
        "is_user_service": service_def["is_user_service"],
        "is_socket_activated": service_def.get("socket_activated", False),
        "socket_name": service_def.get("socket_name"),
        "is_conditional": is_conditional,
        "condition_profiles": condition_profiles if is_conditional else None,
        "load_state": load_state,
        "active_state": active_state,
        "sub_state": sub_state,
        "unit_file_state": unit_file_state,
        "health_state": health_state,
        "main_pid": main_pid,
        "uptime_seconds": uptime_seconds,  # Feature 088 US2
        "memory_usage_mb": memory_usage_mb,  # Feature 088 US2
        "restart_count": restart_count,
        "last_active_time": active_enter_timestamp if active_enter_timestamp else None,  # Feature 088 US2
        "status_icon": get_status_icon(health_state),
        "uptime_friendly": uptime_friendly,  # Feature 088 US2
        "can_restart": health_state not in ["disabled"] and load_state != "not-found"
    }

    return service_health


def build_system_health(
    categories: List[Dict[str, Any]],
    monitor_profile: str
) -> Dict[str, Any]:
    """
    Aggregate category health into SystemHealth response with timestamp.

    Args:
        categories: List of ServiceCategory dicts
        monitor_profile: Current monitor profile

    Returns:
        SystemHealth dictionary matching data-model.md schema
    """
    current_timestamp = time.time()
    friendly_time = format_friendly_timestamp(current_timestamp)

    # Calculate aggregate counts
    total_services = 0
    healthy_count = 0
    degraded_count = 0
    critical_count = 0
    disabled_count = 0
    unknown_count = 0

    for category in categories:
        total_services += category["total_count"]
        healthy_count += category["healthy_count"]
        degraded_count += category["degraded_count"]
        critical_count += category["critical_count"]
        disabled_count += category["disabled_count"]
        unknown_count += category["unknown_count"]

    # Determine overall system health
    if critical_count > 0:
        system_health = "critical"
    elif degraded_count > 0:
        system_health = "degraded"
    elif unknown_count > 0:
        system_health = "mixed"
    elif total_services == disabled_count:
        system_health = "mixed"
    else:
        system_health = "healthy"

    return {
        "timestamp": current_timestamp,
        "timestamp_friendly": friendly_time,
        "monitoring_functional": True,
        "current_monitor_profile": monitor_profile,
        "total_services": total_services,
        "healthy_count": healthy_count,
        "degraded_count": degraded_count,
        "critical_count": critical_count,
        "disabled_count": disabled_count,
        "unknown_count": unknown_count,
        "categories": categories,
        "system_health": system_health,
        "error": None
    }


async def query_health_data() -> Dict[str, Any]:
    """
    Query system health view data.

    Returns comprehensive service health monitoring data (Feature 088).
    Queries all systemd services from SERVICE_REGISTRY and returns structured health data.
    """
    try:
        # T036: Log health query start
        logging.info("Feature 088: Starting health query")

        # Read current monitor profile
        monitor_profile = read_monitor_profile()
        logging.info(f"Feature 088: Monitor profile: {monitor_profile}")

        # Get list of services to monitor based on profile
        monitored_services = get_monitored_services(monitor_profile)

        # Query health for each service
        service_health_list = []
        for service_def in monitored_services:
            systemctl_props = query_service_health(
                service_name=service_def["name"],
                is_user_service=service_def["is_user_service"],
                socket_name=service_def.get("socket_name")
            )

            service_health = build_service_health(
                service_def=service_def,
                systemctl_props=systemctl_props,
                monitor_profile=monitor_profile
            )

            service_health_list.append(service_health)

        # Group services by category
        categories_dict = {
            "core": {"category_name": "core", "display_name": "Core Daemons", "services": []},
            "ui": {"category_name": "ui", "display_name": "UI Services", "services": []},
            "system": {"category_name": "system", "display_name": "System Services", "services": []},
            "optional": {"category_name": "optional", "display_name": "Optional Services", "services": []}
        }

        for service_health in service_health_list:
            category_name = service_health["category"]
            categories_dict[category_name]["services"].append(service_health)

        # Calculate category-level health metrics
        categories = []
        for category_name, category_data in categories_dict.items():
            services = category_data["services"]

            # Count health states
            healthy_count = sum(1 for s in services if s["health_state"] == "healthy")
            degraded_count = sum(1 for s in services if s["health_state"] == "degraded")
            critical_count = sum(1 for s in services if s["health_state"] == "critical")
            disabled_count = sum(1 for s in services if s["health_state"] == "disabled")
            unknown_count = sum(1 for s in services if s["health_state"] == "unknown")

            # Determine category health
            if critical_count > 0:
                category_health = "critical"
            elif degraded_count > 0:
                category_health = "degraded"
            elif unknown_count > 0:
                category_health = "mixed"
            elif len(services) == disabled_count:
                category_health = "disabled"
            elif len(services) == healthy_count:
                category_health = "healthy"
            else:
                category_health = "mixed"

            categories.append({
                "category_name": category_name,
                "display_name": category_data["display_name"],
                "services": services,
                "total_count": len(services),
                "healthy_count": healthy_count,
                "degraded_count": degraded_count,
                "critical_count": critical_count,
                "disabled_count": disabled_count,
                "unknown_count": unknown_count,
                "category_health": category_health
            })

        # Build system health response
        system_health = build_system_health(categories, monitor_profile)

        # T036: Log successful health query
        logging.info(f"Feature 088: Health query complete - {system_health['total_services']} services, system health: {system_health['system_health']}")

        return {
            "status": "ok",
            "health": system_health,
            "timestamp": system_health["timestamp"],
            "timestamp_friendly": system_health["timestamp_friendly"],
            "error": None
        }

    except Exception as e:
        # T035: Error handling with logging
        logging.error(f"Feature 088: Health query failed: {type(e).__name__}: {e}")
        current_timestamp = time.time()
        return {
            "status": "error",
            "health": {
                "timestamp": current_timestamp,
                "timestamp_friendly": format_friendly_timestamp(current_timestamp),
                "monitoring_functional": False,
                "current_monitor_profile": "unknown",
                "total_services": 0,
                "healthy_count": 0,
                "degraded_count": 0,
                "critical_count": 0,
                "disabled_count": 0,
                "unknown_count": 0,
                "categories": [],
                "system_health": "critical",
                "error": f"Health query failed: {type(e).__name__}: {e}"
            },
            "timestamp": current_timestamp,
            "timestamp_friendly": format_friendly_timestamp(current_timestamp),
            "error": f"Health query failed: {type(e).__name__}: {e}"
        }


async def query_traces_data() -> Dict[str, Any]:
    """
    Query window traces view data (Feature 101).

    Returns list of active and stopped traces from the daemon's WindowTracer.
    Each trace contains:
    - trace_id: Unique identifier
    - window_id: Sway window ID being traced
    - matcher: Pattern used to match windows
    - is_active: Whether trace is still running
    - event_count: Number of events recorded
    - duration_seconds: Time since trace started
    - started_at: ISO timestamp

    Returns:
        Dict with status, traces list, and metadata
    """
    current_timestamp = time.time()
    socket_path = os.environ.get("I3PM_DAEMON_SOCKET", "/run/i3-project-daemon/ipc.sock")

    try:
        logging.info("Feature 101: Starting traces query")

        # Connect to daemon and query traces
        client = DaemonClient(socket_path=socket_path, timeout=2.0)
        await client.connect()

        try:
            result = await client.call("trace.list", {})
            traces = result.get("traces", [])
            count = result.get("count", len(traces))
        finally:
            await client.close()

        # Format each trace for display
        formatted_traces = []
        for trace in traces:
            formatted_traces.append({
                "trace_id": trace.get("trace_id", ""),
                "window_id": trace.get("window_id"),
                "matcher": trace.get("matcher", {}),
                "matcher_display": " ".join(f"{k}={v}" for k, v in trace.get("matcher", {}).items()),
                "is_active": trace.get("is_active", False),
                "event_count": trace.get("event_count", 0),
                "duration_seconds": trace.get("duration_seconds", 0.0),
                "duration_display": f"{trace.get('duration_seconds', 0.0):.1f}s",
                "started_at": trace.get("started_at", ""),
                "status_icon": "🔴" if trace.get("is_active") else "⏹",
                "status_label": "ACTIVE" if trace.get("is_active") else "STOPPED"
            })

        return {
            "status": "ok",
            "traces": formatted_traces,
            "trace_count": count,
            "active_count": sum(1 for t in formatted_traces if t["is_active"]),
            "stopped_count": sum(1 for t in formatted_traces if not t["is_active"]),
            "timestamp": current_timestamp,
            "timestamp_friendly": format_friendly_timestamp(current_timestamp)
        }

    except DaemonError as e:
        logging.error(f"Feature 101: Daemon error querying traces: {e}")
        return {
            "status": "error",
            "traces": [],
            "trace_count": 0,
            "active_count": 0,
            "stopped_count": 0,
            "timestamp": current_timestamp,
            "timestamp_friendly": format_friendly_timestamp(current_timestamp),
            "error": f"Daemon error: {e}"
        }
    except Exception as e:
        logging.exception(f"Feature 101: Failed to query traces: {e}")
        return {
            "status": "error",
            "traces": [],
            "trace_count": 0,
            "active_count": 0,
            "stopped_count": 0,
            "timestamp": current_timestamp,
            "timestamp_friendly": format_friendly_timestamp(current_timestamp),
            "error": f"Query failed: {type(e).__name__}: {e}"
        }


async def stream_monitoring_data():
    """
    Stream monitoring data to stdout on Sway events (deflisten mode).

    Features:
    - Subscribes to window/workspace/output events via i3ipc
    - Feature 107: Uses inotify for immediate badge detection (<15ms latency)
    - Outputs JSON on every event (<100ms latency)
    - Heartbeat every 5s to detect stale connections
    - Automatic reconnection with exponential backoff (1s, 2s, 4s, max 10s)
    - Graceful shutdown on SIGTERM/SIGINT/SIGPIPE

    Exit codes:
        0: Graceful shutdown (signal received)
        1: Fatal error (cannot recover)
    """
    if I3Connection is None:
        logger.error("i3ipc.aio module not available - cannot use --listen mode")
        sys.exit(1)

    setup_signal_handlers()
    logger.info("Starting event stream mode (deflisten)")

    reconnect_delay = 1.0  # Start with 1s delay
    max_reconnect_delay = 10.0
    last_update = 0.0
    heartbeat_interval = 5.0

    # Feature 107: Start inotify watcher for badge directory
    badge_watcher_process: Optional[asyncio.subprocess.Process] = None
    badge_change_event = asyncio.Event()
    inotify_reader_task: Optional[asyncio.Task] = None
    use_inotify = True  # Will be set to False if inotifywait unavailable

    try:
        badge_watcher_process = await create_badge_watcher()
        if badge_watcher_process:
            inotify_reader_task = asyncio.create_task(
                read_inotify_events(badge_watcher_process, badge_change_event)
            )
            logger.info("Feature 107: inotify watcher active for badge detection")
        else:
            use_inotify = False
            logger.info("Feature 107: Falling back to polling for badge detection")
    except Exception as e:
        logger.warning(f"Feature 107: Failed to start inotify: {e}, using polling")
        use_inotify = False

    while not shutdown_requested:
        try:
            logger.info("Connecting to Sway IPC...")
            ipc = await I3Connection().connect()
            logger.info("Connected to Sway IPC")

            # Reset reconnect delay on successful connection
            reconnect_delay = 1.0

            # Query and output initial state
            data = await query_monitoring_data()
            print(json.dumps(data, separators=(",", ":")), flush=True)
            last_update = time.time()
            logger.info("Sent initial state")

            # Subscribe to relevant events
            def on_window_event(ipc, event):
                """Handle window events (new, close, focus, etc.)"""
                # Feature 095: Clear badge when window with badge gets focused
                if event.change == "focus" and event.container:
                    window_id = str(event.container.id)
                    badge_file = BADGE_STATE_DIR / f"{window_id}.json"
                    if badge_file.exists():
                        try:
                            badge_file.unlink()
                            logger.debug(f"Feature 095: Cleared badge for focused window {window_id}")
                        except OSError as e:
                            logger.warning(f"Feature 095: Failed to clear badge file: {e}")
                asyncio.create_task(refresh_and_output())

            def on_workspace_event(ipc, event):
                """Handle workspace events (focus, init, empty, etc.)"""
                asyncio.create_task(refresh_and_output())

            def on_output_event(ipc, event):
                """Handle output events (monitor connect/disconnect)"""
                asyncio.create_task(refresh_and_output())

            # Feature 095 Enhancement: Track if we have working badges for spinner animation
            has_working_badge = False

            async def refresh_and_output():
                """Query daemon and output updated JSON."""
                nonlocal last_update, has_working_badge
                try:
                    data = await query_monitoring_data()
                    # Track if we have working badges to enable spinner updates
                    has_working_badge = data.get("has_working_badge", False)
                    print(json.dumps(data, separators=(",", ":")), flush=True)
                    last_update = time.time()
                except Exception as e:
                    logger.warning(f"Error refreshing data: {e}")

            # Register event handlers
            ipc.on('window', on_window_event)
            ipc.on('workspace', on_workspace_event)
            ipc.on('output', on_output_event)

            # Feature 095 Enhancement: Spinner animation interval (120ms)
            # Only used when has_working_badge is True
            spinner_interval = SPINNER_INTERVAL_MS / 1000.0  # Convert to seconds
            last_spinner_update = time.time()

            # Feature 107: Polling fallback interval (500ms when inotify unavailable)
            # Only used when inotify is not available
            polling_fallback_interval = 0.5  # 500ms
            last_polling_check = time.time()

            # Event loop with heartbeat
            while not shutdown_requested:
                current_time = time.time()

                # Feature 107: Check for inotify-triggered badge changes (immediate)
                if use_inotify and badge_change_event.is_set():
                    badge_change_event.clear()
                    logger.debug("Feature 107: inotify triggered badge refresh")
                    await refresh_and_output()

                # Feature 107: Polling fallback when inotify unavailable
                elif not use_inotify and not has_working_badge:
                    if (current_time - last_polling_check) >= polling_fallback_interval:
                        badge_state = load_badge_state_from_files()
                        if any(b.get("state") == "working" for b in badge_state.values()):
                            logger.debug("Feature 095: Detected working badge from file (polling), triggering refresh")
                            await refresh_and_output()
                        last_polling_check = current_time

                # Feature 095 Enhancement: Fast updates for spinner animation when working badge exists
                if has_working_badge and (current_time - last_spinner_update) >= spinner_interval:
                    logger.debug("Sending spinner frame update")
                    await refresh_and_output()
                    last_spinner_update = current_time
                # Send heartbeat if no updates in last N seconds (normal mode)
                elif current_time - last_update > heartbeat_interval:
                    logger.debug("Sending heartbeat")
                    await refresh_and_output()

                # Feature 107: Sleep duration depends on mode
                # - With inotify: longer sleep (badge changes trigger immediately)
                # - Without inotify: shorter sleep for polling
                # - With spinner: shortest sleep for animation
                if has_working_badge:
                    sleep_time = 0.05  # 50ms for spinner animation
                elif use_inotify:
                    sleep_time = 0.5   # 500ms when using inotify (events wake us up)
                else:
                    sleep_time = 0.25  # 250ms for polling fallback
                await asyncio.sleep(sleep_time)

        except ConnectionError as e:
            logger.warning(f"Connection lost: {e}, reconnecting in {reconnect_delay}s")
            await asyncio.sleep(reconnect_delay)
            # Exponential backoff
            reconnect_delay = min(reconnect_delay * 2, max_reconnect_delay)

        except Exception as e:
            logger.error(f"Unexpected error in stream loop: {e}", exc_info=True)
            await asyncio.sleep(reconnect_delay)
            reconnect_delay = min(reconnect_delay * 2, max_reconnect_delay)

    # Feature 107: Cleanup inotify watcher
    if inotify_reader_task:
        inotify_reader_task.cancel()
        try:
            await inotify_reader_task
        except asyncio.CancelledError:
            pass
    if badge_watcher_process:
        badge_watcher_process.terminate()
        await badge_watcher_process.wait()
        logger.info("Feature 107: inotify watcher stopped")

    logger.info("Shutdown complete")
    sys.exit(0)


# =============================================================================
# Feature 092: Event Logging - Backend Implementation
# =============================================================================

# Global event buffer (initialized on first stream)
_event_buffer: Optional[EventBuffer] = None


async def query_events_data() -> Dict[str, Any]:
    """
    Query events data (one-shot mode).

    Returns current event buffer state. Buffer must be initialized by stream mode first.

    Returns:
        EventsViewData as dict (Pydantic model_dump)
    """
    global _event_buffer

    current_time = time.time()

    # If buffer not initialized, return empty state
    if _event_buffer is None:
        view_data = EventsViewData(
            status="ok",
            events=[],
            event_count=0,
            oldest_timestamp=None,
            newest_timestamp=None,
            daemon_available=True,
            ipc_connected=False,
            timestamp=current_time,
            timestamp_friendly=format_friendly_timestamp(current_time),
        )
        return view_data.model_dump(mode="json")

    # Get all events from buffer (refresh timestamps for accurate display)
    events = _event_buffer.get_all(refresh_timestamps=True)

    # Feature 102 T066-T067: Compute cross-reference validity
    # Build sets of valid trace_ids and correlation_ids (root events only)
    valid_trace_ids: set = set()
    root_correlation_ids: set = set()
    for event in events:
        if event.trace_id:
            valid_trace_ids.add(event.trace_id)
        # Root events have correlation_id but causality_depth == 0
        if event.correlation_id and event.causality_depth == 0:
            root_correlation_ids.add(event.correlation_id)

    # Mark events with evicted traces or missing parents
    for event in events:
        # T066: Check if trace_id references a trace not in current view
        # (This is a simplified check - ideally we'd query daemon for trace existence)
        # For now, we mark as evicted if trace_id is set but not in valid_trace_ids
        # Actually, all events with trace_id should be in valid_trace_ids by construction
        # So we skip this for now - the trace_evicted field is for future daemon integration

        # T067: Check if event has parent correlation but parent is missing
        if event.correlation_id and event.causality_depth > 0:
            if event.correlation_id not in root_correlation_ids:
                event.parent_missing = True

    # Feature 102 T053: Create duration-sorted list (slowest first)
    events_by_duration = sorted(
        events,
        key=lambda e: e.processing_duration_ms,
        reverse=True  # Slowest first
    )

    view_data = EventsViewData(
        status="ok",
        events=events,
        events_by_duration=events_by_duration,
        event_count=len(events),
        oldest_timestamp=events[0].timestamp if events else None,
        newest_timestamp=events[-1].timestamp if events else None,
        daemon_available=True,
        ipc_connected=True,
        timestamp=current_time,
        timestamp_friendly=format_friendly_timestamp(current_time),
    )

    return view_data.model_dump(mode="json")


async def stream_events():
    """
    Stream events (deflisten mode) - Feature 092.

    Subscribes to Sway IPC window/workspace/output events and outputs JSON to stdout.
    Similar architecture to stream_monitoring_data() but focused on event logging.
    """
    global _event_buffer

    # Initialize buffer
    _event_buffer = EventBuffer(max_size=500)

    # Setup signal handlers for graceful shutdown
    shutdown_event = asyncio.Event()

    def signal_handler(signum, frame):
        logger.info(f"Received signal {signum}, initiating shutdown")
        shutdown_event.set()

    signal.signal(signal.SIGTERM, signal_handler)
    signal.signal(signal.SIGINT, signal_handler)

    # Connect to Sway IPC
    try:
        conn = await I3Connection(auto_reconnect=True).connect()
        logger.info("Connected to Sway IPC for event streaming")
    except Exception as e:
        logger.critical(f"Failed to connect to Sway IPC: {e}")
        error_time = time.time()
        error_data = EventsViewData(
            status="error",
            error=f"Sway IPC connection failed: {e}",
            events=[],
            event_count=0,
            daemon_available=False,
            ipc_connected=False,
            timestamp=error_time,
            timestamp_friendly=format_friendly_timestamp(error_time),
        )
        print(json.dumps(error_data.model_dump(mode="json"), separators=(",", ":")))
        sys.exit(1)

    # Event handlers
    def create_event_from_sway(event_type: EventType, change_type: str, sway_payload: Dict[str, Any]) -> Event:
        """Helper to create Event from Sway IPC event."""
        current_time = time.time()

        # Get icon, color, and source from EVENT_ICONS (Feature 102: T017)
        icon_data = EVENT_ICONS.get(event_type, {"icon": "󰀄", "color": "#a6adc8", "source": "sway"})
        icon = icon_data["icon"]
        color = icon_data["color"]
        source = icon_data.get("source", "sway")  # Default to "sway" for backwards compatibility

        # Determine category - Feature 102: Added i3pm categories (T017)
        if event_type.startswith("window::"):
            category = "window"
        elif event_type.startswith("workspace::"):
            category = "workspace"
        elif event_type.startswith("output::"):
            category = "output"
        elif event_type.startswith("binding::"):
            category = "binding"
        elif event_type.startswith("mode::"):
            category = "mode"
        elif event_type.startswith("project::"):
            category = "project"
        elif event_type.startswith("visibility::"):
            category = "visibility"
        elif event_type.startswith("scratchpad::"):
            category = "scratchpad"
        elif event_type.startswith("launch::"):
            category = "launch"
        elif event_type.startswith("state::"):
            category = "state"
        elif event_type.startswith("command::"):
            category = "command"
        elif event_type.startswith("trace::"):
            category = "trace"
        else:
            category = "system"

        # Build searchable text (basic version)
        searchable_parts = [event_type, change_type]
        if "container" in sway_payload and sway_payload["container"]:
            container = sway_payload["container"]
            searchable_parts.append(container.get("app_id", ""))
            searchable_parts.append(container.get("name", ""))
        if "current" in sway_payload and sway_payload["current"]:
            searchable_parts.append(str(sway_payload["current"].get("num", "")))

        searchable_text = " ".join(filter(None, searchable_parts))

        # Create payload model
        payload = SwayEventPayload(**sway_payload)

        # Feature 102 (T028): Extract trace cross-reference fields
        trace_id = sway_payload.get("trace_id")
        correlation_id = sway_payload.get("correlation_id")
        causality_depth = sway_payload.get("causality_depth", 0)

        # Feature 102 T052: Extract processing duration from daemon events
        processing_duration_ms = sway_payload.get("processing_duration_ms", 0.0)

        return Event(
            timestamp=current_time,
            timestamp_friendly=format_friendly_timestamp(current_time),
            event_type=event_type,
            change_type=change_type,
            payload=payload,
            enrichment=None,  # TODO: Add daemon enrichment in future iteration
            icon=icon,
            color=color,
            source=source,  # Feature 102: T017
            category=category,
            trace_id=trace_id,  # Feature 102: T028
            correlation_id=correlation_id,  # Feature 102: T028
            causality_depth=causality_depth,  # Feature 102: T028
            processing_duration_ms=processing_duration_ms,  # Feature 102: T052
            searchable_text=searchable_text,
        )

    def on_window_event(conn, event):
        """Handle window events."""
        try:
            change = event.change
            event_type = f"window::{change}"

            # Extract payload
            sway_payload = {
                "container": event.container.ipc_data if hasattr(event, "container") else None,
                "change": change,
            }

            # Create and buffer event
            evt = create_event_from_sway(event_type, change, sway_payload)
            _event_buffer.append(evt)

            # Output immediately (refresh timestamps for accurate display)
            current_output_time = time.time()
            events_with_fresh_timestamps = _event_buffer.get_all(refresh_timestamps=True)
            perf_stats = _event_buffer.get_performance_stats()  # Feature 102 T054
            view_data = EventsViewData(
                status="ok",
                events=events_with_fresh_timestamps,
                event_count=_event_buffer.size(),
                oldest_timestamp=events_with_fresh_timestamps[0].timestamp if _event_buffer.size() > 0 else None,
                newest_timestamp=events_with_fresh_timestamps[-1].timestamp if _event_buffer.size() > 0 else None,
                avg_duration_ms=perf_stats["avg_duration_ms"],
                slow_event_count=perf_stats["slow_event_count"],
                critical_event_count=perf_stats["critical_event_count"],
                daemon_available=True,
                ipc_connected=True,
                timestamp=current_output_time,
                timestamp_friendly=format_friendly_timestamp(current_output_time),
            )
            print(json.dumps(view_data.model_dump(mode="json"), separators=(",", ":")), flush=True)

        except Exception as e:
            logger.error(f"Error handling window event: {e}", exc_info=True)

    def on_workspace_event(conn, event):
        """Handle workspace events."""
        try:
            change = event.change
            event_type = f"workspace::{change}"

            # Extract payload
            sway_payload = {
                "current": event.current.ipc_data if hasattr(event, "current") else None,
                "old": event.old.ipc_data if hasattr(event, "old") else None,
                "change": change,
            }

            # Create and buffer event
            evt = create_event_from_sway(event_type, change, sway_payload)
            _event_buffer.append(evt)

            # Output immediately (refresh timestamps for accurate display)
            current_output_time = time.time()
            events_with_fresh_timestamps = _event_buffer.get_all(refresh_timestamps=True)
            perf_stats = _event_buffer.get_performance_stats()  # Feature 102 T054
            view_data = EventsViewData(
                status="ok",
                events=events_with_fresh_timestamps,
                event_count=_event_buffer.size(),
                oldest_timestamp=events_with_fresh_timestamps[0].timestamp if _event_buffer.size() > 0 else None,
                newest_timestamp=events_with_fresh_timestamps[-1].timestamp if _event_buffer.size() > 0 else None,
                avg_duration_ms=perf_stats["avg_duration_ms"],
                slow_event_count=perf_stats["slow_event_count"],
                critical_event_count=perf_stats["critical_event_count"],
                daemon_available=True,
                ipc_connected=True,
                timestamp=current_output_time,
                timestamp_friendly=format_friendly_timestamp(current_output_time),
            )
            print(json.dumps(view_data.model_dump(mode="json"), separators=(",", ":")), flush=True)

        except Exception as e:
            logger.error(f"Error handling workspace event: {e}", exc_info=True)

    # Subscribe to events
    conn.on("window", on_window_event)
    conn.on("workspace", on_workspace_event)

    logger.info("Event subscriptions active, streaming to stdout")

    # Keep running until shutdown
    try:
        await shutdown_event.wait()
    except KeyboardInterrupt:
        logger.info("Keyboard interrupt received")
    finally:
        logger.info("Shutting down event stream")
        await conn.close()
        sys.exit(0)


async def main():
    """
    Main entry point for backend script.

    Modes:
    - windows (default): Window/project hierarchy view
    - projects: Project list view
    - apps: Application registry view
    - health: System health view
    - events: Sway IPC event log view (Feature 092)
    - traces: Window traces view (Feature 101)
    - Stream (--listen): Continuous event stream (deflisten mode)

    Exit codes:
        0: Success (status: "ok" or graceful shutdown)
        1: Error (status: "error" or fatal error)
    """
    # Parse arguments
    parser = argparse.ArgumentParser(description="Monitoring panel data backend")
    parser.add_argument(
        "--mode",
        choices=["windows", "projects", "apps", "health", "events", "traces", "worktree_map"],
        default="windows",
        help="View mode (default: windows). Use worktree_map for Feature 111 visual graph."
    )
    parser.add_argument(
        "--listen",
        action="store_true",
        help="Stream mode (deflisten) - works with windows and events modes"
    )
    args = parser.parse_args()

    # Stream mode (for windows or events view)
    if args.listen:
        if args.mode == "windows":
            await stream_monitoring_data()
            return
        elif args.mode == "events":
            await stream_events()
            return
        else:
            logger.error(f"--listen flag only works with windows or events mode, got: {args.mode}")
            sys.exit(1)

    # One-shot mode - route to appropriate query function
    try:
        if args.mode == "windows":
            data = await query_monitoring_data()
        elif args.mode == "projects":
            data = await query_projects_data()
        elif args.mode == "apps":
            data = await query_apps_data()
        elif args.mode == "health":
            data = await query_health_data()
        elif args.mode == "events":
            data = await query_events_data()
        elif args.mode == "traces":
            data = await query_traces_data()
        elif args.mode == "worktree_map":
            data = await query_worktree_map_data()
        else:
            raise ValueError(f"Unknown mode: {args.mode}")

        # Output single-line JSON (no formatting for Eww parsing performance)
        # Use separators parameter to minimize output size
        print(json.dumps(data, separators=(",", ":")))

        # Exit with appropriate code
        sys.exit(0 if data["status"] == "ok" else 1)

    except Exception as e:
        # Catastrophic failure - output error JSON and exit with error code
        logger.critical(f"Fatal error in main(): {e}", exc_info=True)
        error_timestamp = time.time()
        error_data = {
            "status": "error",
            "data": {},
            "timestamp": error_timestamp,
            "timestamp_friendly": format_friendly_timestamp(error_timestamp),
            "error": f"Fatal error: {type(e).__name__}: {e}",
        }
        print(json.dumps(error_data, separators=(",", ":")))
        sys.exit(1)


if __name__ == "__main__":
    asyncio.run(main())
# Feature 095 Enhancement build marker: 1764104128
