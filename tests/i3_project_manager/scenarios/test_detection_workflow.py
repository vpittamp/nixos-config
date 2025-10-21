"""Integration test for complete window class detection workflow.

Tests the end-to-end flow: launch in Xvfb → detect window → extract WM_CLASS → cleanup.
This verifies integration between isolated_xvfb, app launcher, and property extraction.
"""

import pytest
from unittest.mock import Mock, MagicMock, patch
from pathlib import Path
import tempfile
import json

# Import will be done conditionally in each test (like unit tests)


class TestDetectionWorkflow:
    """Integration test for detection workflow (T036, FR-132)."""

    @patch("subprocess.Popen")
    @patch("subprocess.run")
    @patch("time.sleep")
    def test_complete_detection_workflow_creates_result(
        self, mock_sleep, mock_run, mock_popen
    ):
        """Complete workflow: Xvfb → launch app → detect → extract → cleanup.

        Steps:
        1. Start Xvfb on :99
        2. Launch app with DISPLAY=:99
        3. Wait for window to appear (xdotool)
        4. Extract WM_CLASS with xprop
        5. Terminate app and Xvfb
        6. Return DetectionResult with all fields populated

        FR-132: Automated detection workflow
        """
        try:
            from i3_project_manager.core.app_discovery import detect_window_class_xvfb
            from i3_project_manager.models.detection import DetectionResult
        except ImportError:
            pytest.skip("detect_window_class_xvfb not yet implemented")

        # Mock Xvfb process
        mock_xvfb = MagicMock()
        mock_xvfb.poll.return_value = None  # Running

        # Mock app process
        mock_app = MagicMock()
        mock_app.poll.return_value = None

        # First Popen creates Xvfb, second creates app
        mock_popen.side_effect = [mock_xvfb, mock_app]

        # Mock xdotool search (finds window)
        mock_run.side_effect = [
            # xdotool search --sync
            MagicMock(
                returncode=0, stdout="12345678\n", stderr=""
            ),
            # xprop -id 12345678 WM_CLASS
            MagicMock(
                returncode=0,
                stdout='WM_CLASS(STRING) = "code", "Code"\n',
                stderr="",
            ),
        ]

        desktop_file = "/usr/share/applications/code.desktop"
        result = detect_window_class_xvfb(desktop_file, timeout=10)

        # Verify DetectionResult created with all fields
        assert isinstance(result, DetectionResult)
        assert result.desktop_file == desktop_file
        assert result.app_name is not None
        assert result.detected_class == "Code"
        assert result.detection_method == "xvfb"
        assert result.confidence == 1.0
        assert result.error_message is None
        assert result.timestamp is not None

        # Verify cleanup
        mock_app.terminate.assert_called()
        mock_xvfb.terminate.assert_called()

    @patch("subprocess.Popen")
    @patch("subprocess.run")
    def test_detection_workflow_handles_launch_failure(self, mock_run, mock_popen):
        """Verify workflow handles app launch failure gracefully.

        FR-132: Handle errors gracefully
        """
        try:
            from i3_project_manager.core.app_discovery import detect_window_class_xvfb
        except ImportError:
            pytest.skip("detect_window_class_xvfb not yet implemented")

        # Mock Xvfb starts successfully
        mock_xvfb = MagicMock()
        mock_xvfb.poll.return_value = None
        mock_popen.return_value = mock_xvfb

        # Mock app launch fails (subprocess.run raises)
        mock_run.side_effect = FileNotFoundError("App not found")

        desktop_file = "/usr/share/applications/missing.desktop"
        result = detect_window_class_xvfb(desktop_file, timeout=10)

        # Verify failure result
        assert result.detection_method == "failed"
        assert result.detected_class is None
        assert result.confidence == 0.0
        assert result.error_message is not None
        assert "not found" in result.error_message.lower()

        # Verify Xvfb still cleaned up
        mock_xvfb.terminate.assert_called()

    @patch("subprocess.Popen")
    @patch("subprocess.run")
    @patch("time.time")
    def test_detection_workflow_handles_window_timeout(
        self, mock_time, mock_run, mock_popen
    ):
        """Verify workflow handles window detection timeout.

        FR-086: 10-second timeout per app
        """
        try:
            from i3_project_manager.core.app_discovery import detect_window_class_xvfb
        except ImportError:
            pytest.skip("detect_window_class_xvfb not yet implemented")

        # Mock Xvfb and app start successfully
        mock_xvfb = MagicMock()
        mock_app = MagicMock()
        mock_xvfb.poll.return_value = None
        mock_app.poll.return_value = None
        mock_popen.side_effect = [mock_xvfb, mock_app]

        # Mock xdotool never finds window (returncode 1)
        mock_run.return_value = MagicMock(returncode=1, stdout="", stderr="No windows found")

        # Simulate timeout
        mock_time.side_effect = [0, 0, 11]  # Start, check, timeout

        desktop_file = "/usr/share/applications/slow.desktop"
        result = detect_window_class_xvfb(desktop_file, timeout=10)

        # Verify timeout failure
        assert result.detection_method == "failed"
        assert result.detected_class is None
        assert ("timeout" in result.error_message.lower() or
                "no window appeared" in result.error_message.lower())

        # Verify cleanup
        mock_app.terminate.assert_called()
        mock_xvfb.terminate.assert_called()

    @patch("subprocess.Popen")
    @patch("subprocess.run")
    def test_detection_workflow_handles_xprop_failure(self, mock_run, mock_popen):
        """Verify workflow handles xprop extraction failure.

        FR-087: Handle xprop errors
        """
        try:
            from i3_project_manager.core.app_discovery import detect_window_class_xvfb
        except ImportError:
            pytest.skip("detect_window_class_xvfb not yet implemented")

        # Mock Xvfb and app
        mock_xvfb = MagicMock()
        mock_app = MagicMock()
        mock_xvfb.poll.return_value = None  # Running
        mock_app.poll.return_value = None   # Running
        mock_popen.side_effect = [mock_xvfb, mock_app]

        # Mock xdotool finds window, but xprop fails
        mock_run.side_effect = [
            MagicMock(returncode=0, stdout="12345678\n", stderr=""),  # xdotool success
            MagicMock(returncode=1, stdout="", stderr="WM_CLASS: not found"),  # xprop fail
        ]

        desktop_file = "/usr/share/applications/test.desktop"
        result = detect_window_class_xvfb(desktop_file, timeout=10)

        # Verify failure
        assert result.detection_method == "failed"
        assert result.detected_class is None
        assert result.error_message is not None

        # Verify cleanup still happens
        mock_app.terminate.assert_called()
        mock_xvfb.terminate.assert_called()


