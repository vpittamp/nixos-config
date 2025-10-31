"""Workspace mode state manager for event-driven navigation.

Feature 042: Event-Driven Workspace Mode Navigation
Manages in-memory state for digit accumulation, workspace switching, and history tracking.
"""

import asyncio
import logging
import time
from datetime import datetime
from pathlib import Path
from typing import Optional, List, Dict, TYPE_CHECKING

# Import Pydantic models from existing models module
from .models import WorkspaceModeState, WorkspaceSwitch, WorkspaceModeEvent

if TYPE_CHECKING:
    from i3ipc.aio import Connection

logger = logging.getLogger(__name__)


class WorkspaceModeManager:
    """Manages workspace mode state in-memory."""

    def __init__(self, i3_connection: "Connection"):
        """Initialize workspace mode manager.

        Args:
            i3_connection: i3ipc async connection for workspace switching
        """
        self._i3 = i3_connection
        self._state = WorkspaceModeState()
        self._history: List[WorkspaceSwitch] = []  # Circular buffer, max 100

    @property
    def state(self) -> WorkspaceModeState:
        """Get current workspace mode state."""
        return self._state

    @property
    def mode_type(self) -> Optional[str]:
        """Get current mode type (goto/move/None)."""
        return self._state.mode_type

    async def enter_mode(self, mode_type: str) -> None:
        """Enter workspace mode (goto, move, or kill).

        Args:
            mode_type: "goto" (navigate to workspace), "move" (move window + follow), or "kill" (close all windows)

        Raises:
            ValueError: If mode_type is not "goto", "move", or "kill"
        """
        if mode_type not in ("goto", "move", "kill"):
            raise ValueError(f"Invalid mode_type: {mode_type}. Must be 'goto', 'move', or 'kill'")

        logger.info(f"Entering workspace mode: {mode_type}")

        self._state.active = True
        self._state.mode_type = mode_type
        self._state.accumulated_digits = ""
        self._state.entered_at = datetime.now()

        # Refresh output cache from i3 IPC
        await self._refresh_output_cache()

        logger.debug(f"Workspace mode entered: state={self._state}")

    async def add_digit(self, digit: str) -> str:
        """Add digit to accumulated state.

        Args:
            digit: Single digit 0-9

        Returns:
            Current accumulated digits string

        Raises:
            ValueError: If digit is not 0-9
            RuntimeError: If mode is not active
        """
        start_time = time.time()

        if not self._state.active:
            raise RuntimeError("Cannot add digit: workspace mode not active")

        if not digit or digit not in "0123456789":
            raise ValueError(f"Invalid digit: {digit}. Must be 0-9")

        # Ignore leading zero
        if digit == "0" and not self._state.accumulated_digits:
            logger.debug("Ignoring leading zero")
            return self._state.accumulated_digits

        self._state.accumulated_digits += digit

        elapsed_ms = (time.time() - start_time) * 1000
        logger.debug(f"Digit added: {digit}, accumulated: {self._state.accumulated_digits} (took {elapsed_ms:.2f}ms)")

        return self._state.accumulated_digits

    async def execute(self) -> Optional[Dict[str, any]]:
        """Execute workspace switch with accumulated digits.

        Returns:
            Dict with workspace number, output name, and success status
            None if no digits accumulated (no-op)

        Raises:
            RuntimeError: If mode is not active
        """
        if not self._state.active:
            raise RuntimeError("Cannot execute: workspace mode not active")

        # Handle empty digits (no-op)
        if not self._state.accumulated_digits:
            logger.info("Execute called with empty digits, exiting mode without action")
            await self.cancel()
            return None

        workspace = int(self._state.accumulated_digits)
        output = self._get_output_for_workspace(workspace)

        logger.info(f"Executing workspace action: ws={workspace}, output={output}, mode={self._state.mode_type}")

        start_time = time.time()
        try:
            # Execute workspace action via i3 IPC
            ipc_start = time.time()
            if self._state.mode_type == "goto":
                await self._i3.command(f"workspace number {workspace}")
            elif self._state.mode_type == "move":
                # Move container + follow user
                await self._i3.command(f"move container to workspace number {workspace}; workspace number {workspace}")
            elif self._state.mode_type == "kill":
                # Kill all windows in the workspace
                await self._kill_workspace_windows(workspace)
            ipc_elapsed_ms = (time.time() - ipc_start) * 1000

            # NOTE: Removed explicit "focus output" command (Feature 042 fix)
            # Sway's "workspace number X" already focuses the correct output automatically
            # based on workspace assignments in sway config. Explicit output focusing
            # was causing the wrong workspace to be focused when daemon's calculated
            # output didn't match Sway's static workspace assignments.

            # Exit mode in Sway (return to default mode)
            await self._i3.command("mode default")

            total_elapsed_ms = (time.time() - start_time) * 1000
            action = "killed" if self._state.mode_type == "kill" else "switched"
            logger.info(f"Workspace action successful: ws={workspace}, action={action} (took {total_elapsed_ms:.2f}ms)")

            # Record history (Feature 042: US4)
            await self._record_switch(workspace, output, self._state.mode_type)

            # Reset state
            mode_type = self._state.mode_type  # Save for return value
            self._state.active = False
            self._state.mode_type = None
            self._state.accumulated_digits = ""

            return {
                "workspace": workspace,
                "output": output,
                "success": True,
                "mode_type": mode_type
            }

        except Exception as e:
            logger.error(f"Workspace switch failed: {e}")
            # Don't reset state on error - user can retry
            raise

    async def cancel(self) -> None:
        """Cancel workspace mode without action."""
        if not self._state.active:
            logger.debug("Cancel called but mode not active, no-op")
            return

        logger.info("Cancelling workspace mode")

        # Exit mode in Sway (return to default mode)
        await self._i3.command("mode default")

        self._state.active = False
        self._state.mode_type = None
        self._state.accumulated_digits = ""
        self._state.entered_at = None

    def get_history(self, limit: Optional[int] = None) -> List[WorkspaceSwitch]:
        """Get workspace switch history.

        Args:
            limit: Maximum number of entries to return (default: all)

        Returns:
            List of WorkspaceSwitch entries, most recent first
        """
        history = list(reversed(self._history))
        if limit:
            return history[:limit]
        return history

    async def _refresh_output_cache(self) -> None:
        """Refresh output cache from i3 IPC.

        Updates output_cache dict with PRIMARY/SECONDARY/TERTIARY mappings
        based on active output count (1-3 monitors).
        """
        try:
            outputs = await self._i3.get_outputs()
            active_outputs = [o for o in outputs if o.active]

            if len(active_outputs) == 0:
                logger.warning("No active outputs detected, using fallback (eDP-1)")
                self._state.output_cache = {
                    "PRIMARY": "eDP-1",
                    "SECONDARY": "eDP-1",
                    "TERTIARY": "eDP-1"
                }
            elif len(active_outputs) == 1:
                # Single monitor - all outputs map to same display
                self._state.output_cache = {
                    "PRIMARY": active_outputs[0].name,
                    "SECONDARY": active_outputs[0].name,
                    "TERTIARY": active_outputs[0].name
                }
            elif len(active_outputs) == 2:
                # Two monitors
                self._state.output_cache = {
                    "PRIMARY": active_outputs[0].name,
                    "SECONDARY": active_outputs[1].name,
                    "TERTIARY": active_outputs[1].name  # Tertiary uses secondary
                }
            elif len(active_outputs) >= 3:
                # Three or more monitors
                self._state.output_cache = {
                    "PRIMARY": active_outputs[0].name,
                    "SECONDARY": active_outputs[1].name,
                    "TERTIARY": active_outputs[2].name
                }

            logger.debug(f"Output cache refreshed: {self._state.output_cache}")

        except Exception as e:
            logger.error(f"Failed to refresh output cache: {e}")
            # Use fallback
            self._state.output_cache = {
                "PRIMARY": "eDP-1",
                "SECONDARY": "eDP-1",
                "TERTIARY": "eDP-1"
            }

    def _get_output_for_workspace(self, workspace: int) -> str:
        """Get output name for workspace number.

        Distribution rules:
        - Workspaces 1-2: PRIMARY
        - Workspaces 3-5: SECONDARY
        - Workspaces 6+: TERTIARY

        Args:
            workspace: Workspace number

        Returns:
            Output name (e.g., "eDP-1", "HEADLESS-1")
        """
        if workspace in (1, 2):
            return self._state.output_cache.get("PRIMARY", "eDP-1")
        elif workspace in (3, 4, 5):
            return self._state.output_cache.get("SECONDARY", "eDP-1")
        else:
            return self._state.output_cache.get("TERTIARY", "eDP-1")

    async def _kill_workspace_windows(self, workspace: int) -> None:
        """Kill all windows in the specified workspace.

        Args:
            workspace: Workspace number to clear
        """
        try:
            # Get the workspace tree
            tree = await self._i3.get_tree()

            # Find all windows in the target workspace
            window_ids = []
            for node in tree:
                if hasattr(node, 'type') and node.type == 'workspace' and hasattr(node, 'num') and node.num == workspace:
                    # Recursively find all window nodes
                    def find_windows(n):
                        if hasattr(n, 'pid') and n.pid:
                            window_ids.append(n.id)
                        if hasattr(n, 'nodes'):
                            for child in n.nodes:
                                find_windows(child)
                        if hasattr(n, 'floating_nodes'):
                            for child in n.floating_nodes:
                                find_windows(child)
                    find_windows(node)
                    break

            if not window_ids:
                logger.info(f"No windows found in workspace {workspace}")
                return

            logger.info(f"Killing {len(window_ids)} window(s) in workspace {workspace}")

            # Kill all windows gracefully
            for window_id in window_ids:
                try:
                    await self._i3.command(f"[con_id={window_id}] kill")
                    logger.debug(f"Killed window {window_id}")
                except Exception as e:
                    logger.warning(f"Failed to kill window {window_id}: {e}")

        except Exception as e:
            logger.error(f"Error killing workspace windows: {e}")
            raise

    async def _record_switch(self, workspace: int, output: str, mode_type: str) -> None:
        """Record workspace switch in history.

        Args:
            workspace: Workspace number switched to
            output: Output name focused
            mode_type: "goto", "move", or "kill"
        """
        switch = WorkspaceSwitch(
            workspace_number=workspace,
            output_name=output,
            timestamp=datetime.now(),
            mode_type=mode_type
        )

        self._history.append(switch)

        # Maintain max 100 entries (circular buffer)
        if len(self._history) > 100:
            self._history.pop(0)

        logger.debug(f"Recorded workspace switch: {switch}")

    def create_event(self, event_type: str = "state_change") -> WorkspaceModeEvent:
        """Create event payload for broadcasting.

        Args:
            event_type: Type of event ("digit", "execute", "cancel", "enter", "exit", "state_change")

        Returns:
            WorkspaceModeEvent with current state
        """
        return WorkspaceModeEvent(
            event_type=event_type,
            state=self._state,
            timestamp=datetime.now()
        )
