"""
Pydantic models for i3pm daemon.

Feature 058: Python Backend Consolidation
- Added Pydantic models for Layout and Project (replacing old dataclasses)
- Legacy models re-exported from legacy.py for backward compatibility

Feature 001: Declarative Workspace-to-Monitor Assignment
- Added monitor role configuration models (monitor_config.py)
- Added floating window configuration models (floating_config.py)
- New models will replace legacy Feature 049 models in Phase 8 (T070)

Feature 087: Remote Project Environment Support
- Added RemoteConfig model for SSH-based remote projects
- Extended Project model with optional remote configuration

Feature 091: Optimize i3pm Project Switching Performance
- Added WindowCommand and CommandBatch models for parallel command execution
- Added PerformanceMetrics models for tracking switch performance

Version: 1.3.0 - Added Feature 091 models
"""

# Feature 058: New Pydantic models (replace old dataclass versions)
from .layout import WindowSnapshot, Layout
from .project import Project, ActiveProjectState
from .remote_config import RemoteConfig

# Feature 091: Performance optimization models
from .window_command import WindowCommand, CommandBatch, CommandType
from .performance_metrics import (
    OperationMetrics,
    ProjectSwitchMetrics,
    PerformanceSnapshot,
)

# Feature 001: Declarative workspace-to-monitor assignment
from .monitor_config import (
    MonitorRole as MonitorRoleV2,
    OutputInfo as OutputInfoV2,
    MonitorRoleConfig,
    MonitorRoleAssignment,
    WorkspaceAssignment as WorkspaceAssignmentV2,
    MonitorStateV2,
)
from .floating_config import (
    FloatingSize,
    Scope,
    FloatingWindowConfig,
    FLOATING_SIZE_DIMENSIONS,
    get_floating_dimensions,
)

# Feature 058: Workspace Mode Visual Feedback
from .workspace_mode_feedback import (
    PendingWorkspaceState,
)

# Feature 078: Enhanced Project Selection in Eww Preview Dialog
from .project_filter import (
    MatchPosition,
    GitStatus,
    ProjectListItem,
    ScoredMatch,
    FilterState,
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
    # Feature 087: Remote Project Environment Support
    "RemoteConfig",
    # Feature 091: Performance optimization models
    "WindowCommand",
    "CommandBatch",
    "CommandType",
    "OperationMetrics",
    "ProjectSwitchMetrics",
    "PerformanceSnapshot",
    # Feature 058: Workspace Mode Visual Feedback
    "PendingWorkspaceState",
    # Feature 078: Enhanced Project Selection
    "MatchPosition",
    "GitStatus",
    "ProjectListItem",
    "ScoredMatch",
    "FilterState",
    # Feature 001: Monitor role and floating window models
    "MonitorRoleV2",
    "OutputInfoV2",
    "MonitorRoleConfig",
    "MonitorRoleAssignment",
    "WorkspaceAssignmentV2",
    "MonitorStateV2",
    "FloatingSize",
    "Scope",
    "FloatingWindowConfig",
    "FLOATING_SIZE_DIMENSIONS",
    "get_floating_dimensions",
    # Legacy models (Feature 049 - to be replaced in Phase 8)
    "WindowInfo",
    "ApplicationClassification",
    "IdentificationRule",
    "EventQueueEntry",
    "WorkspaceInfo",
    "EventEntry",
    "EventCorrelation",
    "DaemonState",
    "MonitorRole",  # Legacy - use MonitorRoleV2 for Feature 001
    "MonitorDistribution",
    "DistributionRules",
    "WorkspaceMonitorConfig",
    "OutputRect",
    "MonitorConfig",
    "WorkspaceAssignment",  # Legacy - use WorkspaceAssignmentV2 for Feature 001
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
    "OutputInfo",  # Legacy - use OutputInfoV2 for Feature 001
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
