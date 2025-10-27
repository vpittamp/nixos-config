"""Test fixtures and factories for IPC Launch Context tests.

Feature 041: IPC Launch Context - T014

Provides factory functions and mock objects for testing launch notification and
window correlation functionality.
"""

import time
from pathlib import Path
from typing import Dict, Any, Optional
from unittest.mock import AsyncMock, Mock


def create_pending_launch(
    app_name: str = "vscode",
    project_name: str = "nixos",
    project_directory: str = "/etc/nixos",
    launcher_pid: int = 12345,
    workspace_number: int = 2,
    timestamp: Optional[float] = None,
    expected_class: str = "Code",
    matched: bool = False
) -> Dict[str, Any]:
    """
    Factory function for creating PendingLaunch test data.

    Args:
        app_name: Application name from registry (default: "vscode")
        project_name: Project name for this launch (default: "nixos")
        project_directory: Absolute path to project directory (default: "/etc/nixos")
        launcher_pid: Process ID of launcher wrapper (default: 12345)
        workspace_number: Target workspace number 1-70 (default: 2)
        timestamp: Unix timestamp when launch notification sent (default: current time)
        expected_class: Window class expected from registry (default: "Code")
        matched: True if matched to a window (default: False)

    Returns:
        Dictionary with PendingLaunch data suitable for Pydantic model creation
    """
    if timestamp is None:
        timestamp = time.time()

    return {
        "app_name": app_name,
        "project_name": project_name,
        "project_directory": Path(project_directory),
        "launcher_pid": launcher_pid,
        "workspace_number": workspace_number,
        "timestamp": timestamp,
        "expected_class": expected_class,
        "matched": matched
    }


def create_window_info(
    window_id: int = 94532735639728,
    window_class: str = "Code",
    window_pid: Optional[int] = 12346,
    workspace_number: int = 2,
    timestamp: Optional[float] = None
) -> Dict[str, Any]:
    """
    Factory function for creating LaunchWindowInfo test data.

    Args:
        window_id: i3 window/container ID (default: 94532735639728)
        window_class: X11 window class (default: "Code")
        window_pid: Process ID of window (default: 12346)
        workspace_number: Workspace number where window appeared (default: 2)
        timestamp: Unix timestamp when window::new event received (default: current time)

    Returns:
        Dictionary with LaunchWindowInfo data suitable for Pydantic model creation
    """
    if timestamp is None:
        timestamp = time.time()

    return {
        "window_id": window_id,
        "window_class": window_class,
        "window_pid": window_pid,
        "workspace_number": workspace_number,
        "timestamp": timestamp
    }


class MockIPCServer:
    """
    Mock IPC server for testing launch notification endpoints.

    Simulates the daemon's IPC server behavior for testing notify_launch,
    get_launch_stats, and get_pending_launches endpoints without requiring
    a running daemon.
    """

    def __init__(self):
        """Initialize mock IPC server with empty launch registry."""
        self.pending_launches: Dict[str, Dict[str, Any]] = {}
        self.stats = {
            "total_notifications": 0,
            "total_matched": 0,
            "total_expired": 0,
            "total_failed_correlation": 0
        }
        self.application_registry = {
            "vscode": {"expected_class": "Code", "preferred_workspace": 2},
            "terminal": {"expected_class": "Alacritty", "preferred_workspace": 1},
            "browser": {"expected_class": "firefox", "preferred_workspace": 3}
        }

    async def notify_launch(self, params: Dict[str, Any]) -> Dict[str, Any]:
        """
        Mock notify_launch endpoint.

        Args:
            params: Launch notification parameters

        Returns:
            Response dict with status, launch_id, expected_class, pending_count
        """
        app_name = params["app_name"]

        # Validate app exists in registry
        if app_name not in self.application_registry:
            raise ValueError(f"Application '{app_name}' not found in registry")

        expected_class = self.application_registry[app_name]["expected_class"]

        # Generate launch_id
        launch_id = f"{app_name}-{params['timestamp']}"

        # Store pending launch
        self.pending_launches[launch_id] = {
            **params,
            "expected_class": expected_class,
            "matched": False
        }

        self.stats["total_notifications"] += 1

        return {
            "status": "success",
            "launch_id": launch_id,
            "expected_class": expected_class,
            "pending_count": len(self.pending_launches)
        }

    async def get_launch_stats(self) -> Dict[str, Any]:
        """
        Mock get_launch_stats endpoint.

        Returns:
            LaunchRegistryStats dict with current state and counters
        """
        total_pending = len(self.pending_launches)
        unmatched_pending = sum(
            1 for l in self.pending_launches.values() if not l["matched"]
        )

        match_rate = 0.0
        if self.stats["total_notifications"] > 0:
            match_rate = (self.stats["total_matched"] / self.stats["total_notifications"]) * 100

        expiration_rate = 0.0
        if self.stats["total_notifications"] > 0:
            expiration_rate = (self.stats["total_expired"] / self.stats["total_notifications"]) * 100

        return {
            "total_pending": total_pending,
            "unmatched_pending": unmatched_pending,
            "total_notifications": self.stats["total_notifications"],
            "total_matched": self.stats["total_matched"],
            "total_expired": self.stats["total_expired"],
            "total_failed_correlation": self.stats["total_failed_correlation"],
            "match_rate": match_rate,
            "expiration_rate": expiration_rate
        }

    async def get_pending_launches(self, params: Dict[str, Any]) -> Dict[str, Any]:
        """
        Mock get_pending_launches endpoint.

        Args:
            params: Query parameters with include_matched flag

        Returns:
            Dict with launches list
        """
        include_matched = params.get("include_matched", False)
        current_time = time.time()

        launches = []
        for launch_id, launch in self.pending_launches.items():
            if not include_matched and launch["matched"]:
                continue

            launches.append({
                "launch_id": launch_id,
                "app_name": launch["app_name"],
                "project_name": launch["project_name"],
                "expected_class": launch["expected_class"],
                "workspace_number": launch["workspace_number"],
                "matched": launch["matched"],
                "age": current_time - launch["timestamp"],
                "timestamp": launch["timestamp"]
            })

        return {"launches": launches}

    def mark_matched(self, launch_id: str) -> None:
        """
        Mark a pending launch as matched (for testing correlation).

        Args:
            launch_id: Launch identifier to mark as matched
        """
        if launch_id in self.pending_launches:
            self.pending_launches[launch_id]["matched"] = True
            self.stats["total_matched"] += 1

    def expire_launch(self, launch_id: str) -> None:
        """
        Expire a pending launch (for testing timeout handling).

        Args:
            launch_id: Launch identifier to expire
        """
        if launch_id in self.pending_launches:
            del self.pending_launches[launch_id]
            self.stats["total_expired"] += 1

    def reset(self) -> None:
        """Reset mock server state (for test isolation)."""
        self.pending_launches.clear()
        self.stats = {
            "total_notifications": 0,
            "total_matched": 0,
            "total_expired": 0,
            "total_failed_correlation": 0
        }
