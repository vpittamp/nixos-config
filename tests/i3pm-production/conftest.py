"""
pytest configuration for i3pm production readiness tests

This file is automatically loaded by pytest and provides:
- Fixtures for i3 IPC mocking
- Test utilities for daemon interaction
- Sample data and layout fixtures
"""

import pytest
import sys
import os
from pathlib import Path

# Add daemon source to Python path for testing
DAEMON_SRC = Path("/etc/nixos/home-modules/desktop/i3-project-event-daemon")
sys.path.insert(0, str(DAEMON_SRC))

# Test configuration
TEST_DATA_DIR = Path(__file__).parent / "fixtures"
TEST_DATA_DIR.mkdir(exist_ok=True)


@pytest.fixture
def test_data_dir():
    """Provide path to test data directory"""
    return TEST_DATA_DIR


@pytest.fixture
def sample_project():
    """Sample project configuration for testing"""
    return {
        "name": "test-project",
        "display_name": "Test Project",
        "icon": "🧪",
        "directory": "/tmp/test-project",
        "created_at": "2025-10-23T12:00:00Z",
        "scoped_classes": ["Code", "org.kde.ghostty"],
    }


@pytest.fixture
def sample_window():
    """Sample window data for testing"""
    return {
        "id": 12345,
        "window_class": "Code",
        "instance": "code",
        "title": "test.py - Visual Studio Code",
        "workspace": "1",
        "output": "eDP-1",
        "marks": ["project:test-project"],
        "floating": False,
        "geometry": {"x": 0, "y": 0, "width": 1920, "height": 1080},
        "pid": 5678,
        "visible": True,
    }


# pytest_plugins moved to top-level conftest.py to avoid deprecation warning
