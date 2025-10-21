"""Core data models for i3 project management.

This module defines all entities and their relationships:
- Project: Project configuration with auto-launch and layouts
- AutoLaunchApp: Application auto-launch configuration
- SavedLayout: Saved window layout for restoration
- WorkspaceLayout: Layout for a single workspace
- LayoutWindow: Window configuration in a layout
- AppClassification: Global app scoping configuration
- TUIState: Runtime TUI state (not persisted)
"""

import json
from dataclasses import asdict, dataclass, field
from datetime import datetime
from pathlib import Path
from typing import Any, Dict, List, Optional


@dataclass
class AutoLaunchApp:
    """Auto-launch application configuration."""

    command: str  # Shell command to execute
    workspace: Optional[int] = None  # Target workspace (1-10)
    env: Dict[str, str] = field(default_factory=dict)  # Additional environment variables
    wait_for_mark: Optional[str] = None  # Expected mark (e.g., "project:nixos")
    wait_timeout: float = 5.0  # Timeout in seconds
    launch_delay: float = 0.5  # Delay before launch (seconds)

    def __post_init__(self):
        """Validate auto-launch app configuration."""
        if not self.command or not self.command.strip():
            raise ValueError("Launch command cannot be empty")
        if self.workspace is not None and not (1 <= self.workspace <= 10):
            raise ValueError("Workspace must be 1-10")
        if not (0.1 <= self.wait_timeout <= 30.0):
            raise ValueError("Timeout must be 0.1-30.0 seconds")

    def to_json(self) -> dict:
        """Serialize to JSON."""
        return asdict(self)

    @classmethod
    def from_json(cls, data: dict) -> "AutoLaunchApp":
        """Deserialize from JSON."""
        return cls(**data)

    def get_full_env(self, project: "Project") -> Dict[str, str]:
        """Get environment with project context.

        Args:
            project: Project to get context from

        Returns:
            Environment dict with PROJECT_DIR, PROJECT_NAME, and custom env vars
        """
        import os
        return {
            **os.environ,
            "PROJECT_DIR": str(project.directory),
            "PROJECT_NAME": project.name,
            "I3_PROJECT": project.name,
            **self.env
        }


