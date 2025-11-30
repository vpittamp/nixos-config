"""
Scratchpad Terminal Models

Pydantic models for project-scoped scratchpad terminal state management.
Feature 062 - Project-Scoped Scratchpad Terminal
Feature 101 - Unified mark format with scoped: prefix
"""

from pydantic import BaseModel, Field, field_validator
from pathlib import Path
from typing import Optional
import psutil
import time


class ScratchpadTerminal(BaseModel):
    """
    Represents a project-scoped scratchpad terminal instance.

    Attributes:
        project_name: Project identifier or 'global' for global terminal
        pid: Process ID of the terminal emulator (Ghostty or Alacritty)
        window_id: Sway window container ID
        mark: Sway window mark in format 'scoped:{project_name}:{window_id}' (unified format)
        working_dir: Initial working directory (project root)
        created_at: Unix timestamp of terminal creation
        last_shown_at: Unix timestamp of last show operation (None if never shown)
    """

    project_name: str = Field(
        ...,
        description="Project identifier or 'global' for global terminal",
        min_length=1,
        max_length=100,
    )

    pid: int = Field(
        ...,
        description="Process ID of the terminal emulator",
        gt=0,
    )

    window_id: int = Field(
        ...,
        description="Sway window container ID",
        gt=0,
    )

    mark: str = Field(
        ...,
        description="Sway window mark in format 'scoped:{project_name}:{window_id}' (unified with regular scoped marks)",
        # Feature 101: Unified mark format - scoped:ACCOUNT/REPO:BRANCH:WINDOW_ID
        pattern=r"^scoped:[a-zA-Z0-9\-_/:]+:\d+$",
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
        """Validate project name format.

        Feature 101: Support qualified names (account/repo:branch) in addition to
        simple alphanumeric names with hyphens/underscores.
        """
        # Allow "global" as a special case
        if v == "global":
            return v

        # Feature 101: Accept qualified names (account/repo:branch)
        if "/" in v or ":" in v:
            allowed_chars = set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_/:")
            if set(v).issubset(allowed_chars) and len(v) > 0:
                return v
            raise ValueError("Qualified name contains invalid characters")

        # Legacy: simple alphanumeric names with hyphens/underscores
        if not v.replace("-", "").replace("_", "").isalnum():
            raise ValueError("Project name must be alphanumeric with optional hyphens/underscores, or a qualified name (account/repo:branch)")
        return v

    @field_validator("working_dir")
    @classmethod
    def validate_working_dir(cls, v: Path) -> Path:
        """Validate working directory is absolute path."""
        if not v.is_absolute():
            raise ValueError("Working directory must be absolute path")
        return v

    def is_process_running(self) -> bool:
        """
        Check if the terminal process is still running.

        Returns:
            True if process exists and is running, False otherwise
        """
        return psutil.pid_exists(self.pid)

    def mark_shown(self) -> None:
        """Update last_shown_at timestamp to current time."""
        self.last_shown_at = time.time()

    @classmethod
    def create_mark(cls, project_name: str, window_id: int) -> str:
        """
        Generate Sway mark for project scratchpad terminal.

        Feature 101: Unified mark format - scratchpad terminals now use scoped: prefix
        with window_id, same as regular scoped windows.

        Args:
            project_name: Project identifier
            window_id: Sway window container ID

        Returns:
            Mark string in format 'scoped:{project_name}:{window_id}'
        """
        return f"scoped:{project_name}:{window_id}"

    def to_dict(self) -> dict:
        """
        Convert to dictionary for JSON serialization.

        Returns:
            Dictionary representation of terminal state
        """
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
        """Pydantic model configuration."""
        arbitrary_types_allowed = True
