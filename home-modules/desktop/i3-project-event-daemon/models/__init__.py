"""
Pydantic models for i3pm daemon.

Feature 058: Python Backend Consolidation
- Added Pydantic models for Layout and Project (replacing old dataclasses)
- Legacy models re-exported from legacy.py for backward compatibility

Feature 051: i3run-Inspired Scratchpad Enhancements
- Added models for mouse-cursor positioning and boundary detection
- State persistence via Sway marks
- Configurable screen edge gaps and workspace summoning

Version: 1.1.0 - Feature 051 enhancement models
"""

# Feature 058: New Pydantic models (replace old dataclass versions)
from .layout import WindowSnapshot, Layout
from .project import Project, ActiveProjectState

# Feature 062: Scratchpad terminal models
from .scratchpad import ScratchpadTerminal

# Feature 051: Scratchpad enhancement models
from .scratchpad_enhancement import (
    GapConfig,
    WorkspaceGeometry,
    WindowDimensions,
    CursorPosition,
    TerminalPosition,
    ScratchpadState,
    SummonBehavior,
    SummonMode,
)

# Legacy models - import everything EXCEPT the ones we're replacing
from .legacy import (
    WindowInfo,
    # Project,  # REPLACED by new Pydantic version in project.py
    # ActiveProjectState,  # REPLACED by new Pydantic version in project.py
    ApplicationClassification,
    IdentificationRule,
    EventQueueEntry,
    WorkspaceInfo,
    EventEntry,
    EventCorrelation,
    DaemonState,
    MonitorRole,
    MonitorDistribution,
    DistributionRules,
    WorkspaceMonitorConfig,
    OutputRect,
    MonitorConfig,
    WorkspaceAssignment,
    MonitorSystemState,
    ValidationIssue,
    ConfigValidationResult,
    WindowIdentity,
    I3PMEnvironment,
    WorkspaceRule,
    EventSubscription,
    WindowEvent,
    StateMismatch,
    StateValidation,
    OutputInfo,
    I3IPCState,
    DiagnosticReport,
    PendingLaunch,
    LaunchWindowInfo,
    ConfidenceLevel,
    CorrelationResult,
    LaunchRegistryStats,
    WorkspaceModeState,
    WorkspaceSwitch,
    WorkspaceModeEvent,
)

__all__ = [
    # Feature 058: New Pydantic models
    "WindowSnapshot",
    "Layout",
    "Project",
    "ActiveProjectState",
    # Feature 062: Scratchpad terminal
    "ScratchpadTerminal",
    # Feature 051: Scratchpad enhancements
    "GapConfig",
    "WorkspaceGeometry",
    "WindowDimensions",
    "CursorPosition",
    "TerminalPosition",
    "ScratchpadState",
    "SummonBehavior",
    "SummonMode",
    # Legacy models
    "WindowInfo",
    "ApplicationClassification",
    "IdentificationRule",
    "EventQueueEntry",
    "WorkspaceInfo",
    "EventEntry",
    "EventCorrelation",
    "DaemonState",
    "MonitorRole",
    "MonitorDistribution",
    "DistributionRules",
    "WorkspaceMonitorConfig",
    "OutputRect",
    "MonitorConfig",
    "WorkspaceAssignment",
    "MonitorSystemState",
    "ValidationIssue",
    "ConfigValidationResult",
    "WindowIdentity",
    "I3PMEnvironment",
    "WorkspaceRule",
    "EventSubscription",
    "WindowEvent",
    "StateMismatch",
    "StateValidation",
    "OutputInfo",
    "I3IPCState",
    "DiagnosticReport",
    "PendingLaunch",
    "LaunchWindowInfo",
    "ConfidenceLevel",
    "CorrelationResult",
    "LaunchRegistryStats",
    "WorkspaceModeState",
    "WorkspaceSwitch",
    "WorkspaceModeEvent",
]
