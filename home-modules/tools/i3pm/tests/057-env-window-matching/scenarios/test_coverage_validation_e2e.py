"""
End-to-end scenario test for environment variable coverage validation (User Story 2).

Tests complete workflow: Launch all registered apps → Query all windows → Validate 100% coverage.
"""

import pytest
import asyncio
import time
from pathlib import Path
from typing import List, Dict

# Import test utilities
import sys
sys.path.insert(0, str(Path(__file__).parent.parent))
from test_utils import read_process_environ, launch_test_app, cleanup_test_processes


@pytest.mark.asyncio
async def test_full_coverage_validation_end_to_end(
    sway_connection,
    validate_environment_coverage_func,
    app_registry,
):
    """
    T025: End-to-end test - Full coverage validation across all registered apps.

    Workflow:
    1. Get all registered apps from app-registry-data.nix
    2. Launch each app via launcher wrapper
    3. Query all windows and validate I3PM_* variables present
    4. Generate coverage report
    5. Assert status="PASS" with 100% coverage
    """
    # Get subset of registered apps for testing (to avoid overwhelming the system)
    test_app_commands = [
        "code --skip-release-notes /tmp/test-workspace",
        "ghostty",
        "firefox --new-window about:blank",
    ]

    processes = []
    launched_windows = []

    try:
        # Step 1-2: Launch each app via launcher wrapper
        for app_command in test_app_commands:
            process, window_id = await launch_test_app(
                sway_connection,
                app_command,
                timeout=10,
            )
            processes.append(process)
            launched_windows.append(window_id)

        # Wait for all windows to stabilize
        await asyncio.sleep(2)

        # Step 3: Query all windows
        tree = await sway_connection.get_tree()
        all_windows = tree.leaves()

        # Validate each launched window has I3PM_* variables
        for window in all_windows:
            if window.id in launched_windows:
                assert window.pid is not None, \
                    f"Launched window {window.id} has no PID"

                env_vars = read_process_environ(window.pid)

                # Validate 100% have I3PM_* variables
                assert "I3PM_APP_ID" in env_vars, \
                    f"Window {window.id} missing I3PM_APP_ID"
                assert env_vars["I3PM_APP_ID"], \
                    f"Window {window.id} has empty I3PM_APP_ID"
                assert "I3PM_APP_NAME" in env_vars, \
                    f"Window {window.id} missing I3PM_APP_NAME"
                assert "I3PM_SCOPE" in env_vars, \
                    f"Window {window.id} missing I3PM_SCOPE"

        # Step 4: Generate coverage report
        coverage_report = await validate_environment_coverage_func(sway_connection)

        # Step 5: Assert status="PASS"
        assert coverage_report.status == "PASS", \
            f"Expected PASS status, got {coverage_report.status}. " \
            f"Coverage: {coverage_report.coverage_percentage}%, " \
            f"Missing: {len(coverage_report.missing_windows)} windows"

        # Verify 100% coverage for launched apps
        # Note: There might be other unmanaged windows (system windows, etc.)
        # so we verify that AT LEAST our launched apps have 100% coverage
        for window_id in launched_windows:
            # Verify this window is not in missing_windows list
            missing_ids = [w.window_id for w in coverage_report.missing_windows]
            assert window_id not in missing_ids, \
                f"Launched window {window_id} reported as missing I3PM_* variables"

        # Verify coverage report structure
        assert coverage_report.total_windows > 0, \
            "Expected at least one window in coverage report"
        assert coverage_report.windows_with_env >= len(launched_windows), \
            f"Expected at least {len(launched_windows)} windows with env vars"
        assert coverage_report.coverage_percentage == 100.0, \
            f"Expected 100% coverage, got {coverage_report.coverage_percentage}%"

    finally:
        # Cleanup: Terminate all test applications
        await cleanup_test_processes(processes)


