"""Pytest configuration and fixtures for i3pm TUI tests.

Provides test fixtures for:
- Isolated test environments (temp directories)
- Mock daemon and i3 connections
- Test projects and layouts
- Textual app instances
"""

import pytest
import tempfile
import shutil
from pathlib import Path
from typing import Dict, Any
import json

from tests.i3pm.mocks.daemon_client import MockDaemonClient
from tests.i3pm.mocks.i3_connection import MockI3Connection, MockWindow, MockWorkspace


@pytest.fixture
def temp_config_dir(tmp_path):
    """Create temporary i3pm config directory.

    Provides isolated config directory for each test with standard structure.

    Yields:
        Path: Temporary config directory path
    """
    config_dir = tmp_path / "config" / "i3"
    config_dir.mkdir(parents=True)

    # Create standard subdirectories
    (config_dir / "projects").mkdir()
    (config_dir / "layouts").mkdir()

    # Create app-classes.json
    app_classes = {
        "scoped_classes": ["Ghostty", "Code", "neovide"],
        "global_classes": ["firefox", "pwa-youtube", "k9s"]
    }
    with open(config_dir / "app-classes.json", "w") as f:
        json.dump(app_classes, f)

    yield config_dir

    # Cleanup
    shutil.rmtree(tmp_path, ignore_errors=True)


@pytest.fixture
def mock_daemon():
    """Create mock daemon client.

    Returns:
        MockDaemonClient: Mock daemon for testing
    """
    return MockDaemonClient()


@pytest.fixture
def mock_i3():
    """Create mock i3 connection.

    Returns:
        MockI3Connection: Mock i3 IPC connection
    """
    return MockI3Connection()


@pytest.fixture
def sample_project(temp_config_dir):
    """Create sample project configuration.

    Args:
        temp_config_dir: Temporary config directory

    Returns:
        Dict: Project configuration dict
    """
    project_data = {
        "name": "test-project",
        "display_name": "Test Project",
        "directory": "/tmp/test-project",
        "icon": "",
        "auto_launch": [
            {
                "command": "ghostty",
                "workspace": 1,
                "environment": {"PROJECT_DIR": "/tmp/test-project"},
                "wait_timeout": 5.0
            },
            {
                "command": "code $PROJECT_DIR",
                "workspace": 1,
                "environment": {},
                "wait_timeout": 8.0
            }
        ],
        "workspace_preferences": {
            "1": "primary",
            "2": "primary",
            "3": "secondary"
        }
    }

    project_file = temp_config_dir / "projects" / "test-project.json"
    with open(project_file, "w") as f:
        json.dump(project_data, f, indent=2)

    return project_data


@pytest.fixture
def sample_layout(temp_config_dir):
    """Create sample layout configuration.

    Args:
        temp_config_dir: Temporary config directory

    Returns:
        Dict: Layout configuration dict
    """
    layout_data = {
        "name": "coding-layout",
        "project_name": "test-project",
        "workspaces": [
            {
                "number": 1,
                "output": "primary",
                "windows": [
                    {
                        "window_class": "Ghostty",
                        "window_title": "Terminal",
                        "geometry": {"width": 960, "height": 1080, "x": 0, "y": 0},
                        "layout_role": "terminal",
                        "split_before": None,
                        "launch_command": "ghostty",
                        "launch_env": {"PROJECT_DIR": "/tmp/test-project"},
                        "expected_marks": ["project:test-project"],
                        "cwd": "/tmp/test-project",
                        "launch_timeout": 5.0,
                        "max_retries": 3,
                        "retry_delay": 1.0
                    },
                    {
                        "window_class": "Code",
                        "window_title": "VS Code",
                        "geometry": {"width": 960, "height": 1080, "x": 960, "y": 0},
                        "layout_role": "editor",
                        "split_before": "vertical",
                        "launch_command": "code $PROJECT_DIR",
                        "launch_env": {"PROJECT_DIR": "/tmp/test-project"},
                        "expected_marks": ["project:test-project"],
                        "cwd": "/tmp/test-project",
                        "launch_timeout": 8.0,
                        "max_retries": 3,
                        "retry_delay": 1.0
                    }
                ]
            }
        ],
        "created_at": "2025-10-21T12:00:00",
        "last_used_at": "2025-10-21T12:00:00"
    }

    # Create project layouts directory
    layouts_dir = temp_config_dir / "layouts" / "test-project"
    layouts_dir.mkdir(parents=True, exist_ok=True)

    layout_file = layouts_dir / "coding-layout.json"
    with open(layout_file, "w") as f:
        json.dump(layout_data, f, indent=2)

    return layout_data


@pytest.fixture
def mock_windows(mock_i3):
    """Add sample windows to mock i3 connection.

    Args:
        mock_i3: Mock i3 connection

    Returns:
        List[MockWindow]: List of created windows
    """
    windows = [
        MockWindow(
            name="Terminal - Ghostty",
            window_class="Ghostty",
            window_id=1001,
            workspace="1",
            marks=["project:test-project"]
        ),
        MockWindow(
            name="VS Code",
            window_class="Code",
            window_id=1002,
            workspace="1",
            marks=["project:test-project"]
        ),
        MockWindow(
            name="Firefox",
            window_class="firefox",
            window_id=1003,
            workspace="2",
            marks=[]
        )
    ]

    # Add windows to workspaces
    for window in windows[:2]:
        mock_i3.add_window(1, window)
    mock_i3.add_window(2, windows[2])

    return windows


@pytest.fixture
def isolated_test_env(temp_config_dir, mock_daemon, mock_i3, sample_project):
    """Create fully isolated test environment.

    Combines all fixtures into complete test environment.

    Args:
        temp_config_dir: Temp config directory
        mock_daemon: Mock daemon client
        mock_i3: Mock i3 connection
        sample_project: Sample project config

    Yields:
        Dict: Test environment with all components
    """
    yield {
        "config_dir": temp_config_dir,
        "daemon": mock_daemon,
        "i3": mock_i3,
        "project": sample_project
    }

    # Cleanup
    mock_daemon.clear_captured_requests()
    mock_i3.clear_commands()


# Pytest configuration
def pytest_configure(config):
    """Configure pytest with custom markers."""
    config.addinivalue_line(
        "markers", "slow: marks tests as slow (deselect with '-m \"not slow\"')"
    )
    config.addinivalue_line(
        "markers", "integration: marks tests as integration tests"
    )
    config.addinivalue_line(
        "markers", "tui: marks tests as TUI tests requiring Pilot"
    )
