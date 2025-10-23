"""
Automatic Recovery Module

Feature 030: Production Readiness
Task T024: Automatic recovery on startup

Implements automatic recovery logic for daemon startup,
handling crashed state, corrupted data, and connection failures.
"""

import logging
import asyncio
from dataclasses import dataclass, field
from datetime import datetime
from typing import Optional, List
from pathlib import Path

try:
    from ..validation.state_validator import ValidationResult, validate_daemon_state
except ImportError:
    # Fallback for testing
    from validation.state_validator import ValidationResult, validate_daemon_state

logger = logging.getLogger(__name__)


@dataclass
class RecoveryResult:
    """
    Result of recovery attempt

    Tracks recovery status, actions taken, and remaining issues.
    """
    success: bool = True
    actions_taken: List[str] = field(default_factory=list)
    errors: List[str] = field(default_factory=list)
    timestamp: datetime = field(default_factory=datetime.now)
    validation_result: Optional[ValidationResult] = None

    def add_action(self, message: str) -> None:
        """Record recovery action taken"""
        self.actions_taken.append(message)
        logger.info(f"Recovery action: {message}")

    def add_error(self, message: str) -> None:
        """Record recovery error"""
        self.success = False
        self.errors.append(message)
        logger.error(f"Recovery error: {message}")

    def to_dict(self) -> dict:
        """Convert to dictionary for JSON serialization"""
        return {
            "success": self.success,
            "actions_taken": self.actions_taken,
            "errors": self.errors,
            "timestamp": self.timestamp.isoformat(),
            "validation_result": self.validation_result.to_dict() if self.validation_result else None,
        }


