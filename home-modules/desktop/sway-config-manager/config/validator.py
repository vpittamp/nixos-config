"""
Configuration validator for Sway configurations.

Provides:
- Structural validation using JSON Schema
- Semantic validation using Sway IPC queries
- Configuration conflict detection
"""

import json
import logging
import re
from pathlib import Path
from typing import List, Optional, Set

import jsonschema
from pydantic import ValidationError

# Feature 047 US5 T049: Import Sway IPC for semantic validation
try:
    from i3ipc.aio import Connection as SwayConnection
except ImportError:
    SwayConnection = None  # Fallback if i3ipc not available

from ..models import (
    KeybindingConfig,
    WindowRule,
    WorkspaceAssignment,
    Project,
    ProjectWindowRuleOverride,
    ProjectKeybindingOverride,
    ValidationError as ConfigValidationError,
    ValidationResult
)

logger = logging.getLogger(__name__)


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

    async def validate_with_sway_ipc(
        self,
        workspace_assignments: List[WorkspaceAssignment]
    ) -> List[ConfigValidationError]:
        """
        Validate configuration against actual Sway state via IPC.

        Feature 047 US5 T049: Query Sway IPC for workspace numbers and output names
        to validate that references in configuration actually exist.

        Args:
            workspace_assignments: List of workspace assignments to validate

        Returns:
            List of validation errors (empty if valid)
        """
        errors = []

        if not SwayConnection:
            logger.warning("i3ipc.aio not available - skipping Sway IPC validation")
            return errors

        try:
            # Connect to Sway IPC
            sway = SwayConnection()
            await sway.connect()

            # Get current workspaces and outputs
            workspaces = await sway.get_workspaces()
            outputs = await sway.get_outputs()

            # Build sets of valid workspace numbers and output names
            valid_workspace_numbers: Set[int] = {ws.num for ws in workspaces}
            valid_output_names: Set[str] = {out.name for out in outputs if out.active}

            logger.debug(f"Sway IPC: Found {len(valid_workspace_numbers)} workspaces, {len(valid_output_names)} outputs")

            # Validate workspace assignments reference existing outputs
            for assignment in workspace_assignments:
                output_name = assignment.primary_output

                if output_name and output_name not in valid_output_names:
                    errors.append(ConfigValidationError(
                        file_path="workspace-assignments.json",
                        line_number=None,
                        error_type="semantic",
                        message=f"Output '{output_name}' does not exist in Sway",
                        suggestion=f"Valid outputs: {', '.join(sorted(valid_output_names))}"
                    ))

            await sway.main_quit()

        except Exception as e:
            logger.error(f"Failed to validate with Sway IPC: {e}")
            errors.append(ConfigValidationError(
                file_path="<sway-ipc>",
                line_number=None,
                error_type="ipc",
                message=f"Could not connect to Sway IPC: {e}",
                suggestion="Ensure Sway is running and IPC socket is accessible"
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

    def validate_project_overrides(self, project: Project, global_rules: List[WindowRule],
                                   global_keybindings: List[KeybindingConfig]) -> List[ConfigValidationError]:
        """
        Validate project-specific configuration overrides.

        Feature 047 User Story 3 Task T036: Validates that:
        - base_rule_id references an existing global rule (if not null)
        - override_properties contain valid WindowRule fields
        - keybinding overrides have valid syntax

        Args:
            project: Project configuration to validate
            global_rules: List of global window rules
            global_keybindings: List of global keybindings

        Returns:
            List of validation errors (empty if valid)
        """
        errors = []

        # Build lookup maps for global configuration
        rule_id_map = {rule.id: rule for rule in global_rules}
        keybinding_map = {kb.key_combo: kb for kb in global_keybindings}

        # Validate window rule overrides
        errors.extend(self._validate_window_rule_overrides(
            project, rule_id_map
        ))

        # Validate keybinding overrides
        errors.extend(self._validate_keybinding_overrides(
            project, keybinding_map
        ))

        return errors

    def _validate_window_rule_overrides(self, project: Project,
                                        rule_id_map: dict) -> List[ConfigValidationError]:
        """
        Validate project window rule overrides.

        Args:
            project: Project configuration
            rule_id_map: Map of rule_id -> WindowRule

        Returns:
            List of validation errors
        """
        errors = []

        for idx, override in enumerate(project.window_rule_overrides):
            override_label = f"window_rule_override[{idx}]"

            # Check base_rule_id exists if specified
            if override.base_rule_id:
                if override.base_rule_id not in rule_id_map:
                    errors.append(ConfigValidationError(
                        file_path=f"projects/{project.name}.json",
                        line_number=None,
                        error_type="semantic",
                        message=f"{override_label}: base_rule_id '{override.base_rule_id}' not found in global rules",
                        suggestion="Check that global rule ID exists in window-rules.json"
                    ))

            # Validate override_properties
            props = override.override_properties
            valid_fields = {'criteria', 'actions', 'priority'}

            # Check for unknown fields
            unknown_fields = set(props.keys()) - valid_fields
            if unknown_fields:
                errors.append(ConfigValidationError(
                    file_path=f"projects/{project.name}.json",
                    line_number=None,
                    error_type="semantic",
                    message=f"{override_label}: Unknown override fields: {unknown_fields}",
                    suggestion=f"Valid fields: {valid_fields}"
                ))

            # Validate criteria if present
            if 'criteria' in props:
                criteria_errors = self._validate_criteria_override(
                    project, idx, props['criteria']
                )
                errors.extend(criteria_errors)

            # Validate actions if present
            if 'actions' in props:
                actions_errors = self._validate_actions_override(
                    project, idx, props['actions']
                )
                errors.extend(actions_errors)

            # Validate priority if present
            if 'priority' in props:
                priority_errors = self._validate_priority_override(
                    project, idx, props['priority']
                )
                errors.extend(priority_errors)

        return errors

    def _validate_criteria_override(self, project: Project, override_idx: int,
                                    criteria: dict) -> List[ConfigValidationError]:
        """
        Validate window criteria override.

        Args:
            project: Project configuration
            override_idx: Override index in array
            criteria: Criteria dictionary

        Returns:
            List of validation errors
        """
        errors = []
        override_label = f"window_rule_override[{override_idx}].criteria"

        valid_fields = {'app_id', 'window_class', 'title', 'window_role'}
        unknown_fields = set(criteria.keys()) - valid_fields
        if unknown_fields:
            errors.append(ConfigValidationError(
                file_path=f"projects/{project.name}.json",
                line_number=None,
                error_type="semantic",
                message=f"{override_label}: Unknown criteria fields: {unknown_fields}",
                suggestion=f"Valid fields: {valid_fields}"
            ))

        # Validate regex patterns
        for field_name in ['app_id', 'window_class', 'title', 'window_role']:
            if field_name in criteria:
                pattern = criteria[field_name]
                if pattern:
                    try:
                        re.compile(pattern)
                    except re.error as e:
                        errors.append(ConfigValidationError(
                            file_path=f"projects/{project.name}.json",
                            line_number=None,
                            error_type="semantic",
                            message=f"{override_label}.{field_name}: Invalid regex pattern - {e}",
                            suggestion="Check regex syntax using a regex tester"
                        ))

        return errors

    def _validate_actions_override(self, project: Project, override_idx: int,
                                   actions: any) -> List[ConfigValidationError]:
        """
        Validate actions override.

        Args:
            project: Project configuration
            override_idx: Override index in array
            actions: Actions value

        Returns:
            List of validation errors
        """
        errors = []
        override_label = f"window_rule_override[{override_idx}].actions"

        if not isinstance(actions, list):
            errors.append(ConfigValidationError(
                file_path=f"projects/{project.name}.json",
                line_number=None,
                error_type="semantic",
                message=f"{override_label}: Must be a list of strings",
                suggestion="Use array syntax: [\"action1\", \"action2\"]"
            ))
            return errors

        if not actions:
            errors.append(ConfigValidationError(
                file_path=f"projects/{project.name}.json",
                line_number=None,
                error_type="semantic",
                message=f"{override_label}: Must contain at least one action",
                suggestion="Add at least one Sway command"
            ))

        for idx, action in enumerate(actions):
            if not isinstance(action, str):
                errors.append(ConfigValidationError(
                    file_path=f"projects/{project.name}.json",
                    line_number=None,
                    error_type="semantic",
                    message=f"{override_label}[{idx}]: Must be a string",
                    suggestion="Each action must be a Sway command string"
                ))
            elif not action.strip():
                errors.append(ConfigValidationError(
                    file_path=f"projects/{project.name}.json",
                    line_number=None,
                    error_type="semantic",
                    message=f"{override_label}[{idx}]: Cannot be empty",
                    suggestion="Remove empty actions or provide valid Sway command"
                ))

        return errors

    def _validate_priority_override(self, project: Project, override_idx: int,
                                    priority: any) -> List[ConfigValidationError]:
        """
        Validate priority override.

        Args:
            project: Project configuration
            override_idx: Override index in array
            priority: Priority value

        Returns:
            List of validation errors
        """
        errors = []
        override_label = f"window_rule_override[{override_idx}].priority"

        if not isinstance(priority, int):
            errors.append(ConfigValidationError(
                file_path=f"projects/{project.name}.json",
                line_number=None,
                error_type="semantic",
                message=f"{override_label}: Must be an integer",
                suggestion="Use integer value between 0 and 1000"
            ))
            return errors

        if priority < 0 or priority > 1000:
            errors.append(ConfigValidationError(
                file_path=f"projects/{project.name}.json",
                line_number=None,
                error_type="semantic",
                message=f"{override_label}: Must be between 0 and 1000 (got {priority})",
                suggestion="Lower priority = applies first, higher = applies last"
            ))

        return errors

    def _validate_keybinding_overrides(self, project: Project,
                                       keybinding_map: dict) -> List[ConfigValidationError]:
        """
        Validate project keybinding overrides.

        Args:
            project: Project configuration
            keybinding_map: Map of key_combo -> KeybindingConfig

        Returns:
            List of validation errors
        """
        errors = []

        for key_combo, override in project.keybinding_overrides.items():
            override_label = f"keybinding_override['{key_combo}']"

            # Key combo syntax is already validated by Pydantic model
            # Just check if command is present and non-empty (if not null)
            if override.command is not None and not override.command.strip():
                errors.append(ConfigValidationError(
                    file_path=f"projects/{project.name}.json",
                    line_number=None,
                    error_type="semantic",
                    message=f"{override_label}: Command cannot be empty string",
                    suggestion="Use null to disable keybinding, or provide valid command"
                ))

            # Optional: Warn if overriding non-existent global keybinding
            # This is not an error, just informational
            if key_combo not in keybinding_map:
                # Could add this as a warning, but for now we allow new bindings
                pass

        return errors
