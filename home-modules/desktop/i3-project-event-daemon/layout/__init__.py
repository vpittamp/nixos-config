"""
Layout module for i3pm production readiness

This module provides data models and functionality for workspace layout
capture, persistence, and restoration.

Feature 030: Production Readiness
Task T006: Core data models
Task T030: Layout capture
"""

from .models import (
    # Core entities
    Project,
    Window,
    WindowGeometry,
    WindowPlaceholder,
    LayoutSnapshot,
    WorkspaceLayout,
    Container,
    Monitor,
    MonitorConfiguration,
    Event,
    ClassificationRule,

    # Enums
    LayoutMode,
    EventSource,
    ScopeType,
    PatternType,
    RuleSource,
    Resolution,
    Position,
)

from .capture import LayoutCapture, capture_layout
from .persistence import LayoutPersistence, save_layout, load_layout, list_layouts, delete_layout
from .restore import LayoutRestore, restore_layout

__all__ = [
    # Models
    "Project",
    "Window",
    "WindowGeometry",
    "WindowPlaceholder",
    "LayoutSnapshot",
    "WorkspaceLayout",
    "Container",
    "Monitor",
    "MonitorConfiguration",
    "Event",
    "ClassificationRule",

    # Enums
    "LayoutMode",
    "EventSource",
    "ScopeType",
    "PatternType",
    "RuleSource",
    "Resolution",
    "Position",

    # Capture
    "LayoutCapture",
    "capture_layout",

    # Persistence
    "LayoutPersistence",
    "save_layout",
    "load_layout",
    "list_layouts",
    "delete_layout",

    # Restore
    "LayoutRestore",
    "restore_layout",
]
