"""
Feature 100: CloneService - Bare Clone with Worktree Setup

Implements the bare repository clone workflow:
1. git clone --bare <url> .bare
2. Create .git pointer file
3. Detect default branch
4. Create main worktree
"""

import subprocess
import logging
from pathlib import Path
from typing import Optional
from datetime import datetime

from ..models.bare_repo import BareRepository
from ..models.worktree import Worktree
from ..models.account import AccountConfig, AccountsStorage
from .git_utils import parse_github_url, get_default_branch

logger = logging.getLogger(__name__)


class CloneError(Exception):
    """Base exception for clone operations."""
    pass


class RepoExistsError(CloneError):
    """Repository already exists."""
    pass


class InvalidURLError(CloneError):
    """Invalid GitHub URL."""
    pass


class CloneService:
    """
    Service for cloning repositories with bare clone pattern.

    Creates structure:
      ~/repos/<account>/<repo>/
      ├── .bare/     # Bare git database
      ├── .git       # Pointer file
      └── main/      # Main worktree
    """

    def __init__(self, accounts_storage: Optional[AccountsStorage] = None):
        """
        Initialize CloneService.

        Args:
            accounts_storage: Optional AccountsStorage for account lookup
        """
        self.accounts_storage = accounts_storage

    def clone(
        self,
        url: str,
        account: Optional[str] = None
    ) -> BareRepository:
        """
        Clone a repository using bare clone pattern.

        Args:
            url: GitHub repository URL (SSH or HTTPS)
            account: Override account detection (optional)

        Returns:
            BareRepository object representing the cloned repo

        Raises:
            InvalidURLError: If URL is not a valid GitHub URL
            RepoExistsError: If repository already exists
            CloneError: If clone operation fails
        """
        # Parse URL to get account and repo name
        try:
            detected_account, repo_name = parse_github_url(url)
        except ValueError as e:
            raise InvalidURLError(str(e))

        # Use override account if provided
        target_account = account or detected_account

        # Find account configuration
        account_config = self._get_account_config(target_account)
        if account_config is None:
            # Create default path if no account config
            base_path = Path.home() / "repos" / target_account
        else:
            base_path = account_config.expanded_path

        # Create repo container directory
        repo_path = base_path / repo_name
        bare_path = repo_path / ".bare"

        # Check if repo already exists
        if bare_path.exists():
            raise RepoExistsError(f"Repository already exists at {repo_path}")

        logger.info(f"Cloning {url} to {repo_path}")

        # Create directory structure
        repo_path.mkdir(parents=True, exist_ok=True)

        try:
            # Step 1: git clone --bare
            self._run_bare_clone(url, bare_path)

            # Step 2: Create .git pointer file
            self._create_git_pointer(repo_path)

            # Step 3: Detect default branch
            default_branch = get_default_branch(str(bare_path))
            logger.info(f"Default branch: {default_branch}")

            # Step 4: Create main worktree
            main_path = repo_path / default_branch
            self._create_worktree(bare_path, main_path, default_branch)

            # Create BareRepository object
            return BareRepository(
                account=target_account,
                name=repo_name,
                path=str(repo_path),
                remote_url=url,
                default_branch=default_branch,
                worktrees=[
                    Worktree(
                        branch=default_branch,
                        path=str(main_path),
                        is_main=True
                    )
                ],
                discovered_at=datetime.utcnow()
            )

        except Exception as e:
            # Clean up on failure
            logger.error(f"Clone failed: {e}")
            if repo_path.exists():
                import shutil
                shutil.rmtree(repo_path, ignore_errors=True)
            raise CloneError(f"Clone failed: {e}")

    def _get_account_config(self, account_name: str) -> Optional[AccountConfig]:
        """Get account config by name."""
        if self.accounts_storage:
            return self.accounts_storage.get_account_by_name(account_name)
        return None

    def _run_bare_clone(self, url: str, bare_path: Path) -> None:
        """Run git clone --bare."""
        result = subprocess.run(
            ["git", "clone", "--bare", url, str(bare_path)],
            capture_output=True,
            text=True,
            timeout=120
        )
        if result.returncode != 0:
            raise CloneError(f"git clone --bare failed: {result.stderr}")

    def _create_git_pointer(self, repo_path: Path) -> None:
        """Create .git pointer file."""
        git_pointer = repo_path / ".git"
        git_pointer.write_text("gitdir: ./.bare\n")
        logger.debug(f"Created .git pointer at {git_pointer}")

    def _create_worktree(
        self,
        bare_path: Path,
        worktree_path: Path,
        branch: str
    ) -> None:
        """Create a worktree."""
        result = subprocess.run(
            ["git", "-C", str(bare_path), "worktree", "add", str(worktree_path), branch],
            capture_output=True,
            text=True,
            timeout=30
        )
        if result.returncode != 0:
            raise CloneError(f"git worktree add failed: {result.stderr}")
        logger.debug(f"Created worktree at {worktree_path}")
