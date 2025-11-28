"""
Project Configuration Data Models

Feature 094: Enhanced Projects & Applications CRUD Interface
Feature 097: Git-Centric Project and Worktree Management
Storage: ~/.config/i3/projects/*.json
"""

from datetime import datetime
from enum import Enum
from pathlib import Path
from typing import Optional, Literal, List
from pydantic import BaseModel, Field, field_validator, model_validator
import re
import os


# ============================================================================
# Feature 097: Source Type and Status Enums
# ============================================================================

class SourceType(str, Enum):
    """
    Classification of project type (Feature 097).

    - repository: Primary entry point for a bare repo (ONE per bare_repo_path)
    - worktree: Git worktree linked to a Repository Project
    - standalone: Non-git directory OR simple repo with no worktrees
    """
    REPOSITORY = "repository"
    WORKTREE = "worktree"
    STANDALONE = "standalone"


class ProjectStatus(str, Enum):
    """
    Current availability status (Feature 097).

    - active: Directory exists and is accessible
    - missing: Directory no longer exists or inaccessible
    - orphaned: Worktree with no matching Repository Project (bare_repo_path mismatch)
    """
    ACTIVE = "active"
    MISSING = "missing"
    ORPHANED = "orphaned"


# ============================================================================
# Feature 097: Git Metadata
# ============================================================================

class GitMetadata(BaseModel):
    """
    Cached git state attached to projects (Feature 097).

    This is populated by git commands and cached in the project JSON.
    """
    current_branch: str = Field(..., description="Branch name or 'HEAD' if detached")
    commit_hash: str = Field(..., min_length=7, max_length=7, description="Short SHA (7 characters)")
    is_clean: bool = Field(..., description="No uncommitted changes")
    has_untracked: bool = Field(..., description="Untracked files present")
    ahead_count: int = Field(default=0, ge=0, description="Commits ahead of upstream")
    behind_count: int = Field(default=0, ge=0, description="Commits behind upstream")
    remote_url: Optional[str] = Field(default=None, description="Origin remote URL")
    last_modified: Optional[datetime] = Field(default=None, description="Most recent file modification")
    last_refreshed: Optional[datetime] = Field(default=None, description="When metadata was last updated")


class RemoteConfig(BaseModel):
    """Remote SSH configuration for remote projects"""
    enabled: bool = False
    host: str = Field(default="", description="SSH hostname or Tailscale FQDN")
    user: str = Field(default="", description="SSH username")
    remote_dir: str = Field(
        default="",
        alias="working_dir",  # Legacy field name compatibility
        description="Remote working directory (absolute path)"
    )
    port: int = Field(default=22, ge=1, le=65535, description="SSH port")

    model_config = {"populate_by_name": True}  # Accept both field name and alias

    @model_validator(mode="after")
    def validate_remote_fields_when_enabled(self) -> "RemoteConfig":
        """Only validate remote fields when enabled=True"""
        if self.enabled:
            if not self.host:
                raise ValueError("Host is required when remote is enabled")
            if not self.user:
                raise ValueError("User is required when remote is enabled")
            if not self.remote_dir:
                raise ValueError("Remote directory is required when remote is enabled")
            if not self.remote_dir.startswith("/"):
                raise ValueError(f"Remote directory must be absolute path, got: {self.remote_dir}")
        return self


