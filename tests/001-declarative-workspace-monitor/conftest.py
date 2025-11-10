"""Pytest configuration and fixtures for Feature 001 tests.

This module provides fixtures for testing monitor role assignment and
floating window configuration features.
"""

import pytest
import pytest_asyncio
from unittest.mock import AsyncMock, MagicMock
from typing import List, Dict, Any


@pytest_asyncio.fixture
async def mock_i3ipc_connection():
    """Mock async i3ipc connection for testing.

    Returns:
        AsyncMock: Mocked i3ipc.aio.Connection instance
    """
    connection = AsyncMock()
    connection.get_outputs = AsyncMock(return_value=[])
    connection.get_workspaces = AsyncMock(return_value=[])
    connection.get_tree = AsyncMock(return_value=MagicMock())
    connection.command = AsyncMock(return_value=[MagicMock(success=True)])

    yield connection


@pytest.fixture
def mock_outputs() -> List[Dict[str, Any]]:
    """Mock Sway output list for testing.

    Returns:
        List[Dict]: Three active monitors (HEADLESS-1, HEADLESS-2, HEADLESS-3)
    """
    return [
        {
            "name": "HEADLESS-1",
            "active": True,
            "width": 1920,
            "height": 1080,
            "scale": 1.0,
        },
        {
            "name": "HEADLESS-2",
            "active": True,
            "width": 1920,
            "height": 1080,
            "scale": 1.0,
        },
        {
            "name": "HEADLESS-3",
            "active": True,
            "width": 1920,
            "height": 1080,
            "scale": 1.0,
        },
    ]


@pytest.fixture
def mock_two_outputs() -> List[Dict[str, Any]]:
    """Mock Sway output list with 2 monitors (tertiary disconnected).

    Returns:
        List[Dict]: Two active monitors
    """
    return [
        {
            "name": "HEADLESS-1",
            "active": True,
            "width": 1920,
            "height": 1080,
            "scale": 1.0,
        },
        {
            "name": "HEADLESS-2",
            "active": True,
            "width": 1920,
            "height": 1080,
            "scale": 1.0,
        },
    ]


@pytest.fixture
def mock_single_output() -> List[Dict[str, Any]]:
    """Mock Sway output list with 1 monitor (fallback to primary only).

    Returns:
        List[Dict]: Single active monitor
    """
    return [
        {
            "name": "HEADLESS-1",
            "active": True,
            "width": 1920,
            "height": 1080,
            "scale": 1.0,
        },
    ]


@pytest.fixture
def sample_monitor_role_configs() -> List[Dict[str, Any]]:
    """Sample monitor role configurations for testing.

    Returns:
        List[Dict]: Application monitor role preferences
    """
    return [
        {
            "app_name": "terminal",
            "preferred_workspace": 1,
            "preferred_monitor_role": "primary",
            "source": "app-registry",
        },
        {
            "app_name": "code",
            "preferred_workspace": 2,
            "preferred_monitor_role": "primary",
            "source": "app-registry",
        },
        {
            "app_name": "firefox",
            "preferred_workspace": 3,
            "preferred_monitor_role": "secondary",
            "source": "app-registry",
        },
        {
            "app_name": "youtube-pwa",
            "preferred_workspace": 50,
            "preferred_monitor_role": "tertiary",
            "source": "pwa-sites",
        },
    ]


@pytest.fixture
def sample_floating_window_configs() -> List[Dict[str, Any]]:
    """Sample floating window configurations for testing.

    Returns:
        List[Dict]: Floating window preferences
    """
    return [
        {
            "app_name": "btop",
            "floating": True,
            "floating_size": "medium",
            "scope": "global",
        },
        {
            "app_name": "floating-terminal",
            "floating": True,
            "floating_size": "scratchpad",
            "scope": "scoped",
        },
        {
            "app_name": "regular-app",
            "floating": False,
            "floating_size": None,
            "scope": "scoped",
        },
    ]


@pytest.fixture
def temp_state_file(tmp_path):
    """Temporary state file for testing persistence.

    Args:
        tmp_path: pytest tmp_path fixture

    Returns:
        Path: Path to temporary monitor-state.json
    """
    state_file = tmp_path / "monitor-state.json"
    return state_file
