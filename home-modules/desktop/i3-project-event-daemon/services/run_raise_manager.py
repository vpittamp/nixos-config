"""Run-raise-hide manager for application launching - Feature 051."""

import asyncio
import logging
import subprocess
import time
from pathlib import Path
from typing import Optional, Dict, Any

try:
    from i3ipc.aio import Connection, Con
except ImportError:
    Connection = None
    Con = None

# Import models from the daemon package
from ..models.window_state import WindowState, WindowStateInfo, RunMode
from ..window_filtering import WorkspaceTracker

logger = logging.getLogger(__name__)


class RunRaiseManager:
    """Manages run-raise-hide state machine for application launching."""

    def __init__(
        self,
        sway: Connection,
        workspace_tracker: WorkspaceTracker,
        app_launcher_path: str = "/run/current-system/sw/bin/app-launcher-wrapper.sh",
    ):
        """Initialize run-raise manager.

        Args:
            sway: Sway IPC connection
            workspace_tracker: WorkspaceTracker instance for state storage
            app_launcher_path: Path to app-launcher-wrapper.sh
        """
        self.sway = sway
        self.workspace_tracker = workspace_tracker
        self.app_launcher_path = app_launcher_path
        self._window_tracking: Dict[str, int] = {}  # app_name -> window_id mapping

    def register_window(self, app_name: str, window_id: int) -> None:
        """Register window_id for app_name (called on window::new events).

        Args:
            app_name: Application name from I3PM_APP_NAME
            window_id: Sway container ID
        """
        self._window_tracking[app_name] = window_id
        logger.debug(f"Registered window {window_id} for app '{app_name}'")

    def unregister_window(self, app_name: str) -> None:
        """Unregister window for app_name (called on window::close events).

        Args:
            app_name: Application name
        """
        if app_name in self._window_tracking:
            del self._window_tracking[app_name]
            logger.debug(f"Unregistered window for app '{app_name}'")

    def _get_window_id_by_app_name(self, app_name: str) -> Optional[int]:
        """Lookup window_id from daemon tracking.

        Args:
            app_name: Application name

        Returns:
            Window ID or None if not found
        """
        return self._window_tracking.get(app_name)

    async def detect_window_state(self, app_name: str) -> WindowStateInfo:
        """Detect current state of window for given app.

        Args:
            app_name: Application name from registry

        Returns:
            WindowStateInfo with detected state
        """
        # Get Sway tree and focused workspace
        tree = await self.sway.get_tree()
        focused = tree.find_focused()
        current_workspace = focused.workspace().name if focused and focused.workspace() else "1"

        # Lookup window_id from daemon tracking
        window_id = self._get_window_id_by_app_name(app_name)

        if window_id is None:
            return WindowStateInfo(
                state=WindowState.NOT_FOUND,
                window=None,
                current_workspace=current_workspace,
                window_workspace=None,
                is_focused=False,
            )

        # Find window by ID
        window = tree.find_by_id(window_id)

        if not window:
            # Window was tracked but no longer exists
            self.unregister_window(app_name)
            return WindowStateInfo(
                state=WindowState.NOT_FOUND,
                window=None,
                current_workspace=current_workspace,
                window_workspace=None,
                is_focused=False,
            )

        # Determine window state
        workspace = window.workspace()
        window_workspace_name = workspace.name if workspace else "__i3_scratch"

        # Check if in scratchpad
        if window_workspace_name == "__i3_scratch":
            return WindowStateInfo(
                state=WindowState.SCRATCHPAD,
                window=window,
                current_workspace=current_workspace,
                window_workspace=window_workspace_name,
                is_focused=False,
            )

        # Check workspace match
        if window_workspace_name != current_workspace:
            return WindowStateInfo(
                state=WindowState.DIFFERENT_WORKSPACE,
                window=window,
                current_workspace=current_workspace,
                window_workspace=window_workspace_name,
                is_focused=False,
            )

        # Same workspace - check focus
        is_focused = window.focused

        if is_focused:
            return WindowStateInfo(
                state=WindowState.SAME_WORKSPACE_FOCUSED,
                window=window,
                current_workspace=current_workspace,
                window_workspace=window_workspace_name,
                is_focused=True,
            )
        else:
            return WindowStateInfo(
                state=WindowState.SAME_WORKSPACE_UNFOCUSED,
                window=window,
                current_workspace=current_workspace,
                window_workspace=window_workspace_name,
                is_focused=False,
            )

    async def execute_transition(
        self,
        app_name: str,
        state_info: WindowStateInfo,
        mode: str = "summon",
        force_launch: bool = False,
    ) -> Dict[str, Any]:
        """Execute state transition based on detected state.

        Args:
            app_name: Application name
            state_info: Detected window state
            mode: Run mode (summon, hide, nohide)
            force_launch: Skip state detection and launch new instance

        Returns:
            Response dict with action, window_id, focused, message
        """
        # Force launch bypasses state machine
        if force_launch:
            return await self._transition_launch(app_name)

        # Dispatch based on state
        if state_info.state == WindowState.NOT_FOUND:
            return await self._transition_launch(app_name)

        elif state_info.state == WindowState.DIFFERENT_WORKSPACE:
            # Mode doesn't matter for different workspace (always bring to focus)
            return await self._transition_goto(state_info.window)

        elif state_info.state == WindowState.SAME_WORKSPACE_UNFOCUSED:
            return await self._transition_focus(state_info.window)

        elif state_info.state == WindowState.SAME_WORKSPACE_FOCUSED:
            # Mode matters here - only hide in HIDE mode
            if mode == "hide":
                # Will be implemented in Phase 5 (User Story 3)
                return {
                    "action": "none",
                    "window_id": state_info.window_id,
                    "focused": True,
                    "message": f"Hide mode not yet implemented for {app_name}",
                }
            else:
                # summon or nohide - window already focused, no action needed
                return {
                    "action": "none",
                    "window_id": state_info.window_id,
                    "focused": True,
                    "message": f"{app_name.capitalize()} already focused",
                }

        elif state_info.state == WindowState.SCRATCHPAD:
            # Will be implemented in Phase 5 (User Story 3)
            return {
                "action": "none",
                "window_id": state_info.window_id,
                "focused": False,
                "message": f"Scratchpad show not yet implemented for {app_name}",
            }

        else:
            raise ValueError(f"Unknown window state: {state_info.state}")

    async def _transition_launch(self, app_name: str) -> Dict[str, Any]:
        """Launch new application instance.

        Args:
            app_name: Application name

        Returns:
            Response dict
        """
        logger.info(f"Launching {app_name} via app-launcher-wrapper.sh")

        try:
            # Launch via app-launcher-wrapper.sh
            # This script injects I3PM_* environment variables
            result = subprocess.run(
                [self.app_launcher_path, app_name],
                capture_output=True,
                text=True,
                timeout=5,
            )

            if result.returncode != 0:
                error_msg = result.stderr.strip() or "Launch failed"
                logger.error(f"Failed to launch {app_name}: {error_msg}")
                raise RuntimeError(f"Launch failed: {error_msg}")

            return {
                "action": "launched",
                "window_id": None,  # Window not yet created
                "focused": False,
                "message": f"Launched {app_name}",
            }

        except subprocess.TimeoutExpired:
            logger.error(f"Launch timeout for {app_name}")
            raise RuntimeError(f"Launch timeout after 5 seconds")

        except FileNotFoundError:
            logger.error(f"app-launcher-wrapper.sh not found at {self.app_launcher_path}")
            raise RuntimeError(f"Launcher script not found: {self.app_launcher_path}")

    async def _transition_focus(self, window: Con) -> Dict[str, Any]:
        """Focus window.

        Args:
            window: Sway window container

        Returns:
            Response dict
        """
        logger.info(f"Focusing window {window.id}")

        try:
            await self.sway.command(f'[con_id={window.id}] focus')

            return {
                "action": "focused",
                "window_id": window.id,
                "focused": True,
                "message": f"Focused window {window.id}",
            }

        except Exception as e:
            logger.error(f"Failed to focus window {window.id}: {e}")
            raise RuntimeError(f"Focus failed: {e}")

    async def _transition_goto(self, window: Con) -> Dict[str, Any]:
        """Switch to window's workspace and focus.

        Args:
            window: Sway window container

        Returns:
            Response dict
        """
        workspace = window.workspace()
        workspace_name = workspace.name if workspace else "unknown"

        logger.info(f"Switching to workspace {workspace_name} and focusing window {window.id}")

        try:
            # Switch to workspace
            await self.sway.command(f'workspace {workspace_name}')

            # Focus window
            await self.sway.command(f'[con_id={window.id}] focus')

            return {
                "action": "focused",
                "window_id": window.id,
                "focused": True,
                "message": f"Switched to workspace {workspace_name}",
            }

        except Exception as e:
            logger.error(f"Failed to goto window {window.id}: {e}")
            raise RuntimeError(f"Goto failed: {e}")
