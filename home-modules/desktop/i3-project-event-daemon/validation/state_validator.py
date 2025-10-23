"""
Daemon State Validator

Feature 030: Production Readiness
Task T023: State validator implementation

Validates daemon state for consistency and detects corruption
that requires recovery. Used during startup and after errors.
"""

import logging
from dataclasses import dataclass, field
from typing import List, Optional, Dict, Any
from datetime import datetime
from pathlib import Path
import json

logger = logging.getLogger(__name__)


@dataclass
class ValidationResult:
    """
    Result of state validation

    Tracks validation status, errors, warnings, and suggested fixes.
    """
    is_valid: bool = True
    errors: List[str] = field(default_factory=list)
    warnings: List[str] = field(default_factory=list)
    fixes: List[str] = field(default_factory=list)
    timestamp: datetime = field(default_factory=datetime.now)

    def add_error(self, message: str, fix: Optional[str] = None) -> None:
        """Add validation error with optional fix suggestion"""
        self.is_valid = False
        self.errors.append(message)
        if fix:
            self.fixes.append(fix)
        logger.error(f"Validation error: {message}")

    def add_warning(self, message: str) -> None:
        """Add validation warning (non-critical)"""
        self.warnings.append(message)
        logger.warning(f"Validation warning: {message}")

    def to_dict(self) -> Dict[str, Any]:
        """Convert to dictionary for JSON serialization"""
        return {
            "is_valid": self.is_valid,
            "errors": self.errors,
            "warnings": self.warnings,
            "fixes": self.fixes,
            "timestamp": self.timestamp.isoformat(),
        }


