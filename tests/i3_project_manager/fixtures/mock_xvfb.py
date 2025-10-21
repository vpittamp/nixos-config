"""Mock Xvfb for testing without requiring actual X server."""

from contextlib import contextmanager
from typing import Generator
from unittest.mock import MagicMock, patch
import subprocess


@contextmanager
def mock_xvfb_session(
    window_class: str | None = "TestApp",
    window_id: str = "123456789",
    timeout: bool = False,
    cleanup_fail: bool = False,
) -> Generator[str, None, None]:
    """Mock isolated Xvfb session for testing.

    Args:
        window_class: WM_CLASS to return (None for detection failure)
        window_id: Window ID to return from xdotool
        timeout: If True, simulate timeout waiting for window
        cleanup_fail: If True, simulate cleanup failure

    Yields:
        Mock DISPLAY string (e.g., ":99")
    """
    with patch("subprocess.Popen") as mock_popen, \
         patch("subprocess.run") as mock_run:

        # Mock Xvfb process
        mock_xvfb_proc = MagicMock()
        mock_xvfb_proc.terminate = MagicMock()
        mock_xvfb_proc.kill = MagicMock()
        mock_xvfb_proc.wait = MagicMock(return_value=0)

        if cleanup_fail:
            mock_xvfb_proc.wait.side_effect = [
                subprocess.TimeoutExpired(cmd="Xvfb", timeout=5),
                0,  # After SIGKILL
            ]

        mock_popen.return_value = mock_xvfb_proc

        # Mock xdotool search (window ID)
        if timeout:
            # Simulate timeout - no window found
            mock_run.side_effect = [
                subprocess.CompletedProcess(
                    args=["xdotool", "search"],
                    returncode=1,
                    stdout=b"",
                    stderr=b"No windows found",
                )
            ]
        else:
            # Mock successful window detection
            mock_run.side_effect = [
                # xdotool search returns window ID
                subprocess.CompletedProcess(
                    args=["xdotool", "search"],
                    returncode=0,
                    stdout=window_id.encode(),
                    stderr=b"",
                ),
                # xprop returns WM_CLASS
                subprocess.CompletedProcess(
                    args=["xprop", "-id", window_id, "WM_CLASS"],
                    returncode=0,
                    stdout=f'WM_CLASS(STRING) = "instance", "{window_class}"'.encode()
                    if window_class
                    else b"WM_CLASS: not found.",
                    stderr=b"",
                ),
            ]

        yield ":99"

        # Verify cleanup was called
        if not timeout and not cleanup_fail:
            mock_xvfb_proc.terminate.assert_called_once()


def mock_xvfb_unavailable():
    """Mock environment where Xvfb is not available."""
    with patch("shutil.which", return_value=None):
        yield


@contextmanager
def mock_xvfb_dependencies(
    xvfb_available: bool = True,
    xdotool_available: bool = True,
    xprop_available: bool = True,
) -> Generator[None, None, None]:
    """Mock availability of Xvfb dependencies.

    Args:
        xvfb_available: Whether Xvfb is available
        xdotool_available: Whether xdotool is available
        xprop_available: Whether xprop is available
    """

    def mock_which(cmd: str) -> str | None:
        if cmd == "Xvfb" and not xvfb_available:
            return None
        if cmd == "xdotool" and not xdotool_available:
            return None
        if cmd == "xprop" and not xprop_available:
            return None
        return f"/usr/bin/{cmd}"

    with patch("shutil.which", side_effect=mock_which):
        yield
