"""
Configuration state tracking for Sway Configuration Manager.

Tracks active configuration version, load timestamp, and validation errors.
"""

from typing import List, Optional

from .models import ValidationError


class ConfigurationState:
    """
    Tracks current configuration state with telemetry.

    Feature 047 Phase 8 T068: Telemetry for reload success rate tracking
    """

    def __init__(self):
        """Initialize configuration state."""
        self.active_config_version: Optional[str] = None
        self.config_load_timestamp: Optional[float] = None
        self.validation_errors: List[ValidationError] = []
        self.file_watcher_active: bool = False
        self.reload_count: int = 0
        self.last_reload_success: bool = False

        # Feature 047 Phase 8 T068: Telemetry tracking
        self.telemetry = {
            "total_reload_attempts": 0,
            "successful_reloads": 0,
            "failed_reloads": 0,
            "validation_failures": 0,
            "apply_failures": 0,
            "rollback_count": 0,
            "success_rate_percent": 0.0,
            "average_reload_duration_ms": 0,
            "last_reload_duration_ms": 0,
            "total_reload_time_ms": 0
        }

    def reset(self):
        """Reset state to initial values."""
        self.active_config_version = None
        self.config_load_timestamp = None
        self.validation_errors = []
        self.file_watcher_active = False
        self.reload_count = 0
        self.last_reload_success = False

        # Reset telemetry
        self.telemetry = {
            "total_reload_attempts": 0,
            "successful_reloads": 0,
            "failed_reloads": 0,
            "validation_failures": 0,
            "apply_failures": 0,
            "rollback_count": 0,
            "success_rate_percent": 0.0,
            "average_reload_duration_ms": 0,
            "last_reload_duration_ms": 0,
            "total_reload_time_ms": 0
        }

    def record_reload_attempt(self, success: bool, duration_ms: int, phase: str):
        """
        Record reload attempt telemetry.

        Feature 047 Phase 8 T068: Track reload success rate

        Args:
            success: Whether reload succeeded
            duration_ms: Reload duration in milliseconds
            phase: Phase where reload ended ("validation", "apply", "complete")
        """
        self.telemetry["total_reload_attempts"] += 1
        self.telemetry["last_reload_duration_ms"] = duration_ms
        self.telemetry["total_reload_time_ms"] += duration_ms

        if success:
            self.telemetry["successful_reloads"] += 1
        else:
            self.telemetry["failed_reloads"] += 1
            if phase == "validation":
                self.telemetry["validation_failures"] += 1
            elif phase == "apply":
                self.telemetry["apply_failures"] += 1

        # Calculate success rate
        if self.telemetry["total_reload_attempts"] > 0:
            self.telemetry["success_rate_percent"] = round(
                (self.telemetry["successful_reloads"] / self.telemetry["total_reload_attempts"]) * 100,
                2
            )

        # Calculate average duration
        if self.telemetry["total_reload_attempts"] > 0:
            self.telemetry["average_reload_duration_ms"] = int(
                self.telemetry["total_reload_time_ms"] / self.telemetry["total_reload_attempts"]
            )

    def record_rollback(self):
        """
        Record rollback event.

        Feature 047 Phase 8 T068: Track rollback frequency
        """
        self.telemetry["rollback_count"] += 1

    def to_dict(self) -> dict:
        """
        Convert state to dictionary.

        Returns:
            State as dictionary with telemetry
        """
        return {
            "active_config_version": self.active_config_version,
            "config_load_timestamp": self.config_load_timestamp,
            "validation_errors": [e.dict() for e in self.validation_errors],
            "file_watcher_active": self.file_watcher_active,
            "reload_count": self.reload_count,
            "last_reload_success": self.last_reload_success,
            "telemetry": self.telemetry  # Feature 047 Phase 8 T068
        }
