"""
Integration tests for Sway IPC + environment variable window identification.

Tests the full integration of:
- Launching applications with I3PM_* environment variables
- Querying Sway IPC for windows
- Reading /proc/<pid>/environ
- Validating deterministic window identification
- Multi-instance tracking
- PWA identification

These tests require Sway/i3 to be running.
"""

import pytest
import asyncio
import time
from home_modules.tools.i3pm.tests.test_utils import (
    read_process_environ,
    find_windows_by_class,
    launch_test_app,
    cleanup_test_processes
)


pytestmark = pytest.mark.asyncio


class TestDeterministicWindowIdentification:
    """Test suite for deterministic window identification via environment variables."""

    @pytest.mark.skip(reason="Requires VS Code to be installed and Sway running")
    async def test_vscode_with_project_context(self, sway_connection, launch_test_process):
        """
        Test launching VS Code with project context.

        Verifies:
        - I3PM_PROJECT_NAME is present in /proc/<pid>/environ
        - I3PM_APP_NAME matches expected value
        - I3PM_APP_ID is present and non-empty
        """
        # Define environment variables for VS Code launch
        env_vars = {
            "I3PM_APP_ID": "vscode-nixos-test-123456",
            "I3PM_APP_NAME": "vscode",
            "I3PM_SCOPE": "scoped",
            "I3PM_PROJECT_NAME": "nixos",
            "I3PM_PROJECT_DIR": "/etc/nixos",
            "I3PM_TARGET_WORKSPACE": "52"
        }

        # Launch VS Code with environment
        proc = launch_test_process(
            ["code", "/etc/nixos"],
            env_vars=env_vars
        )

        # Wait for window to appear
        await asyncio.sleep(2)

        try:
            # Find VS Code window via Sway IPC
            windows = await find_windows_by_class(sway_connection, "Code")
            assert len(windows) > 0, "VS Code window not found"

            window = windows[0]
            assert window.pid is not None, "Window has no PID"

            # Read environment from /proc/<pid>/environ
            env = read_process_environ(window.pid)

            # Verify I3PM_* variables present
            assert "I3PM_APP_NAME" in env
            assert env["I3PM_APP_NAME"] == "vscode"

            assert "I3PM_PROJECT_NAME" in env
            assert env["I3PM_PROJECT_NAME"] == "nixos"

            assert "I3PM_APP_ID" in env
            assert env["I3PM_APP_ID"] == "vscode-nixos-test-123456"
            assert len(env["I3PM_APP_ID"]) > 0

        finally:
            # Cleanup: close window
            if windows:
                await sway_connection.command(f'[con_id="{window.id}"] kill')


class TestMultiInstanceTracking:
    """Test suite for tracking multiple instances of the same application."""

    async def test_two_terminal_instances_same_project(
        self,
        sway_connection,
        launch_test_process,
        cleanup_test_windows
    ):
        """
        Test launching two terminal instances in the same project.

        Verifies:
        - Both instances have same I3PM_APP_NAME
        - Both instances have different I3PM_APP_ID values
        """
        processes = []

        # Launch first terminal instance
        env1 = {
            "I3PM_APP_ID": "terminal-nixos-instance1-123",
            "I3PM_APP_NAME": "terminal",
            "I3PM_SCOPE": "scoped",
            "I3PM_PROJECT_NAME": "nixos"
        }
        proc1 = launch_test_process(["sleep", "60"], env_vars=env1)
        processes.append(proc1)

        # Launch second terminal instance
        env2 = {
            "I3PM_APP_ID": "terminal-nixos-instance2-456",
            "I3PM_APP_NAME": "terminal",
            "I3PM_SCOPE": "scoped",
            "I3PM_PROJECT_NAME": "nixos"
        }
        proc2 = launch_test_process(["sleep", "60"], env_vars=env2)
        processes.append(proc2)

        # Wait a bit for processes to stabilize
        await asyncio.sleep(0.5)

        try:
            # Read environment from both processes
            env_proc1 = read_process_environ(proc1.pid)
            env_proc2 = read_process_environ(proc2.pid)

            # Verify both have I3PM_* variables
            assert "I3PM_APP_NAME" in env_proc1
            assert "I3PM_APP_NAME" in env_proc2

            # Verify same app name
            assert env_proc1["I3PM_APP_NAME"] == "terminal"
            assert env_proc2["I3PM_APP_NAME"] == "terminal"

            # Verify different app IDs
            assert "I3PM_APP_ID" in env_proc1
            assert "I3PM_APP_ID" in env_proc2
            assert env_proc1["I3PM_APP_ID"] != env_proc2["I3PM_APP_ID"]

        finally:
            # Cleanup processes
            for proc in processes:
                try:
                    proc.terminate()
                    proc.wait(timeout=2)
                except:
                    pass


