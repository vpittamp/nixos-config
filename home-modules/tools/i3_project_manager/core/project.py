"""Project management operations.

This module provides high-level project management including:
- CRUD operations (create, read, update, delete, list)
- Project switching (activating/deactivating projects)
- Integration with daemon and i3 for window management
"""

import asyncio
import time
from pathlib import Path
from typing import Dict, List, Optional, Tuple

from .daemon_client import DaemonClient, DaemonError
from .i3_client import I3Client, I3Error
from .models import Project


class ProjectManager:
    """High-level project management operations.

    Coordinates between:
    - Project configuration files
    - Daemon (for project state tracking)
    - i3 window manager (for window operations)
    """

    def __init__(
        self,
        config_dir: Path = Path.home() / ".config/i3/projects",
        daemon_client: Optional[DaemonClient] = None,
        i3_client: Optional[I3Client] = None,
    ):
        """Initialize project manager.

        Args:
            config_dir: Directory containing project configs
            daemon_client: Optional daemon client (creates new if not provided)
            i3_client: Optional i3 client (creates new if not provided)
        """
        self.config_dir = config_dir
        self._daemon_client = daemon_client
        self._i3_client = i3_client

    async def _get_daemon(self) -> DaemonClient:
        """Get daemon client (lazy initialization).

        Returns:
            Connected daemon client
        """
        if not self._daemon_client:
            self._daemon_client = DaemonClient()
            await self._daemon_client.connect()
        return self._daemon_client

    async def _get_i3(self) -> I3Client:
        """Get i3 client (lazy initialization).

        Returns:
            Connected i3 client
        """
        if not self._i3_client:
            self._i3_client = I3Client()
            await self._i3_client.connect()
        return self._i3_client

    # Project CRUD operations

    async def create_project(
        self,
        name: str,
        directory: Path,
        display_name: Optional[str] = None,
        icon: Optional[str] = None,
        scoped_classes: Optional[List[str]] = None,
        **kwargs,
    ) -> Project:
        """Create a new project.

        Args:
            name: Project name (unique identifier)
            directory: Project working directory
            display_name: Optional display name
            icon: Optional icon emoji
            scoped_classes: Optional list of scoped window classes
            **kwargs: Additional project fields

        Returns:
            Created Project instance

        Raises:
            ValueError: If project already exists or validation fails
        """
        # Check if project already exists
        if (self.config_dir / f"{name}.json").exists():
            raise ValueError(f"Project '{name}' already exists")

        # Create project
        project = Project(
            name=name,
            directory=directory,
            display_name=display_name,
            icon=icon,
            scoped_classes=scoped_classes or ["Ghostty", "Code"],
            **kwargs,
        )

        # Save to disk
        project.save(self.config_dir)

        return project

    async def update_project(
        self, name: str, **updates
    ) -> Project:
        """Update an existing project.

        Args:
            name: Project name to update
            **updates: Fields to update

        Returns:
            Updated Project instance

        Raises:
            FileNotFoundError: If project doesn't exist
        """
        # Load existing project
        project = Project.load(name, self.config_dir)

        # Update fields
        for key, value in updates.items():
            if hasattr(project, key):
                setattr(project, key, value)

        # Save
        project.save(self.config_dir)

        return project

    async def delete_project(
        self, name: str, force: bool = False, delete_layouts: bool = True
    ) -> None:
        """Delete a project.

        Args:
            name: Project name to delete
            force: If True, skip confirmation
            delete_layouts: If True, also delete saved layouts

        Raises:
            FileNotFoundError: If project doesn't exist
        """
        project = Project.load(name, self.config_dir)

        if delete_layouts:
            project.delete_with_layouts()
        else:
            project.delete(self.config_dir)

    async def list_projects(
        self, sort_by: str = "modified"
    ) -> List[Project]:
        """List all projects.

        Args:
            sort_by: Sort field ("name", "modified", "directory")

        Returns:
            List of Project instances
        """
        projects = Project.list_all(self.config_dir)

        # Sort
        if sort_by == "name":
            projects.sort(key=lambda p: p.name)
        elif sort_by == "directory":
            projects.sort(key=lambda p: str(p.directory))
        # Default: already sorted by modified_at (newest first)

        return projects

    async def get_project(self, name: str) -> Project:
        """Get a single project.

        Args:
            name: Project name

        Returns:
            Project instance

        Raises:
            FileNotFoundError: If project doesn't exist
        """
        return Project.load(name, self.config_dir)

    # Project switching operations

    async def switch_to_project(
        self, name: str, no_launch: bool = False
    ) -> Tuple[bool, float, Optional[str]]:
        """Switch to a project.

        This sends a tick event to the daemon which triggers:
        1. Daemon processes tick event
        2. Daemon sets active project
        3. Daemon hides old project windows
        4. Daemon shows new project windows
        5. Daemon marks new windows with project mark

        Args:
            name: Project name to switch to
            no_launch: If True, skip auto-launch

        Returns:
            Tuple of (success, elapsed_time_ms, error_message)

        Raises:
            FileNotFoundError: If project doesn't exist
        """
        start_time = time.time()

        # Verify project exists
        project = await self.get_project(name)

        try:
            # Get i3 client
            i3 = await self._get_i3()

            # Send tick event to daemon
            await i3.send_tick(f"project:{name}")

            # Wait for daemon to process (query status until active_project changes)
            daemon = await self._get_daemon()
            max_wait = 0.5  # 500ms max wait
            poll_interval = 0.05  # 50ms polling
            elapsed = 0.0

            while elapsed < max_wait:
                status = await daemon.get_status()
                if status.get("active_project") == name:
                    break
                await asyncio.sleep(poll_interval)
                elapsed += poll_interval

            # Verify switch succeeded
            status = await daemon.get_status()
            if status.get("active_project") != name:
                elapsed_ms = (time.time() - start_time) * 1000
                return False, elapsed_ms, "Daemon did not activate project"

            # Auto-launch applications if configured and not disabled
            if not no_launch and project.auto_launch:
                # Check if windows already exist for this project
                windows = await i3.get_windows_by_mark(f"project:{name}")

                if len(windows) == 0:
                    # No existing windows, launch apps
                    await self._launch_applications(project)

            elapsed_ms = (time.time() - start_time) * 1000
            return True, elapsed_ms, None

        except (DaemonError, I3Error) as e:
            elapsed_ms = (time.time() - start_time) * 1000
            return False, elapsed_ms, str(e)

    async def clear_project(self) -> Tuple[bool, float, Optional[str]]:
        """Clear active project (return to global mode).

        Returns:
            Tuple of (success, elapsed_time_ms, error_message)
        """
        start_time = time.time()

        try:
            # Get i3 client
            i3 = await self._get_i3()

            # Send tick event to daemon
            await i3.send_tick("project:clear")

            # Wait for daemon to process
            daemon = await self._get_daemon()
            max_wait = 0.5  # 500ms max wait
            poll_interval = 0.05  # 50ms polling
            elapsed = 0.0

            while elapsed < max_wait:
                status = await daemon.get_status()
                if status.get("active_project") is None:
                    break
                await asyncio.sleep(poll_interval)
                elapsed += poll_interval

            elapsed_ms = (time.time() - start_time) * 1000
            return True, elapsed_ms, None

        except (DaemonError, I3Error) as e:
            elapsed_ms = (time.time() - start_time) * 1000
            return False, elapsed_ms, str(e)

    async def get_current_project(self) -> Optional[str]:
        """Get current active project name.

        Returns:
            Active project name, or None if no project active

        Raises:
            DaemonError: If daemon query fails
        """
        daemon = await self._get_daemon()
        return await daemon.get_active_project()

    async def get_project_window_count(self, name: str) -> int:
        """Get number of windows for a project.

        Args:
            name: Project name

        Returns:
            Number of windows with project mark
        """
        try:
            i3 = await self._get_i3()
            windows = await i3.get_windows_by_mark(f"project:{name}")
            return len(windows)
        except I3Error:
            return 0

    # Helper methods

    async def _launch_applications(self, project: Project) -> None:
        """Launch auto-launch applications for a project.

        Args:
            project: Project with auto_launch configured
        """
        import subprocess

        i3 = await self._get_i3()

        for app in project.auto_launch:
            try:
                # Focus workspace if specified
                if app.workspace:
                    await i3.focus_workspace(app.workspace)

                # Launch application with environment
                env = app.get_full_env(project)
                subprocess.Popen(
                    app.command,
                    shell=True,
                    env=env,
                    stdout=subprocess.DEVNULL,
                    stderr=subprocess.DEVNULL,
                )

                # Wait for launch delay
                if app.launch_delay > 0:
                    await asyncio.sleep(app.launch_delay)

                # Optional: Wait for window to appear
                # (This is basic implementation - full version in Phase 10)
                if app.wait_for_mark and app.wait_timeout > 0:
                    await asyncio.sleep(min(app.wait_timeout, 1.0))

            except Exception as e:
                # Log error but continue with remaining apps
                print(f"Warning: Failed to launch '{app.command}': {e}")
                continue
