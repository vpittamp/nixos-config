"""Unit tests for Xvfb-based window class detection.

Tests the isolated Xvfb session management, WM_CLASS extraction,
and graceful cleanup with timeouts.
"""

import pytest
from unittest.mock import Mock, MagicMock, patch, call
import subprocess
import time
from pathlib import Path

# Module under test (will be created in implementation phase)
# from i3_project_manager.core.app_discovery import (
#     isolated_xvfb,
#     check_xvfb_available,
#     detect_window_class_xvfb,
# )


class TestIsolatedXvfb:
    """Tests for isolated_xvfb() context manager (T031, FR-084)."""

    @patch("subprocess.Popen")
    def test_xvfb_starts_on_custom_display(self, mock_popen):
        """Verify Xvfb starts on specified display number.

        FR-084: Launch isolated Xvfb session on :99
        """
        # Import here to ensure test runs even if module doesn't exist yet
        try:
            from i3_project_manager.core.app_discovery import isolated_xvfb
        except ImportError:
            pytest.skip("isolated_xvfb not yet implemented")

        mock_process = MagicMock()
        mock_process.poll.return_value = None  # Process is running
        mock_popen.return_value = mock_process

        with isolated_xvfb(display_num=99) as display:
            # Verify Xvfb started with correct display
            assert display == ":99"
            mock_popen.assert_called_once()
            args = mock_popen.call_args[0][0]
            assert "Xvfb" in args
            assert ":99" in args

        # Verify cleanup called terminate
        mock_process.terminate.assert_called()

    @patch("subprocess.Popen")
    def test_xvfb_yields_display_environment(self, mock_popen):
        """Verify context manager yields DISPLAY value for subprocess use.

        FR-084: Yield DISPLAY environment variable
        """
        try:
            from i3_project_manager.core.app_discovery import isolated_xvfb
        except ImportError:
            pytest.skip("isolated_xvfb not yet implemented")

        mock_process = MagicMock()
        mock_process.poll.return_value = None
        mock_popen.return_value = mock_process

        with isolated_xvfb(display_num=42) as display:
            assert isinstance(display, str)
            assert display.startswith(":")
            assert "42" in display

    @patch("subprocess.Popen")
    def test_xvfb_terminates_on_exit(self, mock_popen):
        """Verify Xvfb process terminates when context exits.

        FR-088: Graceful termination with SIGTERM
        """
        try:
            from i3_project_manager.core.app_discovery import isolated_xvfb
        except ImportError:
            pytest.skip("isolated_xvfb not yet implemented")

        mock_process = MagicMock()
        mock_process.poll.return_value = None
        mock_popen.return_value = mock_process

        with isolated_xvfb(display_num=99):
            pass

        # Verify terminate was called
        mock_process.terminate.assert_called()

    @patch("subprocess.Popen")
    def test_xvfb_terminates_on_exception(self, mock_popen):
        """Verify Xvfb terminates even if context raises exception.

        FR-088: Cleanup in finally block
        """
        try:
            from i3_project_manager.core.app_discovery import isolated_xvfb
        except ImportError:
            pytest.skip("isolated_xvfb not yet implemented")

        mock_process = MagicMock()
        mock_process.poll.return_value = None
        mock_popen.return_value = mock_process

        with pytest.raises(RuntimeError):
            with isolated_xvfb(display_num=99):
                raise RuntimeError("Test exception")

        # Verify terminate still called
        mock_process.terminate.assert_called()


