"""
Scratchpad Terminal Manager

Manages lifecycle and state of project-scoped scratchpad terminals.
Handles terminal launch, validation, toggle operations, and state tracking.

Feature 062 - Project-Scoped Scratchpad Terminal
"""

import asyncio
import logging
import os
import time
from pathlib import Path
from typing import Dict, Optional, List, Tuple
import sys

# Add parent directory to path for imports
sys.path.insert(0, str(Path(__file__).parent.parent))

from models.scratchpad import ScratchpadTerminal
from daemon.terminal_launcher import (
    build_unified_launcher_invocation,
    select_terminal_emulator,
)

logger = logging.getLogger(__name__)


class ScratchpadManager:
    """
    Manages scratchpad terminal lifecycle and state.

    Responsibilities:
        - Launch terminals via unified launcher (Feature 041/057 integration)
        - Track terminal state (PID, window ID, mark, working dir)
        - Validate terminal health (process + window existence)
        - Toggle terminal visibility (show/hide via Sway IPC)
        - Clean up invalid terminals (dead processes, missing windows)

    State:
        terminals: Dict[project_name → ScratchpadTerminal]
            In-memory mapping of project name to terminal instance

    Integration:
        - Uses Sway IPC for authoritative window state (Principle XI)
        - Uses unified launcher for consistent app launching (Feature 041)
        - Uses I3PM_* environment variables for window matching (Feature 057)
    """

    def __init__(self, sway_connection):
        """
        Initialize scratchpad manager.

        Args:
            sway_connection: i3ipc.aio.Connection instance for Sway IPC
        """
        self.terminals: Dict[str, ScratchpadTerminal] = {}
        self.sway = sway_connection
        self.logger = logging.getLogger(__name__)
        self._launch_lock = asyncio.Lock()  # Serialize launch operations per FR-020

    async def launch_terminal(
        self,
        project_name: str,
        working_dir: Path,
        workspace_number: int = 1,
    ) -> ScratchpadTerminal:
        """
        Launch new scratchpad terminal for project via unified launcher.

        Flow:
            1. Send pre-launch notification to launch registry (Feature 041)
            2. Invoke app-launcher-wrapper.sh with parameters
            3. Wait for window event (timeout: 2s per FR-019)
            4. Correlate window via launch notification or /proc fallback
            5. Mark window with scratchpad:{project_name}
            6. Set floating + dimensions (1200x700, centered)
            7. Track in daemon state

        Args:
            project_name: Project identifier or "global"
            working_dir: Initial working directory for terminal
            workspace_number: Target workspace (default: 1)

        Returns:
            ScratchpadTerminal instance

        Raises:
            ValueError: If project already has scratchpad terminal
            RuntimeError: If terminal launch fails or times out
        """
        async with self._launch_lock:
            # Check for existing terminal
            if project_name in self.terminals:
                raise ValueError(f"Scratchpad terminal already exists for project '{project_name}'")

            self.logger.info(f"Launching scratchpad terminal for project '{project_name}' in {working_dir}")

            # Build unified launcher invocation
            cmd, env, notification = build_unified_launcher_invocation(
                project_name,
                working_dir,
                workspace_number,
            )

            # TODO: Send pre-launch notification to launch registry (Feature 041)
            # await self._send_launch_notification(notification)

            # Launch terminal via unified launcher
            try:
                proc = await asyncio.create_subprocess_exec(
                    *cmd,
                    env={**os.environ, **env},
                    stdout=asyncio.subprocess.PIPE,
                    stderr=asyncio.subprocess.PIPE,
                )

                self.logger.debug(
                    f"Launched terminal process: pid={proc.pid}, "
                    f"project={project_name}, notification_id={notification['launch_id']}"
                )

            except Exception as e:
                self.logger.error(f"Failed to launch terminal: {e}")
                raise RuntimeError(f"Terminal launch failed: {e}")

            # Wait for window to appear (timeout: 2s per FR-019)
            mark = ScratchpadTerminal.create_mark(project_name)
            window = await self._wait_for_window(
                mark,
                notification['expected_class'],
                timeout=2.0,
            )

            if not window:
                self.logger.error(
                    f"Window did not appear within 2s timeout for project '{project_name}'"
                )
                # Terminate launched process
                try:
                    proc.terminate()
                    await asyncio.wait_for(proc.wait(), timeout=1.0)
                except Exception:
                    proc.kill()

                raise RuntimeError(
                    f"Terminal window did not appear within 2s timeout. "
                    f"Check that terminal emulator is installed and working."
                )

            # Mark window with scratchpad mark
            await self.sway.command(f'[con_id={window.id}] mark {mark}')

            # Set floating and dimensions (1200x700, centered)
            await self.sway.command(
                f'[con_id={window.id}] floating enable, '
                f'resize set 1200 700, '
                f'move position center'
            )

            self.logger.info(
                f"Configured scratchpad terminal: "
                f"window_id={window.id}, mark={mark}, floating=true, size=1200x700"
            )

            # Create terminal instance
            terminal = ScratchpadTerminal(
                project_name=project_name,
                pid=window.pid,
                window_id=window.id,
                mark=mark,
                working_dir=working_dir,
                created_at=time.time(),
            )

            # Track in state
            self.terminals[project_name] = terminal

            self.logger.info(
                f"Scratchpad terminal launched successfully: "
                f"project={project_name}, pid={window.pid}, window_id={window.id}"
            )

            return terminal

    async def _wait_for_window(
        self,
        mark: str,
        expected_class: str,
        timeout: float = 2.0,
    ):
        """
        Wait for window to appear with specified mark or app_id.

        Uses polling strategy with 50ms intervals (max 40 attempts for 2s timeout).

        Args:
            mark: Expected Sway mark (e.g., "scratchpad:nixos")
            expected_class: Expected app_id (e.g., "com.mitchellh.ghostty" or "Alacritty")
            timeout: Maximum wait time in seconds

        Returns:
            Window container object or None if timeout
        """
        attempts = int(timeout / 0.05)  # 50ms polling interval

        for attempt in range(attempts):
            await asyncio.sleep(0.05)

            # Query Sway tree for matching window
            tree = await self.sway.get_tree()

            # Try to find by mark first
            for window in tree.descendants():
                if mark in window.marks:
                    self.logger.debug(f"Found window by mark '{mark}': id={window.id}")
                    return window

            # Fallback: find by app_id (for newly created windows without mark yet)
            for window in tree.descendants():
                if window.app_id and expected_class.lower() in window.app_id.lower():
                    # Check if window is unmarked (newly created)
                    if not any(m.startswith("scratchpad:") for m in window.marks):
                        self.logger.debug(
                            f"Found unmarked window by app_id '{expected_class}': "
                            f"id={window.id}, app_id={window.app_id}"
                        )
                        return window

        self.logger.warning(
            f"Window not found after {timeout}s: mark={mark}, "
            f"expected_class={expected_class}"
        )
        return None

    async def validate_terminal(self, project_name: str) -> bool:
        """
        Validate scratchpad terminal exists and is still running.

        Validation checks (per Principle XI - Sway IPC authoritative):
            1. Terminal exists in daemon state
            2. Process is still running (via psutil)
            3. Window exists in Sway tree (via GET_TREE)
            4. Window has correct mark (re-apply if missing)

        Args:
            project_name: Project identifier

        Returns:
            True if terminal is valid, False otherwise

        Side Effects:
            - Removes terminal from state if invalid (process dead or window missing)
            - Re-applies mark if window exists but mark is missing
        """
        terminal = self.terminals.get(project_name)
        if not terminal:
            return False

        # Check 1: Process still running
        if not terminal.is_process_running():
            self.logger.warning(
                f"Terminal process {terminal.pid} not running for project '{project_name}'"
            )
            del self.terminals[project_name]
            return False

        # Check 2: Window exists in Sway tree
        tree = await self.sway.get_tree()
        window = tree.find_by_id(terminal.window_id)
        if not window:
            self.logger.warning(
                f"Terminal window {terminal.window_id} not found in Sway tree "
                f"for project '{project_name}'"
            )
            del self.terminals[project_name]
            return False

        # Check 3: Window has correct mark
        if terminal.mark not in window.marks:
            self.logger.warning(
                f"Terminal window {terminal.window_id} missing mark '{terminal.mark}', "
                f"re-applying"
            )
            # Re-apply mark (recoverable)
            await self.sway.command(f'[con_id={terminal.window_id}] mark {terminal.mark}')

        return True

    async def get_terminal_state(self, project_name: str) -> Optional[str]:
        """
        Get current visibility state of scratchpad terminal.

        Queries Sway IPC for authoritative window state.

        Args:
            project_name: Project identifier

        Returns:
            "visible" if window is on a workspace
            "hidden" if window is in __i3_scratch workspace (scratchpad)
            None if terminal doesn't exist or is invalid
        """
        terminal = self.terminals.get(project_name)
        if not terminal:
            return None

        # Validate terminal first
        if not await self.validate_terminal(project_name):
            return None

        # Query Sway tree for window state
        tree = await self.sway.get_tree()
        window = tree.find_by_id(terminal.window_id)

        if not window:
            return None

        # Check if window is in scratchpad workspace
        if window.workspace() and window.workspace().name == "__i3_scratch":
            return "hidden"
        else:
            return "visible"

    async def toggle_terminal(self, project_name: str) -> str:
        """
        Toggle scratchpad terminal visibility (show if hidden, hide if visible).

        Args:
            project_name: Project identifier

        Returns:
            "shown" if terminal was hidden and is now visible
            "hidden" if terminal was visible and is now hidden

        Raises:
            ValueError: If terminal doesn't exist or is invalid
        """
        terminal = self.terminals.get(project_name)
        if not terminal:
            raise ValueError(f"No scratchpad terminal found for project '{project_name}'")

        # Validate terminal
        if not await self.validate_terminal(project_name):
            raise ValueError(
                f"Scratchpad terminal for project '{project_name}' is invalid "
                f"(process dead or window missing)"
            )

        # Get current state
        state = await self.get_terminal_state(project_name)

        if state == "visible":
            # Hide to scratchpad
            await self.sway.command(f'[con_mark="{terminal.mark}"] move scratchpad')
            self.logger.info(f"Hid scratchpad terminal for project '{project_name}'")
            return "hidden"
        else:
            # Show from scratchpad
            await self.sway.command(f'[con_mark="{terminal.mark}"] scratchpad show')
            terminal.mark_shown()
            self.logger.info(f"Shown scratchpad terminal for project '{project_name}'")
            return "shown"

    def get_terminal(self, project_name: str) -> Optional[ScratchpadTerminal]:
        """
        Retrieve scratchpad terminal for project.

        Args:
            project_name: Project identifier

        Returns:
            ScratchpadTerminal instance or None if not found
        """
        return self.terminals.get(project_name)

    async def list_terminals(self) -> List[ScratchpadTerminal]:
        """
        List all tracked scratchpad terminals.

        Returns:
            List of ScratchpadTerminal instances
        """
        return list(self.terminals.values())

    async def cleanup_invalid_terminals(self) -> Tuple[int, List[str]]:
        """
        Remove invalid terminals from state (dead processes, missing windows).

        Validates all terminals and removes those that are no longer valid.

        Returns:
            Tuple of (count_cleaned, projects_cleaned):
                - count_cleaned: Number of invalid terminals removed
                - projects_cleaned: List of project names whose terminals were removed
        """
        projects_to_remove = []

        for project_name in list(self.terminals.keys()):
            if not await self.validate_terminal(project_name):
                projects_to_remove.append(project_name)

        # Remove invalid terminals
        for project_name in projects_to_remove:
            if project_name in self.terminals:
                del self.terminals[project_name]
                self.logger.info(f"Cleaned up invalid terminal for project '{project_name}'")

        if projects_to_remove:
            self.logger.info(
                f"Cleanup complete: removed {len(projects_to_remove)} invalid terminal(s)"
            )

        return (len(projects_to_remove), projects_to_remove)

    async def close_terminal(self, project_name: str) -> None:
        """
        Close scratchpad terminal for project.

        Terminates window via Sway IPC and removes from daemon state.

        Args:
            project_name: Project identifier

        Raises:
            ValueError: If no terminal found for project
            RuntimeError: If failed to close terminal window
        """
        terminal = self.terminals.get(project_name)
        if not terminal:
            raise ValueError(f"No scratchpad terminal found for project '{project_name}'")

        # Close window via Sway IPC
        try:
            await self.sway.command(f'[con_id={terminal.window_id}] kill')
            self.logger.info(
                f"Closed scratchpad terminal window: "
                f"project={project_name}, window_id={terminal.window_id}"
            )
        except Exception as e:
            self.logger.error(f"Failed to close terminal window: {e}")
            raise RuntimeError(f"Failed to close terminal window: {e}")

        # Remove from state
        del self.terminals[project_name]

        self.logger.info(f"Removed terminal from state: project={project_name}")