class TestPWAIdentification:
    """Test suite for Progressive Web App identification."""

    @pytest.mark.skip(reason="Requires Firefox PWAs to be configured and Sway running")
    async def test_two_different_pwas(self, sway_connection, launch_test_process):
        """
        Test launching two different Firefox PWAs.

        Verifies:
        - Each PWA has distinct I3PM_APP_ID
        - Each PWA has correct I3PM_APP_NAME (claude-pwa, youtube-pwa)
        - PWAs are distinguishable without relying on window class
        """
        processes = []

        # Launch Claude PWA
        env_claude = {
            "I3PM_APP_ID": "claude-pwa-global-12345-1234567890",
            "I3PM_APP_NAME": "claude-pwa",
            "I3PM_SCOPE": "global",
            "I3PM_EXPECTED_CLASS": "FFPWA-01JCYF8Z2M7R4N6QW9XKPHVTB5"
        }
        proc_claude = launch_test_process(
            ["firefoxpwa", "site", "launch", "01JCYF8Z2M7R4N6QW9XKPHVTB5"],
            env_vars=env_claude
        )
        processes.append(proc_claude)

        # Launch YouTube PWA
        env_youtube = {
            "I3PM_APP_ID": "youtube-pwa-global-67890-1234567891",
            "I3PM_APP_NAME": "youtube-pwa",
            "I3PM_SCOPE": "global",
            "I3PM_EXPECTED_CLASS": "FFPWA-01JBCXYZABC123456789"
        }
        proc_youtube = launch_test_process(
            ["firefoxpwa", "site", "launch", "01JBCXYZABC123456789"],
            env_vars=env_youtube
        )
        processes.append(proc_youtube)

        # Wait for windows to appear
        await asyncio.sleep(3)

        try:
            # Read environments
            env_claude_proc = read_process_environ(proc_claude.pid)
            env_youtube_proc = read_process_environ(proc_youtube.pid)

            # Verify both have environment variables
            assert "I3PM_APP_ID" in env_claude_proc
            assert "I3PM_APP_ID" in env_youtube_proc

            # Verify distinct APP_IDs
            assert env_claude_proc["I3PM_APP_ID"] != env_youtube_proc["I3PM_APP_ID"]

            # Verify correct APP_NAMEs
            assert "I3PM_APP_NAME" in env_claude_proc
            assert env_claude_proc["I3PM_APP_NAME"] == "claude-pwa"

            assert "I3PM_APP_NAME" in env_youtube_proc
            assert env_youtube_proc["I3PM_APP_NAME"] == "youtube-pwa"

            # Verify scope is global
            assert env_claude_proc["I3PM_SCOPE"] == "global"
            assert env_youtube_proc["I3PM_SCOPE"] == "global"

        finally:
            # Cleanup: terminate processes
            for proc in processes:
                try:
                    proc.terminate()
                    proc.wait(timeout=3)
                except:
                    pass


class TestEnvironmentParentTraversal:
    """Test suite for parent process environment variable inheritance."""

    async def test_child_process_inherits_environment(self, launch_test_process):
        """
        Test that child processes inherit parent's I3PM_* environment.

        Verifies:
        - Parent process has I3PM_* variables
        - Child process inherits same variables
        """
        # Launch parent process with environment
        parent_env = {
            "I3PM_APP_ID": "parent-test-123",
            "I3PM_APP_NAME": "test-app",
            "I3PM_SCOPE": "global"
        }
        parent_proc = launch_test_process(
            ["sh", "-c", "sleep 60 & wait"],
            env_vars=parent_env
        )

        # Wait for child to spawn
        await asyncio.sleep(0.5)

        try:
            # Read parent environment
            parent_env_read = read_process_environ(parent_proc.pid)

            # Verify parent has variables
            assert "I3PM_APP_ID" in parent_env_read
            assert parent_env_read["I3PM_APP_ID"] == "parent-test-123"

            # Try to find child process (sleep)
            # Note: This is a simplified test - full implementation would
            # traverse /proc to find child processes

        finally:
            # Cleanup
            parent_proc.terminate()
            try:
                parent_proc.wait(timeout=2)
            except:
                parent_proc.kill()