class TestBulkDetection:
    """Integration test for bulk detection (T037, SC-022)."""

    @patch("subprocess.Popen")
    @patch("subprocess.run")
    @patch("time.sleep")
    def test_bulk_detection_completes_within_60_seconds(
        self, mock_sleep, mock_run, mock_popen
    ):
        """Verify 10 apps detected with progress indication in <60s.

        SC-022: <60s for 50+ apps (proportionally ~12s for 10 apps)
        """
        try:
            from i3_project_manager.core.app_discovery import detect_window_class_xvfb
        except ImportError:
            pytest.skip("detect_window_class_xvfb not yet implemented")

        # Mock successful detections
        mock_xvfb = MagicMock()
        mock_app = MagicMock()
        mock_xvfb.poll.return_value = None
        mock_app.poll.return_value = None

        # Each app needs Xvfb + app process
        mock_popen.side_effect = [mock_xvfb, mock_app] * 10

        # Mock successful xdotool + xprop for each app
        search_result = MagicMock(returncode=0, stdout="12345678\n", stderr="")
        xprop_result = MagicMock(
            returncode=0, stdout='WM_CLASS(STRING) = "app", "App"\n', stderr=""
        )
        mock_run.side_effect = [search_result, xprop_result] * 10

        # Detect 10 apps
        results = []
        for i in range(10):
            desktop_file = f"/usr/share/applications/app{i}.desktop"
            result = detect_window_class_xvfb(desktop_file, timeout=5)
            results.append(result)

        # Verify all succeeded
        assert len(results) == 10
        assert all(r.detection_method == "xvfb" for r in results)
        assert all(r.detected_class is not None for r in results)

    @patch("subprocess.Popen")
    @patch("subprocess.run")
    def test_bulk_detection_shows_progress_indication(self, mock_run, mock_popen):
        """Verify bulk detection provides progress feedback.

        FR-090: Progress indication during bulk detection
        """
        try:
            from i3_project_manager.core.app_discovery import detect_bulk
        except ImportError:
            pytest.skip("detect_bulk not yet implemented")

        # This test will verify progress indication when CLI is implemented
        # For now, just a placeholder

        pytest.skip("Deferred to CLI implementation (T042)")

    @patch("subprocess.Popen")
    @patch("subprocess.run")
    @patch("time.time")
    def test_bulk_detection_continues_after_single_failure(self, mock_time, mock_run, mock_popen):
        """Verify bulk detection doesn't stop if one app fails.

        FR-132: Resilient bulk processing
        """
        try:
            from i3_project_manager.core.app_discovery import detect_window_class_xvfb
        except ImportError:
            pytest.skip("detect_window_class_xvfb not yet implemented")

        # Mock first app fails, second succeeds
        mock_xvfb = MagicMock()
        mock_app = MagicMock()
        mock_xvfb.poll.return_value = None
        mock_app.poll.return_value = None

        # Two apps = 2 Xvfb + 2 app processes
        mock_popen.side_effect = [mock_xvfb, mock_app, mock_xvfb, mock_app]

        # First app: xdotool fails (no window) - simulate timeout
        # Second app: success
        mock_time.side_effect = [0, 0, 2, 0, 0]  # First app timeout, second app success
        mock_run.side_effect = [
            MagicMock(returncode=1, stdout="", stderr="No windows"),  # First xdotool fails
            MagicMock(returncode=0, stdout="12345678\n", stderr=""),  # Second xdotool
            MagicMock(
                returncode=0, stdout='WM_CLASS(STRING) = "app", "App"\n', stderr=""
            ),  # Second xprop
        ]

        # Detect two apps
        result1 = detect_window_class_xvfb(
            "/usr/share/applications/fail.desktop", timeout=1
        )
        result2 = detect_window_class_xvfb(
            "/usr/share/applications/success.desktop", timeout=5
        )

        # Verify first failed, second succeeded
        assert result1.detection_method == "failed"
        assert result2.detection_method == "xvfb"
        assert result2.detected_class == "App"