class AutoRecovery:
    """
    Automatic recovery system

    Handles:
    - State validation on startup
    - Automatic fixes for common issues
    - i3 connection recovery
    - Configuration file repair
    - Event buffer recovery
    """

    def __init__(self, config_dir: Path = None):
        """
        Initialize recovery system

        Args:
            config_dir: Path to i3pm configuration directory
        """
        self.config_dir = config_dir or Path.home() / ".config/i3"
        self.projects_dir = self.config_dir / "projects"
        self.app_classes_file = self.config_dir / "app-classes.json"
        self.max_recovery_attempts = 3

    async def recover_on_startup(
        self,
        i3_connection=None,
        event_buffer=None,
        project_manager=None,
    ) -> RecoveryResult:
        """
        Run automatic recovery on daemon startup

        Steps:
        1. Validate current state
        2. Apply automatic fixes
        3. Re-validate
        4. Report results

        Args:
            i3_connection: i3ipc connection
            event_buffer: EventBuffer instance
            project_manager: ProjectManager instance

        Returns:
            RecoveryResult with actions taken
        """
        result = RecoveryResult()

        logger.info("Starting automatic recovery on daemon startup")

        # Step 1: Validate current state
        validation = await validate_daemon_state(
            i3_connection=i3_connection,
            event_buffer=event_buffer,
            project_manager=project_manager,
            config_dir=self.config_dir,
        )

        result.validation_result = validation

        if validation.is_valid:
            result.add_action("No recovery needed - state is valid")
            logger.info("State validation passed - no recovery needed")
            return result

        logger.warning(f"State validation failed with {len(validation.errors)} errors")

        # Step 2: Apply automatic fixes
        await self._apply_fixes(result, validation, i3_connection, event_buffer)

        # Step 3: Re-validate
        final_validation = await validate_daemon_state(
            i3_connection=i3_connection,
            event_buffer=event_buffer,
            project_manager=project_manager,
            config_dir=self.config_dir,
        )

        result.validation_result = final_validation

        if final_validation.is_valid:
            result.add_action("Recovery successful - state is now valid")
            logger.info("Recovery completed successfully")
        else:
            result.add_error(
                f"Recovery incomplete - {len(final_validation.errors)} errors remain"
            )
            logger.error(f"Recovery failed - {len(final_validation.errors)} errors remain")

        return result

    async def _apply_fixes(
        self,
        result: RecoveryResult,
        validation: ValidationResult,
        i3_connection,
        event_buffer,
    ) -> None:
        """
        Apply automatic fixes based on validation errors

        Args:
            result: RecoveryResult to update
            validation: ValidationResult with errors
            i3_connection: i3ipc connection
            event_buffer: EventBuffer instance
        """
        # Fix missing config directory
        if "Config directory does not exist" in str(validation.errors):
            if self._create_config_directory():
                result.add_action(f"Created config directory: {self.config_dir}")
            else:
                result.add_error(f"Failed to create config directory: {self.config_dir}")

        # Fix missing projects directory
        if "Projects directory does not exist" in str(validation.warnings):
            if self._create_projects_directory():
                result.add_action(f"Created projects directory: {self.projects_dir}")

        # Fix missing app classes file
        if "App classes file does not exist" in str(validation.warnings):
            if self._create_app_classes_file():
                result.add_action(f"Created app classes file: {self.app_classes_file}")

        # Fix corrupted app classes file
        if "invalid JSON" in str(validation.errors) and "app-classes" in str(validation.errors):
            if self._repair_app_classes_file():
                result.add_action(f"Repaired app classes file: {self.app_classes_file}")

        # Fix i3 connection
        if "i3 connection" in str(validation.errors):
            result.add_action("i3 connection recovery requires manual reconnection")
            # Note: Actual reconnection is handled by reconnection logic (T025)

        # Fix event buffer issues
        if "Event buffer" in str(validation.errors):
            if self._repair_event_buffer(event_buffer):
                result.add_action("Repaired event buffer")

    def _create_config_directory(self) -> bool:
        """Create config directory if missing"""
        try:
            self.config_dir.mkdir(parents=True, exist_ok=True)
            logger.info(f"Created config directory: {self.config_dir}")
            return True
        except Exception as e:
            logger.error(f"Failed to create config directory: {e}")
            return False

    def _create_projects_directory(self) -> bool:
        """Create projects directory if missing"""
        try:
            self.projects_dir.mkdir(parents=True, exist_ok=True)
            logger.info(f"Created projects directory: {self.projects_dir}")
            return True
        except Exception as e:
            logger.error(f"Failed to create projects directory: {e}")
            return False

    def _create_app_classes_file(self) -> bool:
        """Create app classes file with default content"""
        try:
            import json
            default_content = {
                "scoped_classes": []
            }
            with open(self.app_classes_file, 'w') as f:
                json.dump(default_content, f, indent=2)
            logger.info(f"Created app classes file: {self.app_classes_file}")
            return True
        except Exception as e:
            logger.error(f"Failed to create app classes file: {e}")
            return False

    def _repair_app_classes_file(self) -> bool:
        """Repair corrupted app classes file"""
        try:
            import json
            import shutil

            # Backup existing file
            if self.app_classes_file.exists():
                backup_path = self.app_classes_file.with_suffix('.json.backup')
                shutil.copy(self.app_classes_file, backup_path)
                logger.info(f"Backed up corrupted file to: {backup_path}")

            # Replace with default content
            return self._create_app_classes_file()

        except Exception as e:
            logger.error(f"Failed to repair app classes file: {e}")
            return False

    def _repair_event_buffer(self, event_buffer) -> bool:
        """Repair event buffer by removing corrupted entries"""
        try:
            if not event_buffer:
                return False

            # Remove None entries
            if hasattr(event_buffer, 'events'):
                original_size = len(event_buffer.events)
                event_buffer.events = [e for e in event_buffer.events if e is not None]
                removed_count = original_size - len(event_buffer.events)

                if removed_count > 0:
                    logger.info(f"Removed {removed_count} corrupted events from buffer")

                return True

        except Exception as e:
            logger.error(f"Failed to repair event buffer: {e}")
            return False

        return False


async def run_startup_recovery(
    i3_connection=None,
    event_buffer=None,
    project_manager=None,
    config_dir: Path = None,
) -> RecoveryResult:
    """
    Convenience function to run startup recovery

    Args:
        i3_connection: i3ipc connection
        event_buffer: EventBuffer instance
        project_manager: ProjectManager instance
        config_dir: Config directory path

    Returns:
        RecoveryResult
    """
    recovery = AutoRecovery(config_dir=config_dir)
    return await recovery.recover_on_startup(
        i3_connection=i3_connection,
        event_buffer=event_buffer,
        project_manager=project_manager,
    )
