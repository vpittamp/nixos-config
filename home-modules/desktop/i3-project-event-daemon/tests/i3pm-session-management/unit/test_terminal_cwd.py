"""Unit tests for TerminalCwdTracker service.

Feature 074: Session Management
Tests for terminal working directory tracking (T032-T041, US2)
"""

import pytest
import asyncio
import tempfile
from pathlib import Path
from unittest.mock import Mock, patch, AsyncMock

# Import directly from module to avoid services/__init__.py relative import issues
import sys
from pathlib import Path as ImportPath
sys.path.insert(0, str(ImportPath(__file__).parent.parent.parent / "services"))
from terminal_cwd import TerminalCwdTracker, TERMINAL_CLASSES


# ============================================================================
# TerminalCwdTracker Initialization Tests
# ============================================================================

class TestTerminalCwdTrackerInit:
    """Test TerminalCwdTracker initialization."""

    def test_initialization(self):
        """Test basic TerminalCwdTracker initialization."""
        tracker = TerminalCwdTracker()
        assert tracker is not None

    def test_terminal_classes_constant(self):
        """Test TERMINAL_CLASSES constant is defined (T034, US2)."""
        assert TERMINAL_CLASSES is not None
        assert isinstance(TERMINAL_CLASSES, set)

        # Check for known terminal classes
        expected_terminals = {"ghostty", "Alacritty", "kitty", "foot", "WezTerm"}
        for terminal in expected_terminals:
            assert terminal in TERMINAL_CLASSES, f"{terminal} should be in TERMINAL_CLASSES"


# ============================================================================
# Terminal Window Detection Tests (T034-T035, US2)
# ============================================================================

class TestTerminalWindowDetection:
    """Test terminal window detection methods."""

    def test_is_terminal_window_with_known_classes(self):
        """Test is_terminal_window() recognizes known terminal classes (T035, US2)."""
        tracker = TerminalCwdTracker()

        # Test known terminal classes
        for terminal_class in ["ghostty", "Alacritty", "kitty", "foot", "WezTerm", "org.wezfurlong.wezterm", "footclient", "Ghostty"]:
            result = tracker.is_terminal_window(terminal_class)
            assert result is True, f"{terminal_class} should be recognized as terminal"

    def test_is_terminal_window_with_non_terminal_classes(self):
        """Test is_terminal_window() rejects non-terminal classes."""
        tracker = TerminalCwdTracker()

        # Test non-terminal classes
        for non_terminal_class in ["Code", "firefox", "Chrome", "Spotify", "Slack"]:
            result = tracker.is_terminal_window(non_terminal_class)
            assert result is False, f"{non_terminal_class} should not be recognized as terminal"

    def test_is_terminal_window_with_empty_class(self):
        """Test is_terminal_window() handles empty window class."""
        tracker = TerminalCwdTracker()

        assert tracker.is_terminal_window("") is False
        assert tracker.is_terminal_window(None) is False

    def test_is_terminal_window_case_insensitive(self):
        """Test is_terminal_window() handles case variations."""
        tracker = TerminalCwdTracker()

        # Should match case-insensitively
        assert tracker.is_terminal_window("ghostty") is True
        assert tracker.is_terminal_window("Ghostty") is True
        assert tracker.is_terminal_window("GHOSTTY") is True  # All uppercase variation


# ============================================================================
# Terminal CWD Extraction Tests (T033, US2)
# ============================================================================

class TestTerminalCwdExtraction:
    """Test terminal working directory extraction via /proc."""

    @pytest.mark.asyncio
    async def test_get_terminal_cwd_valid_pid(self):
        """Test get_terminal_cwd() reads /proc/{pid}/cwd (T033, US2)."""
        tracker = TerminalCwdTracker()

        # Use current process PID (should have valid cwd)
        import os
        current_pid = os.getpid()

        cwd_path = await tracker.get_terminal_cwd(current_pid)

        assert cwd_path is not None
        assert isinstance(cwd_path, Path)
        assert cwd_path.is_absolute()
        assert cwd_path.is_dir()

    @pytest.mark.asyncio
    async def test_get_terminal_cwd_invalid_pid(self):
        """Test get_terminal_cwd() handles invalid PID gracefully."""
        tracker = TerminalCwdTracker()

        # Invalid PIDs should return None
        assert await tracker.get_terminal_cwd(-1) is None
        assert await tracker.get_terminal_cwd(0) is None

    @pytest.mark.asyncio
    async def test_get_terminal_cwd_nonexistent_pid(self):
        """Test get_terminal_cwd() handles non-existent PID."""
        tracker = TerminalCwdTracker()

        # Use absurdly high PID that doesn't exist
        nonexistent_pid = 9999999

        cwd_path = await tracker.get_terminal_cwd(nonexistent_pid)

        # Should return None, not raise exception
        assert cwd_path is None

    @pytest.mark.asyncio
    async def test_get_terminal_cwd_returns_absolute_path(self):
        """Test get_terminal_cwd() returns absolute path."""
        tracker = TerminalCwdTracker()

        import os
        current_pid = os.getpid()

        cwd_path = await tracker.get_terminal_cwd(current_pid)

        assert cwd_path is not None
        assert cwd_path.is_absolute(), "Returned path should be absolute"

    @pytest.mark.asyncio
    async def test_get_terminal_cwd_async_execution(self):
        """Test get_terminal_cwd() uses async executor to avoid blocking."""
        tracker = TerminalCwdTracker()

        import os
        current_pid = os.getpid()

        # Should complete without blocking
        cwd_path = await asyncio.wait_for(
            tracker.get_terminal_cwd(current_pid),
            timeout=1.0  # Should complete in <1s
        )

        assert cwd_path is not None


