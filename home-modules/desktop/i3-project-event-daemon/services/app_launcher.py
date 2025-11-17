"""Unified application launcher for wrapper-based restoration.

Feature 074: Session Management
Tasks T015B-T015G: AppLauncher service for Feature 057 integration

Ensures all app launches (Walker, restore, daemon, CLI) use the same
wrapper system with I3PM_* environment variable injection.
"""

import asyncio
import json
import logging
import os
import re
import subprocess
from pathlib import Path
from typing import Any, Dict, List, Optional

from ..models.worktree_environment import WorktreeEnvironment

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

    def _build_command(
        self,
        app_info: Dict[str, Any],
        project: Optional[str],
        cwd: Optional[Path]
    ) -> List[str]:
        """Build launch command with $PROJECT_DIR and $CWD substitution (T015E, US3).

        Args:
            app_info: App registry entry
            project: Project name for $PROJECT_DIR substitution
            cwd: Working directory for $CWD substitution

        Returns:
            Command as list of strings
        """
        # Get command and parameters from registry
        command = app_info["command"]
        parameters = app_info.get("parameters", [])

        # Build command list
        cmd_parts = [command]

        # Process parameters with substitutions
        for param in parameters:
            # Substitute $PROJECT_DIR with project directory
            if "$PROJECT_DIR" in param and project:
                # TODO: Look up project directory from project registry
                # For now, assume project directory is ~/projects/{project}
                project_dir = Path.home() / "projects" / project
                param = param.replace("$PROJECT_DIR", str(project_dir))

            # Substitute $CWD with provided working directory
            if "$CWD" in param and cwd:
                param = param.replace("$CWD", str(cwd))

            cmd_parts.append(param)

        logger.debug(f"Built command: {' '.join(cmd_parts)}")
        return cmd_parts

    def _build_environment(
        self,
        app_info: Dict[str, Any],
        project: Optional[str],
        restore_mark: Optional[str],
        extra_env: Optional[Dict[str, str]]
    ) -> Dict[str, str]:
        """Build environment with I3PM_* variable injection (T015F, US3).

        Args:
            app_info: App registry entry
            project: Project context
            restore_mark: I3PM_RESTORE_MARK for correlation
            extra_env: Additional environment variables

        Returns:
            Complete environment dictionary
        """
        # Start with current environment
        env = os.environ.copy()

        # Add I3PM_APP_NAME (critical for Feature 057 window matching)
        app_name = app_info["name"]
        env["I3PM_APP_NAME"] = app_name

        # Add I3PM_PROJECT if provided
        if project:
            env["I3PM_PROJECT"] = project

        # Add I3PM_RESTORE_MARK if provided (for layout correlation)
        if restore_mark:
            env["I3PM_RESTORE_MARK"] = restore_mark

        # Add I3PM_APP_ID (unique launch identifier)
        import uuid
        env["I3PM_APP_ID"] = str(uuid.uuid4())

        # Feature 079: T060-T062 - Inject worktree metadata environment variables
        if project:
            worktree_env = self._load_worktree_environment(project)
            if worktree_env:
                env.update(worktree_env.to_env_dict())
                logger.debug(f"Injected worktree env vars: {worktree_env.to_env_dict()}")

        # Add extra environment variables
        if extra_env:
            env.update(extra_env)

        logger.debug(
            f"Built environment: I3PM_APP_NAME={app_name}, "
            f"I3PM_PROJECT={project}, I3PM_RESTORE_MARK={restore_mark}"
        )

        return env

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

        # If terminal app and project provided, use project directory
        if app_info.get("terminal") and project:
            project_dir = Path.home() / "projects" / project
            if project_dir.exists():
                return project_dir

        # Fall back to home directory for terminals
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

    def _load_worktree_environment(self, project_name: str) -> Optional[WorktreeEnvironment]:
        """Load worktree metadata from project JSON (Feature 079: T060-T062).

        Args:
            project_name: Name of the project

        Returns:
            WorktreeEnvironment instance with metadata, or None if loading fails
        """
        project_file = Path.home() / ".config/i3/projects" / f"{project_name}.json"

        if not project_file.exists():
            logger.debug(f"Project file not found: {project_file}")
            return None

        try:
            with open(project_file, "r") as f:
                project_data = json.load(f)

            # Check if this is a worktree project
            worktree_data = project_data.get("worktree")

            if worktree_data:
                # Extract branch metadata (T061, T062)
                branch = worktree_data.get("branch", "")
                branch_number = None
                branch_type = None

                # Extract numeric prefix from branch name
                match = re.match(r"^(\d+)-", branch)
                if match:
                    branch_number = match.group(1)

                # Classify branch type based on name patterns
                if "-fix-" in branch or branch.startswith("fix-"):
                    branch_type = "fix"
                elif "-feature-" in branch or "-feat-" in branch:
                    branch_type = "feature"
                elif "-refactor-" in branch:
                    branch_type = "refactor"
                else:
                    # Default to feature for numbered branches
                    branch_type = "feature" if branch_number else None

                # Resolve parent project name
                parent_project = None
                repository_path = worktree_data.get("repository_path", "")
                if repository_path:
                    # Try to find parent project by directory
                    parent_project = self._resolve_parent_project_name(repository_path)

                return WorktreeEnvironment(
                    is_worktree=True,
                    parent_project=parent_project,
                    branch_type=branch_type,
                    branch_number=branch_number,
                    full_branch_name=branch,
                )
            else:
                # Not a worktree project
                return WorktreeEnvironment(
                    is_worktree=False,
                    parent_project=None,
                    branch_type=None,
                    branch_number=None,
                    full_branch_name=None,
                )

        except Exception as e:
            logger.warning(f"Failed to load worktree environment for {project_name}: {e}")
            return None

    def _resolve_parent_project_name(self, repository_path: str) -> Optional[str]:
        """Resolve parent project name from repository path.

        Args:
            repository_path: Absolute path to parent repository

        Returns:
            Name of parent project or None if not found
        """
        # Search all project JSONs for matching directory
        project_dir = Path.home() / ".config/i3/projects"

        if not project_dir.exists():
            return None

        try:
            for project_file in project_dir.glob("*.json"):
                with open(project_file, "r") as f:
                    project_data = json.load(f)

                # Check if this project's directory matches the repository path
                if project_data.get("directory") == repository_path:
                    return project_data.get("name")
        except Exception as e:
            logger.warning(f"Failed to resolve parent project: {e}")

        return None

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