@dataclass
class Project:
    """Project configuration entity."""

    # Primary fields (required)
    name: str  # Unique identifier (filesystem-safe)
    directory: Path  # Project working directory

    # Display fields
    display_name: Optional[str] = None  # Human-readable name (defaults to name)
    icon: Optional[str] = None  # Unicode emoji/icon for UI

    # Application associations
    scoped_classes: List[str] = field(default_factory=list)  # Project-specific app classes

    # Workspace configuration
    workspace_preferences: Dict[int, str] = field(
        default_factory=dict
    )  # {ws_num: output_role}

    # Auto-launch configuration
    auto_launch: List[AutoLaunchApp] = field(default_factory=list)

    # Saved layouts
    saved_layouts: List[str] = field(default_factory=list)  # Layout names

    # Metadata
    created_at: datetime = field(default_factory=datetime.now)
    modified_at: datetime = field(default_factory=datetime.now)

    def __post_init__(self):
        """Initialize derived fields and validate."""
        # Convert string path to Path object
        if isinstance(self.directory, str):
            self.directory = Path(self.directory).expanduser()

        # Default display_name to name
        if self.display_name is None:
            self.display_name = self.name

        # Validate name (filesystem-safe)
        if not self.name.replace("-", "").replace("_", "").isalnum():
            raise ValueError(
                f"Project name '{self.name}' must be alphanumeric (with - or _)"
            )

        # Validate directory exists
        if not self.directory.exists():
            raise ValueError(f"Project directory does not exist: {self.directory}")

        # Validate scoped_classes is not empty
        if not self.scoped_classes:
            raise ValueError("Project must have at least one scoped application class")

        # Validate workspace preferences
        for ws_num, output_role in self.workspace_preferences.items():
            if not (1 <= ws_num <= 10):
                raise ValueError(f"Workspace number must be 1-10, got {ws_num}")
            if output_role not in ["primary", "secondary", "tertiary"]:
                raise ValueError(
                    f"Invalid output role '{output_role}', must be primary/secondary/tertiary"
                )

    def to_json(self) -> dict:
        """Serialize to JSON (for file storage)."""
        data = {
            "name": self.name,
            "directory": str(self.directory),
            "display_name": self.display_name,
            "icon": self.icon,
            "scoped_classes": self.scoped_classes,
            "workspace_preferences": {
                str(k): v for k, v in self.workspace_preferences.items()
            },
            "auto_launch": [app.to_json() for app in self.auto_launch],
            "saved_layouts": self.saved_layouts,
            "created_at": self.created_at.isoformat(),
            "modified_at": self.modified_at.isoformat(),
        }
        return data

    @classmethod
    def from_json(cls, data: dict) -> "Project":
        """Deserialize from JSON."""
        data_copy = data.copy()

        # Parse datetime fields
        data_copy["created_at"] = datetime.fromisoformat(data["created_at"])
        data_copy["modified_at"] = datetime.fromisoformat(data["modified_at"])

        # Parse workspace_preferences (convert string keys back to int)
        data_copy["workspace_preferences"] = {
            int(k): v for k, v in data.get("workspace_preferences", {}).items()
        }

        # Parse AutoLaunchApp objects
        data_copy["auto_launch"] = [
            AutoLaunchApp.from_json(app) for app in data.get("auto_launch", [])
        ]

        # Ensure directory is a Path object
        if "directory" in data_copy and not isinstance(data_copy["directory"], Path):
            data_copy["directory"] = Path(data_copy["directory"])

        return cls(**data_copy)

    def save(
        self, config_dir: Path = Path.home() / ".config/i3/projects"
    ) -> None:
        """Save project to disk.

        Args:
            config_dir: Directory to save project config to
        """
        config_dir.mkdir(parents=True, exist_ok=True)
        config_file = config_dir / f"{self.name}.json"

        self.modified_at = datetime.now()

        with config_file.open("w") as f:
            json.dump(self.to_json(), f, indent=2)

    @classmethod
    def load(
        cls, name: str, config_dir: Path = Path.home() / ".config/i3/projects"
    ) -> "Project":
        """Load project from disk.

        Args:
            name: Project name to load
            config_dir: Directory to load from

        Returns:
            Loaded Project instance

        Raises:
            FileNotFoundError: If project config file doesn't exist
        """
        config_file = config_dir / f"{name}.json"

        if not config_file.exists():
            raise FileNotFoundError(f"Project not found: {name}")

        with config_file.open("r") as f:
            data = json.load(f)

        return cls.from_json(data)

    @classmethod
    def list_all(
        cls, config_dir: Path = Path.home() / ".config/i3/projects"
    ) -> List["Project"]:
        """List all projects.

        Args:
            config_dir: Directory to list projects from

        Returns:
            List of Project instances sorted by modified_at (newest first)
        """
        if not config_dir.exists():
            return []

        projects = []
        for config_file in config_dir.glob("*.json"):
            try:
                projects.append(cls.load(config_file.stem, config_dir))
            except Exception as e:
                # Log warning but continue (don't fail entire list)
                print(f"Warning: Failed to load {config_file}: {e}")

        return sorted(projects, key=lambda p: p.modified_at, reverse=True)

    def delete(
        self, config_dir: Path = Path.home() / ".config/i3/projects"
    ) -> None:
        """Delete project from disk.

        Args:
            config_dir: Directory containing project config
        """
        config_file = config_dir / f"{self.name}.json"
        if config_file.exists():
            config_file.unlink()

    def get_layouts(self) -> List[str]:
        """Get all saved layout names for this project.

        Returns:
            List of layout names
        """
        from .layout import SavedLayout

        return SavedLayout.list_for_project(self.name)

    def delete_with_layouts(self) -> None:
        """Delete project and all its layouts.

        This is a cascading delete operation.
        """
        # Delete layouts
        layout_dir = Path.home() / ".config/i3/layouts" / self.name
        if layout_dir.exists():
            for layout_file in layout_dir.glob("*.json"):
                layout_file.unlink()
            layout_dir.rmdir()

        # Delete project
        self.delete()


