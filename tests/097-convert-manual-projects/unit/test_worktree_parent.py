"""
Unit tests for worktree parent repository resolution.

Feature 097: Git-Based Project Discovery and Management
Task T029: Test parent repository resolution

Tests the `get_worktree_parent()` function that resolves the path
to the main repository from a worktree's .git file.
"""

import pytest
from pathlib import Path
import tempfile
import shutil


class TestWorktreeParentResolution:
    """Test cases for resolving worktree parent repository."""

    @pytest.fixture
    def temp_workspace(self) -> Path:
        """Create a temporary workspace."""
        workspace = Path(tempfile.mkdtemp())
        yield workspace
        shutil.rmtree(workspace, ignore_errors=True)

    def test_resolve_parent_from_gitdir(self, temp_workspace: Path):
        """Should resolve parent from .git file gitdir path."""
        from home_modules.desktop.i3_project_event_daemon.services.discovery_service import (
            get_worktree_parent
        )

        # Simulate a worktree structure
        main_repo = temp_workspace / "main-repo"
        main_repo.mkdir()
        git_dir = main_repo / ".git"
        git_dir.mkdir()

        worktrees_dir = git_dir / "worktrees" / "feature-branch"
        worktrees_dir.mkdir(parents=True)

        worktree_path = temp_workspace / "feature-branch"
        worktree_path.mkdir()

        # Create .git file pointing to worktrees dir
        git_file = worktree_path / ".git"
        git_file.write_text(f"gitdir: {worktrees_dir}\n")

        # The function uses commondir or path structure
        # Since we don't have commondir, it should use path structure
        result = get_worktree_parent(worktree_path)

        assert result == str(main_repo)

    def test_resolve_parent_with_commondir(self, temp_workspace: Path):
        """Should resolve parent from commondir file when present."""
        from home_modules.desktop.i3_project_event_daemon.services.discovery_service import (
            get_worktree_parent
        )

        # Create main repo structure
        main_repo = temp_workspace / "main-repo"
        main_repo.mkdir()
        main_git = main_repo / ".git"
        main_git.mkdir()

        # Create worktree gitdir
        worktrees_dir = main_git / "worktrees" / "my-worktree"
        worktrees_dir.mkdir(parents=True)

        # Create commondir file (points to parent .git relative to worktree gitdir)
        commondir_file = worktrees_dir / "commondir"
        commondir_file.write_text("../..")  # Relative path: worktrees/my-worktree -> .git

        # Create worktree with .git file
        worktree_path = temp_workspace / "my-worktree"
        worktree_path.mkdir()
        git_file = worktree_path / ".git"
        git_file.write_text(f"gitdir: {worktrees_dir}\n")

        result = get_worktree_parent(worktree_path)

        assert result == str(main_repo)

    def test_non_worktree_returns_none(self, temp_workspace: Path):
        """Non-worktree directory should return None."""
        from home_modules.desktop.i3_project_event_daemon.services.discovery_service import (
            get_worktree_parent
        )

        # Regular repo with .git directory
        repo_path = temp_workspace / "regular-repo"
        repo_path.mkdir()
        (repo_path / ".git").mkdir()

        result = get_worktree_parent(repo_path)

        assert result is None

    def test_missing_git_file_returns_none(self, temp_workspace: Path):
        """Directory without .git file should return None."""
        from home_modules.desktop.i3_project_event_daemon.services.discovery_service import (
            get_worktree_parent
        )

        non_git_path = temp_workspace / "plain-dir"
        non_git_path.mkdir()

        result = get_worktree_parent(non_git_path)

        assert result is None

    def test_invalid_gitdir_format_returns_none(self, temp_workspace: Path):
        """Invalid .git file format should return None."""
        from home_modules.desktop.i3_project_event_daemon.services.discovery_service import (
            get_worktree_parent
        )

        worktree_path = temp_workspace / "bad-worktree"
        worktree_path.mkdir()
        git_file = worktree_path / ".git"
        git_file.write_text("some random content")  # Not gitdir: format

        result = get_worktree_parent(worktree_path)

        assert result is None

    def test_nonexistent_path_returns_none(self, temp_workspace: Path):
        """Nonexistent path should return None."""
        from home_modules.desktop.i3_project_event_daemon.services.discovery_service import (
            get_worktree_parent
        )

        result = get_worktree_parent(temp_workspace / "does-not-exist")

        assert result is None
