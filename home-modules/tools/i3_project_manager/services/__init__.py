"""
Services module for i3 Project Manager

Feature 094: Enhanced Projects & Applications CRUD Interface
"""

from .project_editor import ProjectEditor
from .app_registry_editor import AppRegistryEditor
from .form_validator import FormValidator

__all__ = [
    "ProjectEditor",
    "AppRegistryEditor",
    "FormValidator",
]