# ============================================================================
# Launch CWD Calculation Tests (T038-T039, US2)
# ============================================================================

class TestLaunchCwdCalculation:
    """Test get_launch_cwd() fallback chain logic."""

    def test_get_launch_cwd_uses_saved_cwd(self):
        """Test get_launch_cwd() prioritizes saved cwd (T038, US2)."""
        tracker = TerminalCwdTracker()

        with tempfile.TemporaryDirectory() as temp_dir:
            saved_cwd = Path(temp_dir)
            project_dir = Path("/etc/nixos")
            fallback_home = Path.home()

            result = tracker.get_launch_cwd(
                saved_cwd=saved_cwd,
                project_directory=project_dir,
                fallback_home=fallback_home
            )

            # Should use saved cwd (exists and is directory)
            assert result == saved_cwd

    def test_get_launch_cwd_falls_back_to_project_dir(self):
        """Test get_launch_cwd() falls back to project directory (T039, US2)."""
        tracker = TerminalCwdTracker()

        saved_cwd = Path("/nonexistent/directory")
        project_dir = Path("/etc/nixos")
        fallback_home = Path.home()

        result = tracker.get_launch_cwd(
            saved_cwd=saved_cwd,
            project_directory=project_dir,
            fallback_home=fallback_home
        )

        # Should fall back to project directory
        assert result == project_dir

    def test_get_launch_cwd_falls_back_to_home(self):
        """Test get_launch_cwd() ultimate fallback to $HOME (T039, US2)."""
        tracker = TerminalCwdTracker()

        saved_cwd = Path("/nonexistent/directory")
        project_dir = Path("/also/nonexistent")
        fallback_home = Path.home()

        result = tracker.get_launch_cwd(
            saved_cwd=saved_cwd,
            project_directory=project_dir,
            fallback_home=fallback_home
        )

        # Should fall back to home directory
        assert result == fallback_home

    def test_get_launch_cwd_with_none_saved_cwd(self):
        """Test get_launch_cwd() handles None saved_cwd."""
        tracker = TerminalCwdTracker()

        result = tracker.get_launch_cwd(
            saved_cwd=None,
            project_directory=Path("/etc/nixos"),
            fallback_home=Path.home()
        )

        # Should skip to project directory
        assert result == Path("/etc/nixos")

    def test_get_launch_cwd_with_none_project_directory(self):
        """Test get_launch_cwd() handles None project_directory."""
        tracker = TerminalCwdTracker()

        result = tracker.get_launch_cwd(
            saved_cwd=None,
            project_directory=None,
            fallback_home=Path.home()
        )

        # Should fall back to home
        assert result == Path.home()

    def test_get_launch_cwd_fallback_chain_order(self):
        """Test get_launch_cwd() respects fallback chain: cwd → project → home."""
        tracker = TerminalCwdTracker()

        with tempfile.TemporaryDirectory() as temp_dir1:
            with tempfile.TemporaryDirectory() as temp_dir2:
                saved_cwd = Path(temp_dir1)
                project_dir = Path(temp_dir2)
                fallback_home = Path.home()

                # All exist - should use saved_cwd (highest priority)
                result = tracker.get_launch_cwd(saved_cwd, project_dir, fallback_home)
                assert result == saved_cwd

                # Remove saved_cwd - should use project_dir
                saved_cwd = Path("/nonexistent")
                result = tracker.get_launch_cwd(saved_cwd, project_dir, fallback_home)
                assert result == project_dir

                # Remove project_dir - should use fallback_home
                project_dir = Path("/also/nonexistent")
                result = tracker.get_launch_cwd(saved_cwd, project_dir, fallback_home)
                assert result == fallback_home


# ============================================================================
# Integration Tests
# ============================================================================

class TestTerminalCwdTrackerIntegration:
    """Integration tests for TerminalCwdTracker."""

    @pytest.mark.asyncio
    async def test_complete_workflow(self):
        """Test complete terminal cwd tracking workflow."""
        tracker = TerminalCwdTracker()

        # 1. Detect terminal window
        assert tracker.is_terminal_window("ghostty") is True

        # 2. Get terminal cwd
        import os
        current_pid = os.getpid()
        cwd_path = await tracker.get_terminal_cwd(current_pid)
        assert cwd_path is not None

        # 3. Calculate launch cwd with fallback
        launch_cwd = tracker.get_launch_cwd(
            saved_cwd=cwd_path,
            project_directory=Path("/etc/nixos"),
            fallback_home=Path.home()
        )
        assert launch_cwd == cwd_path  # Should use saved cwd since it exists

    @pytest.mark.asyncio
    async def test_workflow_with_deleted_directory(self):
        """Test workflow when saved cwd has been deleted."""
        tracker = TerminalCwdTracker()

        # Simulate deleted cwd
        deleted_cwd = Path("/tmp/deleted/terminal/cwd")

        # Should fall back to project directory
        launch_cwd = tracker.get_launch_cwd(
            saved_cwd=deleted_cwd,
            project_directory=Path("/etc/nixos"),
            fallback_home=Path.home()
        )
        assert launch_cwd == Path("/etc/nixos")

    def test_multiple_terminal_types(self):
        """Test handling multiple terminal types."""
        tracker = TerminalCwdTracker()

        terminal_classes = ["ghostty", "Alacritty", "kitty", "foot", "WezTerm"]

        for terminal_class in terminal_classes:
            # Each should be recognized
            assert tracker.is_terminal_window(terminal_class) is True

            # Each could have different cwd handling (but interface is the same)
            # In reality, all use /proc/{pid}/cwd


if __name__ == "__main__":
    pytest.main([__file__, "-v"])
