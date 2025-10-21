"""Project configuration validator using JSON schema.

Validates project configurations against schema and performs additional
filesystem and business logic validation.
"""

import json
from pathlib import Path
from typing import Dict, List, Optional, Tuple

# JSON Schema for project configuration
PROJECT_SCHEMA = {
    "$schema": "http://json-schema.org/draft-07/schema#",
    "title": "i3 Project Configuration",
    "type": "object",
    "required": ["name", "directory", "scoped_classes"],
    "properties": {
        "name": {
            "type": "string",
            "pattern": "^[a-zA-Z0-9_-]+$",
            "minLength": 1,
            "maxLength": 64,
        },
        "directory": {"type": "string", "minLength": 1},
        "display_name": {"type": "string"},
        "icon": {"type": "string", "maxLength": 4},
        "scoped_classes": {
            "type": "array",
            "items": {"type": "string"},
            "minItems": 1,
            "uniqueItems": True,
        },
        "workspace_preferences": {
            "type": "object",
            "patternProperties": {
                "^[1-9]|10$": {
                    "type": "string",
                    "enum": ["primary", "secondary", "tertiary"],
                }
            },
            "additionalProperties": False,
        },
        "auto_launch": {
            "type": "array",
            "items": {
                "type": "object",
                "required": ["command"],
                "properties": {
                    "command": {"type": "string", "minLength": 1},
                    "workspace": {"type": "integer", "minimum": 1, "maximum": 10},
                    "env": {"type": "object"},
                    "wait_for_mark": {"type": "string"},
                    "wait_timeout": {"type": "number", "minimum": 0.1, "maximum": 30.0},
                    "launch_delay": {"type": "number", "minimum": 0, "maximum": 10.0},
                },
            },
        },
        "saved_layouts": {"type": "array", "items": {"type": "string"}},
        "created_at": {"type": "string", "format": "date-time"},
        "modified_at": {"type": "string", "format": "date-time"},
    },
}


class ValidationError:
    """Single validation error with path and message."""

    def __init__(self, path: str, message: str, severity: str = "error"):
        """Initialize validation error.

        Args:
            path: JSON path to error (e.g., "auto_launch[0].command")
            message: Error message
            severity: "error" or "warning"
        """
        self.path = path
        self.message = message
        self.severity = severity

    def __repr__(self) -> str:
        return f"ValidationError({self.path}: {self.message})"

    def __str__(self) -> str:
        return f"{self.severity.upper()}: {self.path}: {self.message}"


