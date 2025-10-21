"""Workspace configuration data model."""

from dataclasses import dataclass
from typing import Optional, Literal


@dataclass
class WorkspaceConfig:
    """Workspace configuration with metadata.

    Attributes:
        number: Workspace number (1-9)
        name: Optional human-readable workspace name
        icon: Optional Unicode icon/emoji for display
        default_output_role: Default output assignment role

    Examples:
        >>> ws = WorkspaceConfig(1, name="Terminal", icon="󰨊", default_output_role="primary")
        >>> ws.number
        1
        >>> ws.name
        'Terminal'

        >>> ws = WorkspaceConfig(5, default_output_role="secondary")
        >>> ws.to_json()
        {'number': 5, 'name': None, 'icon': None, 'default_output_role': 'secondary'}
    """

    number: int
    name: Optional[str] = None
    icon: Optional[str] = None
    default_output_role: Literal["auto", "primary", "secondary", "tertiary"] = "auto"

    def __post_init__(self):
        """Validate workspace configuration."""
        if not (1 <= self.number <= 9):
            raise ValueError(f"Workspace number must be 1-9, got {self.number}")

        valid_roles = ["auto", "primary", "secondary", "tertiary"]
        if self.default_output_role not in valid_roles:
            raise ValueError(
                f"Invalid output role: {self.default_output_role}. "
                f"Must be one of: {', '.join(valid_roles)}"
            )

    def to_json(self) -> dict:
        """Serialize to JSON-compatible dict.

        Returns:
            Dictionary with all fields for JSON serialization
        """
        return {
            "number": self.number,
            "name": self.name,
            "icon": self.icon,
            "default_output_role": self.default_output_role,
        }

    @classmethod
    def from_json(cls, data: dict) -> "WorkspaceConfig":
        """Deserialize from JSON-compatible dict.

        Args:
            data: Dictionary with workspace configuration fields

        Returns:
            WorkspaceConfig instance

        Raises:
            ValueError: If data is invalid
        """
        return cls(
            number=data["number"],
            name=data.get("name"),
            icon=data.get("icon"),
            default_output_role=data.get("default_output_role", "auto"),
        )


def load_workspace_config(config_path: str) -> list[WorkspaceConfig]:
    """Load workspace configuration from JSON file.

    Args:
        config_path: Path to workspace-config.json file

    Returns:
        List of WorkspaceConfig objects. Returns default configs if file doesn't exist.

    Examples:
        >>> configs = load_workspace_config("~/.config/i3/workspace-config.json")
        >>> len(configs)
        9
        >>> configs[0].name
        'Terminal'
    """
    import json
    from pathlib import Path

    path = Path(config_path).expanduser()

    # Return defaults if file doesn't exist
    if not path.exists():
        return _default_workspace_configs()

    try:
        with open(path, "r") as f:
            data = json.load(f)

        if not isinstance(data, list):
            raise ValueError("workspace-config.json must be a JSON array")

        return [WorkspaceConfig.from_json(item) for item in data]

    except json.JSONDecodeError as e:
        raise ValueError(f"Invalid JSON in {config_path}: {e}")
    except KeyError as e:
        raise ValueError(f"Missing required field in workspace config: {e}")


def _default_workspace_configs() -> list[WorkspaceConfig]:
    """Generate default workspace configurations.

    Returns:
        List of 9 workspace configs with default names and roles
    """
    defaults = [
        (1, "Terminal", "󰨊", "primary"),
        (2, "Editor", "", "primary"),
        (3, "Browser", "󰈹", "secondary"),
        (4, "Media", "", "secondary"),
        (5, "Files", "󰉋", "secondary"),
        (6, "Chat", "󰭹", "tertiary"),
        (7, "Email", "󰇮", "tertiary"),
        (8, "Music", "󰝚", "tertiary"),
        (9, "Misc", "󰇙", "tertiary"),
    ]

    return [
        WorkspaceConfig(number=num, name=name, icon=icon, default_output_role=role)
        for num, name, icon, role in defaults
    ]
