"""
Project and ActiveProjectState Pydantic models for project management.

Feature 058: Python Backend Consolidation
Provides data validation and JSON serialization for project state.
"""

from pydantic import BaseModel, Field, field_validator
from datetime import datetime
from pathlib import Path
from typing import Optional, List
import json
import logging

logger = logging.getLogger(__name__)


class Project(BaseModel):
    """Project definition with metadata."""

    name: str = Field(..., min_length=1, pattern=r'^[a-zA-Z0-9_-]+$')
    directory: str = Field(..., min_length=1)
    display_name: str = Field(..., min_length=1)
    icon: str = Field(default="📁")
    created_at: datetime = Field(default_factory=datetime.now)
    updated_at: datetime = Field(default_factory=datetime.now)

    @field_validator('directory', mode='before')
    @classmethod
    def validate_directory(cls, v) -> str:
        """Ensure directory exists and is absolute path. Handles PosixPath for backward compatibility."""
        # Convert PosixPath to string (backward compatibility with old dataclass serialization)
        if isinstance(v, Path):
            v = str(v)

        path = Path(v).expanduser()

        if not path.is_absolute():
            raise ValueError("directory must be absolute path")

        if not path.exists():
            raise ValueError(f"directory does not exist: {v}")

        if not path.is_dir():
            raise ValueError(f"path is not a directory: {v}")

        return str(path)

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
