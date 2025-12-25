"""Repos.json loader service with caching.

Feature 101: Centralized loading of repos.json with in-memory caching
to eliminate duplicate file reads across the daemon.
"""

import json
import logging
import time
from pathlib import Path
from typing import Dict, List, Optional, Any

from pydantic import BaseModel, Field, ValidationError

from .constants import ConfigPaths
from .worktree_utils import parse_qualified_name, ParsedQualifiedName, validate_worktree_path

logger = logging.getLogger(__name__)


# Feature 137: Pydantic models for repos.json schema validation
class WorktreeEntry(BaseModel):
    """Schema for a worktree entry in repos.json."""
    branch: str = Field(..., description="Git branch name")
    path: str = Field(..., description="Filesystem path to worktree")
    is_bare: bool = Field(default=False, description="Whether this is a bare repository")
    is_main_worktree: bool = Field(default=False, description="Whether this is the main worktree")


class RepositoryEntry(BaseModel):
    """Schema for a repository entry in repos.json."""
    account: str = Field(..., description="Git account/organization name")
    name: str = Field(..., description="Repository name")
    path: str = Field(..., description="Filesystem path to repository")
    worktrees: List[WorktreeEntry] = Field(default_factory=list, description="List of worktrees")
    remote_url: Optional[str] = Field(default=None, description="Git remote URL")


class ReposConfig(BaseModel):
    """Schema for repos.json root object."""
    version: str = Field(default="1.0", description="Schema version")
    repositories: List[RepositoryEntry] = Field(..., description="List of repositories")
    last_updated: Optional[str] = Field(default=None, description="Last update timestamp")


class ReposLoaderError(Exception):
    """Base exception for repos loader errors."""
    pass


class ReposNotFoundError(ReposLoaderError):
    """Raised when repos.json doesn't exist."""
    pass


class ReposParseError(ReposLoaderError):
    """Raised when repos.json is malformed."""
    pass


