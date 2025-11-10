"""Floating window configuration models for Feature 001.

This module defines Pydantic models and constants for declarative floating
window behavior and size presets.
"""

from enum import Enum
from typing import Optional, Tuple
from pydantic import BaseModel, Field, validator


class FloatingSize(str, Enum):
    """Floating window size presets.

    Four predefined size presets plus null (natural size) option:
    - SCRATCHPAD: 1200×600 (based on Feature 062 dimensions)
    - SMALL: 800×500 (lightweight tools, system monitors)
    - MEDIUM: 1200×800 (medium-sized apps, settings)
    - LARGE: 1600×1000 (full-featured applications)
    - null: Natural size (application decides)
    """

    SCRATCHPAD = "scratchpad"
    SMALL = "small"
    MEDIUM = "medium"
    LARGE = "large"

    @classmethod
    def from_str(cls, value: str) -> "FloatingSize":
        """Parse size preset from string (case-insensitive).

        Args:
            value: Size preset name string

        Returns:
            FloatingSize: Parsed enum value

        Raises:
            ValueError: If value is not a valid preset
        """
        try:
            return cls(value.lower())
        except ValueError:
            valid_presets = ", ".join([s.value for s in cls])
            raise ValueError(
                f"Invalid floating size preset '{value}': must be one of {valid_presets}"
            )


class Scope(str, Enum):
    """Application project scope for filtering.

    Determines window visibility across project switches:
    - SCOPED: Window hides when switching projects (tied to specific project)
    - GLOBAL: Window remains visible across all projects (system-wide)

    Integrates with existing project filtering system from Features 037-038.
    """

    SCOPED = "scoped"
    GLOBAL = "global"

    @classmethod
    def from_str(cls, value: str) -> "Scope":
        """Parse scope from string (case-insensitive).

        Args:
            value: Scope name string

        Returns:
            Scope: Parsed enum value

        Raises:
            ValueError: If value is not a valid scope
        """
        try:
            return cls(value.lower())
        except ValueError:
            valid_scopes = ", ".join([s.value for s in cls])
            raise ValueError(
                f"Invalid scope '{value}': must be one of {valid_scopes}"
            )


class FloatingWindowConfig(BaseModel):
    """Floating window configuration from Nix app definitions.

    Represents an application's floating window preferences declared in
    app-registry-data.nix.
    """

    app_name: str = Field(..., description="Application identifier")
    floating: bool = Field(..., description="Enable floating mode")
    floating_size: Optional[FloatingSize] = Field(
        None, description="Size preset (null = natural size)"
    )
    scope: Scope = Field(..., description="Project filtering scope")

    @validator("app_name")
    def validate_app_name(cls, v):
        """Validate app name is non-empty."""
        if not v or v.strip() == "":
            raise ValueError("app_name cannot be empty")
        return v

    @validator("floating_size")
    def validate_floating_size(cls, v, values):
        """Validate floating_size only used when floating=true."""
        if v is not None and not values.get("floating", False):
            raise ValueError("floating_size requires floating=true")
        return v


# Floating window size preset dimensions (width, height)
# Used by FloatingWindowManager to convert presets to pixel dimensions
FLOATING_SIZE_DIMENSIONS: dict[FloatingSize, Tuple[int, int]] = {
    FloatingSize.SCRATCHPAD: (1200, 600),  # Feature 062 scratchpad terminal size
    FloatingSize.SMALL: (800, 500),  # Lightweight tools
    FloatingSize.MEDIUM: (1200, 800),  # Medium apps
    FloatingSize.LARGE: (1600, 1000),  # Full-featured apps
}


def get_floating_dimensions(size_preset: Optional[FloatingSize]) -> Optional[Tuple[int, int]]:
    """Get pixel dimensions for a floating size preset.

    Args:
        size_preset: FloatingSize enum value or None

    Returns:
        Tuple[int, int]: (width, height) in pixels, or None for natural size
    """
    if size_preset is None:
        return None
    return FLOATING_SIZE_DIMENSIONS.get(size_preset)