class StateValidator:
    """
    Validates daemon state for consistency

    Checks:
    - Project configuration integrity
    - Window mark consistency
    - i3 connection state
    - File system state (config files exist)
    - Event buffer integrity
    """

    def __init__(self, config_dir: Path = None):
        """
        Initialize validator

        Args:
            config_dir: Path to i3pm configuration directory (default: ~/.config/i3)
        """
        self.config_dir = config_dir or Path.home() / ".config/i3"
        self.projects_dir = self.config_dir / "projects"
        self.app_classes_file = self.config_dir / "app-classes.json"

    async def validate_all(
        self,
        i3_connection=None,
        event_buffer=None,
        project_manager=None,
    ) -> ValidationResult:
        """
        Run all validation checks

        Args:
            i3_connection: i3ipc connection (optional)
            event_buffer: EventBuffer instance (optional)
            project_manager: ProjectManager instance (optional)

        Returns:
            ValidationResult with all checks
        """
        result = ValidationResult()

        # File system checks
        self._validate_config_directory(result)
        self._validate_projects_directory(result)
        self._validate_app_classes_file(result)

        # i3 connection check
        if i3_connection:
            self._validate_i3_connection(result, i3_connection)

        # Project configuration checks
        if project_manager:
            await self._validate_projects(result, project_manager)

        # Window mark consistency
        if i3_connection and project_manager:
            await self._validate_window_marks(result, i3_connection, project_manager)

        # Event buffer integrity
        if event_buffer:
            self._validate_event_buffer(result, event_buffer)

        # Log summary
        if result.is_valid:
            logger.info("State validation passed")
        else:
            logger.error(f"State validation failed with {len(result.errors)} errors")

        return result

    def _validate_config_directory(self, result: ValidationResult) -> None:
        """Validate config directory exists"""
        if not self.config_dir.exists():
            result.add_error(
                f"Config directory does not exist: {self.config_dir}",
                fix=f"Create directory: mkdir -p {self.config_dir}"
            )
        elif not self.config_dir.is_dir():
            result.add_error(
                f"Config path is not a directory: {self.config_dir}",
                fix=f"Remove file and create directory: rm {self.config_dir} && mkdir {self.config_dir}"
            )

    def _validate_projects_directory(self, result: ValidationResult) -> None:
        """Validate projects directory exists"""
        if not self.projects_dir.exists():
            result.add_warning(f"Projects directory does not exist: {self.projects_dir}")
            result.fixes.append(f"Create directory: mkdir -p {self.projects_dir}")

    def _validate_app_classes_file(self, result: ValidationResult) -> None:
        """Validate app classes file exists and is valid JSON"""
        if not self.app_classes_file.exists():
            result.add_warning(f"App classes file does not exist: {self.app_classes_file}")
            return

        try:
            with open(self.app_classes_file) as f:
                data = json.load(f)

            if not isinstance(data, dict):
                result.add_error(
                    "App classes file is not a JSON object",
                    fix=f"Replace with empty object: echo '{{}}' > {self.app_classes_file}"
                )

            # Validate structure
            if "scoped_classes" in data and not isinstance(data["scoped_classes"], list):
                result.add_error("app-classes.json: 'scoped_classes' must be a list")

        except json.JSONDecodeError as e:
            result.add_error(
                f"App classes file contains invalid JSON: {e}",
                fix=f"Fix JSON syntax or replace: echo '{{}}' > {self.app_classes_file}"
            )

    def _validate_i3_connection(self, result: ValidationResult, i3_connection) -> None:
        """Validate i3 connection is active"""
        try:
            # Check connection object
            if not hasattr(i3_connection, 'get_tree'):
                result.add_error(
                    "i3 connection object is invalid",
                    fix="Reconnect to i3 IPC"
                )
                return

            # Try a simple query
            tree = i3_connection.get_tree()
            if tree is None:
                result.add_error(
                    "i3 connection returned None for tree query",
                    fix="Reconnect to i3 IPC"
                )

        except Exception as e:
            result.add_error(
                f"i3 connection is not responding: {e}",
                fix="Reconnect to i3 IPC"
            )

    async def _validate_projects(self, result: ValidationResult, project_manager) -> None:
        """Validate project configurations"""
        try:
            # Get all project files
            if not self.projects_dir.exists():
                return

            project_files = list(self.projects_dir.glob("*.json"))

            for project_file in project_files:
                try:
                    with open(project_file) as f:
                        project_data = json.load(f)

                    # Validate required fields
                    required_fields = ["name", "display_name", "directory"]
                    for field in required_fields:
                        if field not in project_data:
                            result.add_error(
                                f"Project {project_file.stem} missing required field: {field}",
                                fix=f"Edit {project_file} and add '{field}' field"
                            )

                    # Validate directory exists
                    if "directory" in project_data:
                        project_dir = Path(project_data["directory"])
                        if not project_dir.exists():
                            result.add_warning(
                                f"Project {project_file.stem} directory does not exist: {project_dir}"
                            )

                except json.JSONDecodeError as e:
                    result.add_error(
                        f"Project file {project_file.name} contains invalid JSON: {e}",
                        fix=f"Fix JSON syntax in {project_file}"
                    )
                except Exception as e:
                    result.add_error(f"Failed to validate project {project_file.name}: {e}")

        except Exception as e:
            result.add_error(f"Failed to validate projects: {e}")

    async def _validate_window_marks(
        self,
        result: ValidationResult,
        i3_connection,
        project_manager
    ) -> None:
        """Validate window marks are consistent with projects"""
        try:
            # Get all marks from i3
            tree = i3_connection.get_tree()
            all_marks = []

            def collect_marks(node):
                if hasattr(node, 'marks') and node.marks:
                    all_marks.extend(node.marks)
                if hasattr(node, 'nodes'):
                    for child in node.nodes:
                        collect_marks(child)

            collect_marks(tree)

            # Check for project: marks
            project_marks = [m for m in all_marks if m.startswith("project:")]

            # Get active projects
            active_projects = []
            if self.projects_dir.exists():
                for project_file in self.projects_dir.glob("*.json"):
                    try:
                        with open(project_file) as f:
                            data = json.load(f)
                        if "name" in data:
                            active_projects.append(data["name"])
                    except:
                        pass

            # Check for orphaned project marks
            for mark in project_marks:
                project_name = mark.split(":", 1)[1]
                if project_name not in active_projects:
                    result.add_warning(
                        f"Found window marked with non-existent project: {project_name}"
                    )

        except Exception as e:
            result.add_error(f"Failed to validate window marks: {e}")

    def _validate_event_buffer(self, result: ValidationResult, event_buffer) -> None:
        """Validate event buffer integrity"""
        try:
            # Check buffer exists
            if not hasattr(event_buffer, 'events'):
                result.add_error(
                    "Event buffer object is invalid",
                    fix="Reinitialize event buffer"
                )
                return

            # Check buffer size is reasonable
            buffer_size = len(event_buffer.events)
            max_size = getattr(event_buffer, 'max_size', 500)

            if buffer_size > max_size:
                result.add_error(
                    f"Event buffer size ({buffer_size}) exceeds max_size ({max_size})",
                    fix="Clear or prune event buffer"
                )

            # Check for None events
            none_count = sum(1 for e in event_buffer.events if e is None)
            if none_count > 0:
                result.add_error(
                    f"Event buffer contains {none_count} None entries",
                    fix="Clear corrupted events from buffer"
                )

        except Exception as e:
            result.add_error(f"Failed to validate event buffer: {e}")


async def validate_daemon_state(
    i3_connection=None,
    event_buffer=None,
    project_manager=None,
    config_dir: Path = None,
) -> ValidationResult:
    """
    Convenience function to validate daemon state

    Args:
        i3_connection: i3ipc connection
        event_buffer: EventBuffer instance
        project_manager: ProjectManager instance
        config_dir: Config directory path

    Returns:
        ValidationResult
    """
    validator = StateValidator(config_dir=config_dir)
    return await validator.validate_all(
        i3_connection=i3_connection,
        event_buffer=event_buffer,
        project_manager=project_manager,
    )