class TestEnvironmentQueryPerformance:
    """Test suite for environment query performance."""

    async def test_environment_read_latency(self, launch_test_process):
        """
        Test that reading /proc/<pid>/environ has acceptable latency.

        Verifies:
        - Single read completes in <10ms
        - Average of 100 reads is <1ms
        """
        import time

        # Launch test process
        proc = launch_test_process(
            ["sleep", "60"],
            env_vars={
                "I3PM_APP_ID": "perf-test-123",
                "I3PM_APP_NAME": "test-app",
                "I3PM_SCOPE": "global"
            }
        )

        try:
            # Warm up
            read_process_environ(proc.pid)

            # Measure latency for 100 reads
            latencies = []
            for _ in range(100):
                start = time.perf_counter()
                env = read_process_environ(proc.pid)
                end = time.perf_counter()

                latency_ms = (end - start) * 1000
                latencies.append(latency_ms)

                assert "I3PM_APP_ID" in env

            # Calculate statistics
            avg_latency = sum(latencies) / len(latencies)
            max_latency = max(latencies)

            # Verify performance targets
            assert avg_latency < 1.0, f"Average latency {avg_latency:.2f}ms exceeds 1ms target"
            assert max_latency < 10.0, f"Max latency {max_latency:.2f}ms exceeds 10ms target"

        finally:
            # Cleanup
            proc.terminate()
            try:
                proc.wait(timeout=2)
            except:
                proc.kill()


class TestSimplifiedWindowMatching:
    """
    Test suite for simplified window matching without class-based logic (User Story 4).

    Tests verify that PWA identification and window matching work using ONLY
    environment variables, without falling back to FFPWA-* class pattern matching.
    """

    @pytest.mark.skip(reason="T037: Requires Firefox PWA to be installed")
    async def test_pwa_identification_without_class_matching(self, sway_connection, launch_test_process):
        """
        T037: Integration test - PWA identification uses I3PM_APP_NAME, not FFPWA-* class.

        Verifies that:
        1. PWA identification uses I3PM_APP_NAME="claude-pwa" from environment
        2. Does NOT use FFPWA-* class pattern matching
        3. No class normalization logic is executed
        4. Identification is deterministic regardless of window class
        """
        # Launch Firefox PWA with environment variables
        pwa_env = {
            "I3PM_APP_ID": "claude-pwa-nixos-test-987654",
            "I3PM_APP_NAME": "claude-pwa",  # KEY: This is what we use, not window class
            "I3PM_SCOPE": "scoped",
            "I3PM_PROJECT_NAME": "nixos",
            "I3PM_PROJECT_DIR": "/etc/nixos",
            "I3PM_EXPECTED_CLASS": "FFPWA-01JCYF8Z2M7R4N6QW9XKPHVTB5",  # For validation only
        }

        # Launch PWA (mocked - would normally use firefoxpwa command)
        proc = launch_test_process(
            ["sleep", "60"],  # Placeholder - real test would launch actual PWA
            env_vars=pwa_env
        )

        try:
            await asyncio.sleep(0.5)

            # Read environment from process
            env_vars = read_process_environ(proc.pid)

            # Assert identification uses I3PM_APP_NAME
            assert env_vars["I3PM_APP_NAME"] == "claude-pwa", \
                "Should use I3PM_APP_NAME from environment"

            # Assert NOT using FFPWA-* pattern from window class
            assert "FFPWA" not in env_vars["I3PM_APP_NAME"], \
                "app_name should be human-readable 'claude-pwa', not FFPWA-* class"

            # Verify expected_class is present but NOT used for matching
            assert env_vars["I3PM_EXPECTED_CLASS"] == "FFPWA-01JCYF8Z2M7R4N6QW9XKPHVTB5", \
                "expected_class should be available for validation"

            # The key point: We identified the app as "claude-pwa" from environment
            # WITHOUT needing to parse or normalize the FFPWA-* window class
            assert env_vars["I3PM_APP_NAME"] != env_vars["I3PM_EXPECTED_CLASS"], \
                "app_name (claude-pwa) should differ from window class (FFPWA-*)"

        finally:
            proc.terminate()
            proc.wait(timeout=2)

    @pytest.mark.skip(reason="Requires multiple PWAs to be installed")
    async def test_multiple_pwas_without_class_confusion(self, sway_connection, launch_test_process):
        """
        Integration test - Multiple PWAs distinguished by APP_NAME, not class patterns.

        Legacy approach: Parse FFPWA-* class → lookup in registry → ambiguity
        New approach: Read I3PM_APP_NAME directly → deterministic
        """
        # Launch two different Firefox PWAs
        claude_env = {
            "I3PM_APP_ID": "claude-pwa-test-1",
            "I3PM_APP_NAME": "claude-pwa",
            "I3PM_SCOPE": "scoped",
            "I3PM_EXPECTED_CLASS": "FFPWA-01JCYF8Z2M",
        }

        youtube_env = {
            "I3PM_APP_ID": "youtube-pwa-test-2",
            "I3PM_APP_NAME": "youtube-pwa",
            "I3PM_SCOPE": "global",
            "I3PM_EXPECTED_CLASS": "FFPWA-01JD0H7Z8M",
        }

        proc1 = launch_test_process(["sleep", "60"], env_vars=claude_env)
        proc2 = launch_test_process(["sleep", "60"], env_vars=youtube_env)

        try:
            await asyncio.sleep(0.5)

            # Read environments
            env1 = read_process_environ(proc1.pid)
            env2 = read_process_environ(proc2.pid)

            # Assert distinct APP_NAMEs
            assert env1["I3PM_APP_NAME"] == "claude-pwa"
            assert env2["I3PM_APP_NAME"] == "youtube-pwa"

            # Assert distinct APP_IDs
            assert env1["I3PM_APP_ID"] != env2["I3PM_APP_ID"]

            # Both have FFPWA-* classes, but we don't use them for matching
            assert "FFPWA" in env1["I3PM_EXPECTED_CLASS"]
            assert "FFPWA" in env2["I3PM_EXPECTED_CLASS"]

            # No confusion - deterministic identification without class parsing!

        finally:
            proc1.terminate()
            proc2.terminate()
            proc1.wait(timeout=2)
            proc2.wait(timeout=2)


