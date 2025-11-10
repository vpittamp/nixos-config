"""JSON Schema validation tests for Feature 001 contracts.

Tests validation logic for:
- monitor-role-config.schema.json
- workspace-assignments.schema.json
"""

import json
import pytest
from pathlib import Path
from jsonschema import validate, ValidationError, Draft7Validator


# Schema paths
CONTRACTS_DIR = Path("/etc/nixos/specs/001-declarative-workspace-monitor/contracts")
MONITOR_ROLE_SCHEMA = CONTRACTS_DIR / "monitor-role-config.schema.json"
WORKSPACE_ASSIGNMENTS_SCHEMA = CONTRACTS_DIR / "workspace-assignments.schema.json"


def load_schema(schema_path: Path) -> dict:
    """Load JSON schema from file.

    Args:
        schema_path: Path to schema file

    Returns:
        dict: Parsed JSON schema
    """
    with open(schema_path, "r") as f:
        return json.load(f)


@pytest.fixture
def monitor_role_schema():
    """Load monitor role configuration schema."""
    return load_schema(MONITOR_ROLE_SCHEMA)


@pytest.fixture
def workspace_assignments_schema():
    """Load workspace assignments schema."""
    return load_schema(WORKSPACE_ASSIGNMENTS_SCHEMA)


class TestMonitorRoleConfigSchema:
    """Test cases for monitor-role-config.schema.json validation."""

    def test_valid_monitor_role_config(self, monitor_role_schema):
        """Test validation of valid MonitorRoleConfig."""
        valid_config = {
            "app_name": "code",
            "preferred_workspace": 2,
            "preferred_monitor_role": "primary",
            "source": "app-registry",
        }

        # Should not raise ValidationError
        validate(instance=valid_config, schema=monitor_role_schema)

    def test_monitor_role_config_null_role(self, monitor_role_schema):
        """Test validation when preferred_monitor_role is null."""
        config_with_null = {
            "app_name": "firefox",
            "preferred_workspace": 3,
            "preferred_monitor_role": None,
            "source": "app-registry",
        }

        # Should not raise ValidationError
        validate(instance=config_with_null, schema=monitor_role_schema)

    def test_monitor_role_config_invalid_role(self, monitor_role_schema):
        """Test validation fails for invalid monitor role."""
        invalid_config = {
            "app_name": "code",
            "preferred_workspace": 2,
            "preferred_monitor_role": "quaternary",  # Invalid
            "source": "app-registry",
        }

        with pytest.raises(ValidationError):
            validate(instance=invalid_config, schema=monitor_role_schema)

    def test_monitor_role_config_workspace_out_of_range(self, monitor_role_schema):
        """Test validation fails for workspace number outside 1-70."""
        invalid_config = {
            "app_name": "code",
            "preferred_workspace": 71,  # Out of range
            "preferred_monitor_role": "primary",
            "source": "app-registry",
        }

        with pytest.raises(ValidationError):
            validate(instance=invalid_config, schema=monitor_role_schema)

    def test_monitor_role_config_missing_required_field(self, monitor_role_schema):
        """Test validation fails when required field is missing."""
        invalid_config = {
            # Missing app_name
            "preferred_workspace": 2,
            "preferred_monitor_role": "primary",
            "source": "app-registry",
        }

        with pytest.raises(ValidationError):
            validate(instance=invalid_config, schema=monitor_role_schema)


