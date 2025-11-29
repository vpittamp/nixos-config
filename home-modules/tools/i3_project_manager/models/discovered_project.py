"""
Feature 100: DiscoveredProject - Unified View for UI Display

Flattened view of repositories and worktrees for monitoring panel integration.
"""

from pydantic import BaseModel, Field, computed_field
from enum import Enum
from typing import Optional, TYPE_CHECKING

if TYPE_CHECKING:
    from .bare_repo import BareRepository
    from .worktree import Worktree


class ProjectType(str, Enum):
    """Type of discovered project."""
    REPOSITORY = "repository"
    WORKTREE = "worktree"


class GitStatus(BaseModel):
    """Git status information for display."""
    commit: Optional[str] = Field(default=None, description="Short commit hash")
    is_clean: bool = Field(default=True, description="No uncommitted changes")
    ahead: int = Field(default=0, description="Commits ahead of remote")
    behind: int = Field(default=0, description="Commits behind remote")

    @computed_field
    @property
    def dirty_indicator(self) -> str:
        """Return '●' if dirty, empty otherwise."""
        return "●" if not self.is_clean else ""

    @computed_field
    @property
    def sync_indicator(self) -> str:
        """Return '↑3 ↓2' format."""
        parts = []
        if self.ahead > 0:
            parts.append(f"↑{self.ahead}")
        if self.behind > 0:
            parts.append(f"↓{self.behind}")
        return " ".join(parts)


class DiscoveredProject(BaseModel):
    """
    Unified view for UI display - represents either a repository or a worktree.

    This model provides a consistent interface for the monitoring panel,
    abstracting the difference between repository projects and worktree projects.

    Fields:
        id: Unique identifier (qualified name)
        account: GitHub account name
        repo_name: Repository name
        branch: Branch name (null for repo-level)
        type: "repository" or "worktree"
        path: Working directory path
        display_name: Human-readable name
        icon: Display icon
        is_active: Currently active project
        git_status: Git metadata
        parent_id: Parent repository ID (for worktrees)
    """
    id: str = Field(..., description="Unique identifier (qualified name)")
    account: str = Field(..., description="GitHub account name")
    repo_name: str = Field(..., description="Repository name")
    branch: Optional[str] = Field(default=None, description="Branch name (null for repo)")
    type: ProjectType = Field(..., description="repository or worktree")
    path: str = Field(..., description="Working directory path")
    display_name: str = Field(..., description="Human-readable name")
    icon: str = Field(default="📦", description="Display icon")
    is_active: bool = Field(default=False, description="Currently active project")
    git_status: Optional[GitStatus] = Field(default=None, description="Git metadata")
    parent_id: Optional[str] = Field(default=None, description="Parent repository ID")

    @classmethod
    def from_repository(
        cls,
        repo: "BareRepository",
        is_active: bool = False
    ) -> "DiscoveredProject":
        """Create from a BareRepository."""
        return cls(
            id=repo.qualified_name,
            account=repo.account,
            repo_name=repo.name,
            type=ProjectType.REPOSITORY,
            path=repo.path,
            display_name=repo.name,
            icon="📦",
            is_active=is_active,
        )

    @classmethod
    def from_worktree(
        cls,
        repo: "BareRepository",
        wt: "Worktree",
        is_active: bool = False
    ) -> "DiscoveredProject":
        """Create from a Worktree linked to a BareRepository."""
        return cls(
            id=f"{repo.qualified_name}:{wt.branch}",
            account=repo.account,
            repo_name=repo.name,
            branch=wt.branch,
            type=ProjectType.WORKTREE,
            path=wt.path,
            display_name=wt.display_name,
            icon="🌿",
            parent_id=repo.qualified_name,
            is_active=is_active,
            git_status=GitStatus(
                commit=wt.commit,
                is_clean=wt.is_clean if wt.is_clean is not None else True,
                ahead=wt.ahead,
                behind=wt.behind,
            ),
        )