@dataclass
class LayoutWindow:
    """Window configuration in a layout."""

    window_class: str  # WM_CLASS (e.g., "Ghostty", "Code")
    window_title: Optional[str] = None  # Window title (for matching)
    geometry: Optional[Dict[str, int]] = None  # {"width": 1920, "height": 1080, "x": 0, "y": 0}
    layout_role: Optional[str] = None  # "main", "editor", "terminal", "browser"
    split_before: Optional[str] = None  # "horizontal", "vertical", None
    launch_command: str = ""  # Command to launch this window
    launch_env: Dict[str, str] = field(default_factory=dict)
    expected_marks: List[str] = field(default_factory=list)  # e.g., ["project:nixos"]

    def __post_init__(self):
        """Validate window configuration."""
        if not self.window_class:
            raise ValueError("Window class cannot be empty")
        if self.split_before and self.split_before not in ["horizontal", "vertical"]:
            raise ValueError("Invalid split orientation")

    def to_json(self) -> dict:
        """Serialize to JSON."""
        return asdict(self)

    @classmethod
    def from_json(cls, data: dict) -> "LayoutWindow":
        """Deserialize from JSON."""
        return cls(**data)


@dataclass
class WorkspaceLayout:
    """Workspace layout configuration."""

    number: int  # Workspace number (1-10)
    output_role: str = "primary"  # "primary", "secondary", "tertiary"
    windows: List[LayoutWindow] = field(default_factory=list)
    split_orientation: Optional[str] = None  # "horizontal", "vertical", None

    def __post_init__(self):
        """Validate workspace layout."""
        if not (1 <= self.number <= 10):
            raise ValueError("Workspace number must be 1-10")
        if self.output_role not in ["primary", "secondary", "tertiary"]:
            raise ValueError("Invalid output role")
        if self.split_orientation and self.split_orientation not in [
            "horizontal",
            "vertical",
        ]:
            raise ValueError("Invalid split orientation")

    def to_json(self) -> dict:
        """Serialize to JSON."""
        data = asdict(self)
        data["windows"] = [w.to_json() for w in self.windows]
        return data

    @classmethod
    def from_json(cls, data: dict) -> "WorkspaceLayout":
        """Deserialize from JSON."""
        data_copy = data.copy()
        data_copy["windows"] = [
            LayoutWindow.from_json(w) for w in data.get("windows", [])
        ]
        return cls(**data_copy)


@dataclass
class SavedLayout:
    """Saved project layout."""

    layout_version: str = "1.0"
    project_name: str = ""  # Associated project
    layout_name: str = "default"  # Layout name
    workspaces: List[WorkspaceLayout] = field(default_factory=list)
    saved_at: datetime = field(default_factory=datetime.now)
    monitor_config: str = "single"  # "single", "dual", "triple"
    total_windows: int = 0

    def __post_init__(self):
        """Validate layout."""
        if self.layout_version != "1.0":
            raise ValueError(f"Unsupported layout version: {self.layout_version}")
        if not self.layout_name.replace("-", "").replace("_", "").isalnum():
            raise ValueError("Layout name must be alphanumeric (with - or _)")

    def to_json(self) -> dict:
        """Serialize to JSON."""
        data = asdict(self)
        data["saved_at"] = self.saved_at.isoformat()
        data["workspaces"] = [ws.to_json() for ws in self.workspaces]
        return data

    @classmethod
    def from_json(cls, data: dict) -> "SavedLayout":
        """Deserialize from JSON."""
        data_copy = data.copy()
        data_copy["saved_at"] = datetime.fromisoformat(data["saved_at"])
        data_copy["workspaces"] = [
            WorkspaceLayout.from_json(ws) for ws in data.get("workspaces", [])
        ]
        return cls(**data_copy)

    def save(
        self, config_dir: Path = Path.home() / ".config/i3/layouts"
    ) -> None:
        """Save layout to disk.

        Args:
            config_dir: Base layouts directory
        """
        layout_dir = config_dir / self.project_name
        layout_dir.mkdir(parents=True, exist_ok=True)

        layout_file = layout_dir / f"{self.layout_name}.json"

        with layout_file.open("w") as f:
            json.dump(self.to_json(), f, indent=2)

    @classmethod
    def load(
        cls,
        project_name: str,
        layout_name: str,
        config_dir: Path = Path.home() / ".config/i3/layouts",
    ) -> "SavedLayout":
        """Load layout from disk.

        Args:
            project_name: Project name
            layout_name: Layout name
            config_dir: Base layouts directory

        Returns:
            Loaded SavedLayout instance

        Raises:
            FileNotFoundError: If layout doesn't exist
        """
        layout_file = config_dir / project_name / f"{layout_name}.json"

        if not layout_file.exists():
            raise FileNotFoundError(f"Layout not found: {project_name}/{layout_name}")

        with layout_file.open("r") as f:
            data = json.load(f)

        return cls.from_json(data)

    @classmethod
    def list_for_project(
        cls, project_name: str, config_dir: Path = Path.home() / ".config/i3/layouts"
    ) -> List[str]:
        """List all layout names for a project.

        Args:
            project_name: Project to list layouts for
            config_dir: Base layouts directory

        Returns:
            List of layout names (without .json extension)
        """
        layout_dir = config_dir / project_name
        if not layout_dir.exists():
            return []

        return [f.stem for f in layout_dir.glob("*.json")]


