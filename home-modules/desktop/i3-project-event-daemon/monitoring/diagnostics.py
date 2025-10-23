"""
Diagnostic Snapshots Module

Feature 030: Production Readiness
Task T015: Diagnostic snapshot generation

Generates complete diagnostic reports including:
- Daemon state
- Window tree
- Recent events
- Configuration
"""

import json
import time
from datetime import datetime
from dataclasses import dataclass, field, asdict
from typing import Optional, List, Dict, Any
from pathlib import Path
import logging

logger = logging.getLogger(__name__)


@dataclass
class DiagnosticSnapshot:
    """
    Complete diagnostic snapshot of daemon state

    This snapshot can be exported for debugging, support tickets,
    or post-mortem analysis.
    """
    # Metadata
    timestamp: str = field(default_factory=lambda: datetime.now().isoformat())
    daemon_version: str = "2.0.0"  # TODO: Get from version file
    hostname: str = ""

    # Daemon state
    health_metrics: Optional[dict] = None
    performance_metrics: Optional[dict] = None

    # i3 state
    i3_tree: Optional[dict] = None
    i3_workspaces: List[dict] = field(default_factory=list)
    i3_outputs: List[dict] = field(default_factory=list)

    # Event history
    recent_events: List[dict] = field(default_factory=list)
    event_buffer_size: int = 0

    # Configuration
    active_project: Optional[str] = None
    projects: List[dict] = field(default_factory=list)
    classification_rules: List[dict] = field(default_factory=list)

    # Window state
    tracked_windows: List[dict] = field(default_factory=list)
    window_count: int = 0
    hidden_window_count: int = 0

    # System info
    system_info: Dict[str, Any] = field(default_factory=dict)

    def to_dict(self) -> dict:
        """Convert snapshot to dictionary"""
        return asdict(self)

    def to_json(self, indent: int = 2) -> str:
        """Convert snapshot to JSON string"""
        return json.dumps(self.to_dict(), indent=indent, default=str)

    def save_to_file(self, output_path: Path):
        """
        Save snapshot to file

        Args:
            output_path: Path to output file (JSON)
        """
        output_path.parent.mkdir(parents=True, exist_ok=True)

        with open(output_path, 'w') as f:
            f.write(self.to_json())

        logger.info(f"Diagnostic snapshot saved to {output_path}")


async def generate_diagnostic_snapshot(
    include_i3_tree: bool = True,
    include_events: bool = True,
    event_limit: int = 100,
    sanitize: bool = True,
) -> DiagnosticSnapshot:
    """
    Generate complete diagnostic snapshot

    This is an async function because it may query i3 IPC and read from
    various daemon components.

    Args:
        include_i3_tree: Include full i3 window tree (can be large)
        include_events: Include recent event history
        event_limit: Maximum number of events to include
        sanitize: Apply sanitization to sensitive data

    Returns:
        DiagnosticSnapshot with all collected information
    """
    import socket
    from ..monitoring.health import get_health_metrics
    from ..monitoring.metrics import get_performance_metrics

    snapshot = DiagnosticSnapshot()

    # System info
    snapshot.hostname = socket.gethostname()
    snapshot.system_info = {
        "python_version": _get_python_version(),
        "platform": _get_platform_info(),
    }

    # Health and performance metrics
    try:
        health = get_health_metrics()
        snapshot.health_metrics = health.to_dict()
    except Exception as e:
        logger.error(f"Failed to collect health metrics: {e}")
        snapshot.health_metrics = {"error": str(e)}

    try:
        perf = get_performance_metrics()
        snapshot.performance_metrics = perf.to_dict()
    except Exception as e:
        logger.error(f"Failed to collect performance metrics: {e}")
        snapshot.performance_metrics = {"error": str(e)}

    # i3 state
    try:
        snapshot.i3_workspaces = await _get_i3_workspaces()
        snapshot.i3_outputs = await _get_i3_outputs()

        if include_i3_tree:
            snapshot.i3_tree = await _get_i3_tree()
    except Exception as e:
        logger.error(f"Failed to collect i3 state: {e}")

    # Event history
    if include_events:
        try:
            snapshot.recent_events = await _get_recent_events(event_limit, sanitize)
            snapshot.event_buffer_size = len(snapshot.recent_events)
        except Exception as e:
            logger.error(f"Failed to collect event history: {e}")

    # Configuration
    try:
        snapshot.active_project = await _get_active_project()
        snapshot.projects = await _get_projects()
        snapshot.classification_rules = await _get_classification_rules()
    except Exception as e:
        logger.error(f"Failed to collect configuration: {e}")

    # Window state
    try:
        windows = await _get_tracked_windows()
        snapshot.tracked_windows = windows
        snapshot.window_count = len(windows)
        snapshot.hidden_window_count = len([w for w in windows if w.get('hidden', False)])
    except Exception as e:
        logger.error(f"Failed to collect window state: {e}")

    return snapshot


# ============================================================================
# Helper Functions for Data Collection
# ============================================================================

def _get_python_version() -> str:
    """Get Python version string"""
    import sys
    return sys.version


def _get_platform_info() -> dict:
    """Get platform information"""
    import platform
    return {
        "system": platform.system(),
        "release": platform.release(),
        "version": platform.version(),
        "machine": platform.machine(),
    }


async def _get_i3_workspaces() -> List[dict]:
    """Get i3 workspace state"""
    # TODO: Implement i3 IPC query
    # This will be integrated with existing daemon i3 connection
    return []


async def _get_i3_outputs() -> List[dict]:
    """Get i3 output (monitor) state"""
    # TODO: Implement i3 IPC query
    return []


async def _get_i3_tree() -> dict:
    """Get i3 window tree"""
    # TODO: Implement i3 IPC query
    return {}


async def _get_recent_events(limit: int, sanitize: bool) -> List[dict]:
    """Get recent events from event buffer"""
    # TODO: Integrate with event_buffer.py
    # Apply sanitization if requested
    return []


async def _get_active_project() -> Optional[str]:
    """Get currently active project name"""
    # TODO: Query daemon state
    return None


async def _get_projects() -> List[dict]:
    """Get all configured projects"""
    # TODO: Load from config
    return []


async def _get_classification_rules() -> List[dict]:
    """Get classification rules"""
    # TODO: Load from config
    return []


async def _get_tracked_windows() -> List[dict]:
    """Get tracked window state"""
    # TODO: Query daemon state
    return []


# Synchronous wrapper for non-async contexts
def generate_diagnostic_snapshot_sync(**kwargs) -> DiagnosticSnapshot:
    """
    Synchronous wrapper for generate_diagnostic_snapshot

    For use in non-async contexts. Creates an event loop if needed.
    """
    import asyncio

    try:
        loop = asyncio.get_event_loop()
    except RuntimeError:
        loop = asyncio.new_event_loop()
        asyncio.set_event_loop(loop)

    return loop.run_until_complete(generate_diagnostic_snapshot(**kwargs))
