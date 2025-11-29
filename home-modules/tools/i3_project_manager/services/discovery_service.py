"""
Feature 100: DiscoveryService - Repository and Worktree Discovery

Scans configured account directories for bare repositories and their worktrees.
"""

import logging
from pathlib import Path
from typing import Optional
from datetime import datetime

from ..models.account import AccountConfig, AccountsStorage
from ..models.bare_repo import BareRepository, RepositoriesStorage
from ..models.worktree import Worktree
from ..models.discovered_project import DiscoveredProject, ProjectType
from .git_utils import (
    parse_github_url,
    get_default_branch,
    list_worktrees,
    prune_worktrees,
    get_git_metadata,
)

logger = logging.getLogger(__name__)


class DiscoveryError(Exception):
    """Base exception for discovery operations."""
    pass


class DiscoveryResult:
    """Result of a discovery operation."""

    def __init__(self):
        self.repos: int = 0
        self.worktrees: int = 0
        self.errors: list[str] = []
        self.duration_ms: int = 0

    @property
    def total(self) -> int:
        return self.repos + self.worktrees


class DiscoveryService:
    """
    Service for discovering bare repositories and worktrees.

    Scans configured account directories and discovers:
    - Bare repositories with .bare/ structure
    - All worktrees linked to each repository
    - Git metadata (branch, commit, clean/dirty)
    """

    def __init__(
        self,
        accounts_storage: Optional[AccountsStorage] = None,
        repos_storage: Optional[RepositoriesStorage] = None
    ):
        """
        Initialize DiscoveryService.

        Args:
            accounts_storage: Account configuration storage
            repos_storage: Repository cache storage
        """
        self.accounts_storage = accounts_storage or AccountsStorage()
        self.repos_storage = repos_storage or RepositoriesStorage()

    def discover_all(self) -> DiscoveryResult:
        """
        Discover all repositories in configured account directories.

        Returns:
            DiscoveryResult with counts and any errors
        """
        import time
        start_time = time.time()

        result = DiscoveryResult()

        # Clear existing repos and re-discover
        self.repos_storage.repositories = []

        for account in self.accounts_storage.accounts:
            try:
                account_result = self._discover_account(account)
                result.repos += account_result.repos
                result.worktrees += account_result.worktrees
                result.errors.extend(account_result.errors)
            except Exception as e:
                logger.error(f"Error discovering account {account.name}: {e}")
                result.errors.append(f"Account {account.name}: {str(e)}")

        # Update last discovery timestamp
        self.repos_storage.last_discovery = datetime.utcnow()

        result.duration_ms = int((time.time() - start_time) * 1000)
        logger.info(
            f"Discovery complete: {result.repos} repos, {result.worktrees} worktrees "
            f"in {result.duration_ms}ms"
        )

        return result

    def _discover_account(self, account: AccountConfig) -> DiscoveryResult:
        """
        Discover all repositories for a single account.

        Args:
            account: Account configuration

        Returns:
            DiscoveryResult for this account
        """
        result = DiscoveryResult()
        account_path = account.expanded_path

        if not account_path.exists():
            logger.warning(f"Account path does not exist: {account_path}")
            return result

        # Scan for directories containing .bare/
        for repo_dir in account_path.iterdir():
            if not repo_dir.is_dir():
                continue

            bare_path = repo_dir / ".bare"
            if not bare_path.exists():
                continue

            try:
                repo = self._discover_repository(account, repo_dir, bare_path)
                self.repos_storage.update_repository(repo)
                result.repos += 1
                result.worktrees += len(repo.worktrees)
            except Exception as e:
                logger.warning(f"Error discovering repo {repo_dir}: {e}")
                result.errors.append(f"Repo {repo_dir.name}: {str(e)}")

        return result

    def _discover_repository(
        self,
        account: AccountConfig,
        repo_dir: Path,
        bare_path: Path
    ) -> BareRepository:
        """
        Discover a single repository and its worktrees.

        Args:
            account: Account this repo belongs to
            repo_dir: Repository container directory
            bare_path: Path to .bare/ directory

        Returns:
            BareRepository object
        """
        # Get remote URL
        remote_url = self._get_remote_url(bare_path)

        # Get default branch
        try:
            default_branch = get_default_branch(str(bare_path))
        except ValueError:
            default_branch = "main"

        # Prune stale worktree references
        prune_worktrees(str(bare_path))

        # Discover worktrees
        worktrees = self._discover_worktrees(bare_path, default_branch)

        return BareRepository(
            account=account.name,
            name=repo_dir.name,
            path=str(repo_dir),
            remote_url=remote_url,
            default_branch=default_branch,
            worktrees=worktrees,
            discovered_at=datetime.utcnow(),
            last_scanned=datetime.utcnow()
        )

    def _discover_worktrees(
        self,
        bare_path: Path,
        default_branch: str
    ) -> list[Worktree]:
        """
        Discover all worktrees for a repository.

        Args:
            bare_path: Path to .bare/ directory
            default_branch: Default branch name

        Returns:
            List of Worktree objects
        """
        worktrees = []
        wt_list = list_worktrees(str(bare_path))

        for wt_info in wt_list:
            path = wt_info.get('path', '')
            branch = wt_info.get('branch', '')
            commit = wt_info.get('commit', '')

            if not path or not branch:
                continue

            # Get git metadata for this worktree
            metadata = get_git_metadata(path)

            worktree = Worktree(
                branch=branch,
                path=path,
                commit=commit or (metadata.get('commit_hash') if metadata else None),
                is_clean=metadata.get('is_clean') if metadata else None,
                ahead=metadata.get('ahead_count', 0) if metadata else 0,
                behind=metadata.get('behind_count', 0) if metadata else 0,
                is_main=(branch == default_branch or branch in ('main', 'master'))
            )
            worktrees.append(worktree)

        return worktrees

    def _get_remote_url(self, bare_path: Path) -> str:
        """Get remote origin URL from bare repo."""
        import subprocess
        try:
            result = subprocess.run(
                ["git", "-C", str(bare_path), "remote", "get-url", "origin"],
                capture_output=True,
                text=True,
                timeout=5
            )
            if result.returncode == 0:
                return result.stdout.strip()
        except (subprocess.TimeoutExpired, OSError):
            pass
        return ""

    def get_all_projects(
        self,
        active_project: Optional[str] = None
    ) -> list[DiscoveredProject]:
        """
        Get all discovered projects as DiscoveredProject objects.

        Args:
            active_project: Name of currently active project (optional)

        Returns:
            Flat list of DiscoveredProject objects (repos and worktrees)
        """
        projects = []

        for repo in self.repos_storage.repositories:
            # Add repository as project
            projects.append(DiscoveredProject.from_repository(
                repo,
                is_active=(active_project == repo.qualified_name)
            ))

            # Add each worktree as project
            for wt in repo.worktrees:
                wt_id = f"{repo.qualified_name}:{wt.branch}"
                projects.append(DiscoveredProject.from_worktree(
                    repo,
                    wt,
                    is_active=(active_project == wt_id)
                ))

        return projects

    def get_repository(self, qualified_name: str) -> Optional[BareRepository]:
        """
        Get a repository by qualified name.

        Args:
            qualified_name: Repository qualified name (account/repo)

        Returns:
            BareRepository or None
        """
        return self.repos_storage.get_by_qualified_name(qualified_name)

    def list_repositories(
        self,
        account: Optional[str] = None
    ) -> list[BareRepository]:
        """
        List all repositories, optionally filtered by account.

        Args:
            account: Filter by account name (optional)

        Returns:
            List of BareRepository objects
        """
        if account:
            return self.repos_storage.get_by_account(account)
        return self.repos_storage.repositories
