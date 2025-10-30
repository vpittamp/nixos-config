"""
Rules engine for Sway dynamic configuration management.

Modules:
- appearance_manager: Manage gaps/borders appearance settings
- keybinding_manager: Apply keybindings via Sway IPC
- window_rule_engine: Dynamic window rule application
- workspace_assignments: Hot-reload workspace assignments
"""

from .appearance_manager import AppearanceManager
from .keybinding_manager import KeybindingManager
from .window_rule_engine import WindowRuleEngine
from .workspace_assignments import WorkspaceAssignmentHandler

__all__ = [
    "AppearanceManager",
    "KeybindingManager",
    "WindowRuleEngine",
    "WorkspaceAssignmentHandler",
]
