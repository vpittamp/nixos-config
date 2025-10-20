"""Daemon state assertions for test scenarios.

This module provides assertion functions for validating the i3-project-daemon state via JSON-RPC.
"""

import logging
from typing import Any, Dict, Optional

from i3_project_monitor.daemon_client import DaemonClient


logger = logging.getLogger(__name__)


class StateAssertions:
    """Assertions for daemon state validation."""

    def __init__(self, daemon_client: DaemonClient):
        """Initialize state assertions.

        Args:
            daemon_client: Client for communicating with daemon
        """
        self.daemon_client = daemon_client

    async def assert_active_project(self, expected: Optional[str]) -> None:
        """Assert that the active project matches expected value.

        Args:
            expected: Expected project name (None for no active project)

        Raises:
            AssertionError: If active project doesn't match
        """
        status = await self.daemon_client.get_status()
        actual = status.get("active_project")

        if actual != expected:
            raise AssertionError(
                f"Expected active project '{expected}', got '{actual}'"
            )

        logger.info(f"✓ Active project is '{expected}'")

    async def assert_window_count(self, expected: int) -> None:
        """Assert that the tracked window count matches expected value.

        Args:
            expected: Expected number of tracked windows

        Raises:
            AssertionError: If window count doesn't match
        """
        status = await self.daemon_client.get_status()
        actual = status.get("window_count", 0)

        if actual != expected:
            raise AssertionError(
                f"Expected {expected} tracked windows, got {actual}"
            )

        logger.info(f"✓ Window count is {expected}")

    async def assert_project_exists(self, project_name: str) -> None:
        """Assert that a project exists in daemon state.

        Args:
            project_name: Name of project to check

        Raises:
            AssertionError: If project doesn't exist
        """
        projects = await self.daemon_client.list_projects()

        if project_name not in projects:
            raise AssertionError(
                f"Expected project '{project_name}' to exist, but it was not found. "
                f"Available projects: {projects}"
            )

        logger.info(f"✓ Project '{project_name}' exists")

    async def assert_window_marked(
        self,
        window_id: int,
        expected_mark: str,
    ) -> None:
        """Assert that a window has the expected mark.

        Args:
            window_id: Window ID to check
            expected_mark: Expected mark string

        Raises:
            AssertionError: If window doesn't have expected mark
        """
        windows = await self.daemon_client.get_windows()

        # Find window by ID
        window = next((w for w in windows if w.get("id") == window_id), None)

        if window is None:
            raise AssertionError(
                f"Window {window_id} not found in daemon state"
            )

        actual_marks = window.get("marks", [])

        if expected_mark not in actual_marks:
            raise AssertionError(
                f"Expected window {window_id} to have mark '{expected_mark}', "
                f"but marks were: {actual_marks}"
            )

        logger.info(f"✓ Window {window_id} has mark '{expected_mark}'")

    async def assert_daemon_connected(self) -> None:
        """Assert that the daemon is connected to i3 IPC.

        Raises:
            AssertionError: If daemon is not connected
        """
        status = await self.daemon_client.get_status()
        connected = status.get("connected", False)

        if not connected:
            raise AssertionError("Daemon is not connected to i3 IPC")

        logger.info("✓ Daemon is connected to i3 IPC")

    async def assert_daemon_running(self) -> None:
        """Assert that the daemon is running.

        Raises:
            AssertionError: If daemon is not running
        """
        try:
            await self.daemon_client.get_status()
            logger.info("✓ Daemon is running")
        except Exception as e:
            raise AssertionError(f"Daemon is not running: {e}")

    async def assert_event_count_min(self, min_count: int) -> None:
        """Assert that event buffer has at least min_count events.

        Args:
            min_count: Minimum expected event count

        Raises:
            AssertionError: If event count is below minimum
        """
        status = await self.daemon_client.get_status()
        actual = status.get("event_count", 0)

        if actual < min_count:
            raise AssertionError(
                f"Expected at least {min_count} events, got {actual}"
            )

        logger.info(f"✓ Event count {actual} >= {min_count}")

    async def get_state(self) -> Dict[str, Any]:
        """Get complete daemon state.

        Returns:
            Dictionary with daemon status, projects, windows

        Raises:
            RuntimeError: If unable to get state
        """
        try:
            status = await self.daemon_client.get_status()
            projects = await self.daemon_client.list_projects()
            windows = await self.daemon_client.get_windows()

            return {
                "status": status,
                "projects": projects,
                "windows": windows,
            }

        except Exception as e:
            raise RuntimeError(f"Failed to get daemon state: {e}")
