"""
Feature 100: Worktree - Git Worktree Model

Working directory linked to a bare repository.
"""

from pydantic import BaseModel, Field, computed_field
import re
from typing import Optional


class Worktree(BaseModel):
    """
    Git worktree linked to a bare repository.

    A Worktree represents a working directory created via `git worktree add`.
    Each worktree has its own checked-out branch but shares the git database
    with the parent bare repository.

    Fields:
        branch: Branch name (e.g., "main", "100-feature")
        path: Full path to worktree directory
        commit: Current commit hash (short, 7 chars)
        is_clean: No uncommitted changes
        ahead: Commits ahead of remote
        behind: Commits behind remote
        is_main: Is this the main/master worktree
    """
    branch: str = Field(..., description="Branch name")
    path: str = Field(..., description="Full path to worktree directory")
    commit: Optional[str] = Field(
        default=None,
        description="Current commit hash (short)"
    )
    is_clean: Optional[bool] = Field(
        default=None,
        description="No uncommitted changes"
    )
    ahead: int = Field(default=0, description="Commits ahead of remote")
    behind: int = Field(default=0, description="Commits behind remote")
    is_main: bool = Field(default=False, description="Is main/master worktree")

    # Feature 108: Enhanced status fields
    is_merged: bool = Field(default=False, description="Branch merged into main")
    is_stale: bool = Field(default=False, description="No commits in 30+ days")
    has_conflicts: bool = Field(default=False, description="Has unresolved merge conflicts")
    staged_count: int = Field(default=0, description="Number of staged files")
    modified_count: int = Field(default=0, description="Number of modified files")
    untracked_count: int = Field(default=0, description="Number of untracked files")
    last_commit_timestamp: int = Field(default=0, description="Unix timestamp of last commit")
    last_commit_message: str = Field(default="", description="Last commit message (truncated)")

    @computed_field
    @property
    def display_name(self) -> str:
        """
        Human-readable display name.

        Extracts feature number if present: "100-feature" → "100 - Feature"
        """
        match = re.match(r'^(\d+)-(.+)$', self.branch)
        if match:
            number = match.group(1)
            rest = match.group(2).replace('-', ' ').title()
            return f"{number} - {rest}"
        return self.branch

    @computed_field
    @property
    def feature_number(self) -> Optional[int]:
        """
        Extract feature number from branch name.

        Returns None if branch doesn't follow feature-number pattern.
        """
        match = re.match(r'^(\d+)-', self.branch)
        return int(match.group(1)) if match else None

    @computed_field
    @property
    def dirty_indicator(self) -> str:
        """Return '●' if dirty, empty otherwise."""
        if self.is_clean is False:
            return "●"
        return ""

    @computed_field
    @property
    def sync_indicator(self) -> str:
        """Return '↑3 ↓2' format for ahead/behind."""
        parts = []
        if self.ahead > 0:
            parts.append(f"↑{self.ahead}")
        if self.behind > 0:
            parts.append(f"↓{self.behind}")
        return " ".join(parts)
