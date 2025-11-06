"""
pytest configuration for scratchpad terminal tests.

Feature 062 - Project-Scoped Scratchpad Terminal
"""

import pytest
import asyncio
from pathlib import Path


@pytest.fixture(scope="session")
def event_loop():
    """
    Create event loop for async tests.

    Provides a session-scoped event loop for pytest-asyncio.
    """
    loop = asyncio.get_event_loop_policy().new_event_loop()
    yield loop
    loop.close()


@pytest.fixture
def mock_project_name():
    """Provide a mock project name for testing."""
    return "test-project"


@pytest.fixture
def mock_working_dir(tmp_path):
    """Provide a temporary working directory for testing."""
    test_dir = tmp_path / "test-project"
    test_dir.mkdir()
    return test_dir


@pytest.fixture
def mock_global_working_dir(tmp_path):
    """Provide a temporary home directory for global terminal testing."""
    home_dir = tmp_path / "home"
    home_dir.mkdir()
    return home_dir
