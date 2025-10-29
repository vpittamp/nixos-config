"""
Configuration state tracking for Sway Configuration Manager.

Tracks active configuration version, load timestamp, and validation errors.
"""

from typing import List, Optional

from .models import ValidationError


class ConfigurationState:
    """Tracks current configuration state."""

    def __init__(self):
        """Initialize configuration state."""
        self.active_config_version: Optional[str] = None
        self.config_load_timestamp: Optional[float] = None
        self.validation_errors: List[ValidationError] = []
        self.file_watcher_active: bool = False
        self.reload_count: int = 0
        self.last_reload_success: bool = False

    def reset(self):
        """Reset state to initial values."""
        self.active_config_version = None
        self.config_load_timestamp = None
        self.validation_errors = []
        self.file_watcher_active = False
        self.reload_count = 0
        self.last_reload_success = False

    def to_dict(self) -> dict:
        """
        Convert state to dictionary.

        Returns:
            State as dictionary
        """
        return {
            "active_config_version": self.active_config_version,
            "config_load_timestamp": self.config_load_timestamp,
            "validation_errors": [e.dict() for e in self.validation_errors],
            "file_watcher_active": self.file_watcher_active,
            "reload_count": self.reload_count,
            "last_reload_success": self.last_reload_success
        }