class TestGracefulTermination:
    """Tests for SIGTERM → wait → SIGKILL sequence (T032, FR-088, FR-089)."""

    @patch("subprocess.Popen")
    @patch("time.sleep")
    def test_sigterm_then_sigkill_sequence(self, mock_sleep, mock_popen):
        """Verify graceful termination uses SIGTERM then SIGKILL.

        FR-088: Send SIGTERM first
        FR-089: SIGKILL if process doesn't exit
        """
        try:
            from i3_project_manager.core.app_discovery import isolated_xvfb
        except ImportError:
            pytest.skip("isolated_xvfb not yet implemented")

        mock_process = MagicMock()
        # Simulate process running initially (poll returns None), then timeout on wait
        mock_process.poll.return_value = None  # Process is running
        mock_process.wait.side_effect = [subprocess.TimeoutExpired("Xvfb", 2.0), None]
        mock_popen.return_value = mock_process

        with isolated_xvfb(display_num=99):
            pass

        # Verify SIGTERM called first
        mock_process.terminate.assert_called()
        # Verify SIGKILL called after timeout
        mock_process.kill.assert_called()

    @patch("subprocess.Popen")
    def test_no_sigkill_if_sigterm_succeeds(self, mock_popen):
        """Verify SIGKILL not sent if process exits cleanly.

        FR-088: Only use SIGKILL if SIGTERM fails
        """
        try:
            from i3_project_manager.core.app_discovery import isolated_xvfb
        except ImportError:
            pytest.skip("isolated_xvfb not yet implemented")

        mock_process = MagicMock()
        # Simulate process running initially, then exiting cleanly after SIGTERM
        mock_process.poll.return_value = None  # Process is running
        mock_process.wait.return_value = 0
        mock_popen.return_value = mock_process

        with isolated_xvfb(display_num=99):
            pass

        # Verify SIGTERM called
        mock_process.terminate.assert_called()
        # Verify SIGKILL NOT called
        mock_process.kill.assert_not_called()


class TestCleanupOnTimeout:
    """Tests for resource cleanup after timeout (T033, FR-086, FR-089, SC-027)."""

    @patch("subprocess.run")
    @patch("subprocess.Popen")
    @patch("time.time")
    def test_cleanup_resources_after_timeout(self, mock_time, mock_popen, mock_run):
        """Verify all resources cleaned up when detection times out.

        FR-086: 10-second timeout
        FR-089: Cleanup all processes
        SC-027: <10s per app
        """
        try:
            from i3_project_manager.core.app_discovery import detect_window_class_xvfb
        except ImportError:
            pytest.skip("detect_window_class_xvfb not yet implemented")

        mock_xvfb = MagicMock()
        mock_app = MagicMock()
        mock_xvfb.poll.return_value = None  # Xvfb is running
        mock_app.poll.return_value = None   # App is running

        # First Popen creates Xvfb, second creates app
        mock_popen.side_effect = [mock_xvfb, mock_app]

        # Mock xdotool to never find a window (timeout scenario)
        mock_run.return_value = MagicMock(returncode=1, stdout="", stderr="No windows")

        # Simulate timeout
        mock_time.side_effect = [0, 0, 11]  # Start, check, timeout

        desktop_file = "/usr/share/applications/test.desktop"
        result = detect_window_class_xvfb(desktop_file, timeout=10)

        # Verify detection failed due to timeout
        assert result.detection_method == "failed"
        assert ("timeout" in result.error_message.lower() or
                "no window appeared" in result.error_message.lower())

        # Verify both processes were terminated
        mock_xvfb.terminate.assert_called()
        mock_app.terminate.assert_called()

    @patch("subprocess.Popen")
    def test_app_process_killed_on_timeout(self, mock_popen):
        """Verify launched app is killed when detection times out.

        FR-089: Kill all spawned processes
        """
        try:
            from i3_project_manager.core.app_discovery import detect_window_class_xvfb
        except ImportError:
            pytest.skip("detect_window_class_xvfb not yet implemented")

        mock_xvfb = MagicMock()
        mock_app = MagicMock()
        mock_xvfb.poll.return_value = None
        mock_app.poll.return_value = None

        # First call creates Xvfb, second creates app
        mock_popen.side_effect = [mock_xvfb, mock_app]

        desktop_file = "/usr/share/applications/test.desktop"
        result = detect_window_class_xvfb(desktop_file, timeout=0.1)

        # Verify both processes terminated
        mock_xvfb.terminate.assert_called()
        mock_app.terminate.assert_called()


