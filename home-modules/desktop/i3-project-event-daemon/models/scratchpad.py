"""
Scratchpad Terminal Models

Pydantic models for project-scoped scratchpad terminal management.
"""

from pydantic import BaseModel, Field, field_validator
from pathlib import Path
from typing import Optional
import psutil
import time


class ScratchpadTerminal(BaseModel):
    """Represents a project-scoped scratchpad terminal."""

    project_name: str = Field(
        ...,
        description="Project identifier or 'global' for global terminal",
        min_length=1,
        max_length=100,
    )

    pid: int = Field(
        ...,
        description="Process ID of the Alacritty terminal",
        gt=0,
    )

    window_id: int = Field(
        ...,
        description="Sway window container ID",
        gt=0,
    )

    mark: str = Field(
        ...,
        description="Sway window mark in format 'scratchpad:{project_name}'",
        pattern=r"^scratchpad:.+$",
    )

    working_dir: Path = Field(
        ...,
        description="Initial working directory (project root)",
    )

    created_at: float = Field(
        default_factory=time.time,
        description="Unix timestamp of terminal creation",
    )

    last_shown_at: Optional[float] = Field(
        None,
        description="Unix timestamp of last show operation",
    )

    @field_validator("project_name")
    @classmethod
    def validate_project_name(cls, v: str) -> str:
        """Validate project name contains only alphanumeric characters and hyphens."""
        if not v.replace("-", "").replace("_", "").isalnum():
            raise ValueError("Project name must be alphanumeric with optional hyphens/underscores")
        return v

    @field_validator("working_dir")
    @classmethod
    def validate_working_dir(cls, v: Path) -> Path:
        """Validate working directory is absolute path."""
        if not v.is_absolute():
            raise ValueError("Working directory must be absolute path")
        return v

    def is_process_running(self) -> bool:
        """Check if the terminal process is still running."""
        return psutil.pid_exists(self.pid)

    def mark_shown(self) -> None:
        """Update last_shown_at timestamp to current time."""
        object.__setattr__(self, 'last_shown_at', time.time())

    @classmethod
    def create_mark(cls, project_name: str) -> str:
        """Generate Sway mark for project scratchpad terminal."""
        return f"scratchpad:{project_name}"

    def to_dict(self) -> dict:
        """Convert to dictionary for JSON serialization."""
        return {
            "project_name": self.project_name,
            "pid": self.pid,
            "window_id": self.window_id,
            "mark": self.mark,
            "working_dir": str(self.working_dir),
            "created_at": self.created_at,
            "last_shown_at": self.last_shown_at,
        }

    class Config:
        """Pydantic configuration."""
        arbitrary_types_allowed = True
