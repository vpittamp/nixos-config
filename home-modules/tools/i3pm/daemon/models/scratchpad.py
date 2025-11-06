"""Scratchpad state models for window hide/show operations - Feature 051."""

from pydantic import BaseModel, Field
from typing import Optional


class WindowGeometry(BaseModel):
    """Window geometry for scratchpad state preservation."""
    x: int = Field(..., description="X position in pixels (from rect.x)")
    y: int = Field(..., description="Y position in pixels (from rect.y)")
    width: int = Field(..., ge=1, description="Width in pixels (minimum 1)")
    height: int = Field(..., ge=1, description="Height in pixels (minimum 1)")

    class Config:
        frozen = True  # Immutable after creation


class ScratchpadState(BaseModel):
    """Scratchpad state for window hide/show operations."""
    window_id: int = Field(..., description="Sway container ID")
    app_name: str = Field(..., description="Application name from registry")
    floating: bool = Field(..., description="True if window was floating when hidden")
    geometry: Optional[WindowGeometry] = Field(
        None,
        description="Window geometry (None for tiled windows)"
    )
    hidden_at: float = Field(..., description="Unix timestamp when hidden")
    project_name: Optional[str] = Field(None, description="Project name (if scoped)")

    class Config:
        frozen = True
