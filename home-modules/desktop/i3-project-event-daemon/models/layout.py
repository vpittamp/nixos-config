"""
Layout and WindowSnapshot Pydantic models for layout management.

Feature 058: Python Backend Consolidation
Provides data validation and JSON serialization for window layout snapshots.
"""

from pydantic import BaseModel, Field, field_validator
from datetime import datetime
from typing import List, Optional
from pathlib import Path
import json
import logging

logger = logging.getLogger(__name__)


class WindowSnapshot(BaseModel):
    """Window state snapshot for layout restore."""

    window_id: int = Field(..., gt=0, description="i3/Sway window ID")
    app_id: str = Field(..., min_length=1, description="I3PM_APP_ID for deterministic matching")
    app_name: str = Field(..., min_length=1, description="Application name (e.g., vscode)")
    window_class: str = Field(default="", description="X11 window class (validation only)")
    title: str = Field(default="", description="Window title (display only)")
    workspace: int = Field(..., ge=1, le=70, description="Workspace number (1-70)")
    output: str = Field(..., min_length=1, description="Output name (e.g., HEADLESS-1)")
    rect: dict[str, int] = Field(..., description="Window geometry {x, y, width, height}")
    floating: bool = Field(..., description="Floating vs tiled state")
    focused: bool = Field(..., description="Had focus when captured")

    @field_validator('rect')
    @classmethod
    def validate_rect(cls, v: dict[str, int]) -> dict[str, int]:
        """Ensure rect contains required fields."""
        required = {'x', 'y', 'width', 'height'}
        if not required.issubset(v.keys()):
            raise ValueError(f"rect must contain fields: {required}")

        # Validate positive dimensions
        if v['width'] <= 0 or v['height'] <= 0:
            raise ValueError("width and height must be positive")

        return v

    def matches_window_id(self, window_env: dict) -> bool:
        """Check if this snapshot matches a window's environment."""
        return window_env.get('I3PM_APP_ID') == self.app_id


class Layout(BaseModel):
    """Complete layout snapshot with schema versioning."""

    schema_version: str = Field(default="1.0", description="Layout format version")
    project_name: str = Field(..., min_length=1, pattern=r'^[a-zA-Z0-9_-]+$')
    layout_name: str = Field(..., min_length=1)
    timestamp: datetime = Field(default_factory=datetime.now)
    windows: List[WindowSnapshot] = Field(default_factory=list)

    @field_validator('windows')
    @classmethod
    def validate_windows(cls, v: List[WindowSnapshot]) -> List[WindowSnapshot]:
        """Validate window list (can be empty for blank layouts)."""
        # Check for duplicate app_ids within same layout
        app_ids = [w.app_id for w in v]
        duplicates = [aid for aid in app_ids if app_ids.count(aid) > 1]
        if duplicates:
            raise ValueError(f"Duplicate app_ids in layout: {set(duplicates)}")
        return v

    def save_to_file(self, path: Path) -> None:
        """Save layout to JSON file."""
        path.parent.mkdir(parents=True, exist_ok=True)
        with open(path, 'w') as f:
            json.dump(
                self.model_dump(mode='json'),
                f,
                indent=2,
                default=str  # Handle datetime serialization
            )

    @classmethod
    def load_from_file(cls, path: Path) -> "Layout":
        """Load layout from JSON file with automatic migration."""
        if not path.exists():
            raise FileNotFoundError(f"Layout file not found: {path}")

        with open(path) as f:
            data = json.load(f)

        # Auto-migrate old format
        if 'schema_version' not in data:
            logger.info(f"Migrating layout from v0 to v1.0: {path}")
            data = cls._migrate_v0_to_v1(data)

        return cls.model_validate(data)

    @classmethod
    def _migrate_v0_to_v1(cls, data: dict) -> dict:
        """Migrate pre-versioning layout to v1.0."""
        data['schema_version'] = '1.0'

        # Ensure all windows have app_id (old layouts may use class-based matching)
        for window in data.get('windows', []):
            if 'app_id' not in window:
                # Generate synthetic app_id from window_id
                window['app_id'] = f"migrated-{window['window_id']}"
                window['app_name'] = window.get('window_class', 'unknown')
                logger.warning(
                    f"Migrated window without app_id: {window.get('title', 'unknown')}"
                )

        return data
