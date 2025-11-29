"""
Feature 100: WorktreeService - Worktree CRUD Operations

Create, list, and remove git worktrees.
"""

import subprocess
import logging
from pathlib import Path
from typing import Optional

from ..models.bare_repo import BareRepository
from ..models.worktree import Worktree
from .git_utils import get_git_metadata

logger = logging.getLogger(__name__)


class WorktreeError(Exception):
    """Base exception for worktree operations."""
    pass


class WorktreeExistsError(WorktreeError):
    """Worktree already exists."""
    pass


class WorktreeDirtyError(WorktreeError):
    """Worktree has uncommitted changes."""
    pass


class CannotRemoveMainError(WorktreeError):
    """Cannot remove main worktree."""
    pass


class WorktreeService:
    """
    Service for managing git worktrees.

    Creates worktrees as siblings to main:
      ~/repos/<account>/<repo>/
      ├── main/          # Main worktree
      ├── 100-feature/   # Feature worktree
      └── 101-bugfix/    # Another worktree
    """

    def create(
        self,
        repo: BareRepository,
        branch: str,
        from_branch: Optional[str] = None
    ) -> Worktree:
        """
        Create a new worktree as sibling to main.

        Args:
            repo: BareRepository to create worktree in
            branch: Branch name for new worktree
            from_branch: Base branch to create from (default: repo's default_branch)

        Returns:
            Worktree object representing the new worktree

        Raises:
            WorktreeExistsError: If worktree for this branch already exists
            WorktreeError: If worktree creation fails
        """
        # Check if worktree already exists
        if repo.get_worktree_by_branch(branch):
            raise WorktreeExistsError(f"Worktree for branch '{branch}' already exists")

        # Determine base branch
        base_branch = from_branch or repo.default_branch

        # Create worktree path as sibling to other worktrees
        worktree_path = Path(repo.path) / branch

        if worktree_path.exists():
            raise WorktreeExistsError(f"Directory already exists: {worktree_path}")

        logger.info(f"Creating worktree at {worktree_path} from {base_branch}")

        try:
            # Create worktree with new branch
            result = subprocess.run(
                [
                    "git", "-C", repo.bare_path,
                    "worktree", "add",
                    str(worktree_path),
                    "-b", branch,
                    base_branch
                ],
                capture_output=True,
                text=True,
                timeout=30
            )

            if result.returncode != 0:
                raise WorktreeError(f"git worktree add failed: {result.stderr}")

            # Get git metadata for new worktree
            metadata = get_git_metadata(str(worktree_path))

            return Worktree(
                branch=branch,
                path=str(worktree_path),
                commit=metadata.get('commit_hash') if metadata else None,
                is_clean=metadata.get('is_clean') if metadata else True,
                ahead=0,
                behind=0,
                is_main=False
            )

        except subprocess.TimeoutExpired:
            raise WorktreeError("git worktree add timed out")
        except OSError as e:
            raise WorktreeError(f"Failed to create worktree: {e}")

    def remove(
        self,
        repo: BareRepository,
        branch: str,
        force: bool = False
    ) -> str:
        """
        Remove a worktree.

        Args:
            repo: BareRepository containing the worktree
            branch: Branch name of worktree to remove
            force: Force removal even with uncommitted changes

        Returns:
            Path that was removed

        Raises:
            CannotRemoveMainError: If trying to remove main worktree
            WorktreeDirtyError: If worktree has uncommitted changes (and not force)
            WorktreeError: If removal fails
        """
        worktree = repo.get_worktree_by_branch(branch)
        if not worktree:
            raise WorktreeError(f"Worktree for branch '{branch}' not found")

        # Don't allow removing main worktree
        if worktree.is_main:
            raise CannotRemoveMainError("Cannot remove main worktree")

        # Check for uncommitted changes (unless force)
        if not force:
            metadata = get_git_metadata(worktree.path)
            if metadata and not metadata.get('is_clean', True):
                raise WorktreeDirtyError(
                    f"Worktree '{branch}' has uncommitted changes. Use --force to remove."
                )

        logger.info(f"Removing worktree at {worktree.path}")

        try:
            # Remove worktree
            cmd = ["git", "-C", repo.bare_path, "worktree", "remove"]
            if force:
                cmd.append("--force")
            cmd.append(worktree.path)

            result = subprocess.run(
                cmd,
                capture_output=True,
                text=True,
                timeout=30
            )

            if result.returncode != 0:
                raise WorktreeError(f"git worktree remove failed: {result.stderr}")

            return worktree.path

        except subprocess.TimeoutExpired:
            raise WorktreeError("git worktree remove timed out")
        except OSError as e:
            raise WorktreeError(f"Failed to remove worktree: {e}")

    def list_worktrees(self, repo: BareRepository) -> list[Worktree]:
        """
        List all worktrees for a repository.

        This refreshes worktree metadata from git.

        Args:
            repo: BareRepository to list worktrees for

        Returns:
            List of Worktree objects with fresh metadata
        """
        from .git_utils import list_worktrees as git_list_worktrees

        worktrees = []
        wt_list = git_list_worktrees(repo.bare_path)

        for wt_info in wt_list:
            path = wt_info.get('path', '')
            branch = wt_info.get('branch', '')
            commit = wt_info.get('commit', '')

            if not path or not branch:
                continue

            # Get fresh metadata
            metadata = get_git_metadata(path)

            worktree = Worktree(
                branch=branch,
                path=path,
                commit=commit or (metadata.get('commit_hash') if metadata else None),
                is_clean=metadata.get('is_clean') if metadata else None,
                ahead=metadata.get('ahead_count', 0) if metadata else 0,
                behind=metadata.get('behind_count', 0) if metadata else 0,
                is_main=(branch == repo.default_branch or branch in ('main', 'master'))
            )
            worktrees.append(worktree)

        return worktrees
