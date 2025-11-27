"""
Discovery models for Feature 097: Git-Based Project Discovery and Management.

Provides Pydantic models for:
- Git metadata extraction
- Repository and worktree discovery
- Scan configuration
- Discovery results

Per Constitution Principle X: Python 3.11+, Pydantic for validation.
"""

from datetime import datetime
from enum import Enum
from pathlib import Path
from typing import Optional, List
from pydantic import BaseModel, Field, field_validator


class SourceType(str, Enum):
    """Classification of how a project was discovered.

    Feature 097: All projects must be discovered - no manual creation.
    """
    LOCAL = "local"      # Standard git repository discovered on filesystem
    WORKTREE = "worktree"  # Git worktree linked to parent repository
    REMOTE = "remote"    # GitHub repository not cloned locally (listing only)


class ProjectStatus(str, Enum):
    """Current availability status of a project."""
    ACTIVE = "active"    # Directory exists and is accessible
    MISSING = "missing"  # Directory no longer exists or inaccessible


class GitMetadata(BaseModel):
    """Git-specific metadata attached to discovered projects."""

    current_branch: str = Field(
        ...,
        description="Branch name or 'HEAD' if detached"
    )
    commit_hash: str = Field(
        ...,
        min_length=7,
        max_length=7,
        description="Short SHA (7 characters)"
    )
    is_clean: bool = Field(
        ...,
        description="No uncommitted changes"
    )
    has_untracked: bool = Field(
        ...,
        description="Untracked files present"
    )
    ahead_count: int = Field(
        default=0,
        ge=0,
        description="Commits ahead of upstream"
    )
    behind_count: int = Field(
        default=0,
        ge=0,
        description="Commits behind upstream"
    )
    remote_url: Optional[str] = Field(
        default=None,
        description="Origin remote URL"
    )
    primary_language: Optional[str] = Field(
        default=None,
        description="Dominant programming language"
    )
    last_commit_date: Optional[datetime] = Field(
        default=None,
        description="Most recent commit timestamp"
    )

    @field_validator('commit_hash', mode='before')
    @classmethod
    def validate_commit_hash(cls, v: str) -> str:
        """Allow empty string for repos with no commits."""
        if v == "" or v is None:
            return "0000000"  # Placeholder for empty repos
        return v[:7] if len(v) > 7 else v


class ScanConfiguration(BaseModel):
    """User-defined settings for repository discovery."""

    scan_paths: List[str] = Field(
        min_length=1,
        description="Directories to scan for repositories"
    )
    exclude_patterns: List[str] = Field(
        default_factory=lambda: ["node_modules", "vendor", ".cache"],
        description="Directory names to skip"
    )
    auto_discover_on_startup: bool = Field(
        default=False,
        description="Run discovery when daemon starts"
    )
    max_depth: int = Field(
        default=3,
        ge=1,
        le=10,
        description="Maximum recursion depth for scanning"
    )

    @field_validator('scan_paths', mode='before')
    @classmethod
    def expand_paths(cls, v: List[str]) -> List[str]:
        """Expand ~ and resolve to absolute paths."""
        return [str(Path(p).expanduser().resolve()) for p in v]


class DiscoveredRepository(BaseModel):
    """Intermediate representation of a found repository before project creation."""

    path: str = Field(
        ...,
        description="Absolute path to repository"
    )
    name: str = Field(
        ...,
        description="Derived from directory name"
    )
    is_worktree: bool = Field(
        ...,
        description="True if .git is a file"
    )
    git_metadata: GitMetadata = Field(
        ...,
        description="Extracted git data"
    )
    parent_repo_path: Optional[str] = Field(
        default=None,
        description="For worktrees, path to main repo"
    )
    inferred_icon: str = Field(
        default="📁",
        description="Emoji based on language"
    )


class DiscoveredWorktree(DiscoveredRepository):
    """Worktree-specific discovery result with guaranteed parent reference."""

    is_worktree: bool = Field(
        default=True,
        description="Always True for worktrees"
    )
    parent_repo_path: str = Field(
        ...,
        description="Path to main repository (required for worktrees)"
    )
    inferred_icon: str = Field(
        default="🌿",
        description="Worktree icon"
    )


class SkippedPath(BaseModel):
    """Path that was skipped during discovery with reason."""

    path: str = Field(
        ...,
        description="Absolute path that was skipped"
    )
    reason: str = Field(
        ...,
        description="Reason for skipping (e.g., 'no_git_directory', 'excluded_pattern')"
    )


