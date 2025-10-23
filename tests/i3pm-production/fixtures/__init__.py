"""
Test fixtures for i3pm production readiness tests

Feature 030: Production Readiness
Tasks T020-T022: Test fixtures

This module provides reusable fixtures for testing:
- Mock i3 IPC connections
- Sample layout data
- Load testing profiles
"""

from .mock_i3 import (
    MockI3Connection,
    MockI3Tree,
    create_mock_window,
    create_simple_tree,
    create_multi_monitor_tree,
)
from .sample_layouts import (
    simple_layout,
    complex_layout,
    multi_workspace_layout,
    dual_monitor_layout,
)
from .load_profiles import (
    small_load_profile,
    medium_load_profile,
    large_load_profile,
)

__all__ = [
    # Mock i3
    "MockI3Connection",
    "MockI3Tree",
    "create_mock_window",
    "create_simple_tree",
    "create_multi_monitor_tree",

    # Layouts
    "simple_layout",
    "complex_layout",
    "multi_workspace_layout",
    "dual_monitor_layout",

    # Load profiles
    "small_load_profile",
    "medium_load_profile",
    "large_load_profile",
]
