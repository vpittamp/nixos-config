"""Unified application launcher for wrapper-based restoration.

Feature 074: Session Management
Tasks T015B-T015G: AppLauncher service for Feature 057 integration

Ensures all app launches (Walker, restore, daemon, CLI) use the same
wrapper system with I3PM_* environment variable injection.
"""

import json
import logging
import os
import subprocess
from pathlib import Path
from typing import Any, Dict, List, Optional

logger = logging.getLogger(__name__)


class AppLauncher:
    """Unified app launcher using app registry definitions (Feature 074: T015B, Feature 057 integration).

    Ensures all app launches use wrapper system that injects I3PM_* environment
    variables, maintaining 100% deterministic window matching.

    This service handles:
    - PWAs: Launch via `launch-pwa-by-name <ULID>` wrapper
    - Terminal apps: Use ghostty wrapper with parameters
    - GUI apps: Use standard wrappers
    - I3PM_* environment variable injection
    """

    def __init__(
        self,
        registry_path: Optional[Path] = None
    ):
        """Initialize AppLauncher with app registry (T015C, US3).

        Args:
            registry_path: Path to app registry JSON file.
                          Defaults to ~/.config/i3/application-registry.json
        """
        if registry_path is None:
            registry_path = Path.home() / ".config/i3/application-registry.json"

        self.registry_path = registry_path
        self.registry: Dict[str, Dict[str, Any]] = {}
        self._load_registry()

    def _load_registry(self) -> None:
        """Load app registry from JSON file (T015C, US3)."""
        if not self.registry_path.exists():
            logger.warning(f"App registry not found: {self.registry_path}")
            self.registry = {}
            return

        try:
            with open(self.registry_path, 'r') as f:
                data = json.load(f)

            # Build name->app lookup dictionary
            apps = data.get("applications", [])
            self.registry = {app["name"]: app for app in apps}

            logger.debug(f"Loaded {len(self.registry)} apps from registry: {self.registry_path}")

        except Exception as e:
            logger.error(f"Failed to load app registry from {self.registry_path}: {e}")
            self.registry = {}

    async def launch_app(
        self,
        app_name: str,
        project: Optional[str] = None,
        cwd: Optional[Path] = None,
        extra_env: Optional[Dict[str, str]] = None,
        restore_mark: Optional[str] = None
    ) -> Optional[subprocess.Popen]:
        """Launch application via wrapper system (T015D, US3).

        Args:
            app_name: App name from registry (e.g., "yazi", "claude-pwa", "code")
            project: Project context for I3PM_PROJECT
            cwd: Working directory for terminals
            extra_env: Additional environment variables
            restore_mark: I3PM_RESTORE_MARK for layout correlation

        Returns:
            subprocess.Popen instance or None if launch failed
        """
        # Look up app in registry
        app_info = self.get_app_info(app_name)
        if not app_info:
            logger.error(f"App not found in registry: {app_name}")
            return None

        logger.debug(f"Launching app: {app_name} (project: {project}, cwd: {cwd})")

        # Feature 074: Use unified app launcher wrapper (replaces direct command execution)
        # The wrapper handles:
        # - Loading app from registry
        # - Building command with parameter substitution
        # - Injecting all I3PM_* environment variables
        # - Sending launch notification to daemon
        # - systemd-run process isolation
        import os
        wrapper_path = os.path.expanduser("~/.local/bin/app-launcher-wrapper.sh")
        command = [wrapper_path, app_name]

        # Build environment with restoration context
        env = dict(os.environ)  # Inherit current environment

        # Add I3PM_RESTORE_MARK for layout correlation (Feature 074)
        if restore_mark:
            env["I3PM_RESTORE_MARK"] = restore_mark
            logger.debug(f"Injecting I3PM_RESTORE_MARK={restore_mark}")

        # Add any extra environment variables
        if extra_env:
            env.update(extra_env)

        # Determine working directory
        launch_cwd = self._resolve_cwd(app_info, project, cwd)

        try:
            # Launch via unified wrapper
            process = subprocess.Popen(
                command,
                env=env,
                cwd=launch_cwd,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                start_new_session=True  # Detach from parent
            )

            logger.info(
                f"Launched {app_name} via wrapper (PID: {process.pid}, cwd: {launch_cwd})"
            )

            return process

        except Exception as e:
            logger.error(f"Failed to launch {app_name} via wrapper: {e}", exc_info=True)
            return None

    def _resolve_cwd(
        self,
        app_info: Dict[str, Any],
        project: Optional[str],
        cwd: Optional[Path]
    ) -> Optional[Path]:
        """Resolve working directory for app launch.

        Args:
            app_info: App registry entry
            project: Project name
            cwd: Requested working directory

        Returns:
            Resolved working directory or None for current directory
        """
        # If cwd explicitly provided, use it
        if cwd and cwd.exists():
            return cwd

        # Fall back to home directory for terminals only.
        # Project-aware directory resolution happens in app-launcher-wrapper.sh.
        if app_info.get("terminal"):
            return Path.home()

        # Non-terminal apps: use None (current directory)
        return None

    def get_app_info(self, app_name: str) -> Optional[Dict[str, Any]]:
        """Get app registry entry (T015G, US3).

        Args:
            app_name: App name to look up

        Returns:
            App registry entry or None if not found
        """
        return self.registry.get(app_name)

    def list_apps(
        self,
        scope: Optional[str] = None,
        terminal_only: bool = False
    ) -> List[Dict[str, Any]]:
        """List all apps, optionally filtered (T015G, US3).

        Args:
            scope: Filter by scope ("scoped" or "global")
            terminal_only: If True, only return terminal apps

        Returns:
            List of app registry entries
        """
        apps = list(self.registry.values())

        # Filter by scope if specified
        if scope:
            apps = [app for app in apps if app.get("scope") == scope]

        # Filter by terminal if specified
        if terminal_only:
            apps = [app for app in apps if app.get("terminal")]

        return apps