class ReposLoader:
    """Load and cache repos.json with TTL.

    This class provides cached access to repos.json, reducing disk I/O
    when multiple components need to query repository/worktree data.

    Usage:
        loader = ReposLoader.get_instance()
        repos = await loader.load()
        worktree = loader.find_worktree("vpittamp/nixos-config:main")
    """

    _instance: Optional["ReposLoader"] = None
    _cache: Optional[Dict[str, Any]] = None
    _cache_time: Optional[float] = None
    _cache_ttl_seconds: float = 5.0  # Cache valid for 5 seconds

    def __init__(self):
        """Initialize repos loader."""
        self._cache = None
        self._cache_time = None

    @classmethod
    def get_instance(cls) -> "ReposLoader":
        """Get singleton instance of ReposLoader."""
        if cls._instance is None:
            cls._instance = cls()
        return cls._instance

    @classmethod
    def invalidate_cache(cls) -> None:
        """Invalidate the cached repos data.

        Call this after modifying repos.json to force a reload.
        """
        if cls._instance:
            cls._instance._cache = None
            cls._instance._cache_time = None
            logger.debug("[Feature 101] Repos cache invalidated")

    def load(self, force_refresh: bool = False) -> Dict[str, Any]:
        """Load repos.json with in-memory caching.

        Args:
            force_refresh: If True, bypass cache and reload from disk

        Returns:
            Dict containing repos.json data with 'repositories' key

        Raises:
            ReposNotFoundError: If repos.json doesn't exist
            ReposParseError: If repos.json is malformed

        Example:
            >>> loader = ReposLoader.get_instance()
            >>> data = loader.load()
            >>> len(data["repositories"])
            2
        """
        current_time = time.time()

        # Check cache validity
        if (
            not force_refresh
            and self._cache is not None
            and self._cache_time is not None
            and (current_time - self._cache_time) < self._cache_ttl_seconds
        ):
            logger.debug("[Feature 101] Returning cached repos data")
            return self._cache

        # Load from disk
        repos_file = ConfigPaths.REPOS_FILE

        if not repos_file.exists():
            raise ReposNotFoundError(
                f"repos.json not found at {repos_file}. "
                f"Run 'i3pm discover' to scan for repositories."
            )

        try:
            with open(repos_file) as f:
                data = json.load(f)
        except json.JSONDecodeError as e:
            raise ReposParseError(
                f"repos.json is malformed at line {e.lineno}: {e.msg}"
            )

        # Feature 137: Validate with Pydantic for better error messages
        try:
            validated = ReposConfig.model_validate(data)
            # Convert back to dict for compatibility with existing code
            data = validated.model_dump(mode='json')
        except ValidationError as e:
            # Format validation errors for readability
            error_msgs = []
            for error in e.errors():
                loc = ".".join(str(x) for x in error["loc"])
                error_msgs.append(f"  - {loc}: {error['msg']}")
            raise ReposParseError(
                f"repos.json schema validation failed:\n" + "\n".join(error_msgs)
            )

        # Update cache
        self._cache = data
        self._cache_time = current_time
        logger.debug(
            f"[Feature 101] Loaded repos.json: "
            f"{len(data['repositories'])} repositories"
        )

        return data

    def get_repositories(self, force_refresh: bool = False) -> List[Dict[str, Any]]:
        """Get list of repositories.

        Args:
            force_refresh: If True, bypass cache

        Returns:
            List of repository dicts
        """
        data = self.load(force_refresh)
        return data.get("repositories", [])

    def find_repository(
        self, repo_qualified_name: str, force_refresh: bool = False
    ) -> Optional[Dict[str, Any]]:
        """Find a repository by qualified name (account/repo).

        Args:
            repo_qualified_name: Repository qualified name (e.g., "vpittamp/nixos-config")
            force_refresh: If True, bypass cache

        Returns:
            Repository dict or None if not found
        """
        repos = self.get_repositories(force_refresh)

        for repo in repos:
            account = repo.get("account", "")
            name = repo.get("name", "")
            qualified = f"{account}/{name}"

            if qualified == repo_qualified_name:
                return repo

        return None

    def find_worktree(
        self, qualified_name: str, force_refresh: bool = False
    ) -> Optional[Dict[str, Any]]:
        """Find a worktree by full qualified name (account/repo:branch).

        Args:
            qualified_name: Full qualified name (e.g., "vpittamp/nixos-config:main")
            force_refresh: If True, bypass cache

        Returns:
            Worktree dict or None if not found

        Example:
            >>> loader = ReposLoader.get_instance()
            >>> wt = loader.find_worktree("vpittamp/nixos-config:main")
            >>> wt["path"]
            '/home/user/repos/vpittamp/nixos-config/main'
        """
        try:
            parsed = parse_qualified_name(qualified_name)
        except ValueError as e:
            logger.warning(f"[Feature 101] Invalid qualified name: {e}")
            return None

        repo = self.find_repository(parsed.repo_qualified_name, force_refresh)
        if not repo:
            return None

        worktrees = repo.get("worktrees", [])
        for wt in worktrees:
            if wt.get("branch") == parsed.branch:
                return wt

        return None

    def get_worktree_path(
        self, qualified_name: str, force_refresh: bool = False
    ) -> Optional[Path]:
        """Get the filesystem path for a worktree.

        Args:
            qualified_name: Full qualified name (e.g., "vpittamp/nixos-config:main")
            force_refresh: If True, bypass cache

        Returns:
            Path to worktree directory, or None if not found
        """
        wt = self.find_worktree(qualified_name, force_refresh)
        if wt and wt.get("path"):
            path = Path(wt["path"])
            if path.exists():
                return path
        return None

    def list_all_worktrees(
        self, force_refresh: bool = False
    ) -> List[Dict[str, Any]]:
        """List all worktrees across all repositories.

        Returns:
            List of dicts with worktree info including qualified_name

        Example:
            >>> loader = ReposLoader.get_instance()
            >>> for wt in loader.list_all_worktrees():
            ...     print(wt["qualified_name"])
            vpittamp/nixos-config:main
            vpittamp/nixos-config:feature-branch
        """
        result = []
        repos = self.get_repositories(force_refresh)

        for repo in repos:
            account = repo.get("account", "")
            repo_name = repo.get("name", "")
            repo_qualified = f"{account}/{repo_name}"

            for wt in repo.get("worktrees", []):
                branch = wt.get("branch", "")
                qualified_name = f"{repo_qualified}:{branch}"

                # Add computed fields
                wt_info = {
                    **wt,
                    "qualified_name": qualified_name,
                    "repo_qualified_name": repo_qualified,
                    "account": account,
                    "repo_name": repo_name,
                }

                # Add path validation status
                is_valid, status = validate_worktree_path(wt.get("path"))
                wt_info["status"] = status

                result.append(wt_info)

        return result

    def get_worktrees_for_repo(
        self, repo_qualified_name: str, force_refresh: bool = False
    ) -> List[Dict[str, Any]]:
        """Get all worktrees for a specific repository.

        Args:
            repo_qualified_name: Repository qualified name (e.g., "vpittamp/nixos-config")
            force_refresh: If True, bypass cache

        Returns:
            List of worktree dicts with computed fields
        """
        repo = self.find_repository(repo_qualified_name, force_refresh)
        if not repo:
            return []

        account = repo.get("account", "")
        repo_name = repo.get("name", "")
        result = []

        for wt in repo.get("worktrees", []):
            branch = wt.get("branch", "")
            qualified_name = f"{repo_qualified_name}:{branch}"

            wt_info = {
                **wt,
                "qualified_name": qualified_name,
                "repo_qualified_name": repo_qualified_name,
                "account": account,
                "repo_name": repo_name,
            }

            is_valid, status = validate_worktree_path(wt.get("path"))
            wt_info["status"] = status

            result.append(wt_info)

        return result


# Convenience functions for direct use without instantiating

def load_repos(force_refresh: bool = False) -> Dict[str, Any]:
    """Load repos.json data.

    Convenience function that uses the singleton loader.
    """
    return ReposLoader.get_instance().load(force_refresh)


def find_worktree(qualified_name: str) -> Optional[Dict[str, Any]]:
    """Find a worktree by qualified name.

    Convenience function that uses the singleton loader.
    """
    return ReposLoader.get_instance().find_worktree(qualified_name)


def get_worktree_path(qualified_name: str) -> Optional[Path]:
    """Get path for a worktree.

    Convenience function that uses the singleton loader.
    """
    return ReposLoader.get_instance().get_worktree_path(qualified_name)


def invalidate_repos_cache() -> None:
    """Invalidate the repos cache.

    Call after modifying repos.json.
    """
    ReposLoader.invalidate_cache()
