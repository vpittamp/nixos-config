"""JSON schema validation for configuration files.

T095: Schema validation for app-classes.json and project configurations.
FR-130: Detailed error logging to systemd journal on validation failure.
"""

import json
import logging
from pathlib import Path
from typing import Dict, List, Tuple, Any, Optional
from dataclasses import dataclass

try:
    import jsonschema
    from jsonschema import Draft7Validator, ValidationError
    JSONSCHEMA_AVAILABLE = True
except ImportError:
    JSONSCHEMA_AVAILABLE = False
    jsonschema = None
    Draft7Validator = None
    ValidationError = None


logger = logging.getLogger(__name__)


@dataclass
class SchemaValidationError:
    """Represents a schema validation error.

    Attributes:
        path: JSON path to the error (e.g., "scoped_classes[2]")
        message: Error message
        schema_path: Path in the schema that failed
        value: The invalid value
    """

    path: str
    message: str
    schema_path: str
    value: Any


class SchemaValidator:
    """Validates configuration files against JSON schemas.

    T095: Schema validation implementation
    FR-130: Detailed error logging

    Examples:
        >>> validator = SchemaValidator()
        >>> is_valid, errors = validator.validate_app_classes_file(config_file)
        >>> if not is_valid:
        ...     for error in errors:
        ...         logger.error(f"Validation error at {error.path}: {error.message}")
    """

    def __init__(self):
        """Initialize schema validator."""
        if not JSONSCHEMA_AVAILABLE:
            logger.warning(
                "jsonschema library not available. Schema validation disabled. "
                "Install with: pip install jsonschema"
            )

        self.schemas_dir = Path(__file__).parent.parent / "schemas"
        self._schema_cache: Dict[str, Dict] = {}

    def _load_schema(self, schema_name: str) -> Optional[Dict]:
        """Load a JSON schema from the schemas directory.

        Args:
            schema_name: Name of the schema file (without .json extension)

        Returns:
            Loaded schema dictionary or None if not found
        """
        if schema_name in self._schema_cache:
            return self._schema_cache[schema_name]

        schema_file = self.schemas_dir / f"{schema_name}.json"
        if not schema_file.exists():
            logger.error(f"Schema file not found: {schema_file}")
            return None

        try:
            with open(schema_file, 'r') as f:
                schema = json.load(f)
            self._schema_cache[schema_name] = schema
            return schema
        except Exception as e:
            logger.error(f"Failed to load schema {schema_name}: {e}")
            return None

    def validate_data(
        self,
        data: Dict,
        schema_name: str
    ) -> Tuple[bool, List[SchemaValidationError]]:
        """Validate data against a schema.

        Args:
            data: Data to validate
            schema_name: Name of schema to validate against

        Returns:
            Tuple of (is_valid, errors)
        """
        if not JSONSCHEMA_AVAILABLE:
            logger.warning("jsonschema not available, skipping validation")
            return True, []

        schema = self._load_schema(schema_name)
        if not schema:
            logger.error(f"Schema '{schema_name}' not found, skipping validation")
            return True, []  # Don't fail if schema is missing

        errors: List[SchemaValidationError] = []

        try:
            validator = Draft7Validator(schema)
            validation_errors = sorted(validator.iter_errors(data), key=str)

            for error in validation_errors:
                # Build JSON path
                path = ".".join(str(p) for p in error.absolute_path) if error.absolute_path else "root"
                schema_path = ".".join(str(p) for p in error.absolute_schema_path) if error.absolute_schema_path else "schema"

                errors.append(SchemaValidationError(
                    path=path,
                    message=error.message,
                    schema_path=schema_path,
                    value=error.instance
                ))

        except Exception as e:
            logger.error(f"Validation error: {e}")
            errors.append(SchemaValidationError(
                path="validation",
                message=f"Validation failed: {e}",
                schema_path="",
                value=None
            ))

        return len(errors) == 0, errors

    def validate_app_classes_file(
        self,
        config_file: Path
    ) -> Tuple[bool, List[SchemaValidationError]]:
        """Validate app-classes.json file.

        Args:
            config_file: Path to app-classes.json

        Returns:
            Tuple of (is_valid, errors)

        T095: app-classes.json schema validation
        """
        if not config_file.exists():
            logger.error(f"Config file not found: {config_file}")
            return False, [SchemaValidationError(
                path="file",
                message=f"Configuration file not found: {config_file}",
                schema_path="",
                value=None
            )]

        try:
            with open(config_file, 'r') as f:
                data = json.load(f)
        except json.JSONDecodeError as e:
            logger.error(f"Invalid JSON in {config_file}: {e}")
            return False, [SchemaValidationError(
                path=f"line {e.lineno}",
                message=f"Invalid JSON: {e.msg}",
                schema_path="",
                value=None
            )]
        except Exception as e:
            logger.error(f"Failed to read {config_file}: {e}")
            return False, [SchemaValidationError(
                path="file",
                message=f"Failed to read file: {e}",
                schema_path="",
                value=None
            )]

        return self.validate_data(data, "app_classes_schema")

    def log_validation_errors(
        self,
        errors: List[SchemaValidationError],
        config_file: Path,
        log_level: int = logging.ERROR
    ) -> None:
        """Log validation errors to systemd journal.

        Args:
            errors: List of validation errors
            config_file: Path to the config file
            log_level: Logging level to use

        FR-130: Detailed error logging to systemd journal
        """
        if not errors:
            return

        logger.log(
            log_level,
            f"Configuration validation failed for {config_file} with {len(errors)} error(s)"
        )

        for i, error in enumerate(errors, 1):
            logger.log(
                log_level,
                f"  Error {i}/{len(errors)}: {error.path} - {error.message}"
            )
            if error.value is not None:
                logger.log(
                    log_level,
                    f"    Invalid value: {error.value}"
                )
            if error.schema_path:
                logger.log(
                    log_level,
                    f"    Schema path: {error.schema_path}"
                )

    def validate_and_log(
        self,
        config_file: Path,
        schema_name: str = "app_classes_schema"
    ) -> bool:
        """Validate configuration file and log errors if any.

        Convenience method that combines validation and logging.

        Args:
            config_file: Path to configuration file
            schema_name: Schema to validate against

        Returns:
            True if validation passed, False otherwise

        T095: Convenience method for daemon use
        """
        is_valid, errors = self.validate_app_classes_file(config_file)

        if not is_valid:
            self.log_validation_errors(errors, config_file)

        return is_valid


# Global validator instance
_validator = None


def get_validator() -> SchemaValidator:
    """Get global schema validator instance.

    Returns:
        Shared SchemaValidator instance
    """
    global _validator
    if _validator is None:
        _validator = SchemaValidator()
    return _validator


def validate_app_classes_config(config_file: Path) -> Tuple[bool, List[SchemaValidationError]]:
    """Validate app-classes.json configuration file.

    Convenience function for quick validation.

    Args:
        config_file: Path to app-classes.json

    Returns:
        Tuple of (is_valid, errors)

    Examples:
        >>> is_valid, errors = validate_app_classes_config(Path("~/.config/i3/app-classes.json"))
        >>> if not is_valid:
        ...     for error in errors:
        ...         print(f"{error.path}: {error.message}")
    """
    validator = get_validator()
    return validator.validate_app_classes_file(config_file)
