"""
Services module for i3 project event daemon
Feature 035: Registry-Centric Project & Workspace Management
Feature 039: Workspace Assignment Service (T027)
Feature 051: Cursor Positioning and Boundary Detection
"""

from .window_filter import (
    read_process_environ,
    get_window_pid,
    filter_windows_by_project,
    WindowEnvironment,
)
from .registry_loader import RegistryLoader, RegistryApp
from .workspace_assigner import (
    WorkspaceAssigner,
    WorkspaceAssignment,
    WindowIdentifier,
    get_workspace_assigner,
)
from .cursor_positioner import CursorPositioner, SimpleCursorTracker
from .positioning import BoundaryDetectionAlgorithm, MultiMonitorPositioner

__all__ = [
    "read_process_environ",
    "get_window_pid",
    "filter_windows_by_project",
    "WindowEnvironment",
    "RegistryLoader",
    "RegistryApp",
    "WorkspaceAssigner",
    "WorkspaceAssignment",
    "WindowIdentifier",
    "get_workspace_assigner",
    "CursorPositioner",
    "SimpleCursorTracker",
    "BoundaryDetectionAlgorithm",
    "MultiMonitorPositioner",
]
