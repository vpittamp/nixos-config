"""Mock daemon client fixture for testing diagnostic CLI (Feature 039: T016)."""

import asyncio
import json
from typing import Any, Dict, List, Optional
from dataclasses import dataclass, field
from datetime import datetime


@dataclass
class MockDaemonState:
    """Mock daemon state for testing."""
    version: str = "1.4.0"
    uptime_seconds: float = 3600.0
    i3_ipc_connected: bool = True
    json_rpc_server_running: bool = True
    windows: Dict[int, Dict[str, Any]] = field(default_factory=dict)
    events: List[Dict[str, Any]] = field(default_factory=list)
    event_subscriptions: Dict[str, Dict[str, Any]] = field(default_factory=dict)


class MockDaemonClient:
    """Mock daemon IPC client for testing diagnostic CLI."""

    def __init__(self, state: Optional[MockDaemonState] = None):
        """Initialize mock client."""
        self.state = state or MockDaemonState()
        self._connected = False
        self._socket_path = "/tmp/i3pm-test.sock"

    async def connect(self) -> None:
        """Mock connection."""
        self._connected = True

    async def disconnect(self) -> None:
        """Mock disconnection."""
        self._connected = False

    async def health_check(self) -> Dict[str, Any]:
        """Mock health check RPC call."""
        if not self._connected:
            raise ConnectionError("Not connected to daemon")

        return {
            "generated_at": datetime.now().isoformat(),
            "daemon_version": self.state.version,
            "uptime_seconds": self.state.uptime_seconds,
            "i3_ipc_connected": self.state.i3_ipc_connected,
            "json_rpc_server_running": self.state.json_rpc_server_running,
            "event_subscriptions": list(self.state.event_subscriptions.values()),
            "total_events_processed": sum(
                sub.get("event_count", 0) for sub in self.state.event_subscriptions.values()
            ),
            "total_windows": len(self.state.windows),
            "overall_status": "healthy" if self.state.i3_ipc_connected else "critical",
            "health_issues": []
        }

    async def get_window_identity(self, window_id: int) -> Optional[Dict[str, Any]]:
        """Mock get window identity RPC call."""
        if not self._connected:
            raise ConnectionError("Not connected to daemon")

        return self.state.windows.get(window_id)

    async def get_workspace_rule(self, app_name: str) -> Optional[Dict[str, Any]]:
        """Mock get workspace rule RPC call."""
        if not self._connected:
            raise ConnectionError("Not connected to daemon")

        # Mock rules
        rules = {
            "terminal": {
                "app_identifier": "ghostty",
                "matching_strategy": "normalized",
                "aliases": ["com.mitchellh.ghostty", "Ghostty"],
                "target_workspace": 3,
                "fallback_behavior": "current",
                "app_name": "terminal"
            },
            "vscode": {
                "app_identifier": "Code",
                "matching_strategy": "exact",
                "aliases": ["code"],
                "target_workspace": 2,
                "fallback_behavior": "current",
                "app_name": "vscode"
            }
        }
        return rules.get(app_name)

    async def validate_state(self) -> Dict[str, Any]:
        """Mock state validation RPC call."""
        if not self._connected:
            raise ConnectionError("Not connected to daemon")

        # Simple mock validation (all consistent)
        return {
            "validated_at": datetime.now().isoformat(),
            "total_windows_checked": len(self.state.windows),
            "windows_consistent": len(self.state.windows),
            "windows_inconsistent": 0,
            "mismatches": [],
            "is_consistent": True,
            "consistency_percentage": 100.0
        }

    async def get_recent_events(
        self, limit: int = 50, event_type: Optional[str] = None
    ) -> List[Dict[str, Any]]:
        """Mock get recent events RPC call."""
        if not self._connected:
            raise ConnectionError("Not connected to daemon")

        events = self.state.events[-limit:]
        if event_type:
            events = [e for e in events if e.get("event_type") == event_type]
        return events

    async def get_diagnostic_report(self) -> Dict[str, Any]:
        """Mock comprehensive diagnostic report RPC call."""
        if not self._connected:
            raise ConnectionError("Not connected to daemon")

        health = await self.health_check()
        validation = await self.validate_state()

        return {
            **health,
            "tracked_windows": list(self.state.windows.values()),
            "recent_events": self.state.events[-50:],
            "event_buffer_size": 500,
            "state_validation": validation,
            "i3_ipc_state": {
                "outputs": [{"name": "HDMI-1", "active": True}],
                "active_output_count": 1,
                "workspaces": [
                    {"num": 1, "name": "1:web", "visible": True, "focused": False, "output": "HDMI-1"},
                    {"num": 2, "name": "2:code", "visible": True, "focused": True, "output": "HDMI-1"}
                ],
                "visible_workspace_count": 2,
                "focused_workspace": "2:code",
                "total_windows": len(self.state.windows),
                "marks": [],
                "captured_at": datetime.now().isoformat()
            }
        }

    # Test helper methods

    def add_window(self, window_identity: Dict[str, Any]) -> None:
        """Add a mock window to state."""
        self.state.windows[window_identity["window_id"]] = window_identity

    def add_event(self, event: Dict[str, Any]) -> None:
        """Add a mock event to history."""
        self.state.events.append(event)

    def add_subscription(self, event_type: str, active: bool = True, count: int = 0) -> None:
        """Add a mock event subscription."""
        self.state.event_subscriptions[event_type] = {
            "subscription_type": event_type,
            "is_active": active,
            "event_count": count,
            "last_event_time": datetime.now().isoformat() if count > 0 else None,
            "last_event_change": "new" if count > 0 else None
        }

    def reset(self) -> None:
        """Reset mock state."""
        self.state = MockDaemonState()
        self._connected = False


