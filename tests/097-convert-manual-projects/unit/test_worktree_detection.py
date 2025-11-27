"""
Unit tests for git worktree detection.

Feature 097: Git-Based Project Discovery and Management
Task T028: Test worktree detection (.git file vs directory)

Tests the `is_worktree()` function that distinguishes worktrees from
regular repositories by checking if .git is a file (worktree) or
directory (regular repo).
"""

import pytest
from pathlib import Path
import tempfile
import shutil


class TestWorktreeDetection:
    """Test cases for worktree detection."""

    @pytest.fixture
    def temp_workspace(self) -> Path:
        """Create a temporary workspace."""
        workspace = Path(tempfile.mkdtemp())
        yield workspace
        shutil.rmtree(workspace, ignore_errors=True)

    def test_regular_repo_not_worktree(self, temp_workspace: Path):
        """Regular repo with .git directory should not be detected as worktree."""
        from home_modules.desktop.i3_project_event_daemon.services.discovery_service import (
            is_worktree
        )

        # Create regular repo (.git directory)
        repo_path = temp_workspace / "regular-repo"
        repo_path.mkdir()
        git_dir = repo_path / ".git"
        git_dir.mkdir()

        result = is_worktree(repo_path)

        assert result is False

    def test_worktree_detected_by_git_file(self, temp_workspace: Path):
        """Worktree with .git file should be detected."""
        from home_modules.desktop.i3_project_event_daemon.services.discovery_service import (
            is_worktree
        )

        # Create worktree (.git file)
        worktree_path = temp_workspace / "my-worktree"
        worktree_path.mkdir()
        git_file = worktree_path / ".git"
        git_file.write_text("gitdir: /some/path/to/repo/.git/worktrees/my-worktree\n")

        result = is_worktree(worktree_path)

        assert result is True

    def test_non_git_directory_not_worktree(self, temp_workspace: Path):
        """Directory without .git should not be detected as worktree."""
        from home_modules.desktop.i3_project_event_daemon.services.discovery_service import (
            is_worktree
        )

        # Create directory without .git
        non_git_path = temp_workspace / "not-git"
        non_git_path.mkdir()
        (non_git_path / "some-file.txt").write_text("content")

        result = is_worktree(non_git_path)

        assert result is False

    def test_nonexistent_path_not_worktree(self, temp_workspace: Path):
        """Nonexistent path should not be detected as worktree."""
        from home_modules.desktop.i3_project_event_daemon.services.discovery_service import (
            is_worktree
        )

        result = is_worktree(temp_workspace / "does-not-exist")

        assert result is False

    def test_empty_git_file_is_worktree(self, temp_workspace: Path):
        """Empty .git file is technically a worktree (invalid, but file exists)."""
        from home_modules.desktop.i3_project_event_daemon.services.discovery_service import (
            is_worktree
        )

        worktree_path = temp_workspace / "empty-git"
        worktree_path.mkdir()
        git_file = worktree_path / ".git"
        git_file.write_text("")  # Empty file

        result = is_worktree(worktree_path)

        # Should return True because .git is a file, not directory
        assert result is True


class TestIsGitRepository:
    """Test is_git_repository detects both regular repos and worktrees."""

    @pytest.fixture
    def temp_workspace(self) -> Path:
        """Create a temporary workspace."""
        workspace = Path(tempfile.mkdtemp())
        yield workspace
        shutil.rmtree(workspace, ignore_errors=True)

    def test_regular_repo_is_git_repository(self, temp_workspace: Path):
        """Regular repo with .git directory should be detected."""
        from home_modules.desktop.i3_project_event_daemon.services.discovery_service import (
            is_git_repository
        )

        repo_path = temp_workspace / "repo"
        repo_path.mkdir()
        (repo_path / ".git").mkdir()

        assert is_git_repository(repo_path) is True

    def test_worktree_is_git_repository(self, temp_workspace: Path):
        """Worktree with .git file should be detected as git repository."""
        from home_modules.desktop.i3_project_event_daemon.services.discovery_service import (
            is_git_repository
        )

        worktree_path = temp_workspace / "worktree"
        worktree_path.mkdir()
        (worktree_path / ".git").write_text("gitdir: /path/to/git")

        assert is_git_repository(worktree_path) is True

    def test_non_git_not_repository(self, temp_workspace: Path):
        """Directory without .git should not be detected."""
        from home_modules.desktop.i3_project_event_daemon.services.discovery_service import (
            is_git_repository
        )

        non_git_path = temp_workspace / "plain"
        non_git_path.mkdir()
        (non_git_path / "file.txt").write_text("content")

        assert is_git_repository(non_git_path) is False