class ProjectConfig(BaseModel):
    """
    Unified Project configuration model for i3pm projects (Feature 097).

    This is the single model for all project types: repository, worktree, standalone.
    The source_type field acts as the discriminator.

    Storage: ~/.config/i3/projects/<name>.json
    """
    name: str = Field(..., min_length=1, max_length=64, description="Unique project identifier")
    display_name: str = Field(..., min_length=1, description="Human-readable project name")
    icon: str = Field(default="📦", description="Emoji or file path for visual identification")
    working_dir: str = Field(
        ...,
        min_length=1,
        description="Absolute path to project directory",
        # Feature 094: Accept both "directory" (legacy) and "working_dir" (new) field names
        validation_alias="directory",
        serialization_alias="directory"
    )
    scope: Literal["scoped", "global"] = Field(default="scoped", description="Window hiding behavior")
    remote: Optional[RemoteConfig] = Field(default=None, description="Remote SSH configuration")

    # Feature 097: Git-centric project management fields
    source_type: SourceType = Field(
        default=SourceType.STANDALONE,
        description="Project type: repository (primary), worktree (linked), or standalone (non-git)"
    )
    status: ProjectStatus = Field(
        default=ProjectStatus.ACTIVE,
        description="Availability status: active, missing, or orphaned"
    )
    bare_repo_path: Optional[str] = Field(
        default=None,
        description="GIT_COMMON_DIR - canonical identifier for all worktrees of a repo"
    )
    parent_project: Optional[str] = Field(
        default=None,
        description="For worktrees: name of the parent Repository Project"
    )
    git_metadata: Optional[GitMetadata] = Field(
        default=None,
        description="Cached git state (branch, commit, clean status)"
    )
    scoped_classes: List[str] = Field(
        default_factory=list,
        description="App window classes scoped to this project"
    )
    created_at: Optional[datetime] = Field(
        default=None,
        description="When project was created"
    )
    updated_at: Optional[datetime] = Field(
        default=None,
        description="When project was last modified"
    )

    @field_validator("name")
    @classmethod
    def validate_name_format(cls, v: str) -> str:
        """Per spec.md FR-P-007: lowercase, hyphens only, no spaces"""
        if not v:
            raise ValueError("Project name cannot be empty")
        if not re.match(r'^[a-z0-9-]+$', v):
            raise ValueError("Project name must be lowercase alphanumeric with hyphens only (no spaces)")
        if v.startswith('-') or v.endswith('-'):
            raise ValueError("Project name cannot start or end with a hyphen")
        return v

    @field_validator("name")
    @classmethod
    def validate_name_uniqueness(cls, v: str, info) -> str:
        """Per spec.md Edge Case: Duplicate project names

        Feature 094: Skip uniqueness check when editing (edit_mode=True in context)
        """
        # Skip uniqueness check if in edit mode (context passed from edit_project())
        if info.context and info.context.get("edit_mode"):
            return v

        project_file = Path.home() / f".config/i3/projects/{v}.json"
        if project_file.exists():
            raise ValueError(f"Project '{v}' already exists")
        return v

    @field_validator("working_dir")
    @classmethod
    def validate_working_dir_exists(cls, v: str, info) -> str:
        """Per spec.md FR-P-008: Validate directory exists and is accessible

        Feature 097: Skip existence check when loading existing projects (edit_mode=True)
        Projects with missing directories get status=missing instead of failing validation.
        """
        # Skip validation in edit/load mode - missing dirs handled by status field
        if info.context and info.context.get("edit_mode"):
            return v

        path = Path(v).expanduser().resolve()
        if not path.exists():
            raise ValueError(f"Working directory does not exist: {v}")
        if not path.is_dir():
            raise ValueError(f"Path is not a directory: {v}")
        if not os.access(path, os.R_OK | os.W_OK):
            raise ValueError(f"Working directory not accessible (check permissions): {v}")
        return str(path)

    @field_validator("icon")
    @classmethod
    def validate_icon_format(cls, v: str) -> str:
        """Per spec.md Edge Case: Icon picker integration - emoji or file path"""
        # Allow emoji (1-4 characters) or absolute file path
        if len(v) <= 4:
            return v  # Assume emoji

        # If longer, must be file path
        if not v.startswith("/"):
            raise ValueError(f"Icon must be emoji or absolute file path, got: {v}")

        path = Path(v)
        if path.exists() and not path.is_file():
            raise ValueError(f"Icon path exists but is not a file: {v}")

        return v

    @model_validator(mode="after")
    def validate_worktree_has_parent(self) -> "ProjectConfig":
        """
        Feature 097 T005: Worktree projects MUST have parent_project set.

        This ensures data integrity for the hierarchy display.
        """
        if self.source_type == SourceType.WORKTREE and not self.parent_project:
            raise ValueError("Worktree projects must have parent_project set")
        return self

    model_config = {
        # Feature 094: Allow both "directory" (legacy) and "working_dir" (new) field names
        "populate_by_name": True,
        "json_schema_extra": {
            "examples": [
                {
                    "name": "nixos-094-feature",
                    "display_name": "NixOS Feature 094",
                    "icon": "📦",
                    "working_dir": "/home/vpittamp/nixos-094-enhance-project-tab",
                    "scope": "scoped",
                    "remote": None
                },
                {
                    "name": "hetzner-dev",
                    "display_name": "Hetzner Development",
                    "icon": "🌐",
                    "working_dir": "/home/vpittamp/projects/hetzner-dev",
                    "scope": "scoped",
                    "remote": {
                        "enabled": True,
                        "host": "hetzner-sway.tailnet",
                        "user": "vpittamp",
                        "remote_dir": "/home/vpittamp/dev/my-app",
                        "port": 22
                    }
                }
            ]
        }
    }


