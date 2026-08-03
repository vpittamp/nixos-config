"""Centralized configuration paths and constants for i3-project-event-daemon.

Feature 101: Single source of truth for all file paths used across the daemon.
This eliminates hardcoded paths scattered throughout the codebase.
"""

from pathlib import Path
from typing import Final


class ConfigPaths:
    """Centralized configuration paths.

    All paths are computed once at import time based on user's home directory.
    Use these constants instead of constructing paths manually.

    Example:
        from .constants import ConfigPaths

        # Instead of: Path.home() / ".config" / "i3" / "window-rules.json"
        rules = ConfigPaths.WINDOW_RULES_FILE.read_text()
    """

    # Base directories
    HOME: Final[Path] = Path.home()
    I3_CONFIG_DIR: Final[Path] = HOME / ".config" / "i3"
    SWAY_CONFIG_DIR: Final[Path] = HOME / ".config" / "sway"
    EWW_CONFIG_DIR: Final[Path] = HOME / ".config" / "eww"
    LOCAL_STATE_DIR: Final[Path] = HOME / ".local" / "state"
    LOCAL_SHARE_DIR: Final[Path] = HOME / ".local" / "share" / "i3pm"

    # The worktree inventory (`repos.json`), its account roots, the per-project
    # usage/host-profile sidecars and the discovery config were removed with the
    # RPC family that produced them: identity is now the pane's own checkout
    # path and git answers everything else. `active-worktree.json` is the one
    # survivor because the context RPCs still read it.
    ACTIVE_WORKTREE_FILE: Final[Path] = I3_CONFIG_DIR / "active-worktree.json"

    # Application registry
    APPLICATION_REGISTRY_FILE: Final[Path] = I3_CONFIG_DIR / "application-registry.json"
    APP_CLASSES_FILE: Final[Path] = I3_CONFIG_DIR / "app-classes.json"

    # Sway configuration files
    WINDOW_RULES_FILE: Final[Path] = SWAY_CONFIG_DIR / "window-rules.json"
    OUTPUT_STATES_FILE: Final[Path] = SWAY_CONFIG_DIR / "output-states.json"
    MONITOR_PROFILE_FILE: Final[Path] = SWAY_CONFIG_DIR / "monitor-profile.current"
    MONITOR_PROFILES_DIR: Final[Path] = SWAY_CONFIG_DIR / "monitor-profiles"
    APPEARANCE_FILE: Final[Path] = SWAY_CONFIG_DIR / "appearance.json"

    # Layouts
    LAYOUTS_DIR: Final[Path] = LOCAL_SHARE_DIR / "layouts"

    # IPC socket
    IPC_SOCKET_PATH: Final[Path] = Path("/tmp/i3-project-daemon.sock")

    @classmethod
    def ensure_dirs(cls) -> None:
        """Create all necessary directories if they don't exist.

        Call this during daemon startup to ensure all config directories exist.
        """
        dirs = [
            cls.I3_CONFIG_DIR,
            cls.SWAY_CONFIG_DIR,
            cls.LOCAL_STATE_DIR,
            cls.LOCAL_SHARE_DIR,
            cls.LAYOUTS_DIR,
            cls.MONITOR_PROFILES_DIR,
        ]
        for d in dirs:
            d.mkdir(parents=True, exist_ok=True)

    @classmethod
    def layout_file(cls, project_name: str, layout_name: str) -> Path:
        """Get path to a layout file for a project.

        Args:
            project_name: Project name (can be qualified)
            layout_name: Layout name

        Returns:
            Path to ~/.local/share/i3pm/layouts/{project_name}/{layout_name}.json
        """
        # Sanitize project name for filesystem (replace / and : with -)
        safe_name = project_name.replace("/", "-").replace(":", "-")
        project_layouts_dir = cls.LAYOUTS_DIR / safe_name
        return project_layouts_dir / f"{layout_name}.json"
