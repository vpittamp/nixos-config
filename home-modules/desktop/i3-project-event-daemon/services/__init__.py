"""
Services module for i3 project event daemon
Feature 035: Registry-Centric Project & Workspace Management
"""

from .window_filter import (
    read_process_environ,
    get_window_pid,
    filter_windows_by_project,
    WindowEnvironment,
)
from .registry_loader import RegistryLoader, RegistryApp

__all__ = [
    "read_process_environ",
    "get_window_pid",
    "filter_windows_by_project",
    "WindowEnvironment",
    "RegistryLoader",
    "RegistryApp",
]