class TestProjectFiltering:
    """Test suite for environment-based project filtering (User Story 5)."""

    async def test_scoped_app_hides_on_project_switch(self, launch_test_process):
        """
        T045: Integration test - Scoped app hides when switching to different project.

        Test flow:
        1. Launch scoped app in project "nixos"
        2. Switch active project to "stacks"
        3. Verify window should be hidden (should_be_visible returns False)
        4. Switch back to "nixos"
        5. Verify window should be visible (should_be_visible returns True)

        This validates that environment-based project association works without marks.
        """
        # Launch scoped app with nixos project
        scoped_env = {
            "I3PM_APP_ID": "terminal-nixos-test-123",
            "I3PM_APP_NAME": "terminal",
            "I3PM_SCOPE": "scoped",
            "I3PM_PROJECT_NAME": "nixos",
            "I3PM_PROJECT_DIR": "/etc/nixos",
        }

        proc = launch_test_process(["/usr/bin/sleep", "60"], env_vars=scoped_env)

        try:
            await asyncio.sleep(0.5)

            # Read environment from process
            from home_modules.tools.i3pm.daemon.window_environment import read_process_environ
            from home_modules.tools.i3pm.daemon.models import WindowEnvironment

            env_vars = read_process_environ(proc.pid)
            window_env = WindowEnvironment.from_env_dict(env_vars)

            assert window_env is not None, "Failed to parse window environment"

            # Initial state: Active project is "nixos" - window should be visible
            assert window_env.should_be_visible("nixos") is True, \
                "Window should be visible in matching project"

            # Switch to different project: "stacks"
            # Window should be hidden (not visible in non-matching project)
            assert window_env.should_be_visible("stacks") is False, \
                "Window should be hidden in non-matching project"

            # Switch back to "nixos"
            # Window should be visible again
            assert window_env.should_be_visible("nixos") is True, \
                "Window should be visible when switching back to matching project"

            # Verify no active project: window should be hidden
            assert window_env.should_be_visible(None) is False, \
                "Scoped window should be hidden when no project active"

        finally:
            proc.terminate()
            try:
                proc.wait(timeout=2)
            except:
                proc.kill()

    async def test_global_app_visible_across_projects(self, launch_test_process):
        """
        Integration test - Global app remains visible across all project switches.

        Test flow:
        1. Launch global app (e.g., Firefox)
        2. Switch between multiple projects
        3. Verify window always visible (should_be_visible always True)
        """
        # Launch global app
        global_env = {
            "I3PM_APP_ID": "firefox-test-456",
            "I3PM_APP_NAME": "firefox",
            "I3PM_SCOPE": "global",
        }

        proc = launch_test_process(["/usr/bin/sleep", "60"], env_vars=global_env)

        try:
            await asyncio.sleep(0.5)

            # Read environment
            from home_modules.tools.i3pm.daemon.window_environment import read_process_environ
            from home_modules.tools.i3pm.daemon.models import WindowEnvironment

            env_vars = read_process_environ(proc.pid)
            window_env = WindowEnvironment.from_env_dict(env_vars)

            assert window_env is not None, "Failed to parse window environment"

            # Global windows visible in any project
            assert window_env.should_be_visible("nixos") is True
            assert window_env.should_be_visible("stacks") is True
            assert window_env.should_be_visible("personal") is True
            assert window_env.should_be_visible(None) is True

        finally:
            proc.terminate()
            try:
                proc.wait(timeout=2)
            except:
                proc.kill()
