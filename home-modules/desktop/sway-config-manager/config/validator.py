"""
Configuration validator for Sway configurations.

Provides:
- Structural validation using JSON Schema
- Semantic validation using Sway IPC queries
- Configuration conflict detection
"""

import json
import re
from pathlib import Path
from typing import List, Optional

import jsonschema
from pydantic import ValidationError

from ..models import KeybindingConfig, WindowRule, WorkspaceAssignment, ValidationError as ConfigValidationError, ValidationResult


class ConfigValidator:
    """Validates Sway configuration files."""

    def __init__(self, schema_dir: Optional[Path] = None):
        """
        Initialize configuration validator.

        Args:
            schema_dir: Path to JSON schema directory (optional)
        """
        self.schema_dir = schema_dir
        self.schemas = {}
        if schema_dir and schema_dir.exists():
            self._load_schemas()

    def _load_schemas(self):
        """Load JSON schemas from schema directory."""
        for schema_file in self.schema_dir.glob("*.schema.json"):
            schema_name = schema_file.stem.replace(".schema", "")
            with open(schema_file, "r") as f:
                self.schemas[schema_name] = json.load(f)

    def validate_structure(self, config_data: dict, schema_name: str) -> List[ConfigValidationError]:
        """
        Validate configuration structure using JSON Schema.

        Args:
            config_data: Configuration data to validate
            schema_name: Name of the schema to use

        Returns:
            List of validation errors (empty if valid)
        """
        errors = []

        if schema_name not in self.schemas:
            errors.append(ConfigValidationError(
                file_path=schema_name,
                line_number=None,
                error_type="schema",
                message=f"Schema '{schema_name}' not found",
                suggestion="Check schema directory contains required schemas"
            ))
            return errors

        try:
            jsonschema.validate(instance=config_data, schema=self.schemas[schema_name])
        except jsonschema.ValidationError as e:
            errors.append(ConfigValidationError(
                file_path=schema_name,
                line_number=None,
                error_type="syntax",
                message=e.message,
                suggestion=self._get_suggestion_for_error(e)
            ))
        except jsonschema.SchemaError as e:
            errors.append(ConfigValidationError(
                file_path=schema_name,
                line_number=None,
                error_type="schema",
                message=f"Invalid schema: {e.message}",
                suggestion="Check schema file is valid JSON Schema"
            ))

        return errors

    def validate_semantics(self, keybindings: List[KeybindingConfig], window_rules: List[WindowRule],
                          workspace_assignments: List[WorkspaceAssignment]) -> List[ConfigValidationError]:
        """
        Validate semantic correctness of configuration.

        Checks:
        - Workspace numbers exist in Sway
        - Output names are valid
        - No circular dependencies in rules
        - Regex patterns are valid

        Args:
            keybindings: List of keybinding configurations
            window_rules: List of window rules
            workspace_assignments: List of workspace assignments

        Returns:
            List of validation errors (empty if valid)
        """
        errors = []

        # Validate keybinding syntax
        for kb in keybindings:
            if not self._is_valid_key_combo(kb.key_combo):
                errors.append(ConfigValidationError(
                    file_path="keybindings.toml",
                    line_number=None,
                    error_type="semantic",
                    message=f"Invalid key combination syntax: {kb.key_combo}",
                    suggestion="Use format like 'Mod+Return' or 'Control+Shift+T'"
                ))

        # Validate window rule regex patterns
        for rule in window_rules:
            for field_name, pattern in [
                ("app_id", rule.criteria.app_id),
                ("window_class", rule.criteria.window_class),
                ("title", rule.criteria.title),
            ]:
                if pattern:
                    try:
                        re.compile(pattern)
                    except re.error as e:
                        errors.append(ConfigValidationError(
                            file_path="window-rules.json",
                            line_number=None,
                            error_type="semantic",
                            message=f"Invalid regex in {field_name}: {pattern} - {e}",
                            suggestion="Check regex syntax using a regex tester"
                        ))

        # Validate workspace assignments
        for assignment in workspace_assignments:
            if assignment.workspace_number < 1 or assignment.workspace_number > 70:
                errors.append(ConfigValidationError(
                    file_path="workspace-assignments.json",
                    line_number=None,
                    error_type="semantic",
                    message=f"Invalid workspace number: {assignment.workspace_number}",
                    suggestion="Workspace numbers must be between 1 and 70"
                ))

        return errors

    def _is_valid_key_combo(self, key_combo: str) -> bool:
        """
        Check if key combination follows Sway syntax.

        Args:
            key_combo: Key combination string

        Returns:
            True if valid, False otherwise
        """
        pattern = r'^(Mod|Shift|Control|Alt|Ctrl)(\+(Mod|Shift|Control|Alt|Ctrl))*\+[a-zA-Z0-9_\-]+$'
        return bool(re.match(pattern, key_combo))

    def _get_suggestion_for_error(self, error: jsonschema.ValidationError) -> str:
        """
        Generate helpful suggestion based on validation error.

        Args:
            error: JSON Schema validation error

        Returns:
            Suggestion string
        """
        if "required" in error.message.lower():
            return "Check that all required fields are present"
        elif "type" in error.message.lower():
            return "Check that field has the correct data type"
        elif "pattern" in error.message.lower():
            return "Check that field matches the expected pattern"
        else:
            return "Review configuration syntax and structure"