class WorktreeConfig(ProjectConfig):
    """
    Git worktree configuration (extends ProjectConfig)

    Storage: ~/.config/i3/projects/<name>.json (same as projects)
    Distinguished by presence of parent_project field
    """
    worktree_path: str = Field(..., min_length=1, description="Absolute path to worktree directory")
    branch_name: str = Field(..., min_length=1, description="Git branch name for this worktree")
    parent_project: str = Field(..., min_length=1, description="Name of main project this worktree belongs to")

    @field_validator("worktree_path")
    @classmethod
    def validate_worktree_path_not_exists(cls, v: str) -> str:
        """Per spec.md FR-P-018: Validate worktree path does not already exist"""
        path = Path(v).expanduser().resolve()
        if path.exists():
            raise ValueError(f"Worktree path already exists: {v}")
        return str(path)

    @field_validator("branch_name")
    @classmethod
    def validate_branch_name_format(cls, v: str) -> str:
        """Validate Git branch name format (no spaces, valid Git ref)"""
        # Allow alphanumeric, forward slashes, underscores, hyphens, and dots
        # Examples: main, feature-123, feat/new-feature, release/v1.0.0
        if not re.match(r'^[a-zA-Z0-9/_.-]+$', v):
            raise ValueError(f"Invalid Git branch name format: {v}")
        return v

    @model_validator(mode='after')
    def validate_parent_project_exists(self):
        """Per spec.md Edge Case: Worktree without parent"""
        parent_file = Path.home() / f".config/i3/projects/{self.parent_project}.json"
        if not parent_file.exists():
            raise ValueError(f"Parent project '{self.parent_project}' does not exist")
        return self

    model_config = {
        "json_schema_extra": {
            "examples": [
                {
                    "name": "nixos-095-worktree",
                    "display_name": "Feature 095 Worktree",
                    "icon": "🌿",
                    "working_dir": "/home/vpittamp/nixos-095-worktree",
                    "scope": "scoped",
                    "worktree_path": "/home/vpittamp/nixos-095-worktree",
                    "branch_name": "095-new-feature",
                    "parent_project": "nixos",
                    "remote": None
                }
            ]
        }
    }


# ============================================================================
# Feature 097: Panel Display Models (T013, T014)
# ============================================================================

class RepositoryWithWorktrees(BaseModel):
    """
    Panel display model for a repository with its child worktrees (Feature 097 T014).

    Used by the Eww monitoring panel to render the hierarchical view.
    """
    project: ProjectConfig = Field(..., description="The repository project (source_type=repository)")
    worktree_count: int = Field(default=0, ge=0, description="Number of child worktrees")
    has_dirty: bool = Field(default=False, description="True if any worktree has uncommitted changes")
    is_expanded: bool = Field(default=True, description="UI expansion state")
    worktrees: List[ProjectConfig] = Field(
        default_factory=list,
        description="Child worktree projects (source_type=worktree)"
    )


class PanelProjectsData(BaseModel):
    """
    Complete data structure for the monitoring panel Projects tab (Feature 097 T013).

    This is the structure returned by get_projects_hierarchy() and consumed by Eww.
    """
    repository_projects: List[RepositoryWithWorktrees] = Field(
        default_factory=list,
        description="Repository projects with their grouped worktrees"
    )
    standalone_projects: List[ProjectConfig] = Field(
        default_factory=list,
        description="Standalone projects (non-git or simple repos)"
    )
    orphaned_worktrees: List[ProjectConfig] = Field(
        default_factory=list,
        description="Worktrees with no matching Repository Project"
    )
    active_project: Optional[str] = Field(
        default=None,
        description="Currently active project name (or null for global mode)"
    )
