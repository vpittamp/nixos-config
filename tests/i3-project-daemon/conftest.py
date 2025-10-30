"""Pytest configuration for i3 project daemon tests.

Feature 049: Intelligent Automatic Workspace-to-Monitor Assignment
"""
import pytest
import asyncio


@pytest.fixture(scope="session")
def event_loop():
    """Create an event loop for async tests."""
    loop = asyncio.get_event_loop_policy().new_event_loop()
    yield loop
    loop.close()


pytest_plugins = ["tests.i3-project-daemon.fixtures.mock_i3_connection"]
