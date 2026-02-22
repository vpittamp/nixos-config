"""Tests for JSON schema validation.

T095: Schema validation for app-classes.json
"""

import pytest
import json
from pathlib import Path

from i3_project_manager.validators.schema_validator import (
    SchemaValidator,
    SchemaValidationError,
    validate_app_classes_config,
    JSONSCHEMA_AVAILABLE,
)


# Skip all tests if jsonschema is not available
pytestmark = pytest.mark.skipif(
    not JSONSCHEMA_AVAILABLE,
    reason="jsonschema library not installed"
)


class TestSchemaValidator:
    """Test SchemaValidator class."""

    def test_validator_initialization(self):
        """Verify validator initializes correctly."""
        validator = SchemaValidator()
        assert validator.schemas_dir.exists()
        assert validator.schemas_dir.name == "schemas"

    def test_load_app_classes_schema(self):
        """Verify app_classes_schema loads correctly."""
        validator = SchemaValidator()
        schema = validator._load_schema("app_classes_schema")

        assert schema is not None
        assert schema["type"] == "object"
        assert "scoped_classes" in schema["properties"]
        assert "global_classes" in schema["properties"]
        assert "class_patterns" in schema["properties"]

    def test_schema_caching(self):
        """Verify schemas are cached."""
        validator = SchemaValidator()

        # Load schema twice
        schema1 = validator._load_schema("app_classes_schema")
        schema2 = validator._load_schema("app_classes_schema")

        # Should return same object (cached)
        assert schema1 is schema2


class TestValidAppClassesConfigs:
    """Test validation of valid configurations."""

    def test_minimal_valid_config(self, tmp_path):
        """Verify minimal valid configuration passes."""
        config_file = tmp_path / "app-classes.json"
        config_data = {
            "scoped_classes": [],
            "global_classes": [],
            "class_patterns": []
        }

        with open(config_file, 'w') as f:
            json.dump(config_data, f)

        is_valid, errors = validate_app_classes_config(config_file)

        assert is_valid is True
        assert len(errors) == 0

    def test_typical_valid_config(self, tmp_path):
        """Verify typical configuration passes."""
        config_file = tmp_path / "app-classes.json"
        config_data = {
            "scoped_classes": ["Ghostty", "Code", "neovide"],
            "global_classes": ["firefox", "Google-chrome"],
            "class_patterns": [
                {
                    "pattern": "glob:pwa-*",
                    "scope": "global",
                    "priority": 10,
                    "description": "PWA apps"
                },
                {
                    "pattern": "regex:^terminal.*$",
                    "scope": "scoped",
                    "priority": 5
                }
            ]
        }

        with open(config_file, 'w') as f:
            json.dump(config_data, f)

        is_valid, errors = validate_app_classes_config(config_file)

        assert is_valid is True
        assert len(errors) == 0

    def test_pattern_without_optional_fields(self, tmp_path):
        """Verify patterns work without optional fields."""
        config_file = tmp_path / "app-classes.json"
        config_data = {
            "scoped_classes": [],
            "global_classes": [],
            "class_patterns": [
                {
                    "pattern": "glob:test-*",
                    "scope": "scoped"
                    # priority and description are optional
                }
            ]
        }

        with open(config_file, 'w') as f:
            json.dump(config_data, f)

        is_valid, errors = validate_app_classes_config(config_file)

        assert is_valid is True
        assert len(errors) == 0


