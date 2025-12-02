"""
Unit tests for LazyGitContext model and view selection logic.

Feature 109: Enhanced Worktree User Experience - T022
Tests the lazygit context handling for worktree-specific launching.
"""

import pytest
from pathlib import Path
import sys
import importlib.util

# Get the path to the lazygit_handler module directly
_module_path = Path(__file__).parents[3] / "home-modules" / "desktop" / "i3-project-event-daemon" / "services" / "lazygit_handler.py"


def _load_lazygit_handler():
    """Load lazygit_handler module directly without going through services __init__.py."""
    spec = importlib.util.spec_from_file_location("lazygit_handler", _module_path)
    module = importlib.util.module_from_spec(spec)
    sys.modules["lazygit_handler"] = module
    spec.loader.exec_module(module)
    return module


# Load module once at module level
_lazygit_handler = _load_lazygit_handler()


class TestLazyGitView:
    """Tests for LazyGitView enum."""

    def test_view_enum_values(self):
        """Test that all expected view values exist."""
        LazyGitView = _lazygit_handler.LazyGitView

        assert LazyGitView.STATUS.value == "status"
        assert LazyGitView.BRANCH.value == "branch"
        assert LazyGitView.LOG.value == "log"
        assert LazyGitView.STASH.value == "stash"

    def test_view_enum_count(self):
        """Test that we have exactly 4 view types."""
        LazyGitView = _lazygit_handler.LazyGitView

        assert len(LazyGitView) == 4


class TestLazyGitContext:
    """Tests for LazyGitContext model."""

    def test_minimal_context(self):
        """Test creating context with only required fields."""
        LazyGitContext = _lazygit_handler.LazyGitContext
        LazyGitView = _lazygit_handler.LazyGitView

        context = LazyGitContext(working_directory="/home/user/repo")
        assert context.working_directory == "/home/user/repo"
        assert context.initial_view == LazyGitView.STATUS
        assert context.filter_path is None

    def test_full_context(self):
        """Test creating context with all fields."""
        LazyGitContext = _lazygit_handler.LazyGitContext
        LazyGitView = _lazygit_handler.LazyGitView

        context = LazyGitContext(
            working_directory="/home/user/repo/109-feature",
            initial_view=LazyGitView.BRANCH,
            filter_path="src/models/"
        )
        assert context.working_directory == "/home/user/repo/109-feature"
        assert context.initial_view == LazyGitView.BRANCH
        assert context.filter_path == "src/models/"

    def test_to_command_args_minimal(self):
        """Test command args generation with minimal config."""
        LazyGitContext = _lazygit_handler.LazyGitContext

        context = LazyGitContext(working_directory="/home/user/repo")
        args = context.to_command_args()

        assert args == ["lazygit", "--path", "/home/user/repo", "status"]

    def test_to_command_args_with_view(self):
        """Test command args generation with specific view."""
        LazyGitContext = _lazygit_handler.LazyGitContext
        LazyGitView = _lazygit_handler.LazyGitView

        context = LazyGitContext(
            working_directory="/home/user/repo",
            initial_view=LazyGitView.BRANCH
        )
        args = context.to_command_args()

        assert args == ["lazygit", "--path", "/home/user/repo", "branch"]

    def test_to_command_args_with_filter(self):
        """Test command args generation with filter path."""
        LazyGitContext = _lazygit_handler.LazyGitContext
        LazyGitView = _lazygit_handler.LazyGitView

        context = LazyGitContext(
            working_directory="/home/user/repo",
            initial_view=LazyGitView.LOG,
            filter_path="src/main.py"
        )
        args = context.to_command_args()

        assert args == [
            "lazygit",
            "--path", "/home/user/repo",
            "--filter", "src/main.py",
            "log"
        ]

    def test_to_command_string(self):
        """Test command string generation."""
        LazyGitContext = _lazygit_handler.LazyGitContext
        LazyGitView = _lazygit_handler.LazyGitView

        context = LazyGitContext(
            working_directory="/home/user/repo",
            initial_view=LazyGitView.STATUS
        )
        cmd_str = context.to_command_string()

        assert cmd_str == "lazygit --path /home/user/repo status"

    def test_working_directory_must_be_absolute(self):
        """Test that relative paths are rejected."""
        LazyGitContext = _lazygit_handler.LazyGitContext
        from pydantic import ValidationError

        with pytest.raises(ValidationError):
            LazyGitContext(working_directory="relative/path")


