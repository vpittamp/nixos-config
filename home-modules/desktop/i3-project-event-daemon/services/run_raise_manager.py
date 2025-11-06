"""Run-raise-hide manager for application launching - Feature 051."""

import asyncio
import logging
import shutil
import subprocess
import time
from pathlib import Path
from typing import Optional, Dict, Any

try:
    from i3ipc.aio import Connection, Con
except ImportError:
    Connection = None
    Con = None

from ..models.window_state import WindowState, WindowStateInfo, RunMode
from ..window_filtering import WorkspaceTracker

logger = logging.getLogger(__name__)


class RunRaiseManager:
    """Manages run-raise-hide state machine for application launching."""

    def __init__(
        self,
        sway: Connection,
        workspace_tracker: WorkspaceTracker,
        app_launcher_path: Optional[str] = None,
    ):
        """Initialize run-raise manager.

        Args:
            sway: Sway IPC connection
            workspace_tracker: WorkspaceTracker instance for state storage
            app_launcher_path: Path to app-launcher-wrapper (auto-detected if None)
        """
        self.sway = sway
        self.workspace_tracker = workspace_tracker

        # Auto-detect app-launcher-wrapper path if not provided
        if app_launcher_path is None:
            app_launcher_path = shutil.which("app-launcher-wrapper")
            if app_launcher_path is None:
                raise RuntimeError(
                    "app-launcher-wrapper not found in PATH. "
                    "Ensure home-modules/tools/app-launcher.nix is enabled."
                )

        self.app_launcher_path = app_launcher_path
        logger.info(f"Using app launcher: {self.app_launcher_path}")
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
            # Summon mode: move window to current workspace
            # Default mode (goto): switch to window's workspace
            if mode == "summon":
                return await self._transition_summon(state_info.window, state_info.current_workspace)
            else:
                return await self._transition_goto(state_info.window)

        elif state_info.state == WindowState.SAME_WORKSPACE_UNFOCUSED:
            return await self._transition_focus(state_info.window)

        elif state_info.state == WindowState.SAME_WORKSPACE_FOCUSED:
            # Mode matters here - only hide in HIDE mode
            if mode == "hide":
                return await self._transition_hide(state_info.window, app_name)
            else:
                # summon or nohide - window already focused, no action needed
                return {
                    "action": "none",
                    "window_id": state_info.window.id,
                    "focused": True,
                    "message": f"{app_name.capitalize()} already focused",
                }

        elif state_info.state == WindowState.SCRATCHPAD:
            return await self._transition_show(state_info.window, app_name)

        else:
            raise ValueError(f"Unknown window state: {state_info.state}")

    async def _transition_launch(self, app_name: str) -> Dict[str, Any]:
        """Launch new application instance.

        Args:
            app_name: Application name

        Returns:
            Response dict
        """
        logger.info(f"Launching {app_name} via app-launcher-wrapper")

        try:
            # Launch via app-launcher-wrapper (non-blocking)
            # The wrapper script returns immediately after calling swaymsg exec
            # We use Popen to avoid blocking on script completion
            process = subprocess.Popen(
                [self.app_launcher_path, app_name],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
            )

            # Wait briefly for script to start (but not for app to launch)
            # This allows us to catch immediate errors like "command not found"
            try:
                stdout, stderr = process.communicate(timeout=2)
                if process.returncode != 0:
                    error_msg = stderr.strip() or "Launch failed"
                    logger.error(f"Failed to launch {app_name}: {error_msg}")
                    raise RuntimeError(f"Launch failed: {error_msg}")
            except subprocess.TimeoutExpired:
                # Script is still running (likely waiting for swaymsg)
                # This is normal - the script should complete soon
                logger.debug(f"Launch script still running for {app_name} (normal)")

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

    async def _transition_summon(self, window: Con, current_workspace: str) -> Dict[str, Any]:
        """Move window to current workspace (summon mode).

        Preserves floating state and geometry during the move.

        Args:
            window: Sway window container
            current_workspace: Target workspace name

        Returns:
            Response dict
        """
        logger.info(f"Summoning window {window.id} to workspace {current_workspace}")

        try:
            # Capture current state
            is_floating = window.type == "floating_con" or (
                hasattr(window, 'floating') and window.floating and window.floating != 'auto_off'
            )
            geometry = None

            if is_floating and window.rect:
                geometry = {
                    "x": window.rect.x,
                    "y": window.rect.y,
                    "width": window.rect.width,
                    "height": window.rect.height,
                }
                logger.debug(f"Captured geometry for window {window.id}: {geometry}")

            # Move to current workspace
            await self.sway.command(f'[con_id={window.id}] move container to workspace {current_workspace}')

            # Focus the window
            await self.sway.command(f'[con_id={window.id}] focus')

            # Restore floating state if it was floating
            if is_floating:
                await self.sway.command(f'[con_id={window.id}] floating enable')

                # Restore geometry if we captured it
                if geometry:
                    await self.sway.command(
                        f'[con_id={window.id}] '
                        f'move position {geometry["x"]} {geometry["y"]}'
                    )
                    await self.sway.command(
                        f'[con_id={window.id}] '
                        f'resize set {geometry["width"]} {geometry["height"]}'
                    )
                    logger.debug(f"Restored geometry for window {window.id}")

            return {
                "action": "summoned",
                "window_id": window.id,
                "focused": True,
                "message": f"Summoned to workspace {current_workspace}",
            }

        except Exception as e:
            logger.error(f"Failed to summon window {window.id}: {e}")
            raise RuntimeError(f"Summon failed: {e}")

    async def _transition_hide(self, window: Con, app_name: str) -> Dict[str, Any]:
        """Hide window to scratchpad (preserving state).

        Captures floating state and geometry before hiding, stores in WorkspaceTracker.

        Args:
            window: Sway window container
            app_name: Application name for tracking

        Returns:
            Response dict
        """
        logger.info(f"Hiding window {window.id} to scratchpad")

        try:
            # Capture current state
            is_floating = window.type == "floating_con" or (
                hasattr(window, 'floating') and window.floating and window.floating != 'auto_off'
            )
            geometry = None

            if window.rect:
                geometry = {
                    "x": window.rect.x,
                    "y": window.rect.y,
                    "width": window.rect.width,
                    "height": window.rect.height,
                }
                logger.debug(f"Captured geometry for window {window.id}: {geometry}")

            # Store state via WorkspaceTracker
            # This uses the window-workspace-map.json schema v1.1 with geometry support
            self.workspace_tracker.track_window(
                window_id=window.id,
                workspace="__i3_scratch",  # Mark as scratchpad
                is_floating=is_floating,
                geometry=geometry,
            )

            # Move to scratchpad
            await self.sway.command(f'[con_id={window.id}] move scratchpad')

            logger.info(f"Window {window.id} hidden to scratchpad with state preserved")

            return {
                "action": "hidden",
                "window_id": window.id,
                "focused": False,
                "message": f"Hidden {app_name} to scratchpad",
            }

        except Exception as e:
            logger.error(f"Failed to hide window {window.id}: {e}")
            raise RuntimeError(f"Hide failed: {e}")

    async def _transition_show(self, window: Con, app_name: str) -> Dict[str, Any]:
        """Show window from scratchpad (restoring state).

        Restores floating state and geometry from WorkspaceTracker.

        Args:
            window: Sway window container
            app_name: Application name for tracking

        Returns:
            Response dict
        """
        logger.info(f"Showing window {window.id} from scratchpad")

        try:
            # Load stored state from WorkspaceTracker
            stored_state = self.workspace_tracker.get_window_state(window.id)

            # Show from scratchpad
            await self.sway.command(f'[con_id={window.id}] scratchpad show')

            # Restore state if we have it
            if stored_state:
                is_floating = stored_state.get("is_floating", False)
                geometry = stored_state.get("geometry")

                if is_floating:
                    await self.sway.command(f'[con_id={window.id}] floating enable')
                    logger.debug(f"Restored floating state for window {window.id}")

                if geometry:
                    await self.sway.command(
                        f'[con_id={window.id}] '
                        f'move position {geometry["x"]} {geometry["y"]}'
                    )
                    await self.sway.command(
                        f'[con_id={window.id}] '
                        f'resize set {geometry["width"]} {geometry["height"]}'
                    )
                    logger.debug(f"Restored geometry for window {window.id}: {geometry}")

            return {
                "action": "shown",
                "window_id": window.id,
                "focused": True,
                "message": f"Shown {app_name} from scratchpad",
            }

        except Exception as e:
            logger.error(f"Failed to show window {window.id}: {e}")
            raise RuntimeError(f"Show failed: {e}")