class TestInvalidAppClassesConfigs:
    """Test validation of invalid configurations."""

    def test_missing_required_field(self, tmp_path):
        """Verify error on missing required field."""
        config_file = tmp_path / "app-classes.json"
        config_data = {
            "scoped_classes": [],
            # Missing global_classes and class_patterns
        }

        with open(config_file, 'w') as f:
            json.dump(config_data, f)

        is_valid, errors = validate_app_classes_config(config_file)

        assert is_valid is False
        assert len(errors) > 0
        assert any("global_classes" in error.message or "required" in error.message.lower()
                   for error in errors)

    def test_invalid_class_name_pattern(self, tmp_path):
        """Verify error on invalid class name."""
        config_file = tmp_path / "app-classes.json"
        config_data = {
            "scoped_classes": ["Valid-Class", "Invalid Class With Spaces"],
            "global_classes": [],
            "class_patterns": []
        }

        with open(config_file, 'w') as f:
            json.dump(config_data, f)

        is_valid, errors = validate_app_classes_config(config_file)

        assert is_valid is False
        assert len(errors) > 0
        assert any(
            "match" in error.message.lower()
            or "scoped_classes" in "/".join(str(p) for p in error.path)
            for error in errors
        )

    def test_invalid_scope_value(self, tmp_path):
        """Verify error on invalid scope value."""
        config_file = tmp_path / "app-classes.json"
        config_data = {
            "scoped_classes": [],
            "global_classes": [],
            "class_patterns": [
                {
                    "pattern": "glob:test-*",
                    "scope": "invalid_scope"  # Should be 'scoped' or 'global'
                }
            ]
        }

        with open(config_file, 'w') as f:
            json.dump(config_data, f)

        is_valid, errors = validate_app_classes_config(config_file)

        assert is_valid is False
        assert len(errors) > 0
        assert any("scope" in error.path or "enum" in error.message.lower()
                   for error in errors)

    def test_empty_pattern_string(self, tmp_path):
        """Verify error on empty pattern."""
        config_file = tmp_path / "app-classes.json"
        config_data = {
            "scoped_classes": [],
            "global_classes": [],
            "class_patterns": [
                {
                    "pattern": "",  # Empty pattern
                    "scope": "scoped"
                }
            ]
        }

        with open(config_file, 'w') as f:
            json.dump(config_data, f)

        is_valid, errors = validate_app_classes_config(config_file)

        assert is_valid is False
        assert len(errors) > 0
        assert any("pattern" in error.path or "minLength" in error.message
                   for error in errors)

    def test_additional_properties_not_allowed(self, tmp_path):
        """Verify error on additional properties in pattern."""
        config_file = tmp_path / "app-classes.json"
        config_data = {
            "scoped_classes": [],
            "global_classes": [],
            "class_patterns": [
                {
                    "pattern": "glob:test-*",
                    "scope": "scoped",
                    "extra_field": "not allowed"  # Should fail
                }
            ]
        }

        with open(config_file, 'w') as f:
            json.dump(config_data, f)

        is_valid, errors = validate_app_classes_config(config_file)

        assert is_valid is False
        assert len(errors) > 0
        assert any("additional" in error.message.lower() for error in errors)

    def test_invalid_json_syntax(self, tmp_path):
        """Verify error on invalid JSON."""
        config_file = tmp_path / "app-classes.json"

        with open(config_file, 'w') as f:
            f.write('{ "scoped_classes": [invalid json] }')

        is_valid, errors = validate_app_classes_config(config_file)

        assert is_valid is False
        assert len(errors) > 0
        assert any("JSON" in error.message for error in errors)

    def test_nonexistent_file(self, tmp_path):
        """Verify error on missing file."""
        config_file = tmp_path / "nonexistent.json"

        is_valid, errors = validate_app_classes_config(config_file)

        assert is_valid is False
        assert len(errors) > 0
        assert any("not found" in error.message for error in errors)


class TestSchemaValidationError:
    """Test SchemaValidationError dataclass."""

    def test_error_creation(self):
        """Verify error object creation."""
        error = SchemaValidationError(
            path="scoped_classes[0]",
            message="Invalid format",
            schema_path="properties.scoped_classes.items.pattern",
            value="Invalid Value"
        )

        assert error.path == "scoped_classes[0]"
        assert error.message == "Invalid format"
        assert error.schema_path == "properties.scoped_classes.items.pattern"
        assert error.value == "Invalid Value"


class TestValidatorLogging:
    """Test validation error logging."""

    def test_log_validation_errors(self, tmp_path, caplog):
        """Verify errors are logged correctly."""
        import logging
        caplog.set_level(logging.ERROR)

        validator = SchemaValidator()
        config_file = tmp_path / "app-classes.json"

        errors = [
            SchemaValidationError(
                path="scoped_classes[1]",
                message="Does not match pattern",
                schema_path="items.pattern",
                value="Invalid Class"
            ),
            SchemaValidationError(
                path="class_patterns[0].scope",
                message="Not one of enum values",
                schema_path="properties.scope.enum",
                value="invalid"
            )
        ]

        validator.log_validation_errors(errors, config_file)

        # Check that errors were logged
        assert "validation failed" in caplog.text.lower()
        assert "2 error(s)" in caplog.text
        assert "scoped_classes[1]" in caplog.text
        assert "class_patterns[0].scope" in caplog.text
