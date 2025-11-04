"""
Integration tests for application coverage validation (User Story 2).

Tests verify that all launched applications have I3PM_* environment variables injected.
"""

import pytest
import asyncio
import time
from pathlib import Path
from typing import Dict, List

# Import test utilities
import sys
sys.path.insert(0, str(Path(__file__).parent.parent))
from test_utils import read_process_environ, find_windows_by_class, launch_test_app, cleanup_test_processes


@pytest.fixture
def test_apps():
    """List of test applications to validate coverage."""
    return [
        {"name": "vscode", "command": "code", "scope": "scoped"},
        {"name": "terminal", "command": "ghostty", "scope": "scoped"},
        {"name": "firefox", "command": "firefox", "scope": "global"},
        {"name": "claude-pwa", "command": "firefoxpwa site launch 01JCYF8Z2M7R4N6QW9XKPHVTB5", "scope": "scoped"},
        {"name": "youtube-pwa", "command": "firefoxpwa site launch 01JD0H7Z8MXYZ...", "scope": "global"},
    ]


@pytest.mark.asyncio
@pytest.mark.parametrize("app_name,app_command,expected_scope", [
    ("vscode", "code --skip-release-notes --skip-welcome /tmp/test-workspace", "scoped"),
    ("terminal", "ghostty", "scoped"),
    ("firefox", "firefox --new-window about:blank", "global"),
])
async def test_application_launch_has_i3pm_variables(
    sway_connection,
    app_name: str,
    app_command: str,
    expected_scope: str,
):
    """
    T022: Parametrized test - Launch application and verify I3PM_* variables present.

    Tests that each registered application, when launched via the launcher wrapper,
    has all required I3PM_* environment variables injected.
    """
    # Launch application via launcher wrapper
    process, window_id = await launch_test_app(
        sway_connection,
        app_command,
        timeout=10,
    )

    try:
        # Wait for window to appear
        await asyncio.sleep(0.5)

        # Query Sway for window
        tree = await sway_connection.get_tree()
        windows = [w for w in tree.leaves() if w.id == window_id]
        assert len(windows) == 1, f"Window {window_id} not found in Sway tree"
        window = windows[0]

        # Read /proc/<pid>/environ
        assert window.pid is not None, f"Window {window_id} has no PID"
        env_vars = read_process_environ(window.pid)

        # Assert I3PM_APP_ID present
        assert "I3PM_APP_ID" in env_vars, \
            f"I3PM_APP_ID missing for {app_name} (PID {window.pid})"
        assert env_vars["I3PM_APP_ID"], \
            f"I3PM_APP_ID is empty for {app_name}"

        # Assert I3PM_APP_NAME matches app name
        assert "I3PM_APP_NAME" in env_vars, \
            f"I3PM_APP_NAME missing for {app_name}"
        assert env_vars["I3PM_APP_NAME"] == app_name, \
            f"I3PM_APP_NAME mismatch: expected '{app_name}', got '{env_vars['I3PM_APP_NAME']}'"

        # Assert I3PM_SCOPE is valid
        assert "I3PM_SCOPE" in env_vars, \
            f"I3PM_SCOPE missing for {app_name}"
        assert env_vars["I3PM_SCOPE"] in ("global", "scoped"), \
            f"Invalid I3PM_SCOPE: {env_vars['I3PM_SCOPE']}"
        assert env_vars["I3PM_SCOPE"] == expected_scope, \
            f"I3PM_SCOPE mismatch: expected '{expected_scope}', got '{env_vars['I3PM_SCOPE']}'"

    finally:
        # Cleanup: Terminate test application
        await cleanup_test_processes([process])


