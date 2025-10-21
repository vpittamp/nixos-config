"""Test the test infrastructure itself.

Validates that all fixtures and mocks work correctly.
"""

import pytest
from pathlib import Path


def test_temp_config_dir_structure(temp_config_dir):
    """Verify temp config directory has correct structure."""
    assert temp_config_dir.exists()
    assert (temp_config_dir / "projects").exists()
    assert (temp_config_dir / "layouts").exists()
    assert (temp_config_dir / "app-classes.json").exists()


def test_mock_daemon_basic_operations(mock_daemon):
    """Verify mock daemon captures requests correctly."""
    # Initially no requests
    assert len(mock_daemon.get_captured_requests()) == 0

    # Mock a request (need to use async in real test, but testing infrastructure only)
    import asyncio
    response = asyncio.run(mock_daemon.send_request("daemon.status", {}))

    # Verify request captured
    assert len(mock_daemon.get_captured_requests()) == 1
    requests = mock_daemon.get_captured_requests()
    assert requests[0]["method"] == "daemon.status"

    # Verify response
    assert response["running"] is True


def test_mock_i3_basic_operations(mock_i3):
    """Verify mock i3 connection works correctly."""
    import asyncio

    # Test workspaces
    workspaces = asyncio.run(mock_i3.get_workspaces())
    assert len(workspaces) == 3
    assert workspaces[0]["num"] == 1

    # Test outputs
    outputs = asyncio.run(mock_i3.get_outputs())
    assert len(outputs) == 2
    assert outputs[0]["name"] == "primary"

    # Test command execution
    result = asyncio.run(mock_i3.command("workspace 2"))
    assert result[0]["success"] is True
    assert len(mock_i3.commands_executed) == 1


def test_sample_project_fixture(sample_project, temp_config_dir):
    """Verify sample project fixture creates valid project."""
    assert sample_project["name"] == "test-project"
    assert len(sample_project["auto_launch"]) == 2

    # Verify file created
    project_file = temp_config_dir / "projects" / "test-project.json"
    assert project_file.exists()


def test_sample_layout_fixture(sample_layout, temp_config_dir):
    """Verify sample layout fixture creates valid layout."""
    assert sample_layout["name"] == "coding-layout"
    assert len(sample_layout["workspaces"]) == 1
    assert len(sample_layout["workspaces"][0]["windows"]) == 2

    # Verify file created
    layout_file = temp_config_dir / "layouts" / "test-project" / "coding-layout.json"
    assert layout_file.exists()


def test_mock_windows_fixture(mock_windows, mock_i3):
    """Verify mock windows fixture adds windows to i3."""
    import asyncio

    tree = asyncio.run(mock_i3.get_tree())

    # Find windows by class
    ghostty_windows = tree.find_classed("Ghostty")
    assert len(ghostty_windows) == 1
    assert ghostty_windows[0].window_class == "Ghostty"

    code_windows = tree.find_classed("Code")
    assert len(code_windows) == 1

    # Find windows by mark
    project_windows = tree.find_marked("project:test-project")
    assert len(project_windows) == 2


@pytest.mark.asyncio
async def test_isolated_test_env(isolated_test_env):
    """Verify isolated test environment has all components."""
    env = isolated_test_env

    assert env["config_dir"].exists()
    assert env["daemon"] is not None
    assert env["i3"] is not None
    assert env["project"]["name"] == "test-project"

    # Test daemon in environment
    response = await env["daemon"].send_request("project.current", {})
    assert response is not None

    # Test i3 in environment
    workspaces = await env["i3"].get_workspaces()
    assert len(workspaces) > 0