class TestWorkspaceAssignmentsSchema:
    """Test cases for workspace-assignments.schema.json validation."""

    def test_valid_workspace_assignments(self, workspace_assignments_schema):
        """Test validation of valid workspace assignments config."""
        valid_config = {
            "version": "1.0",
            "assignments": [
                {
                    "workspace": 1,
                    "app_name": "terminal",
                    "monitor_role": "primary",
                    "source": "app-registry",
                },
                {
                    "workspace": 3,
                    "app_name": "firefox",
                    "monitor_role": "secondary",
                    "source": "app-registry",
                },
            ],
        }

        # Should not raise ValidationError
        validate(instance=valid_config, schema=workspace_assignments_schema)

    def test_workspace_assignments_empty_array(self, workspace_assignments_schema):
        """Test validation with empty assignments array."""
        config = {
            "version": "1.0",
            "assignments": [],
        }

        # Should not raise ValidationError
        validate(instance=config, schema=workspace_assignments_schema)

    def test_workspace_assignments_invalid_version(self, workspace_assignments_schema):
        """Test validation fails for invalid version."""
        invalid_config = {
            "version": "2.0",  # Invalid version
            "assignments": [],
        }

        with pytest.raises(ValidationError):
            validate(instance=invalid_config, schema=workspace_assignments_schema)

    def test_workspace_assignments_invalid_source(self, workspace_assignments_schema):
        """Test validation fails for invalid source."""
        invalid_config = {
            "version": "1.0",
            "assignments": [
                {
                    "workspace": 1,
                    "app_name": "terminal",
                    "monitor_role": "primary",
                    "source": "unknown-source",  # Invalid
                }
            ],
        }

        with pytest.raises(ValidationError):
            validate(instance=invalid_config, schema=workspace_assignments_schema)


class TestFloatingWindowConfigSchema:
    """Test cases for FloatingWindowConfig schema validation."""

    def test_valid_floating_window_config(self, monitor_role_schema):
        """Test validation of valid FloatingWindowConfig."""
        valid_config = {
            "app_name": "btop",
            "floating": True,
            "floating_size": "medium",
            "scope": "global",
        }

        # Should not raise ValidationError
        validate(instance=valid_config, schema=monitor_role_schema)

    def test_floating_window_config_null_size(self, monitor_role_schema):
        """Test validation when floating_size is null (natural size)."""
        config_null_size = {
            "app_name": "calculator",
            "floating": True,
            "floating_size": None,
            "scope": "scoped",
        }

        # Should not raise ValidationError
        validate(instance=config_null_size, schema=monitor_role_schema)

    def test_floating_window_config_not_floating(self, monitor_role_schema):
        """Test validation for non-floating window."""
        config_not_floating = {
            "app_name": "code",
            "floating": False,
            "floating_size": None,
            "scope": "scoped",
        }

        # Should not raise ValidationError
        validate(instance=config_not_floating, schema=monitor_role_schema)


class TestMonitorStateV2Schema:
    """Test cases for MonitorStateV2 schema validation."""

    def test_valid_monitor_state_v2(self, monitor_role_schema):
        """Test validation of valid MonitorStateV2 state file."""
        valid_state = {
            "version": "2.0",
            "monitor_roles": {
                "primary": "HEADLESS-1",
                "secondary": "HEADLESS-2",
                "tertiary": "HEADLESS-3",
            },
            "workspaces": {
                "1": {
                    "workspace_num": 1,
                    "output": "HEADLESS-1",
                    "monitor_role": "primary",
                    "app_name": "terminal",
                    "source": "app-registry",
                },
                "3": {
                    "workspace_num": 3,
                    "output": "HEADLESS-2",
                    "monitor_role": "secondary",
                    "app_name": "firefox",
                    "source": "app-registry",
                },
            },
            "last_updated": "2025-11-10T12:00:00Z",
        }

        # Should not raise ValidationError
        validate(instance=valid_state, schema=monitor_role_schema)

    def test_monitor_state_v2_invalid_version(self, monitor_role_schema):
        """Test validation fails for invalid version."""
        invalid_state = {
            "version": "1.0",  # Invalid version
            "monitor_roles": {"primary": "HEADLESS-1"},
            "workspaces": {},
            "last_updated": "2025-11-10T12:00:00Z",
        }

        with pytest.raises(ValidationError):
            validate(instance=invalid_state, schema=monitor_role_schema)


def validate_schema_against_draft7(schema: dict):
    """Validate that schema itself conforms to Draft 7 specification.

    Args:
        schema: JSON schema to validate

    Raises:
        ValidationError: If schema is invalid
    """
    Draft7Validator.check_schema(schema)


def test_monitor_role_schema_is_valid(monitor_role_schema):
    """Test that monitor-role-config.schema.json is valid Draft 7."""
    validate_schema_against_draft7(monitor_role_schema)


def test_workspace_assignments_schema_is_valid(workspace_assignments_schema):
    """Test that workspace-assignments.schema.json is valid Draft 7."""
    validate_schema_against_draft7(workspace_assignments_schema)
