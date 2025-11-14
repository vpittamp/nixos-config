"""State manager for i3 project event daemon.

Manages in-memory daemon state with async-safe operations.
"""

import asyncio
import logging
from typing import Dict, List, Optional
from i3ipc import aio

from .models import DaemonState, WindowInfo, WorkspaceInfo
from .services.launch_registry import LaunchRegistry  # Feature 041: IPC Launch Context - T013
from .services.focus_tracker import FocusTracker  # Feature 074: Session Management - T021
from pathlib import Path

logger = logging.getLogger(__name__)


class StateManager:
    """Manages runtime state for the daemon with async-safe operations."""

    def __init__(self) -> None:
        """Initialize state manager with empty state."""
        self.state = DaemonState()
        self._lock = asyncio.Lock()

        # Feature 041: IPC Launch Context - T013
        # Launch registry for correlating windows to launch notifications
        self.launch_registry = LaunchRegistry(timeout=5.0)
        logger.info("Initialized LaunchRegistry with 5-second timeout")

        # Feature 074: Session Management - T021
        # Focus tracker for workspace and window focus restoration
        config_dir = Path.home() / ".config" / "i3"
        config_dir.mkdir(parents=True, exist_ok=True)
        self.focus_tracker = FocusTracker(self, config_dir)
        logger.info("Initialized FocusTracker for session management")

        # Feature 074: Session Management - T099 (US5)
        # Auto-save manager for automatic layout capture
        # Note: Will be initialized when i3 connection is available
        self.auto_save_manager = None
        self.auto_restore_manager = None

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

    async def rebuild_from_marks(self, tree: aio.Con) -> None:
        """Rebuild window_map from i3 tree by scanning for project marks.

        This is used during daemon startup/reconnection to restore state from marks.

        Args:
            tree: Root container from i3 GET_TREE (async)
        """
        async with self._lock:
            # Clear existing state
            self.state.window_map.clear()
            count = 0

            # Recursively scan tree for windows with project marks
            def scan_container(container: aio.Con) -> None:
                nonlocal count

                # Check if this is a window (has window_id)
                if container.window:
                    # Look for project marks (format: SCOPE:PROJECT:WINDOW_ID)
                    project_marks = [
                        mark for mark in container.marks if mark.startswith("scoped:") or mark.startswith("global:")
                    ]

                    if project_marks:
                        # Extract project name from mark (second field)
                        mark_parts = project_marks[0].split(":")
                        project_name = mark_parts[1] if len(mark_parts) >= 2 else None

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
            from datetime import datetime
            uptime = (datetime.now() - self.state.start_time).total_seconds()

            return {
                "event_count": self.state.event_count,
                "error_count": self.state.error_count,
                "window_count": len(self.state.window_map),
                "workspace_count": len(self.state.workspace_map),
                "active_project": self.state.active_project,
                "uptime_seconds": uptime,
            }

    async def update_app_classification(self, classification: "ApplicationClassification") -> None:
        """Update application classification (scoped/global classes).

        This method is called when reloading configuration via tick event (T030).

        Args:
            classification: New ApplicationClassification object with scoped/global sets
        """
        async with self._lock:
            old_scoped_count = len(self.state.scoped_classes)
            old_global_count = len(self.state.global_classes)

            self.state.scoped_classes = classification.scoped_classes
            self.state.global_classes = classification.global_classes

            logger.info(
                f"Updated app classification: "
                f"scoped {old_scoped_count}→{len(classification.scoped_classes)}, "
                f"global {old_global_count}→{len(classification.global_classes)}"
            )

    def initialize_auto_save_manager(self, conn, ipc_server=None) -> None:
        """Initialize auto-save and auto-restore managers with i3 connection (Feature 074: T099, US5-US6).

        Args:
            conn: i3/Sway async connection
            ipc_server: Optional IPC server for event notifications
        """
        try:
            from .layout.capture import LayoutCapture
            from .layout.restore import LayoutRestore
            from .layout.persistence import LayoutPersistence
            from .layout.auto_save import AutoSaveManager
            from .layout.auto_restore import AutoRestoreManager
            from .models.config import ProjectConfiguration

            # Feature 076 T017-T018, T021-T022: Get mark_manager from ipc_server if available
            mark_manager = ipc_server.mark_manager if ipc_server and hasattr(ipc_server, 'mark_manager') else None

            # Initialize layout services
            layout_capture = LayoutCapture(conn, mark_manager=mark_manager)
            layout_restore = LayoutRestore(conn, mark_manager=mark_manager)  # Feature 076: T021-T022
            layout_persistence = LayoutPersistence()

            # Project config loader function
            def load_project_config(project_name: str):
                try:
                    project_dir = Path.home() / "projects" / project_name
                    return ProjectConfiguration(
                        name=project_name,
                        directory=project_dir
                    )
                except Exception as e:
                    logger.debug(f"Could not load config for {project_name}: {e}")
                    return None

            # Initialize auto-save manager (Feature 074: T099, US5)
            self.auto_save_manager = AutoSaveManager(
                layout_capture,
                layout_persistence,
                load_project_config,
                ipc_server=ipc_server
            )
            logger.info("Initialized AutoSaveManager for session management")

            # Initialize auto-restore manager (Feature 074: T099, US6)
            self.auto_restore_manager = AutoRestoreManager(
                layout_capture,
                layout_restore,
                layout_persistence,
                load_project_config,
                ipc_server=ipc_server
            )
            logger.info("Initialized AutoRestoreManager for session management")

        except Exception as e:
            logger.error(f"Failed to initialize Auto-Save/Auto-Restore managers: {e}")
            self.auto_save_manager = None
            self.auto_restore_manager = None

    async def load_focus_state(self) -> None:
        """Load focus state from disk on daemon startup (Feature 074: T025, US1).

        Loads previously persisted workspace and window focus state to restore
        session management context across daemon restarts.
        """
        if hasattr(self, 'focus_tracker') and self.focus_tracker:
            try:
                await self.focus_tracker.load_focus_state()
                logger.info("Successfully loaded focus state from disk")
            except Exception as e:
                logger.warning(f"Failed to load focus state: {e}")
                # Non-fatal error - daemon can continue without persisted focus state
        else:
            logger.debug("FocusTracker not initialized, skipping focus state load")
