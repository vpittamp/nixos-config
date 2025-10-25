"""
Registry loader service
Feature 035: Registry-Centric Project & Workspace Management

Loads and validates application registry from ~/.config/i3/application-registry.json
on daemon startup.
"""

import json
import logging
from dataclasses import dataclass
from pathlib import Path
from typing import List, Optional, Dict

logger = logging.getLogger(__name__)


@dataclass
class RegistryApp:
    """Application registry entry"""

    name: str
    display_name: str
    icon: str
    command: str
    parameters: List[str]
    terminal: bool
    expected_class: str
    expected_title_contains: Optional[str]
    preferred_workspace: Optional[int]
    scope: str  # "scoped" or "global"
    fallback_behavior: str  # "skip", "use_home", "error"
    multi_instance: bool
    nix_package: Optional[str] = None
    description: Optional[str] = None


class RegistryLoader:
    """Loads and caches application registry"""

    def __init__(self, registry_path: Optional[Path] = None):
        if registry_path is None:
            home = Path.home()
            self.registry_path = home / ".config/i3/application-registry.json"
        else:
            self.registry_path = registry_path

        self.applications: Dict[str, RegistryApp] = {}
        self.version: str = ""

    def load(self) -> None:
        """
        Load registry from disk

        Raises:
            FileNotFoundError: If registry file does not exist
            ValueError: If registry format is invalid
        """
        if not self.registry_path.exists():
            raise FileNotFoundError(
                f"Registry not found at {self.registry_path}. "
                "Run 'nixos-rebuild switch' to generate it."
            )

        try:
            with open(self.registry_path, "r") as f:
                data = json.load(f)

            # Validate schema
            if not isinstance(data, dict):
                raise ValueError("Registry must be a JSON object")

            if "version" not in data:
                raise ValueError("Registry missing 'version' field")

            if "applications" not in data:
                raise ValueError("Registry missing 'applications' field")

            if not isinstance(data["applications"], list):
                raise ValueError("Registry 'applications' must be a list")

            self.version = data["version"]

            # Parse applications
            self.applications = {}
            for app_data in data["applications"]:
                app = self._parse_app(app_data)
                if app.name in self.applications:
                    logger.warning(f"Duplicate application name '{app.name}' in registry")
                self.applications[app.name] = app

            logger.info(
                f"Loaded registry v{self.version} with {len(self.applications)} applications"
            )

        except json.JSONDecodeError as e:
            raise ValueError(f"Invalid JSON in registry: {e}")

    def _parse_app(self, data: dict) -> RegistryApp:
        """Parse application entry from JSON"""
        try:
            return RegistryApp(
                name=data["name"],
                display_name=data["display_name"],
                icon=data["icon"],
                command=data["command"],
                parameters=data.get("parameters", []),
                terminal=data.get("terminal", False),
                expected_class=data["expected_class"],
                expected_title_contains=data.get("expected_title_contains"),
                preferred_workspace=data.get("preferred_workspace"),
                scope=data["scope"],
                fallback_behavior=data.get("fallback_behavior", "use_home"),
                multi_instance=data.get("multi_instance", False),
                nix_package=data.get("nix_package"),
                description=data.get("description"),
            )
        except KeyError as e:
            raise ValueError(f"Missing required field in application entry: {e}")

    def get(self, name: str) -> Optional[RegistryApp]:
        """Get application by name"""
        return self.applications.get(name)

    def list_scoped(self) -> List[RegistryApp]:
        """Get all scoped applications"""
        return [app for app in self.applications.values() if app.scope == "scoped"]

    def list_global(self) -> List[RegistryApp]:
        """Get all global applications"""
        return [app for app in self.applications.values() if app.scope == "global"]

    def list_all(self) -> List[RegistryApp]:
        """Get all applications"""
        return list(self.applications.values())

    def find_by_class(self, window_class: str) -> Optional[RegistryApp]:
        """Find application by window class"""
        for app in self.applications.values():
            if app.expected_class == window_class:
                return app
        return None

    def find_by_title(self, title: str) -> Optional[RegistryApp]:
        """Find application by title substring (fallback matching)"""
        for app in self.applications.values():
            if app.expected_title_contains and app.expected_title_contains in title:
                return app
        return None

    def reload(self) -> None:
        """Reload registry from disk"""
        self.applications.clear()
        self.version = ""
        self.load()

    def is_loaded(self) -> bool:
        """Check if registry is loaded"""
        return len(self.applications) > 0

    def get_version(self) -> str:
        """Get registry version"""
        return self.version

    def get_path(self) -> Path:
        """Get registry file path"""
        return self.registry_path