# Fixture factory functions

def create_healthy_daemon() -> MockDaemonClient:
    """Create a healthy daemon client fixture."""
    state = MockDaemonState()
    state.event_subscriptions = {
        "window": {
            "subscription_type": "window",
            "is_active": True,
            "event_count": 1234,
            "last_event_time": datetime.now().isoformat(),
            "last_event_change": "new"
        },
        "workspace": {
            "subscription_type": "workspace",
            "is_active": True,
            "event_count": 89,
            "last_event_time": datetime.now().isoformat(),
            "last_event_change": "focus"
        }
    }
    return MockDaemonClient(state)


def create_unhealthy_daemon() -> MockDaemonClient:
    """Create an unhealthy daemon client fixture (no events)."""
    state = MockDaemonState()
    state.i3_ipc_connected = False
    state.event_subscriptions = {
        "window": {
            "subscription_type": "window",
            "is_active": False,
            "event_count": 0,
            "last_event_time": None,
            "last_event_change": None
        }
    }
    return MockDaemonClient(state)


def create_daemon_with_drift() -> MockDaemonClient:
    """Create daemon with state drift (for validation tests)."""
    client = create_healthy_daemon()
    client.state.windows = {
        14680068: {
            "window_id": 14680068,
            "workspace_number": 3,  # Daemon thinks it's on WS3
            "daemon_workspace": 3,
            "i3_workspace": 5  # But it's actually on WS5
        }
    }
    return client


# Mock daemon for workspace assignment testing (Feature 039: T021)

