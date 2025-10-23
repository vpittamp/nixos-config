"""
Configuration file management for window rules, app classes, and application registry.
"""

import json
from pathlib import Path
from typing import List, Dict, Any, Optional

try:
    from .models import WindowRule, ApplicationDefinition, Pattern, Scope, PatternType
except ImportError:
    from models import WindowRule, ApplicationDefinition, Pattern, Scope, PatternType


class ConfigManager:
    """Manages reading and writing configuration files."""

    def __init__(self, config_dir: Optional[Path] = None):
        """
        Initialize configuration manager.

        Args:
            config_dir: Configuration directory (defaults to ~/.config/i3)
        """
        self.config_dir = config_dir or (Path.home() / ".config/i3")
        self.window_rules_path = self.config_dir / "window-rules.json"
        self.app_classes_path = self.config_dir / "app-classes.json"
        self.app_registry_path = self.config_dir / "application-registry.json"

    def read_window_rules(self) -> List[WindowRule]:
        """Read and parse window-rules.json."""
        if not self.window_rules_path.exists():
            return []

        try:
            with open(self.window_rules_path, 'r') as f:
                data = json.load(f)

            rules = []
            for rule_data in data.get("rules", []):
                # Parse pattern
                pattern_data = rule_data["pattern"]
                pattern = Pattern(
                    type=PatternType(pattern_data["type"]),
                    value=pattern_data["value"],
                    description=pattern_data.get("description"),
                    priority=pattern_data.get("priority", 10),
                    case_sensitive=pattern_data.get("case_sensitive", True),
                )

                # Parse rule
                rule = WindowRule(
                    pattern=pattern,
                    workspace=rule_data["workspace"],
                    scope=Scope(rule_data["scope"]),
                    enabled=rule_data.get("enabled", True),
                    application_name=rule_data["application_name"],
                    notes=rule_data.get("notes"),
                )
                rules.append(rule)

            return rules
        except Exception as e:
            raise ValueError(f"Failed to read window-rules.json: {e}")

    def write_window_rules(self, rules: List[WindowRule]) -> None:
        """Write window rules to window-rules.json."""
        data = {
            "version": "1.0.0",
            "rules": []
        }

        for rule in rules:
            rule_data = {
                "pattern": {
                    "type": rule.pattern.type.value,
                    "value": rule.pattern.value,
                    "description": rule.pattern.description,
                    "priority": rule.pattern.priority,
                    "case_sensitive": rule.pattern.case_sensitive,
                },
                "workspace": rule.workspace,
                "scope": rule.scope.value,
                "enabled": rule.enabled,
                "application_name": rule.application_name,
            }
            if rule.notes:
                rule_data["notes"] = rule.notes

            data["rules"].append(rule_data)

        # Ensure directory exists
        self.config_dir.mkdir(parents=True, exist_ok=True)

        # Write to file
        with open(self.window_rules_path, 'w') as f:
            json.dump(data, f, indent=2)

    def read_app_classes(self) -> Dict[str, List[str]]:
        """
        Read and parse app-classes.json.

        Returns:
            Dictionary with 'scoped' and 'global' keys containing lists of class patterns
        """
        if not self.app_classes_path.exists():
            return {"scoped": [], "global": []}

        try:
            with open(self.app_classes_path, 'r') as f:
                data = json.load(f)

            # Handle both old format (scoped_classes/global_classes) and new format (scoped/global with dicts)
            result = {"scoped": [], "global": []}

            if "scoped_classes" in data:
                result["scoped"] = data["scoped_classes"]
            elif "scoped" in data:
                # New format is a dict, extract keys
                result["scoped"] = list(data["scoped"].keys()) if isinstance(data["scoped"], dict) else data["scoped"]

            if "global_classes" in data:
                result["global"] = data["global_classes"]
            elif "global" in data:
                # New format is a dict, extract keys
                result["global"] = list(data["global"].keys()) if isinstance(data["global"], dict) else data["global"]

            return result
        except Exception as e:
            raise ValueError(f"Failed to read app-classes.json: {e}")

    def write_app_classes(self, scoped: List[str], global_apps: List[str]) -> None:
        """
        Write app classes to app-classes.json.

        Args:
            scoped: List of scoped application class patterns
            global_apps: List of global application class patterns
        """
        data = {
            "version": "1.0.0",
            "scoped_classes": sorted(set(scoped)),
            "global_classes": sorted(set(global_apps)),
        }

        # Ensure directory exists
        self.config_dir.mkdir(parents=True, exist_ok=True)

        # Write to file
        with open(self.app_classes_path, 'w') as f:
            json.dump(data, f, indent=2)

    def read_application_registry(self) -> List[ApplicationDefinition]:
        """Read and parse application-registry.json."""
        if not self.app_registry_path.exists():
            return []

        try:
            with open(self.app_registry_path, 'r') as f:
                data = json.load(f)

            apps = []
            for app_data in data.get("applications", []):
                app = ApplicationDefinition(
                    name=app_data["name"],
                    display_name=app_data["display_name"],
                    command=app_data["command"],
                    rofi_name=app_data.get("rofi_name"),
                    parameters=app_data.get("parameters"),
                    expected_pattern_type=PatternType(app_data["expected_pattern_type"]),
                    expected_class=app_data.get("expected_class"),
                    expected_title_contains=app_data.get("expected_title_contains"),
                    scope=Scope(app_data["scope"]),
                    preferred_workspace=app_data.get("preferred_workspace"),
                    desktop_file_path=app_data.get("desktop_file_path"),
                    nix_package=app_data.get("nix_package"),
                )
                apps.append(app)

            return apps
        except Exception as e:
            raise ValueError(f"Failed to read application-registry.json: {e}")

    def validate_json_syntax(self, file_path: Path) -> bool:
        """
        Validate JSON syntax of a file.

        Args:
            file_path: Path to JSON file

        Returns:
            True if valid, False otherwise
        """
        try:
            with open(file_path, 'r') as f:
                json.load(f)
            return True
        except json.JSONDecodeError:
            return False
        except FileNotFoundError:
            return False
