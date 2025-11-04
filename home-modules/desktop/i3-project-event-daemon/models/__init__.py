"""
Pydantic models for i3pm daemon.

Feature 058: Python Backend Consolidation
- Added Pydantic models for Layout and Project (replacing old dataclasses)
- Legacy models re-exported from legacy.py for backward compatibility

Version: 1.0.1 - Force rebuild with legacy.py inclusion
"""

# Feature 058: New Pydantic models (replace old dataclass versions)
from .layout import WindowSnapshot, Layout
from .project import Project, ActiveProjectState

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
