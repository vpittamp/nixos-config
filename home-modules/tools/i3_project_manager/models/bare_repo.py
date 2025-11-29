"""
Feature 100: BareRepository - Bare Clone Repository Model

Repository stored as bare clone with .bare/ structure.
Directory layout:
  ~/repos/<account>/<repo>/
  ├── .bare/     # Bare git database
  ├── .git       # Pointer file: "gitdir: ./.bare"
  ├── main/      # Worktree for main branch
  └── feature/   # Additional worktrees
"""

from pydantic import BaseModel, Field, computed_field
from pathlib import Path
from datetime import datetime
from typing import Optional

from .worktree import Worktree


class BareRepository(BaseModel):
    """
    Repository stored as bare clone with .bare/ structure.

    A BareRepository represents a git repository stored using the bare clone pattern:
    - .bare/ directory contains the git database
    - .git file points to .bare/
    - All working directories (including main) are worktrees

    Fields:
        account: GitHub account name owning this repo
        name: Repository name (e.g., "nixos")
        path: Full path to repo container directory
        remote_url: Git remote origin URL
        default_branch: Default branch name (main/master)
        worktrees: List of associated worktrees
        discovered_at: When repository was discovered
        last_scanned: Last metadata refresh
    """
    account: str = Field(..., description="Owning GitHub account name")
    name: str = Field(..., description="Repository name")
    path: str = Field(..., description="Full path to repo container directory")
    remote_url: str = Field(..., description="Git remote origin URL")
    default_branch: str = Field(default="main", description="Default branch name")
    worktrees: list[Worktree] = Field(
        default_factory=list,
        description="Associated worktrees"
    )
    discovered_at: datetime = Field(
        default_factory=datetime.utcnow,
        description="When repository was discovered"
    )
    last_scanned: Optional[datetime] = Field(
        default=None,
        description="Last metadata refresh"
    )

    @computed_field
    @property
    def qualified_name(self) -> str:
        """Full qualified name: account/repo."""
        return f"{self.account}/{self.name}"

    @computed_field
    @property
    def bare_path(self) -> str:
        """Path to .bare/ directory."""
        return str(Path(self.path) / ".bare")

    @computed_field
    @property
    def git_pointer_path(self) -> str:
        """Path to .git pointer file."""
        return str(Path(self.path) / ".git")

    @property
    def main_worktree(self) -> Optional[Worktree]:
        """Get the main/default branch worktree."""
        for wt in self.worktrees:
            if wt.is_main:
                return wt
        # Fallback: find worktree matching default_branch
        for wt in self.worktrees:
            if wt.branch == self.default_branch:
                return wt
        return None

    def get_worktree_by_branch(self, branch: str) -> Optional[Worktree]:
        """Find a worktree by branch name."""
        for wt in self.worktrees:
            if wt.branch == branch:
                return wt
        return None

    def add_worktree(self, worktree: Worktree) -> None:
        """Add a worktree to this repository."""
        # Check for duplicate branch
        if self.get_worktree_by_branch(worktree.branch):
            raise ValueError(f"Worktree for branch '{worktree.branch}' already exists")
        self.worktrees.append(worktree)


class RepositoriesStorage(BaseModel):
    """
    Storage schema for repos.json.

    Location: ~/.config/i3/repos.json
    """
    version: int = Field(default=1, description="Schema version")
    last_discovery: Optional[datetime] = Field(
        default=None,
        description="Last discovery run timestamp"
    )
    repositories: list[BareRepository] = Field(
        default_factory=list,
        description="Discovered repositories"
    )

    def get_by_qualified_name(self, qualified_name: str) -> Optional[BareRepository]:
        """Find repository by qualified name (account/repo)."""
        for repo in self.repositories:
            if repo.qualified_name == qualified_name:
                return repo
        return None

    def get_by_account(self, account: str) -> list[BareRepository]:
        """Get all repositories for an account."""
        return [repo for repo in self.repositories if repo.account == account]

    def add_repository(self, repo: BareRepository) -> None:
        """Add a repository, preventing duplicates."""
        if self.get_by_qualified_name(repo.qualified_name):
            raise ValueError(f"Repository '{repo.qualified_name}' already exists")
        self.repositories.append(repo)

    def update_repository(self, repo: BareRepository) -> None:
        """Update an existing repository or add if not found."""
        for i, existing in enumerate(self.repositories):
            if existing.qualified_name == repo.qualified_name:
                self.repositories[i] = repo
                return
        self.repositories.append(repo)