@dataclass
class AppClassification:
    """Global application classification."""

    scoped_classes: List[str] = field(
        default_factory=list
    )  # Default scoped classes
    global_classes: List[str] = field(default_factory=list)  # Always global
    class_patterns: Dict[str, str] = field(
        default_factory=dict
    )  # {pattern: scope}

    def to_json(self) -> dict:
        """Serialize to JSON."""
        return asdict(self)

    @classmethod
    def from_json(cls, data: dict) -> "AppClassification":
        """Deserialize from JSON."""
        return cls(**data)

    def save(
        self, config_file: Path = Path.home() / ".config/i3/app-classes.json"
    ) -> None:
        """Save to disk.

        Args:
            config_file: Path to app-classes.json
        """
        config_file.parent.mkdir(parents=True, exist_ok=True)

        with config_file.open("w") as f:
            json.dump(self.to_json(), f, indent=2)

    @classmethod
    def load(
        cls, config_file: Path = Path.home() / ".config/i3/app-classes.json"
    ) -> "AppClassification":
        """Load from disk.

        Args:
            config_file: Path to app-classes.json

        Returns:
            AppClassification instance (creates default if file doesn't exist)
        """
        if not config_file.exists():
            # Return default classification
            return cls(
                scoped_classes=["Ghostty", "Code", "neovide"],
                global_classes=["firefox", "Google-chrome", "mpv", "vlc"],
                class_patterns={"pwa-": "global", "terminal": "scoped", "editor": "scoped"},
            )

        with config_file.open("r") as f:
            data = json.load(f)

        return cls.from_json(data)

    def is_scoped(
        self, window_class: str, project: Optional[Project] = None
    ) -> bool:
        """Determine if a window class is scoped.

        Args:
            window_class: Window class to check
            project: Optional project to check project-specific scoped classes

        Returns:
            True if window class should be scoped to projects
        """
        # Check global classes first (always False)
        if window_class in self.global_classes:
            return False

        # Check project-specific scoped classes
        if project and window_class in project.scoped_classes:
            return True

        # Check default scoped classes
        if window_class in self.scoped_classes:
            return True

        # Check patterns
        for pattern, scope in self.class_patterns.items():
            if pattern in window_class.lower():
                return scope == "scoped"

        return False  # Default to global


@dataclass
class TUIState:
    """TUI application state (runtime only, not persisted)."""

    # Screen navigation
    active_screen: str = "browser"  # "browser", "editor", "monitor", "layout", "wizard"
    screen_history: List[str] = field(default_factory=list)

    # Project browser state
    selected_project: Optional[str] = None
    filter_text: str = ""
    sort_by: str = "modified"  # "name", "modified", "directory"
    sort_descending: bool = True

    # Project editor state
    editing_project: Optional[str] = None
    unsaved_changes: bool = False

    # Layout manager state
    selected_layout: Optional[str] = None

    # Daemon connection
    daemon_connected: bool = False
    active_project: Optional[str] = None  # From daemon

    def push_screen(self, screen_name: str) -> None:
        """Navigate to a new screen.

        Args:
            screen_name: Name of screen to navigate to
        """
        self.screen_history.append(self.active_screen)
        self.active_screen = screen_name

    def pop_screen(self) -> Optional[str]:
        """Return to previous screen.

        Returns:
            Previous screen name, or None if no history
        """
        if self.screen_history:
            self.active_screen = self.screen_history.pop()
            return self.active_screen
        return None

    def reset_filters(self) -> None:
        """Reset browser filters to defaults."""
        self.filter_text = ""
        self.sort_by = "modified"
        self.sort_descending = True