@pytest.mark.asyncio
async def test_coverage_report_structure_and_metadata(
    sway_connection,
    validate_environment_coverage_func,
):
    """
    Additional E2E test: Verify coverage report structure and metadata.

    Tests that CoverageReport contains all expected fields with correct types.
    """
    # Generate coverage report
    coverage_report = await validate_environment_coverage_func(sway_connection)

    # Verify report structure
    assert hasattr(coverage_report, "total_windows"), "Missing total_windows field"
    assert hasattr(coverage_report, "windows_with_env"), "Missing windows_with_env field"
    assert hasattr(coverage_report, "windows_without_env"), "Missing windows_without_env field"
    assert hasattr(coverage_report, "coverage_percentage"), "Missing coverage_percentage field"
    assert hasattr(coverage_report, "missing_windows"), "Missing missing_windows field"
    assert hasattr(coverage_report, "status"), "Missing status field"
    assert hasattr(coverage_report, "timestamp"), "Missing timestamp field"

    # Verify field types
    assert isinstance(coverage_report.total_windows, int)
    assert isinstance(coverage_report.windows_with_env, int)
    assert isinstance(coverage_report.windows_without_env, int)
    assert isinstance(coverage_report.coverage_percentage, float)
    assert isinstance(coverage_report.missing_windows, list)
    assert coverage_report.status in ("PASS", "FAIL")

    # Verify math consistency
    assert coverage_report.total_windows == \
        coverage_report.windows_with_env + coverage_report.windows_without_env, \
        "Window counts don't add up"

    # Verify missing_windows list structure
    for missing in coverage_report.missing_windows:
        assert hasattr(missing, "window_id")
        assert hasattr(missing, "window_class")
        assert hasattr(missing, "window_title")
        assert hasattr(missing, "pid")
        assert hasattr(missing, "reason")
        assert missing.reason in (
            "no_pid",
            "permission_denied",
            "process_exited",
            "no_variables"
        )


@pytest.mark.asyncio
async def test_coverage_validation_with_mixed_managed_unmanaged_windows(
    sway_connection,
    validate_environment_coverage_func,
):
    """
    Additional E2E test: Coverage validation with mix of managed and unmanaged windows.

    Tests that coverage report correctly distinguishes between:
    - Managed windows (launched via launcher with I3PM_* vars)
    - Unmanaged windows (launched manually without I3PM_* vars)
    """
    import subprocess

    managed_processes = []
    unmanaged_process = None

    try:
        # Launch managed apps via launcher
        managed_commands = [
            "code --skip-release-notes /tmp/test",
            "ghostty",
        ]

        for cmd in managed_commands:
            process, window_id = await launch_test_app(
                sway_connection,
                cmd,
                timeout=10,
            )
            managed_processes.append(process)

        # Launch unmanaged app (without wrapper)
        unmanaged_process = subprocess.Popen(
            ["xterm", "-hold", "-e", "echo", "unmanaged"],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )

        # Wait for windows to stabilize
        await asyncio.sleep(2)

        # Generate coverage report
        coverage_report = await validate_environment_coverage_func(sway_connection)

        # Verify report reflects mixed state
        assert coverage_report.total_windows >= len(managed_commands) + 1, \
            "Expected at least managed + unmanaged windows"

        # Should have at least 2 managed windows
        assert coverage_report.windows_with_env >= len(managed_commands), \
            f"Expected at least {len(managed_commands)} windows with env vars"

        # Should have at least 1 unmanaged window
        assert coverage_report.windows_without_env >= 1, \
            "Expected at least 1 unmanaged window"

        # Coverage should be < 100% due to unmanaged window
        assert coverage_report.coverage_percentage < 100.0, \
            "Expected coverage < 100% with unmanaged window"

        # Status should be FAIL
        assert coverage_report.status == "FAIL", \
            "Expected FAIL status with unmanaged window"

        # Verify at least one missing window is the unmanaged one
        assert len(coverage_report.missing_windows) >= 1, \
            "Expected at least one missing window"

    finally:
        # Cleanup
        await cleanup_test_processes(managed_processes)
        if unmanaged_process:
            unmanaged_process.terminate()
            unmanaged_process.wait(timeout=5)
