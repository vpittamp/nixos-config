"""
Project and ActiveProjectState Pydantic models for project management.

Feature 058: Python Backend Consolidation
Feature 087: Remote Project Environment Support
Feature 097: Git-Based Project Discovery and Management
Provides data validation and JSON serialization for project state.
"""

from pydantic import BaseModel, Field, field_validator, model_validator
from datetime import datetime
from pathlib import Path
from typing import Optional, List
import json
import logging
from .remote_config import RemoteConfig
from .discovery import SourceType, ProjectStatus, GitMetadata, BranchMetadata

logger = logging.getLogger(__name__)


class Project(BaseModel):
    """Project definition with metadata."""

    name: str = Field(..., min_length=1, pattern=r'^[a-zA-Z0-9_-]+$')
    directory: str = Field(..., min_length=1)
    display_name: str = Field(..., min_length=1)
    icon: str = Field(default="📁")
    created_at: datetime = Field(default_factory=datetime.now)
    updated_at: datetime = Field(default_factory=datetime.now)
    scoped_classes: List[str] = Field(default_factory=list, description="App classes scoped to this project")

    # Feature 087: Optional remote configuration
    remote: Optional[RemoteConfig] = Field(
        default=None,
        description="Remote environment config (SSH-based)"
    )

    # Feature 097: Discovery fields - all projects must be discovered
    source_type: SourceType = Field(
        ...,
        description="How project was discovered (local, worktree, remote)"
    )
    status: ProjectStatus = Field(
        default=ProjectStatus.ACTIVE,
        description="Project availability (active, missing)"
    )
    git_metadata: Optional[GitMetadata] = Field(
        default=None,
        description="Git-specific data (required for local/worktree)"
    )
    discovered_at: datetime = Field(
        default_factory=datetime.now,
        description="When project was discovered"
    )

    # Feature 098: Worktree environment integration fields
    parent_project: Optional[str] = Field(
        default=None,
        description="Name of parent project (if this is a worktree)"
    )
    branch_metadata: Optional[BranchMetadata] = Field(
        default=None,
        description="Parsed branch metadata (number, type, full_name)"
    )

    @field_validator('directory', mode='before')
    @classmethod
    def validate_directory_format(cls, v: str) -> str:
        """Ensure directory is absolute path or URL.

        Feature 097: Remote projects use URLs as "directory" field.
        Local/worktree projects require absolute filesystem paths.
        """
        if not isinstance(v, str):
            raise ValueError("directory must be a string")

        # Allow URLs for remote-only projects
        if v.startswith("https://") or v.startswith("git@"):
            return v

        path = Path(v).expanduser()

        if not path.is_absolute():
            raise ValueError("directory must be absolute path")

        return str(path)

    @model_validator(mode='after')
    def validate_directory_exists(self):
        """Validate directory exists unless status is 'missing' or source_type is 'remote'.

        Feature 097: Projects with status='missing' can have non-existent directories
        to preserve project configuration when repositories are temporarily unavailable.

        Feature 097: Remote-only projects use URLs and don't need directory validation.
        """
        # Skip validation for remote-only projects (URL-based)
        if self.source_type == SourceType.REMOTE:
            return self

        if self.status == ProjectStatus.ACTIVE:
            path = Path(self.directory)
            if not path.exists():
                raise ValueError(f"directory does not exist: {self.directory}")
            if not path.is_dir():
                raise ValueError(f"path is not a directory: {self.directory}")
        return self

    def is_remote(self) -> bool:
        """Check if this is a remote project."""
        return self.remote is not None and self.remote.enabled

    def get_effective_directory(self) -> str:
        """Get directory path (remote working_dir if remote, else local directory)."""
        if self.is_remote():
            return self.remote.working_dir
        return self.directory

    def save_to_file(self, config_dir: Path) -> None:
        """Save project to JSON file."""
        projects_dir = config_dir / "projects"
        projects_dir.mkdir(parents=True, exist_ok=True)

        project_file = projects_dir / f"{self.name}.json"
        with open(project_file, 'w') as f:
            json.dump(
                self.model_dump(mode='json'),
                f,
                indent=2,
                default=str
            )

    @classmethod
    def load_from_file(cls, config_dir: Path, name: str) -> "Project":
        """Load project from JSON file."""
        project_file = config_dir / "projects" / f"{name}.json"

        if not project_file.exists():
            raise FileNotFoundError(f"Project not found: {name}")

        with open(project_file) as f:
            data = json.load(f)

        return cls.model_validate(data)

    @classmethod
    def list_all(cls, config_dir: Path) -> List["Project"]:
        """List all projects in config directory."""
        projects_dir = config_dir / "projects"

        if not projects_dir.exists():
            return []

        projects = []
        for project_file in projects_dir.glob("*.json"):
            try:
                with open(project_file) as f:
                    data = json.load(f)
                projects.append(cls.model_validate(data))
            except Exception as e:
                logger.warning(f"Failed to load project {project_file}: {e}")

        return sorted(projects, key=lambda p: p.name)


class ActiveProjectState(BaseModel):
    """Singleton state for active project."""

    project_name: Optional[str] = Field(default=None, description="Active project name (null = global)")

    @classmethod
    def load(cls, config_dir: Path) -> "ActiveProjectState":
        """Load active project state from file."""
        state_file = config_dir / "active-project.json"

        if not state_file.exists():
            return cls(project_name=None)

        with open(state_file) as f:
            data = json.load(f)

        return cls.model_validate(data)

    def save(self, config_dir: Path) -> None:
        """Save active project state to file."""
        state_file = config_dir / "active-project.json"
        state_file.parent.mkdir(parents=True, exist_ok=True)

        with open(state_file, 'w') as f:
            json.dump(self.model_dump(), f, indent=2)

    def is_active(self, project_name: str) -> bool:
        """Check if given project is active."""
        return self.project_name == project_name

    def is_global_mode(self) -> bool:
        """Check if in global mode (no active project)."""
        return self.project_name is None
