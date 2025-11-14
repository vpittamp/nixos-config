"""Focus tracking service for session management.

Feature 074: Session Management
Tasks T021-T025: FocusTracker service for workspace/window focus tracking

Tracks per-project focused workspace and per-workspace focused window.
Persists focus state to JSON files for daemon restart recovery.
"""

import asyncio
import json
import logging
from pathlib import Path
from typing import Optional

logger = logging.getLogger(__name__)


class FocusTracker:
    """Service for tracking workspace and window focus state (T021, US1)"""

    def __init__(self, state_manager, config_dir: Path = Path.home() / ".config/i3"):
        """Initialize focus tracker.

        Args:
            state_manager: StateManager instance for accessing DaemonState
            config_dir: Directory for persistent focus state files
        """
        self.state_manager = state_manager
        self.config_dir = config_dir
        self.config_dir.mkdir(parents=True, exist_ok=True)

        self.project_focus_file = self.config_dir / "project-focus-state.json"
        self.workspace_focus_file = self.config_dir / "workspace-focus-state.json"

        self._lock = asyncio.Lock()

    async def track_workspace_focus(self, project: str, workspace_num: int) -> None:
        """Track workspace focus for a project (T022, US1)

        Args:
            project: Project name
            workspace_num: Workspace number that was focused
        """
        async with self._lock:
            # Update DaemonState
            self.state_manager.state.set_focused_workspace(project, workspace_num)

            # Persist to disk
            await self.persist_focus_state()

            logger.debug(f"Tracked workspace focus: {project} → workspace {workspace_num}")

    async def track_window_focus(self, workspace_num: int, window_id: int) -> None:
        """Track window focus for a workspace (T065, US4)

        Args:
            workspace_num: Workspace number
            window_id: Window ID that was focused
        """
        async with self._lock:
            # Update DaemonState
            self.state_manager.state.set_focused_window(workspace_num, window_id)

            # Persist to disk
            await self.persist_focus_state()

            logger.debug(f"Tracked window focus: workspace {workspace_num} → window {window_id}")

    async def get_project_focused_workspace(self, project: str) -> Optional[int]:
        """Get focused workspace for a project (T023, US1)

        Args:
            project: Project name

        Returns:
            Workspace number or None if no focus history
        """
        async with self._lock:
            workspace_num = self.state_manager.state.get_focused_workspace(project)
            logger.debug(f"Retrieved focused workspace for {project}: {workspace_num}")
            return workspace_num

    async def get_workspace_focused_window(self, workspace_num: int) -> Optional[int]:
        """Get focused window for a workspace (T066, US4)

        Args:
            workspace_num: Workspace number

        Returns:
            Window ID or None if no focus history
        """
        async with self._lock:
            window_id = self.state_manager.state.get_focused_window(workspace_num)
            logger.debug(f"Retrieved focused window for workspace {workspace_num}: {window_id}")
            return window_id

    async def persist_focus_state(self) -> None:
        """Persist focus state to JSON files (T024, US1)

        Writes both project focus and workspace focus to separate JSON files.
        """
        try:
            # Persist project focus state
            project_focus_data = self.state_manager.state.project_focused_workspace
            self.project_focus_file.write_text(json.dumps(project_focus_data, indent=2))

            # Persist workspace focus state
            workspace_focus_data = {
                str(k): v for k, v in self.state_manager.state.workspace_focused_window.items()
            }
            self.workspace_focus_file.write_text(json.dumps(workspace_focus_data, indent=2))

            logger.debug(f"Persisted focus state to {self.config_dir}")

        except Exception as e:
            logger.error(f"Failed to persist focus state: {e}")

    async def load_focus_state(self) -> None:
        """Load focus state from JSON files (T025, US1)

        Restores both project focus and workspace focus from JSON files.
        Gracefully handles missing or corrupt files.
        """
        try:
            # Load project focus state
            if self.project_focus_file.exists():
                project_focus_data = json.loads(self.project_focus_file.read_text())
                self.state_manager.state.project_focused_workspace = project_focus_data
                logger.info(f"Loaded project focus state: {len(project_focus_data)} projects")
            else:
                logger.debug("No project focus state file found (first run)")

            # Load workspace focus state
            if self.workspace_focus_file.exists():
                workspace_focus_data = json.loads(self.workspace_focus_file.read_text())
                self.state_manager.state.workspace_focused_window = {
                    int(k): v for k, v in workspace_focus_data.items()
                }
                logger.info(f"Loaded workspace focus state: {len(workspace_focus_data)} workspaces")
            else:
                logger.debug("No workspace focus state file found (first run)")

        except Exception as e:
            logger.error(f"Failed to load focus state: {e}")
            # Continue with empty state - not fatal
