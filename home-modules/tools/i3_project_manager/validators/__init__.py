"""Configuration validators for i3 Project Manager.

This module provides validation for configuration files including:
- Project configuration validation (JSON schema)
- app-classes.json validation (JSON schema)
- Schema-based validation with detailed error reporting
"""

from .project_validator import ProjectValidator, ValidationError
from .schema_validator import (
    SchemaValidator,
    SchemaValidationError,
    get_validator,
    validate_app_classes_config,
)

__all__ = [
    "ProjectValidator",
    "ValidationError",
    "SchemaValidator",
    "SchemaValidationError",
    "get_validator",
    "validate_app_classes_config",
]
