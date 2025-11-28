"""
Worktree environment variable model.
Feature 079: Preview Pane User Experience - US8 (T058-T059)
Feature 098: Worktree-Aware Project Environment Integration

Provides environment variables for worktree metadata injection into app launches.
"""

from __future__ import annotations
from typing import Dict, Optional, TYPE_CHECKING
from pydantic import BaseModel

if TYPE_CHECKING:
    from .project import Project
    from .discovery import SourceType


class WorktreeEnvironment(BaseModel):
    """Worktree metadata for environment variable injection (T058).

    Attributes:
        is_worktree: Whether this project is a git worktree
        parent_project: Name of parent project (if worktree)
        branch_type: Type of branch (feature, fix, etc.)
        branch_number: Numeric prefix from branch name (e.g., "079")
        full_branch_name: Complete branch name
    """

    is_worktree: bool
    parent_project: Optional[str] = None
    branch_type: Optional[str] = None
    branch_number: Optional[str] = None
    full_branch_name: Optional[str] = None

    def to_env_dict(self) -> Dict[str, str]:
        """Convert to environment variable dictionary (T059).

        Returns:
            Dictionary of environment variables with string values.
            Only includes non-None optional fields.

        Note:
            - Boolean values are converted to lowercase strings ("true"/"false")
            - None values are excluded from the dictionary
            - All values are strings for shell environment compatibility
        """
        env = {
            "I3PM_IS_WORKTREE": "true" if self.is_worktree else "false",
        }

        # Add optional fields only if present
        if self.parent_project is not None:
            env["I3PM_PARENT_PROJECT"] = self.parent_project

        if self.branch_type is not None:
            env["I3PM_BRANCH_TYPE"] = self.branch_type

        if self.branch_number is not None:
            env["I3PM_BRANCH_NUMBER"] = self.branch_number

        if self.full_branch_name is not None:
            env["I3PM_FULL_BRANCH_NAME"] = self.full_branch_name

        return env

    @classmethod
    def from_project(cls, project: "Project") -> "WorktreeEnvironment":
        """Create WorktreeEnvironment from a Project entity.

        Feature 098: Factory method to create worktree environment from
        persisted project data, enabling zero-runtime branch parsing.

        Args:
            project: Project with optional branch_metadata and parent_project

        Returns:
            WorktreeEnvironment ready for to_env_dict()
        """
        # Import here to avoid circular dependency
        from .discovery import SourceType

        is_worktree = project.source_type == SourceType.WORKTREE

        branch_metadata = project.branch_metadata
        branch_type = branch_metadata.type if branch_metadata else None
        branch_number = branch_metadata.number if branch_metadata else None
        full_branch_name = branch_metadata.full_name if branch_metadata else None

        return cls(
            is_worktree=is_worktree,
            parent_project=project.parent_project,
            branch_type=branch_type,
            branch_number=branch_number,
            full_branch_name=full_branch_name
        )