class DiscoveryError(BaseModel):
    """Non-fatal error encountered during discovery."""

    path: Optional[str] = Field(
        default=None,
        description="Path where error occurred (if applicable)"
    )
    source: Optional[str] = Field(
        default=None,
        description="Error source (e.g., 'github', 'filesystem')"
    )
    error: str = Field(
        ...,
        description="Error code (e.g., 'git_metadata_extraction_failed')"
    )
    message: str = Field(
        ...,
        description="Human-readable error message"
    )


class DiscoveryResult(BaseModel):
    """Ephemeral result returned from a discovery operation."""

    success: bool = Field(
        default=True,
        description="Overall success status"
    )
    discovered_repos: List[DiscoveredRepository] = Field(
        default_factory=list,
        description="Repositories found"
    )
    discovered_worktrees: List[DiscoveredWorktree] = Field(
        default_factory=list,
        description="Worktrees found"
    )
    skipped_paths: List[SkippedPath] = Field(
        default_factory=list,
        description="Paths skipped (not git repos)"
    )
    projects_created: int = Field(
        default=0,
        description="Count of new projects"
    )
    projects_updated: int = Field(
        default=0,
        description="Count of updated projects"
    )
    projects_marked_missing: int = Field(
        default=0,
        description="Count of newly missing projects"
    )
    duration_ms: int = Field(
        default=0,
        description="Time taken in milliseconds"
    )
    errors: List[DiscoveryError] = Field(
        default_factory=list,
        description="Non-fatal errors encountered"
    )


class GitHubRepo(BaseModel):
    """GitHub repository information from gh CLI."""

    name: str = Field(
        ...,
        description="Repository name"
    )
    full_name: str = Field(
        ...,
        description="Full name (owner/repo)"
    )
    description: Optional[str] = Field(
        default=None,
        description="Repository description"
    )
    primary_language: Optional[str] = Field(
        default=None,
        description="Primary programming language"
    )
    pushed_at: Optional[datetime] = Field(
        default=None,
        description="Last push timestamp"
    )
    visibility: str = Field(
        default="public",
        description="Repository visibility (public/private)"
    )
    is_private: bool = Field(
        default=False,
        description="Whether repository is private"
    )
    is_fork: bool = Field(
        default=False,
        description="Whether repository is a fork"
    )
    is_archived: bool = Field(
        default=False,
        description="Whether repository is archived"
    )
    clone_url: str = Field(
        ...,
        description="HTTPS clone URL"
    )
    ssh_url: Optional[str] = Field(
        default=None,
        description="SSH clone URL"
    )
    has_local_clone: bool = Field(
        default=False,
        description="Whether repository exists locally"
    )
    local_project_name: Optional[str] = Field(
        default=None,
        description="Name of local project if cloned"
    )

    @classmethod
    def from_gh_json(cls, data: dict) -> "GitHubRepo":
        """Create GitHubRepo from gh CLI JSON output.

        Feature 097: Parse gh repo list output format.

        Args:
            data: Dictionary from gh CLI JSON output

        Returns:
            GitHubRepo instance
        """
        # Extract primary language from nested structure
        primary_language = None
        if data.get("primaryLanguage"):
            primary_language = data["primaryLanguage"].get("name")

        # Parse pushed_at timestamp
        pushed_at = None
        if data.get("pushedAt"):
            try:
                pushed_at = datetime.fromisoformat(data["pushedAt"].replace("Z", "+00:00"))
            except (ValueError, TypeError):
                pass

        return cls(
            name=data["name"],
            full_name=data["nameWithOwner"],
            description=data.get("description"),
            primary_language=primary_language,
            pushed_at=pushed_at,
            visibility="private" if data.get("isPrivate") else "public",
            is_private=data.get("isPrivate", False),
            is_fork=data.get("isFork", False),
            is_archived=data.get("isArchived", False),
            clone_url=data.get("url", ""),
            ssh_url=data.get("sshUrl"),
        )


class GitHubListResult(BaseModel):
    """Result of listing GitHub repositories."""

    success: bool = Field(
        default=True,
        description="Whether the listing succeeded"
    )
    repos: List[GitHubRepo] = Field(
        default_factory=list,
        description="GitHub repositories"
    )
    total_count: int = Field(
        default=0,
        description="Total number of repositories"
    )
    errors: List[DiscoveryError] = Field(
        default_factory=list,
        description="Errors encountered"
    )


class CorrelationResult(BaseModel):
    """Result of correlating local and remote repositories.

    Feature 097: Identifies which GitHub repos are cloned locally
    and which are remote-only.
    """

    cloned: List[GitHubRepo] = Field(
        default_factory=list,
        description="GitHub repos that have local clones (has_local_clone=True)"
    )
    remote_only: List[GitHubRepo] = Field(
        default_factory=list,
        description="GitHub repos without local clones"
    )
