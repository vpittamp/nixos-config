"""Test scenario modules for i3 project test framework.

This package provides concrete test scenarios for validating i3 project
management functionality.
"""

from .base_scenario import BaseScenario
from .event_stream import EventBufferValidation, EventOrderingValidation
from .monitor_configuration import (
    DaemonI3StateConsistency,
    OutputCountValidation,
    WorkspaceAssignmentValidation,
)
from .project_lifecycle import ProjectLifecycleBasic, ProjectSwitchMultiple
from .window_management import WindowMarkingValidation, WindowVisibilityToggle


# All available test scenarios
ALL_SCENARIOS = [
    # Project lifecycle scenarios
    ProjectLifecycleBasic,
    ProjectSwitchMultiple,
    # Window management scenarios
    WindowMarkingValidation,
    WindowVisibilityToggle,
    # Monitor configuration scenarios
    WorkspaceAssignmentValidation,
    DaemonI3StateConsistency,
    OutputCountValidation,
    # Event stream scenarios
    EventBufferValidation,
    EventOrderingValidation,
]


__all__ = [
    "BaseScenario",
    # Project lifecycle
    "ProjectLifecycleBasic",
    "ProjectSwitchMultiple",
    # Window management
    "WindowMarkingValidation",
    "WindowVisibilityToggle",
    # Monitor configuration
    "WorkspaceAssignmentValidation",
    "DaemonI3StateConsistency",
    "OutputCountValidation",
    # Event stream
    "EventBufferValidation",
    "EventOrderingValidation",
    # Collection
    "ALL_SCENARIOS",
]
