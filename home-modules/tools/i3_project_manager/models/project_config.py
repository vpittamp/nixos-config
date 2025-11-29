"""
Project Configuration Data Models

Feature 094: Enhanced Projects & Applications CRUD Interface
Storage: ~/.config/i3/projects/*.json
"""

from pathlib import Path
from typing import Optional, Literal, List, TYPE_CHECKING
from pydantic import BaseModel, Field, field_validator, model_validator
from enum import Enum
import re
import os

if TYPE_CHECKING:
    from typing import ForwardRef


class SourceType(str, Enum):
    """
    Feature 097/099: Project source type classification

    Determines how the project relates to git repositories.
    """
    REPOSITORY = "repository"  # Main bare/worktree repo, parent of worktrees
    WORKTREE = "worktree"      # Git worktree linked to a repository project
    STANDALONE = "standalone"  # Not git-managed or no worktree structure


class ProjectStatus(str, Enum):
    """
    Feature 097/099: Project validation status

    Indicates the current state of a project.
    """
    OK = "ok"                  # Directory exists, accessible
    MISSING = "missing"        # Directory does not exist
    INACCESSIBLE = "inaccessible"  # Directory exists but not readable/writable


class RemoteConfig(BaseModel):
    """Remote SSH configuration for remote projects"""
    enabled: bool = False
    host: str = Field(default="", description="SSH hostname or Tailscale FQDN")
    user: str = Field(default="", description="SSH username")
    remote_dir: str = Field(default="", description="Remote working directory (absolute path)")
    port: int = Field(default=22, ge=1, le=65535, description="SSH port")

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
    Project configuration model for i3pm projects

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
    def validate_working_dir_exists(cls, v: str) -> str:
        """Per spec.md FR-P-008: Validate directory exists and is accessible"""
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
    def validate_worktree_path_exists(cls, v: str, info) -> str:
        """
        Feature 099: Validate worktree path exists and is a valid directory.

        The workflow is:
        1. Script creates git worktree (directory now exists)
        2. Script calls CRUD handler to register the worktree project

        So we validate that the path EXISTS (reverse of original spec.md FR-P-018).
        Skip validation when in edit mode (editing existing worktree).
        """
        # Skip validation if in edit mode
        if info.context and info.context.get("edit_mode"):
            return str(Path(v).expanduser().resolve())

        path = Path(v).expanduser().resolve()
        if not path.exists():
            raise ValueError(f"Worktree path does not exist: {v}")
        if not path.is_dir():
            raise ValueError(f"Worktree path is not a directory: {v}")
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


class GitMetadata(BaseModel):
    """
    Feature 099: Git repository metadata for display in monitoring panel.

    Tracks git status information for projects and worktrees.
    """
    branch: str = Field(default="", description="Current git branch name")
    commit: str = Field(default="", description="Short commit hash (7 chars)")
    is_clean: bool = Field(default=True, description="True if no uncommitted changes")
    ahead_count: int = Field(default=0, ge=0, description="Commits ahead of remote")
    behind_count: int = Field(default=0, ge=0, description="Commits behind remote")
    has_untracked: bool = Field(default=False, description="Has untracked files")


class RepositoryWithWorktrees(BaseModel):
    """
    Feature 099: Repository project container with nested worktrees.

    Groups a repository project with its child worktrees for hierarchical display.
    """
    project: "ProjectConfig" = Field(..., description="The repository project")
    worktrees: List["ProjectConfig"] = Field(default_factory=list, description="Child worktree projects")
    worktree_count: int = Field(default=0, ge=0, description="Number of worktrees")
    has_dirty: bool = Field(default=False, description="True if repo or any worktree has uncommitted changes")
    is_expanded: bool = Field(default=True, description="UI state: show nested worktrees")

    model_config = {"arbitrary_types_allowed": True}


class PanelProjectsData(BaseModel):
    """
    Feature 099: Complete projects data structure for monitoring panel.

    Contains all project types organized for hierarchical display.
    """
    repository_projects: List[RepositoryWithWorktrees] = Field(
        default_factory=list,
        description="Repository projects with nested worktrees"
    )
    standalone_projects: List["ProjectConfig"] = Field(
        default_factory=list,
        description="Non-git or standalone projects"
    )
    orphaned_worktrees: List["ProjectConfig"] = Field(
        default_factory=list,
        description="Worktrees whose parent repository is not registered"
    )
    active_project: Optional[str] = Field(
        default=None,
        description="Name of currently active project"
    )

    model_config = {"arbitrary_types_allowed": True}
