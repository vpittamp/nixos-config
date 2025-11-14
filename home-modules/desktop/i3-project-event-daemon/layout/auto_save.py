"""Auto-save manager for session management.

Feature 074: Session Management
Tasks T072-T081: AutoSaveManager service for automatic layout capture

Automatically saves layout when switching away from a project.
Prunes old auto-saves to maintain a maximum count per project.
"""

import asyncio
import logging
from datetime import datetime
from pathlib import Path
from typing import Optional

logger = logging.getLogger(__name__)


class AutoSaveManager:
    """Service for automatic layout saving (T072, US5)"""

    def __init__(self, layout_capture, layout_persistence, project_config_loader, ipc_server=None):
        """Initialize auto-save manager.

        Args:
            layout_capture: LayoutCapture instance for capturing layouts
            layout_persistence: LayoutPersistence instance for saving layouts
            project_config_loader: Function to load ProjectConfiguration for a project
            ipc_server: Optional IPC server for event notifications (Feature 074: T081)
        """
        self.layout_capture = layout_capture
        self.layout_persistence = layout_persistence
        self.project_config_loader = project_config_loader
        self.ipc_server = ipc_server

    def should_auto_save(self, project: str) -> bool:
        """Check if auto-save is enabled for a project (T073, US5)

        Args:
            project: Project name

        Returns:
            True if auto-save is enabled for this project
        """
        try:
            project_config = self.project_config_loader(project)
            if project_config and hasattr(project_config, 'auto_save'):
                return project_config.auto_save
        except Exception as e:
            logger.debug(f"Could not load project config for {project}: {e}")

        # Default to True if config not found (conservative default)
        return True

    def generate_auto_save_name(self) -> str:
        """Generate auto-save layout name with timestamp (T074, US5)

        Returns:
            Layout name in format: auto-YYYYMMDD-HHMMSS
        """
        return f"auto-{datetime.now().strftime('%Y%m%d-%H%M%S')}"

    async def prune_old_auto_saves(self, project: str, max_count: int = 10) -> int:
        """Prune old auto-saves for a project (T075-T076, US5)

        Only deletes layouts with names starting with "auto-".
        Keeps the most recent auto-saves up to max_count.

        Args:
            project: Project name
            max_count: Maximum number of auto-saves to keep (default: 10)

        Returns:
            Number of auto-saves deleted
        """
        try:
            # Get layouts directory for project
            layouts_dir = Path.home() / ".local/share/i3pm/layouts" / project
            if not layouts_dir.exists():
                logger.debug(f"No layouts directory for {project}, skipping prune")
                return 0

            # Find all auto-save layout files
            auto_save_files = []
            for layout_file in layouts_dir.glob("auto-*.json"):
                auto_save_files.append(layout_file)

            # Sort by modification time (newest first)
            auto_save_files.sort(key=lambda f: f.stat().st_mtime, reverse=True)

            # Delete old auto-saves beyond max_count
            deleted_count = 0
            for old_layout in auto_save_files[max_count:]:
                try:
                    old_layout.unlink()
                    deleted_count += 1
                    logger.debug(f"Deleted old auto-save: {old_layout.name}")
                except Exception as e:
                    logger.warning(f"Failed to delete old auto-save {old_layout.name}: {e}")

            if deleted_count > 0:
                logger.info(f"Pruned {deleted_count} old auto-saves for {project}")

            return deleted_count

        except Exception as e:
            logger.error(f"Failed to prune old auto-saves for {project}: {e}")
            return 0

    async def auto_save_on_switch(self, old_project: str) -> Optional[str]:
        """Automatically save layout when switching away from a project (T077-T080, US5)

        Args:
            old_project: Project being switched away from

        Returns:
            Layout name if auto-save succeeded, None if skipped or failed
        """
        # Check if auto-save is enabled for this project
        if not self.should_auto_save(old_project):
            logger.debug(f"Auto-save disabled for {old_project}, skipping")
            return None

        try:
            # Generate auto-save name
            layout_name = self.generate_auto_save_name()

            # Capture current layout (async to avoid blocking project switch)
            logger.debug(f"Auto-saving layout for {old_project}: {layout_name}")
            snapshot = await self.layout_capture.capture_current_layout(
                name=layout_name,
                project=old_project
            )

            # Persist layout to disk (synchronous method)
            saved_path = self.layout_persistence.save_layout(snapshot)

            # Prune old auto-saves
            project_config = self.project_config_loader(old_project)
            max_auto_saves = project_config.max_auto_saves if project_config and hasattr(project_config, 'max_auto_saves') else 10
            await self.prune_old_auto_saves(old_project, max_count=max_auto_saves)

            logger.info(f"Auto-saved layout for {old_project}: {layout_name}")

            # Feature 074: T081 - Emit layout.auto_saved event notification
            if self.ipc_server:
                try:
                    # Calculate total window count across all workspaces
                    total_windows = sum(len(ws.windows) for ws in snapshot.workspace_layouts)

                    event_data = {
                        "type": "layout.auto_saved",
                        "project": old_project,
                        "layout_name": layout_name,
                        "path": str(saved_path),
                        "window_count": total_windows,
                        "workspace_count": len(snapshot.workspace_layouts)
                    }
                    # Use asyncio to schedule the broadcast without blocking
                    asyncio.create_task(self.ipc_server.broadcast_event(event_data))
                    logger.debug(f"Emitted layout.auto_saved event for {layout_name}")
                except Exception as event_error:
                    logger.warning(f"Failed to emit auto-save event: {event_error}")

            return layout_name

        except Exception as e:
            logger.error(f"Auto-save failed for {old_project}: {e}")
            return None
