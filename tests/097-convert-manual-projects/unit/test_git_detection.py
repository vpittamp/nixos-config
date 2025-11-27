"""
Unit tests for git repository detection.

Feature 097: Git-Based Project Discovery and Management
Task T014: Test git repository detection logic

Tests the `is_git_repository()` function that detects whether a directory
is a git repository by checking for .git directory or file.
"""

import pytest
from pathlib import Path
import tempfile
import shutil


class TestGitRepositoryDetection:
    """Test cases for detecting git repositories."""

    @pytest.fixture
    def temp_dir(self) -> Path:
        """Create a temporary directory for tests."""
        path = Path(tempfile.mkdtemp())
        yield path
        shutil.rmtree(path, ignore_errors=True)

    def test_directory_with_git_dir_is_repository(self, temp_dir: Path):
        """A directory containing .git directory should be detected as repository."""
        # Create .git directory (standard git repo)
        git_dir = temp_dir / ".git"
        git_dir.mkdir()
        (git_dir / "HEAD").write_text("ref: refs/heads/main\n")
        (git_dir / "config").write_text("[core]\n")

        # Import after fixtures to allow pytest collection without daemon running
        from home_modules.desktop.i3_project_event_daemon.services.discovery_service import (
            is_git_repository
        )

        assert is_git_repository(temp_dir) is True

    def test_directory_with_git_file_is_repository(self, temp_dir: Path):
        """A directory containing .git file (worktree) should be detected as repository."""
        # Create .git file (worktree indicator)
        git_file = temp_dir / ".git"
        git_file.write_text("gitdir: /some/path/.git/worktrees/my-worktree\n")

        from home_modules.desktop.i3_project_event_daemon.services.discovery_service import (
            is_git_repository
        )

        assert is_git_repository(temp_dir) is True

    def test_empty_directory_is_not_repository(self, temp_dir: Path):
        """An empty directory should not be detected as repository."""
        from home_modules.desktop.i3_project_event_daemon.services.discovery_service import (
            is_git_repository
        )

        assert is_git_repository(temp_dir) is False

    def test_directory_with_other_files_is_not_repository(self, temp_dir: Path):
        """A directory with regular files but no .git should not be detected."""
        (temp_dir / "README.md").write_text("# My Project\n")
        (temp_dir / "src").mkdir()
        (temp_dir / "src" / "main.py").write_text("print('hello')\n")

        from home_modules.desktop.i3_project_event_daemon.services.discovery_service import (
            is_git_repository
        )

        assert is_git_repository(temp_dir) is False

    def test_nonexistent_directory_returns_false(self, temp_dir: Path):
        """A nonexistent directory should return False."""
        nonexistent = temp_dir / "does-not-exist"

        from home_modules.desktop.i3_project_event_daemon.services.discovery_service import (
            is_git_repository
        )

        assert is_git_repository(nonexistent) is False

    def test_file_path_returns_false(self, temp_dir: Path):
        """A file path (not directory) should return False."""
        file_path = temp_dir / "some-file.txt"
        file_path.write_text("content")

        from home_modules.desktop.i3_project_event_daemon.services.discovery_service import (
            is_git_repository
        )

        assert is_git_repository(file_path) is False


class TestWorktreeDetection:
    """Test cases for distinguishing worktrees from regular repositories."""

    @pytest.fixture
    def temp_dir(self) -> Path:
        """Create a temporary directory for tests."""
        path = Path(tempfile.mkdtemp())
        yield path
        shutil.rmtree(path, ignore_errors=True)

    def test_directory_with_git_dir_is_not_worktree(self, temp_dir: Path):
        """A directory with .git directory should not be detected as worktree."""
        git_dir = temp_dir / ".git"
        git_dir.mkdir()

        from home_modules.desktop.i3_project_event_daemon.services.discovery_service import (
            is_worktree
        )

        assert is_worktree(temp_dir) is False

    def test_directory_with_git_file_is_worktree(self, temp_dir: Path):
        """A directory with .git file should be detected as worktree."""
        git_file = temp_dir / ".git"
        git_file.write_text("gitdir: /path/.git/worktrees/branch\n")

        from home_modules.desktop.i3_project_event_daemon.services.discovery_service import (
            is_worktree
        )

        assert is_worktree(temp_dir) is True

    def test_directory_without_git_is_not_worktree(self, temp_dir: Path):
        """A directory without .git should not be detected as worktree."""
        from home_modules.desktop.i3_project_event_daemon.services.discovery_service import (
            is_worktree
        )

        assert is_worktree(temp_dir) is False
