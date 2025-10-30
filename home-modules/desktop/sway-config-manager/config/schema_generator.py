"""
JSON Schema generator from Pydantic models.

Generates JSON schemas for configuration validation.
"""

import json
from pathlib import Path
from typing import Type

from pydantic import BaseModel

from ..models import (
    AppearanceConfig,
    KeybindingConfig,
    WindowRule,
    WorkspaceAssignment,
    ProjectWindowRuleOverride,
    ConfigurationVersion,
)


class SchemaGenerator:
    """Generates JSON schemas from Pydantic models."""

    def __init__(self, schema_dir: Path):
        """
        Initialize schema generator.

        Args:
            schema_dir: Directory to write JSON schemas
        """
        self.schema_dir = schema_dir
        self.schema_dir.mkdir(parents=True, exist_ok=True)

    def generate_all_schemas(self):
        """Generate JSON schemas for all configuration models."""
        models = {
            "keybindings": self._create_keybindings_schema(),
            "window-rules": self._create_window_rules_schema(),
            "workspace-assignments": self._create_workspace_assignments_schema(),
            "project": self._create_project_schema(),
            "appearance": self._create_appearance_schema(),
        }

        for name, schema in models.items():
            self._write_schema(name, schema)

    def _create_keybindings_schema(self) -> dict:
        """Create schema for keybindings.toml structure."""
        # TOML will be parsed to dict, validate the resulting structure
        return {
            "$schema": "http://json-schema.org/draft-07/schema#",
            "title": "Sway Keybindings Configuration",
            "type": "object",
            "properties": {
                "keybindings": {
                    "type": "object",
                    "patternProperties": {
                        ".*": {
                            "oneOf": [
                                {"type": "string"},  # Simple string command
                                {
                                    "type": "object",
                                    "properties": {
                                        "command": {"type": "string"},
                                        "description": {"type": "string"},
                                        "mode": {"type": "string"}
                                    },
                                    "required": ["command"]
                                }
                            ]
                        }
                    }
                }
            },
            "required": ["keybindings"]
        }

    def _create_window_rules_schema(self) -> dict:
        """Create schema for window-rules.json."""
        return {
            "$schema": "http://json-schema.org/draft-07/schema#",
            "title": "Sway Window Rules Configuration",
            "type": "object",
            "properties": {
                "version": {"type": "string"},
                "rules": {
                    "type": "array",
                    "items": WindowRule.model_json_schema()
                }
            },
            "required": ["version", "rules"]
        }

    def _create_workspace_assignments_schema(self) -> dict:
        """Create schema for workspace-assignments.json."""
        return {
            "$schema": "http://json-schema.org/draft-07/schema#",
            "title": "Sway Workspace Assignments Configuration",
            "type": "object",
            "properties": {
                "version": {"type": "string"},
                "assignments": {
                    "type": "array",
                    "items": WorkspaceAssignment.model_json_schema()
                }
            },
            "required": ["version", "assignments"]
        }

    def _create_project_schema(self) -> dict:
        """Create schema for project configuration files."""
        return {
            "$schema": "http://json-schema.org/draft-07/schema#",
            "title": "Sway Project Configuration",
            "type": "object",
            "properties": {
                "project_name": {"type": "string"},
                "directory": {"type": "string"},
                "icon": {"type": "string"},
                "window_rule_overrides": {
                    "type": "array",
                    "items": ProjectWindowRuleOverride.model_json_schema()
                },
                "keybinding_overrides": {
                    "type": "object",
                    "patternProperties": {
                        ".*": {
                            "type": "object",
                            "properties": {
                                "command": {"type": "string"},
                                "description": {"type": "string"}
                            },
                            "required": ["command"]
                        }
                    }
                }
            },
            "required": ["project_name"]
        }

    def _create_appearance_schema(self) -> dict:
        """Create schema for appearance.json configuration."""
        schema = AppearanceConfig.model_json_schema()
        schema.update({
            "$schema": "http://json-schema.org/draft-07/schema#",
            "title": "Sway Appearance Configuration",
        })
        return schema

    def _write_schema(self, name: str, schema: dict):
        """
        Write JSON schema to file.

        Args:
            name: Schema name
            schema: JSON schema dict
        """
        schema_path = self.schema_dir / f"{name}.schema.json"
        with open(schema_path, "w") as f:
            json.dump(schema, f, indent=2)


def generate_schemas(schema_dir: Path):
    """
    Generate all JSON schemas.

    Args:
        schema_dir: Directory to write schemas
    """
    generator = SchemaGenerator(schema_dir)
    generator.generate_all_schemas()


if __name__ == "__main__":
    # Generate schemas to default location
    from pathlib import Path
    import os

    config_dir = Path(os.path.expanduser("~/.config/sway"))
    schema_dir = config_dir / "schemas"
    generate_schemas(schema_dir)
    print(f"Schemas generated in {schema_dir}")