class TestViewSelection:
    """Tests for view selection logic."""

    def test_select_view_default(self):
        """Test default view is status."""
        select_view_for_context = _lazygit_handler.select_view_for_context
        LazyGitView = _lazygit_handler.LazyGitView

        view = select_view_for_context()
        assert view == LazyGitView.STATUS

    def test_select_view_dirty_worktree(self):
        """Test dirty worktree selects status view."""
        select_view_for_context = _lazygit_handler.select_view_for_context
        LazyGitView = _lazygit_handler.LazyGitView

        view = select_view_for_context(is_dirty=True)
        assert view == LazyGitView.STATUS

    def test_select_view_behind_remote(self):
        """Test behind remote selects branch view."""
        select_view_for_context = _lazygit_handler.select_view_for_context
        LazyGitView = _lazygit_handler.LazyGitView

        view = select_view_for_context(is_behind=True)
        assert view == LazyGitView.BRANCH

    def test_select_view_conflicts(self):
        """Test conflicts select status view."""
        select_view_for_context = _lazygit_handler.select_view_for_context
        LazyGitView = _lazygit_handler.LazyGitView

        view = select_view_for_context(has_conflicts=True)
        assert view == LazyGitView.STATUS

    def test_select_view_conflicts_takes_priority(self):
        """Test conflicts take priority over behind."""
        select_view_for_context = _lazygit_handler.select_view_for_context
        LazyGitView = _lazygit_handler.LazyGitView

        view = select_view_for_context(has_conflicts=True, is_behind=True)
        assert view == LazyGitView.STATUS

    def test_select_view_dirty_takes_priority_over_behind(self):
        """Test dirty takes priority over behind."""
        select_view_for_context = _lazygit_handler.select_view_for_context
        LazyGitView = _lazygit_handler.LazyGitView

        view = select_view_for_context(is_dirty=True, is_behind=True)
        assert view == LazyGitView.STATUS

    def test_select_view_with_reason_dirty_indicator(self):
        """Test reason-based selection for dirty indicator."""
        select_view_for_context = _lazygit_handler.select_view_for_context
        LazyGitView = _lazygit_handler.LazyGitView
        LazyGitLaunchReason = _lazygit_handler.LazyGitLaunchReason

        view = select_view_for_context(reason=LazyGitLaunchReason.DIRTY_INDICATOR)
        assert view == LazyGitView.STATUS

    def test_select_view_with_reason_sync_indicator(self):
        """Test reason-based selection for sync indicator."""
        select_view_for_context = _lazygit_handler.select_view_for_context
        LazyGitView = _lazygit_handler.LazyGitView
        LazyGitLaunchReason = _lazygit_handler.LazyGitLaunchReason

        view = select_view_for_context(reason=LazyGitLaunchReason.SYNC_INDICATOR)
        assert view == LazyGitView.BRANCH


class TestLazyGitLauncher:
    """Tests for LazyGitLauncher service."""

    def test_launcher_initialization(self):
        """Test launcher can be initialized with terminal preference."""
        LazyGitLauncher = _lazygit_handler.LazyGitLauncher

        launcher = LazyGitLauncher(terminal="ghostty")
        assert launcher.terminal == "ghostty"

    def test_launcher_default_terminal(self):
        """Test launcher defaults to ghostty."""
        LazyGitLauncher = _lazygit_handler.LazyGitLauncher

        launcher = LazyGitLauncher()
        assert launcher.terminal == "ghostty"

    def test_get_launcher_singleton(self):
        """Test get_launcher returns a launcher instance."""
        get_launcher = _lazygit_handler.get_launcher

        launcher = get_launcher()
        assert launcher is not None
        assert launcher.terminal == "ghostty"

    def test_launch_for_worktree_auto_view(self):
        """Test launch_for_worktree builds correct context."""
        LazyGitLauncher = _lazygit_handler.LazyGitLauncher
        from unittest.mock import patch

        launcher = LazyGitLauncher()

        # Mock the subprocess call since we can't actually launch
        with patch.object(_lazygit_handler, 'subprocess') as mock_subprocess_module:
            mock_popen = mock_subprocess_module.Popen
            mock_popen.return_value.pid = 12345

            result = launcher.launch_for_worktree(
                worktree_path="/home/user/repo/109-feature",
                is_dirty=True
            )

            # Should have tried to launch
            mock_popen.assert_called_once()
            call_args = mock_popen.call_args[0][0]

            # Verify command contains lazygit with status view (because dirty)
            cmd_str = " ".join(call_args)
            assert "lazygit --path /home/user/repo/109-feature status" in cmd_str
            assert result["success"] is True
            assert result["pid"] == 12345
