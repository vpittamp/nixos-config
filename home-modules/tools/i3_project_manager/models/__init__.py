# Data models for app discovery and classification

from .detection import DetectionResult
from .pattern import PatternRule
from .layout import (
    SwallowCriteria,
    WindowState,
    WindowGeometry,
    MonitorInfo,
    LaunchCommand,
    LayoutWindow,
    WorkspaceLayout,
    SavedLayout,
    WindowDiff,
)

__all__ = [
    "DetectionResult",
    "PatternRule",
    "SwallowCriteria",
    "WindowState",
    "WindowGeometry",
    "MonitorInfo",
    "LaunchCommand",
    "LayoutWindow",
    "WorkspaceLayout",
    "SavedLayout",
    "WindowDiff",
]