class MockDaemon:
    """
    Mock daemon for workspace assignment integration tests.

    Simulates the 4-tier workspace assignment priority system:
    1. App-specific handlers (VS Code title parsing)
    2. I3PM_TARGET_WORKSPACE environment variable
    3. I3PM_APP_NAME registry lookup
    4. Window class matching
    """

    def __init__(self):
        """Initialize mock daemon."""
        self.registry: Optional[Dict[str, Any]] = None
        self.current_workspace = 1
        self.app_specific_handlers = {
            "Code": self._vscode_handler
        }

    async def initialize(self):
        """Initialize daemon (async for test fixtures)."""
        pass

    async def cleanup(self):
        """Cleanup daemon (async for test fixtures)."""
        pass

    def set_registry(self, registry: Dict[str, Any]):
        """Set application registry."""
        self.registry = registry

    def set_current_workspace(self, workspace: int):
        """Set current workspace number."""
        self.current_workspace = workspace

    async def assign_workspace(
        self,
        window_id: int,
        window_class: str,
        window_title: str,
        window_pid: Optional[int],
        i3pm_env: Optional[Any]
    ) -> Dict[str, Any]:
        """
        Assign workspace to window using 4-tier priority system.

        Returns:
            Dict with keys:
            - success: bool
            - workspace: int (assigned workspace number)
            - source: str (which priority tier was used)
            - duration_ms: float (simulated execution time)
            - project_override: Optional[str] (for app-specific handlers)
        """
        import time
        start = time.perf_counter()

        result = {
            "success": False,
            "workspace": None,
            "source": None,
            "duration_ms": 0.0,
            "project_override": None
        }

        try:
            # Priority 1: App-specific handler
            if window_class in self.app_specific_handlers:
                handler_result = await self.app_specific_handlers[window_class](
                    window_id, window_title, i3pm_env
                )
                if handler_result:
                    result["success"] = True
                    result["workspace"] = handler_result["workspace"]
                    result["source"] = "app_specific_handler"
                    result["project_override"] = handler_result.get("project")
                    result["duration_ms"] = (time.perf_counter() - start) * 1000
                    return result

            # Priority 2: I3PM_TARGET_WORKSPACE environment variable
            if i3pm_env and hasattr(i3pm_env, 'target_workspace') and i3pm_env.target_workspace:
                if 1 <= i3pm_env.target_workspace <= 10:
                    result["success"] = True
                    result["workspace"] = i3pm_env.target_workspace
                    result["source"] = "i3pm_target_workspace"
                    result["duration_ms"] = (time.perf_counter() - start) * 1000
                    return result

            # Priority 3: I3PM_APP_NAME registry lookup
            if i3pm_env and hasattr(i3pm_env, 'app_name') and i3pm_env.app_name and self.registry:
                app_config = self.registry.get(i3pm_env.app_name)
                if app_config and "preferred_workspace" in app_config:
                    workspace = app_config["preferred_workspace"]
                    if 1 <= workspace <= 10:
                        result["success"] = True
                        result["workspace"] = workspace
                        result["source"] = "i3pm_app_name_lookup"
                        result["duration_ms"] = (time.perf_counter() - start) * 1000
                        return result

            # Priority 4: Window class matching
            if self.registry:
                for app_name, app_config in self.registry.items():
                    expected_class = app_config.get("expected_class", "")
                    if expected_class and self._match_class(window_class, expected_class):
                        workspace = app_config.get("preferred_workspace")
                        if workspace and 1 <= workspace <= 10:
                            result["success"] = True
                            result["workspace"] = workspace
                            result["source"] = "window_class_match"
                            result["duration_ms"] = (time.perf_counter() - start) * 1000
                            return result

            # Fallback: Current workspace
            result["success"] = True
            result["workspace"] = self.current_workspace
            result["source"] = "fallback_current"
            result["duration_ms"] = (time.perf_counter() - start) * 1000
            return result

        except Exception as e:
            result["success"] = False
            result["error"] = str(e)
            result["duration_ms"] = (time.perf_counter() - start) * 1000
            return result

    async def _vscode_handler(
        self, window_id: int, window_title: str, i3pm_env: Optional[Any]
    ) -> Optional[Dict[str, Any]]:
        """
        VS Code app-specific handler.

        Extracts project name from window title for workspace lookup.
        Title format: "project - workspace - Visual Studio Code"
        """
        import re

        # Parse project from title
        match = re.match(r"(?:Code - )?([^-]+) -", window_title)
        if match:
            project = match.group(1).strip().lower()

            # VS Code uses workspace 2
            return {
                "workspace": 2,
                "project": project
            }

        return None

    def _match_class(self, window_class: str, expected_class: str) -> bool:
        """
        Match window class (simple exact match for testing).

        In production, this would use tiered matching (exact, instance, normalized).
        """
        # Exact match
        if window_class == expected_class:
            return True

        # Normalized match (lowercase, simple)
        if window_class.lower() == expected_class.lower():
            return True

        return False
