"""Pytest configuration and shared fixtures for i3_project_manager tests."""

import asyncio
import json
import tempfile
from datetime import datetime
from pathlib import Path
from typing import AsyncGenerator, Generator
from unittest.mock import AsyncMock, MagicMock

import pytest


# pytest_plugins moved to top-level conftest.py to avoid deprecation warning


@pytest.fixture
def temp_config_dir() -> Generator[Path, None, None]:
    """Create temporary configuration directory for testing.

    Yields:
        Path to temporary config directory that mimics ~/.config/i3/
    """
    with tempfile.TemporaryDirectory() as tmpdir:
        config_dir = Path(tmpdir)
        projects_dir = config_dir / "projects"
        layouts_dir = config_dir / "layouts"

        projects_dir.mkdir(parents=True)
        layouts_dir.mkdir(parents=True)

        # Create app-classes.json with defaults
        app_classes_file = config_dir / "app-classes.json"
        app_classes_file.write_text(json.dumps({
            "scoped_classes": ["Ghostty", "Code", "neovide"],
            "global_classes": ["firefox", "Google-chrome", "mpv"],
            "class_patterns": {
                "pwa-": "global",
                "terminal": "scoped",
                "editor": "scoped"
            }
        }, indent=2))

        yield config_dir


@pytest.fixture
def sample_project(temp_config_dir: Path) -> dict:
    """Create a sample project configuration for testing.

    Args:
        temp_config_dir: Temporary config directory fixture

    Returns:
        Sample project configuration dict
    """
    project_data = {
        "name": "test-project",
        "directory": "/tmp/test-project",
        "display_name": "Test Project",
        "icon": "🧪",
        "scoped_classes": ["Ghostty", "Code"],
        "workspace_preferences": {
            "1": "primary",
            "2": "secondary"
        },
        "auto_launch": [
            {
                "command": "ghostty",
                "workspace": 1,
                "env": {},
                "wait_for_mark": "project:test-project",
                "wait_timeout": 5.0,
                "launch_delay": 0.5
            }
        ],
        "saved_layouts": [],
        "created_at": datetime.now().isoformat(),
        "modified_at": datetime.now().isoformat()
    }

    # Save to config directory
    project_file = temp_config_dir / "projects" / "test-project.json"
    project_file.write_text(json.dumps(project_data, indent=2))

    return project_data


@pytest.fixture
async def mock_i3_connection() -> AsyncGenerator[AsyncMock, None]:
    """Mock i3ipc.aio.Connection for testing.

    Yields:
        Mocked i3 IPC connection with common methods
    """
    mock = AsyncMock()

    # Mock GET_TREE response
    mock.get_tree.return_value = MagicMock(
        nodes=[
            MagicMock(
                type="workspace",
                name="1",
                num=1,
                nodes=[
                    MagicMock(
                        window=12345,
                        window_class="Ghostty",
                        window_title="test terminal",
                        marks=["project:test-project"],
                        rect=MagicMock(width=1920, height=1080, x=0, y=0)
                    )
                ]
            ),
            MagicMock(
                type="workspace",
                name="2",
                num=2,
                nodes=[
                    MagicMock(
                        window=12346,
                        window_class="Code",
                        window_title="test editor",
                        marks=["project:test-project"],
                        rect=MagicMock(width=2560, height=1440, x=1920, y=0)
                    )
                ]
            )
        ]
    )

    # Mock GET_WORKSPACES response
    mock.get_workspaces.return_value = [
        MagicMock(num=1, name="1", output="eDP-1", visible=True, focused=True),
        MagicMock(num=2, name="2", output="HDMI-1", visible=True, focused=False),
        MagicMock(num=3, name="3", output="HDMI-1", visible=False, focused=False),
    ]

    # Mock GET_OUTPUTS response
    mock.get_outputs.return_value = [
        MagicMock(name="eDP-1", active=True, primary=True, rect=MagicMock(width=1920, height=1080, x=0, y=0)),
        MagicMock(name="HDMI-1", active=True, primary=False, rect=MagicMock(width=2560, height=1440, x=1920, y=0)),
    ]

    # Mock GET_MARKS response
    mock.get_marks.return_value = ["project:test-project", "project:another-project"]

    # Mock COMMAND response
    mock.command.return_value = [MagicMock(success=True)]

    yield mock


@pytest.fixture
async def mock_daemon_client() -> AsyncGenerator[AsyncMock, None]:
    """Mock DaemonClient for testing.

    Yields:
        Mocked daemon client with common methods
    """
    mock = AsyncMock()

    # Mock get_status response
    mock.get_status.return_value = {
        "daemon_connected": True,
        "uptime_seconds": 1234.5,
        "pid": 9999,
        "active_project": "test-project",
        "total_windows": 12,
        "tracked_windows": 5,
        "event_count": 567,
        "event_rate_per_second": 2.3
    }

    # Mock get_events response
    mock.get_events.return_value = {
        "events": [
            {
                "timestamp": "2025-10-20T14:30:00Z",
                "event_type": "window",
                "change": "new",
                "details": {
                    "window_id": 12345,
                    "window_class": "Ghostty",
                    "marked": True,
                    "mark": "project:test-project"
                }
            }
        ],
        "total": 1
    }

    # Mock get_windows response
    mock.get_windows.return_value = {
        "windows": [
            {
                "window_id": 12345,
                "window_class": "Ghostty",
                "window_title": "test terminal",
                "workspace": "1",
                "marks": ["project:test-project"]
            }
        ],
        "total": 1
    }

    # Mock connect/close
    mock.connect.return_value = None
    mock.close.return_value = None

    yield mock


@pytest.fixture
def event_loop():
    """Create an event loop for async tests."""
    loop = asyncio.get_event_loop_policy().new_event_loop()
    yield loop
    loop.close()
