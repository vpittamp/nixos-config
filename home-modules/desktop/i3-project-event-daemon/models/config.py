"""Project configuration models for session management.

Feature 074: Session Management
Task T014-T015: ProjectConfiguration Pydantic model

Per-project session management settings loaded from Nix registry.
"""

import logging
from datetime import datetime
from pathlib import Path
from typing import Optional

from pydantic import BaseModel, Field, field_validator

logger = logging.getLogger(__name__)


class ProjectConfiguration(BaseModel):
    """Session management configuration for a project (T014, US5)"""

    name: str = Field(..., pattern=r'^[a-z0-9-]+$')
    directory: Path
    auto_save: bool = Field(default=True)
    auto_restore: bool = Field(default=False)
    default_layout: Optional[str] = Field(default=None, pattern=r'^[a-z0-9-]+$')
    max_auto_saves: int = Field(default=10, ge=1, le=100)

    @field_validator('directory')
    @classmethod
    def directory_must_exist(cls, v: Path) -> Path:
        """Warn if directory doesn't exist (non-fatal for config loading) (T014)"""
        if not v.exists():
            logger.warning(f"Project directory does not exist: {v}")
        return v.absolute()

    def get_layouts_dir(self) -> Path:
        """Get directory where layouts are stored for this project (T015, US5)"""
        layouts_dir = Path.home() / ".local/share/i3pm/layouts" / self.name
        layouts_dir.mkdir(parents=True, exist_ok=True)
        return layouts_dir

    def get_auto_save_name(self) -> str:
        """Generate auto-save layout name with current timestamp (T015, US5)"""
        return f"auto-{datetime.now().strftime('%Y%m%d-%H%M%S')}"

    def list_auto_saves(self) -> list[Path]:
        """List all auto-saved layouts, sorted newest first (T015, US5)"""
        layouts_dir = self.get_layouts_dir()
        auto_saves = sorted(
            layouts_dir.glob("auto-*.json"),
            key=lambda f: f.stat().st_mtime,
            reverse=True
        )
        return auto_saves

    def get_latest_auto_save(self) -> Optional[str]:
        """Get name of most recent auto-save layout (without .json extension) (T015, US5)"""
        auto_saves = self.list_auto_saves()
        if auto_saves:
            return auto_saves[0].stem
        return None
