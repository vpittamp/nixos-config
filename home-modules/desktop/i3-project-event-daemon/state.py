"""State manager for i3 project event daemon.

Manages in-memory daemon state with thread-safe operations.
"""

import asyncio
import logging
from typing import Dict, List, Optional
import i3ipc

from .models import DaemonState, WindowInfo, WorkspaceInfo

logger = logging.getLogger(__name__)


class StateManager:
    """Manages runtime state for the daemon with thread-safe operations."""

    def __init__(self) -> None:
        """Initialize state manager with empty state."""
        self.state = DaemonState()
        self._lock = asyncio.Lock()

    async def add_window(self, window_info: WindowInfo) -> None:
        """Add a window to the tracking map.

        Args:
            window_info: WindowInfo object to add
        """
        async with self._lock:
            self.state.window_map[window_info.window_id] = window_info
            logger.debug(
                f"Added window {window_info.window_id} "
                f"(class={window_info.window_class}, project={window_info.project})"
            )

    async def remove_window(self, window_id: int) -> None:
        """Remove a window from the tracking map.

        Args:
            window_id: ID of window to remove
        """
        async with self._lock:
            if window_id in self.state.window_map:
                window_info = self.state.window_map.pop(window_id)
                logger.debug(
                    f"Removed window {window_id} "
                    f"(class={window_info.window_class}, project={window_info.project})"
                )
            else:
                logger.warning(f"Attempted to remove non-existent window {window_id}")

    async def update_window(self, window_id: int, **kwargs) -> None:
        """Update window properties.

        Args:
            window_id: ID of window to update
            **kwargs: Properties to update (project, workspace, marks, etc.)
        """
        async with self._lock:
            if window_id not in self.state.window_map:
                logger.warning(f"Attempted to update non-existent window {window_id}")
                return

            window_info = self.state.window_map[window_id]

            # Update allowed fields
            for key, value in kwargs.items():
                if hasattr(window_info, key):
                    setattr(window_info, key, value)
                    logger.debug(f"Updated window {window_id}: {key}={value}")
                else:
                    logger.warning(f"Unknown window property: {key}")

    async def get_window(self, window_id: int) -> Optional[WindowInfo]:
        """Get window by ID.

        Args:
            window_id: ID of window to retrieve

        Returns:
            WindowInfo object or None if not found
        """
        async with self._lock:
            return self.state.window_map.get(window_id)

    async def get_windows_by_project(self, project: str) -> List[WindowInfo]:
        """Get all windows belonging to a specific project.

        Args:
            project: Project name to filter by

        Returns:
            List of WindowInfo objects for the project
        """
        async with self._lock:
            return [
                window_info
                for window_info in self.state.window_map.values()
                if window_info.project == project
            ]

    async def set_active_project(self, project: Optional[str]) -> None:
        """Update the active project.

        Args:
            project: Project name to activate, or None for global mode
        """
        async with self._lock:
            old_project = self.state.active_project
            self.state.active_project = project
            logger.info(f"Active project changed: {old_project} → {project}")

    async def get_active_project(self) -> Optional[str]:
        """Get the currently active project.

        Returns:
            Active project name or None if in global mode
        """
        async with self._lock:
            return self.state.active_project

    async def add_workspace(self, workspace_info: WorkspaceInfo) -> None:
        """Add or update a workspace in the tracking map.

        Args:
            workspace_info: WorkspaceInfo object to add
        """
        async with self._lock:
            self.state.workspace_map[workspace_info.name] = workspace_info
            logger.debug(f"Added workspace {workspace_info.name} on output {workspace_info.output}")

    async def remove_workspace(self, name: str) -> None:
        """Remove a workspace from the tracking map.

        Args:
            name: Workspace name to remove
        """
        async with self._lock:
            if name in self.state.workspace_map:
                self.state.workspace_map.pop(name)
                logger.debug(f"Removed workspace {name}")
            else:
                logger.warning(f"Attempted to remove non-existent workspace {name}")

    async def rebuild_from_marks(self, tree: i3ipc.Con) -> None:
        """Rebuild window_map from i3 tree by scanning for project marks.

        This is used during daemon startup/reconnection to restore state from marks.

        Args:
            tree: Root container from i3 GET_TREE
        """
        async with self._lock:
            # Clear existing state
            self.state.window_map.clear()
            count = 0

            # Recursively scan tree for windows with project marks
            def scan_container(container: i3ipc.Con) -> None:
                nonlocal count

                # Check if this is a window (has window_id)
                if container.window:
                    # Look for project marks (format: project:PROJECT_NAME)
                    project_marks = [
                        mark for mark in container.marks if mark.startswith("project:")
                    ]

                    if project_marks:
                        # Extract project name from mark
                        project_name = project_marks[0].split(":", 1)[1]

                        # Create WindowInfo
                        from datetime import datetime

                        window_info = WindowInfo(
                            window_id=container.window,
                            con_id=container.id,
                            window_class=container.window_class or "unknown",
                            window_title=container.name or "",
                            window_instance=container.window_instance or "",
                            app_identifier=container.window_class
                            or "unknown",  # Will be refined later
                            project=project_name,
                            marks=list(container.marks),
                            workspace=container.workspace().name if container.workspace() else "",
                            output=(
                                container.workspace().ipc_data.get("output", "")
                                if container.workspace()
                                else ""
                            ),
                            is_floating=container.floating == "user_on",
                            created=datetime.now(),
                        )

                        self.state.window_map[container.window] = window_info
                        count += 1

                # Recursively scan children
                for child in container.nodes + container.floating_nodes:
                    scan_container(child)

            scan_container(tree)
            logger.info(f"Rebuilt state: found {count} windows with project marks")

    async def increment_event_count(self) -> None:
        """Increment the total event counter."""
        async with self._lock:
            self.state.event_count += 1

    async def increment_error_count(self) -> None:
        """Increment the error counter."""
        async with self._lock:
            self.state.error_count += 1

    async def get_stats(self) -> Dict:
        """Get daemon statistics.

        Returns:
            Dictionary with event counts, window counts, etc.
        """
        async with self._lock:
            return {
                "event_count": self.state.event_count,
                "error_count": self.state.error_count,
                "window_count": len(self.state.window_map),
                "workspace_count": len(self.state.workspace_map),
                "active_project": self.state.active_project,
                "uptime_seconds": (
                    asyncio.get_event_loop().time() - self.state.start_time.timestamp()
                ),
            }