class TestDependencyCheck:
    """Tests for dependency availability check (T034, FR-083)."""

    @patch("shutil.which")
    def test_returns_false_when_xvfb_missing(self, mock_which):
        """Verify check_xvfb_available() returns False when Xvfb not found.

        FR-083: Check for Xvfb binary
        """
        try:
            from i3_project_manager.core.app_discovery import check_xvfb_available
        except ImportError:
            pytest.skip("check_xvfb_available not yet implemented")

        # Simulate Xvfb not found
        mock_which.side_effect = lambda x: None if x == "Xvfb" else "/usr/bin/" + x

        result = check_xvfb_available()
        assert result is False

    @patch("shutil.which")
    def test_returns_false_when_xdotool_missing(self, mock_which):
        """Verify check_xvfb_available() returns False when xdotool not found.

        FR-083: Check for xdotool binary
        """
        try:
            from i3_project_manager.core.app_discovery import check_xvfb_available
        except ImportError:
            pytest.skip("check_xvfb_available not yet implemented")

        # Simulate xdotool not found
        mock_which.side_effect = lambda x: None if x == "xdotool" else "/usr/bin/" + x

        result = check_xvfb_available()
        assert result is False

    @patch("shutil.which")
    def test_returns_false_when_xprop_missing(self, mock_which):
        """Verify check_xvfb_available() returns False when xprop not found.

        FR-083: Check for xprop binary
        """
        try:
            from i3_project_manager.core.app_discovery import check_xvfb_available
        except ImportError:
            pytest.skip("check_xvfb_available not yet implemented")

        # Simulate xprop not found
        mock_which.side_effect = lambda x: None if x == "xprop" else "/usr/bin/" + x

        result = check_xvfb_available()
        assert result is False

    @patch("shutil.which")
    def test_returns_true_when_all_dependencies_available(self, mock_which):
        """Verify check_xvfb_available() returns True when all tools present.

        FR-083: Check for Xvfb, xdotool, xprop
        """
        try:
            from i3_project_manager.core.app_discovery import check_xvfb_available
        except ImportError:
            pytest.skip("check_xvfb_available not yet implemented")

        # Simulate all tools available
        mock_which.side_effect = lambda x: f"/usr/bin/{x}"

        result = check_xvfb_available()
        assert result is True


class TestWMClassParsing:
    """Tests for WM_CLASS extraction from xprop output (T035, FR-087)."""

    def test_extracts_class_from_xprop_output(self):
        """Verify regex extracts class from xprop WM_CLASS output.

        FR-087: Parse WM_CLASS(STRING) = "instance", "class"
        """
        try:
            from i3_project_manager.core.app_discovery import parse_wm_class
        except ImportError:
            pytest.skip("parse_wm_class not yet implemented")

        xprop_output = 'WM_CLASS(STRING) = "code", "Code"'
        result = parse_wm_class(xprop_output)
        assert result == "Code"

    def test_handles_single_word_class(self):
        """Verify parsing works with single-word class names."""
        try:
            from i3_project_manager.core.app_discovery import parse_wm_class
        except ImportError:
            pytest.skip("parse_wm_class not yet implemented")

        xprop_output = 'WM_CLASS(STRING) = "firefox", "Firefox"'
        result = parse_wm_class(xprop_output)
        assert result == "Firefox"

    def test_handles_lowercase_class(self):
        """Verify parsing extracts exact case from xprop."""
        try:
            from i3_project_manager.core.app_discovery import parse_wm_class
        except ImportError:
            pytest.skip("parse_wm_class not yet implemented")

        xprop_output = 'WM_CLASS(STRING) = "alacritty", "Alacritty"'
        result = parse_wm_class(xprop_output)
        assert result == "Alacritty"

    def test_returns_none_on_invalid_format(self):
        """Verify returns None if xprop output format invalid."""
        try:
            from i3_project_manager.core.app_discovery import parse_wm_class
        except ImportError:
            pytest.skip("parse_wm_class not yet implemented")

        xprop_output = "WM_CLASS: not found"
        result = parse_wm_class(xprop_output)
        assert result is None

    def test_handles_spaces_in_class_name(self):
        """Verify parsing handles class names with spaces."""
        try:
            from i3_project_manager.core.app_discovery import parse_wm_class
        except ImportError:
            pytest.skip("parse_wm_class not yet implemented")

        # Some apps may have spaces in WM_CLASS
        xprop_output = 'WM_CLASS(STRING) = "app", "My App Name"'
        result = parse_wm_class(xprop_output)
        assert result == "My App Name"
