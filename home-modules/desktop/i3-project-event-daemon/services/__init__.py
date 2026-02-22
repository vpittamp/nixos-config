"""
Services module for i3 project event daemon
Feature 035: Registry-Centric Project & Workspace Management
Feature 039: Workspace Assignment Service (T027)
Feature 051: Run-Raise-Hide Application Launching
Feature 091: Optimize i3pm Project Switching Performance
"""

# Feature 091: Import base services FIRST to avoid circular dependencies
# window_filter.py depends on these, so they must be imported before window_filter
from .command_batch import CommandBatchService, CommandResult
from .tree_cache import TreeCacheService, get_tree_cache, initialize_tree_cache
from .performance_tracker import (
    PerformanceTrackerService,
    get_performance_tracker,
    initialize_performance_tracker,
)

# Now import services that depend on Feature 091 modules
from .window_filter import (
    read_process_environ,
    get_window_pid,
    filter_windows_by_project,
    WindowEnvironment,
)
from .registry_loader import RegistryLoader, RegistryApp
from .run_raise_manager import RunRaiseManager

__all__ = [
    "read_process_environ",
    "get_window_pid",
    "filter_windows_by_project",
    "WindowEnvironment",
    "RegistryLoader",
    "RegistryApp",
    "RunRaiseManager",
    # Feature 091: Performance optimization
    "CommandBatchService",
    "CommandResult",
    "TreeCacheService",
    "get_tree_cache",
    "initialize_tree_cache",
    "PerformanceTrackerService",
    "get_performance_tracker",
    "initialize_performance_tracker",
]