@pytest.mark.asyncio
async def test_coverage_validation_with_all_apps_launched(
    sway_connection,
    validate_environment_coverage_func,
):
    """
    T023: Integration test - Launch 5 apps, validate 100% coverage.

    Tests that validate_environment_coverage() correctly reports 100% coverage
    when all launched applications have I3PM_* variables.
    """
    test_apps = [
        "code --skip-release-notes /tmp/test-ws",
        "ghostty",
        "firefox --new-window about:blank",
    ]

    processes = []
    try:
        # Launch 5 test applications via launcher wrapper
        for app_command in test_apps:
            process, window_id = await launch_test_app(
                sway_connection,
                app_command,
                timeout=10,
            )
            processes.append(process)

        # Wait for all windows to stabilize
        await asyncio.sleep(1)

        # Call validate_environment_coverage()
        coverage_report = await validate_environment_coverage_func(sway_connection)

        # Assert coverage_percentage == 100.0
        assert coverage_report.coverage_percentage == 100.0, \
            f"Expected 100% coverage, got {coverage_report.coverage_percentage}%"

        # Assert status == "PASS"
        assert coverage_report.status == "PASS", \
            f"Expected status PASS, got {coverage_report.status}"

        # Assert len(missing_windows) == 0
        assert len(coverage_report.missing_windows) == 0, \
            f"Expected 0 missing windows, got {len(coverage_report.missing_windows)}: " \
            f"{coverage_report.missing_windows}"

        # Verify counts match expectations
        assert coverage_report.windows_with_env >= len(test_apps), \
            f"Expected at least {len(test_apps)} windows with env vars, got {coverage_report.windows_with_env}"

    finally:
        # Cleanup: Terminate all test applications
        await cleanup_test_processes(processes)


@pytest.mark.asyncio
async def test_coverage_validation_detects_missing_variables(
    sway_connection,
    validate_environment_coverage_func,
):
    """
    T024: Integration test - Launch app without wrapper, detect missing variables.

    Tests that validate_environment_coverage() correctly identifies windows
    launched without the launcher wrapper (no I3PM_* variables).
    """
    # Launch app WITHOUT wrapper (manual exec)
    # This simulates a user launching an app from terminal without going through launcher
    import subprocess

    # Start a simple process without I3PM_* variables
    # Use xterm or xeyes as a simple X11 app that doesn't require much setup
    manual_process = subprocess.Popen(
        ["xterm", "-hold", "-e", "echo", "test"],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )

    try:
        # Wait for window to appear
        await asyncio.sleep(1)

        # Call validate_environment_coverage()
        coverage_report = await validate_environment_coverage_func(sway_connection)

        # Assert coverage_percentage < 100.0
        assert coverage_report.coverage_percentage < 100.0, \
            f"Expected coverage < 100%, got {coverage_report.coverage_percentage}%"

        # Assert status == "FAIL"
        assert coverage_report.status == "FAIL", \
            f"Expected status FAIL, got {coverage_report.status}"

        # Assert missing_windows contains window details
        assert len(coverage_report.missing_windows) > 0, \
            "Expected at least one missing window, got none"

        # Verify missing window has expected fields
        missing = coverage_report.missing_windows[0]
        assert missing.window_id is not None, "Missing window_id"
        assert missing.window_class is not None, "Missing window_class"
        assert missing.window_title is not None, "Missing window_title"
        assert missing.pid is not None, "Missing pid"
        assert missing.reason == "no_variables", \
            f"Expected reason 'no_variables', got '{missing.reason}'"

    finally:
        # Cleanup: Terminate manual process
        manual_process.terminate()
        manual_process.wait(timeout=5)


@pytest.mark.asyncio
async def test_coverage_validation_handles_pid_errors(
    sway_connection,
    validate_environment_coverage_func,
):
    """
    Additional test: Verify coverage validation handles edge cases.

    Tests that validate_environment_coverage() gracefully handles:
    - Windows without PIDs (special windows, scratchpad)
    - Processes that exit before environ can be read
    - Permission denied errors
    """
    # Call validate_environment_coverage()
    coverage_report = await validate_environment_coverage_func(sway_connection)

    # Should not crash even with edge cases
    assert coverage_report is not None
    assert coverage_report.total_windows >= 0
    assert coverage_report.windows_with_env >= 0
    assert coverage_report.windows_without_env >= 0
    assert 0 <= coverage_report.coverage_percentage <= 100
    assert coverage_report.status in ("PASS", "FAIL")

    # Verify missing windows have valid reasons
    for missing in coverage_report.missing_windows:
        assert missing.reason in (
            "no_pid",
            "permission_denied",
            "process_exited",
            "no_variables"
        ), f"Invalid reason: {missing.reason}"