class ProjectValidator:
    """Validator for project configurations.

    Performs:
    1. JSON schema validation
    2. Filesystem validation (directory exists)
    3. Business logic validation (name uniqueness, etc.)
    """

    def __init__(
        self, config_dir: Path = Path.home() / ".config/i3/projects"
    ):
        """Initialize validator.

        Args:
            config_dir: Directory containing project configs
        """
        self.config_dir = config_dir
        self.schema = PROJECT_SCHEMA

    def validate_project(
        self, project_dict: Dict, check_uniqueness: bool = True
    ) -> List[ValidationError]:
        """Validate a project configuration dictionary.

        Args:
            project_dict: Project configuration dict
            check_uniqueness: Whether to check name uniqueness

        Returns:
            List of validation errors (empty if valid)
        """
        errors = []

        # Schema validation
        errors.extend(self._validate_schema(project_dict))

        # Filesystem validation
        errors.extend(self._validate_filesystem(project_dict))

        # Business logic validation
        if check_uniqueness:
            errors.extend(self._validate_uniqueness(project_dict))

        return errors

    def validate_file(self, config_file: Path) -> Tuple[bool, List[ValidationError]]:
        """Validate a project configuration file.

        Args:
            config_file: Path to project JSON file

        Returns:
            Tuple of (is_valid, errors)
        """
        errors = []

        # Check file exists
        if not config_file.exists():
            errors.append(
                ValidationError(
                    "", f"Configuration file not found: {config_file}", "error"
                )
            )
            return False, errors

        # Load JSON
        try:
            with config_file.open("r") as f:
                project_dict = json.load(f)
        except json.JSONDecodeError as e:
            errors.append(
                ValidationError("", f"Invalid JSON: {e}", "error")
            )
            return False, errors
        except Exception as e:
            errors.append(
                ValidationError("", f"Failed to read file: {e}", "error")
            )
            return False, errors

        # Validate project
        errors.extend(self.validate_project(project_dict, check_uniqueness=False))

        return len(errors) == 0, errors

    def _validate_schema(self, project_dict: Dict) -> List[ValidationError]:
        """Validate project against JSON schema.

        Args:
            project_dict: Project configuration dict

        Returns:
            List of validation errors
        """
        errors = []

        # Check required fields
        for field in self.schema["required"]:
            if field not in project_dict:
                errors.append(
                    ValidationError(field, f"Required field '{field}' missing", "error")
                )

        # Validate name pattern
        if "name" in project_dict:
            name = project_dict["name"]
            if not isinstance(name, str):
                errors.append(ValidationError("name", "Must be a string", "error"))
            elif not name.replace("-", "").replace("_", "").isalnum():
                errors.append(
                    ValidationError(
                        "name",
                        "Must be alphanumeric with optional - or _",
                        "error",
                    )
                )
            elif len(name) > 64:
                errors.append(
                    ValidationError("name", "Must be 64 characters or less", "error")
                )

        # Validate scoped_classes
        if "scoped_classes" in project_dict:
            scoped = project_dict["scoped_classes"]
            if not isinstance(scoped, list):
                errors.append(
                    ValidationError("scoped_classes", "Must be an array", "error")
                )
            elif len(scoped) == 0:
                errors.append(
                    ValidationError(
                        "scoped_classes",
                        "Must have at least one scoped application",
                        "error",
                    )
                )

        # Validate workspace_preferences
        if "workspace_preferences" in project_dict:
            ws_prefs = project_dict["workspace_preferences"]
            if not isinstance(ws_prefs, dict):
                errors.append(
                    ValidationError(
                        "workspace_preferences", "Must be an object", "error"
                    )
                )
            else:
                for ws_num, output_role in ws_prefs.items():
                    try:
                        ws_int = int(ws_num)
                        if not (1 <= ws_int <= 10):
                            errors.append(
                                ValidationError(
                                    f"workspace_preferences.{ws_num}",
                                    "Workspace number must be 1-10",
                                    "error",
                                )
                            )
                    except ValueError:
                        errors.append(
                            ValidationError(
                                f"workspace_preferences.{ws_num}",
                                "Workspace number must be an integer",
                                "error",
                            )
                        )

                    if output_role not in ["primary", "secondary", "tertiary"]:
                        errors.append(
                            ValidationError(
                                f"workspace_preferences.{ws_num}",
                                f"Invalid output role '{output_role}' (must be primary/secondary/tertiary)",
                                "error",
                            )
                        )

        # Validate auto_launch
        if "auto_launch" in project_dict:
            auto_launch = project_dict["auto_launch"]
            if not isinstance(auto_launch, list):
                errors.append(
                    ValidationError("auto_launch", "Must be an array", "error")
                )
            else:
                for i, app in enumerate(auto_launch):
                    if "command" not in app:
                        errors.append(
                            ValidationError(
                                f"auto_launch[{i}].command",
                                "Required field missing",
                                "error",
                            )
                        )
                    elif not app["command"]:
                        errors.append(
                            ValidationError(
                                f"auto_launch[{i}].command",
                                "Command cannot be empty",
                                "error",
                            )
                        )

                    if "workspace" in app:
                        ws = app["workspace"]
                        if not isinstance(ws, int) or not (1 <= ws <= 10):
                            errors.append(
                                ValidationError(
                                    f"auto_launch[{i}].workspace",
                                    "Workspace must be 1-10",
                                    "error",
                                )
                            )

        return errors

    def _validate_filesystem(self, project_dict: Dict) -> List[ValidationError]:
        """Validate filesystem constraints.

        Args:
            project_dict: Project configuration dict

        Returns:
            List of validation errors
        """
        errors = []

        # Check directory exists
        if "directory" in project_dict:
            directory = Path(project_dict["directory"]).expanduser()
            if not directory.exists():
                errors.append(
                    ValidationError(
                        "directory",
                        f"Directory does not exist: {project_dict['directory']}",
                        "error",
                    )
                )
            elif not directory.is_dir():
                errors.append(
                    ValidationError(
                        "directory",
                        f"Path is not a directory: {project_dict['directory']}",
                        "error",
                    )
                )

        return errors

    def _validate_uniqueness(self, project_dict: Dict) -> List[ValidationError]:
        """Validate project name uniqueness.

        Args:
            project_dict: Project configuration dict

        Returns:
            List of validation errors
        """
        errors = []

        if "name" in project_dict:
            name = project_dict["name"]
            existing_file = self.config_dir / f"{name}.json"

            if existing_file.exists():
                errors.append(
                    ValidationError(
                        "name",
                        f"Project '{name}' already exists",
                        "error",
                    )
                )

        return errors

    def validate_all_projects(self) -> Dict[str, List[ValidationError]]:
        """Validate all projects in config directory.

        Returns:
            Dict mapping project name to list of errors
        """
        results = {}

        if not self.config_dir.exists():
            return results

        for config_file in self.config_dir.glob("*.json"):
            project_name = config_file.stem
            _, errors = self.validate_file(config_file)
            if errors:
                results[project_name] = errors

        return results
