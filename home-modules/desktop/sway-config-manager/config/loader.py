"""
Configuration loader for Sway configuration files.

Loads and parses:
- keybindings.toml (TOML format)
- window-rules.json (JSON format)
- workspace-assignments.json (JSON format)
- project overrides from projects/*.json
"""

import json
import tomllib
from pathlib import Path
from typing import Any, Dict, List, Optional

from ..models import KeybindingConfig, WindowRule, WorkspaceAssignment


class ConfigLoader:
    """Loads configuration from TOML and JSON files."""

    def __init__(self, config_dir: Path):
        """
        Initialize configuration loader.

        Args:
            config_dir: Path to Sway configuration directory (~/.config/sway/)
        """
        self.config_dir = config_dir
        self.keybindings_path = config_dir / "keybindings.toml"
        self.window_rules_path = config_dir / "window-rules.json"
        self.workspace_assignments_path = config_dir / "workspace-assignments.json"
        self.projects_dir = config_dir / "projects"

    def load_keybindings_toml(self) -> List[KeybindingConfig]:
        """
        Load keybindings from TOML configuration file.

        Returns:
            List of KeybindingConfig objects

        Raises:
            FileNotFoundError: If keybindings.toml doesn't exist
            tomllib.TOMLDecodeError: If TOML syntax is invalid
        """
        if not self.keybindings_path.exists():
            return []

        with open(self.keybindings_path, "rb") as f:
            data = tomllib.load(f)

        keybindings = []
        for key_combo, binding_data in data.get("keybindings", {}).items():
            # Handle both simple string and dict formats
            if isinstance(binding_data, str):
                command = binding_data
                description = None
                mode = "default"
            else:
                command = binding_data.get("command")
                description = binding_data.get("description")
                mode = binding_data.get("mode", "default")

            keybindings.append(KeybindingConfig(
                key_combo=key_combo,
                command=command,
                description=description,
                source="runtime",
                mode=mode
            ))

        return keybindings

    def load_window_rules_json(self) -> List[WindowRule]:
        """
        Load window rules from JSON configuration file.

        Returns:
            List of WindowRule objects

        Raises:
            FileNotFoundError: If window-rules.json doesn't exist
            json.JSONDecodeError: If JSON syntax is invalid
        """
        if not self.window_rules_path.exists():
            return []

        with open(self.window_rules_path, "r") as f:
            data = json.load(f)

        rules = []
        for rule_data in data.get("rules", []):
            rules.append(WindowRule(**rule_data))

        return rules

    def load_workspace_assignments_json(self) -> List[WorkspaceAssignment]:
        """
        Load workspace assignments from JSON configuration file.

        Returns:
            List of WorkspaceAssignment objects

        Raises:
            FileNotFoundError: If workspace-assignments.json doesn't exist
            json.JSONDecodeError: If JSON syntax is invalid
        """
        if not self.workspace_assignments_path.exists():
            return []

        with open(self.workspace_assignments_path, "r") as f:
            data = json.load(f)

        assignments = []
        for assignment_data in data.get("assignments", []):
            assignments.append(WorkspaceAssignment(**assignment_data))

        return assignments

    def load_project_overrides(self, project_name: str) -> Optional[Dict[str, Any]]:
        """
        Load project-specific configuration overrides.

        Args:
            project_name: Name of the project

        Returns:
            Project configuration dict or None if project doesn't exist

        Raises:
            json.JSONDecodeError: If project JSON is invalid
        """
        project_path = self.projects_dir / f"{project_name}.json"

        if not project_path.exists():
            return None

        with open(project_path, "r") as f:
            return json.load(f)
