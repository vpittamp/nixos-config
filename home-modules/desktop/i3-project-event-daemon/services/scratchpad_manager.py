"""
Scratchpad Terminal Manager

Manages lifecycle and state of project-scoped scratchpad terminals.
"""

import asyncio
import logging
import os
from pathlib import Path
from typing import Dict, List, Optional
import psutil

from i3ipc.aio import Connection

from ..models.scratchpad import ScratchpadTerminal


logger = logging.getLogger(__name__)


def read_process_environ(pid: int) -> Dict[str, str]:
    """
    Read environment variables from process.

    Args:
        pid: Process ID

    Returns:
        Dictionary of environment variables

    Raises:
        ProcessLookupError: If process doesn't exist
        PermissionError: If unable to read process environ
    """
    environ_path = Path(f"/proc/{pid}/environ")
    try:
        environ_bytes = environ_path.read_bytes()
        environ_str = environ_bytes.decode("utf-8", errors="ignore")
        env_pairs = environ_str.split("\x00")
        env_dict = {}
        for pair in env_pairs:
            if "=" in pair:
                key, value = pair.split("=", 1)
                env_dict[key] = value
        return env_dict
    except FileNotFoundError:
        raise ProcessLookupError(f"Process {pid} not found")
    except PermissionError:
        raise PermissionError(f"Cannot read environ for process {pid}")


class ScratchpadManager:
    """Manages scratchpad terminal lifecycle and state."""

    def __init__(self, sway: Connection):
        """
        Initialize scratchpad manager.

        Args:
            sway: Async Sway IPC connection
        """
        self.terminals: Dict[str, ScratchpadTerminal] = {}
        self.sway = sway
        self.logger = logging.getLogger(__name__)

    async def launch_terminal(
        self,
        project_name: str,
        working_dir: Path,
    ) -> ScratchpadTerminal:
        """
        Launch new scratchpad terminal for project.

        Args:
            project_name: Project identifier or "global"
            working_dir: Initial working directory for terminal

        Returns:
            ScratchpadTerminal instance

        Raises:
            RuntimeError: If terminal launch fails
            ValueError: If project already has scratchpad terminal
        """
        # Validate project doesn't already have a terminal
        if project_name in self.terminals:
            raise ValueError(f"Scratchpad terminal already exists for project: {project_name}")

        # Validate working directory exists
        if not working_dir.exists() or not working_dir.is_dir():
            raise ValueError(f"Working directory does not exist: {working_dir}")

        # Generate mark and prepare environment
        mark = ScratchpadTerminal.create_mark(project_name)

        # Debug: Log Wayland environment
        wayland_display = os.environ.get("WAYLAND_DISPLAY", "NOT_SET")
        self.logger.info(f"Daemon WAYLAND_DISPLAY={wayland_display}")

        env = {
            **os.environ,  # Inherit user environment
            "I3PM_SCRATCHPAD": "true",
            "I3PM_PROJECT_NAME": project_name,
            "I3PM_WORKING_DIR": str(working_dir),
            "I3PM_APP_ID": f"scratchpad-{project_name}-{int(asyncio.get_event_loop().time())}",
            "I3PM_APP_NAME": "scratchpad-terminal",
            "I3PM_SCOPE": "scoped",
            "I3PM_NO_SESH": "1",  # Signal to skip sesh/tmux auto-start in bashrc
            # Force software rendering for headless/VNC environments
            "LIBGL_ALWAYS_SOFTWARE": "1",
        }

        self.logger.info(f"Launching scratchpad terminal for project '{project_name}' in {working_dir}")

        # Launch Alacritty terminal with explicit bash command (no sesh/tmux)
        # The I3PM_SCRATCHPAD env var signals this is a scratchpad terminal
        # and should prevent auto-session managers in bashrc
        # Use DEVNULL for stderr to prevent blocking the event loop (T073 fix)
        try:
            proc = await asyncio.create_subprocess_exec(
                "alacritty",
                env=env,
                cwd=str(working_dir),
                stdout=asyncio.subprocess.DEVNULL,
                stderr=asyncio.subprocess.DEVNULL,
            )
        except FileNotFoundError:
            raise RuntimeError("Alacritty not found - ensure it is installed")

        # Wait for window to appear (with timeout)
        window_id = await self._wait_for_terminal_window(proc.pid, mark, timeout=5.0)

        if window_id is None:
            raise RuntimeError(f"Terminal window did not appear within timeout for project: {project_name}")

        # Create terminal model
        terminal = ScratchpadTerminal(
            project_name=project_name,
            pid=proc.pid,
            window_id=window_id,
            mark=mark,
            working_dir=working_dir,
        )

        # Track in state
        self.terminals[project_name] = terminal

        self.logger.info(f"Scratchpad terminal launched: PID={proc.pid}, WindowID={window_id}, Project={project_name}")

        return terminal

    async def _wait_for_terminal_window(
        self,
        pid: int,
        mark: str,
        timeout: float = 5.0,
    ) -> Optional[int]:
        """
        Wait for terminal window to appear and mark it.

        Args:
            pid: Terminal process ID
            mark: Window mark to apply
            timeout: Maximum time to wait in seconds

        Returns:
            Window ID if found, None otherwise
        """
        start_time = asyncio.get_event_loop().time()

        while asyncio.get_event_loop().time() - start_time < timeout:
            await asyncio.sleep(0.1)  # Poll interval

            # Query Sway tree for windows with matching PID
            tree = await self.sway.get_tree()
            for window in tree.descendants():
                if window.pid == pid and window.app_id and "alacritty" in window.app_id.lower():
                    # Found the window - mark and configure it
                    await self.sway.command(f'[con_id={window.id}] mark {mark}')
                    await self.sway.command(
                        f'[con_id={window.id}] floating enable, '
                        f'resize set 1000 600, move position center'
                    )
                    self.logger.debug(f"Marked and configured terminal window: ID={window.id}, Mark={mark}")
                    return window.id

        self.logger.error(f"Terminal window not found within {timeout}s for PID={pid}")
        return None

    async def validate_terminal(self, project_name: str) -> bool:
        """
        Validate scratchpad terminal exists and is still running.

        Args:
            project_name: Project identifier

        Returns:
            True if terminal is valid, False otherwise

        Side Effects:
            Removes terminal from state if invalid (process dead or window missing)
        """
        terminal = self.terminals.get(project_name)
        if not terminal:
            return False

        # Check 1: Process still running
        if not terminal.is_process_running():
            self.logger.warning(f"Terminal process {terminal.pid} not running for project {project_name}")
            del self.terminals[project_name]
            return False

        # Check 2: Window exists in Sway tree
        tree = await self.sway.get_tree()
        window = tree.find_by_id(terminal.window_id)
        if not window:
            self.logger.warning(f"Terminal window {terminal.window_id} not found in Sway tree for project {project_name}")
            del self.terminals[project_name]
            return False

        # Check 3: Window has correct mark (repair if missing)
        if terminal.mark not in window.marks:
            self.logger.warning(f"Terminal window {terminal.window_id} missing mark {terminal.mark}, re-applying")
            await self.sway.command(f'[con_id={terminal.window_id}] mark {terminal.mark}')

        return True

    async def get_terminal_state(self, project_name: str) -> Optional[str]:
        """
        Get current visibility state of scratchpad terminal.

        Args:
            project_name: Project identifier

        Returns:
            "visible", "hidden", or None if terminal doesn't exist
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
        if window.parent and window.parent.name == "__i3_scratch":
            return "hidden"
        else:
            return "visible"

    async def toggle_terminal(self, project_name: str) -> str:
        """
        Toggle scratchpad terminal visibility (show if hidden, hide if visible).

        Args:
            project_name: Project identifier

        Returns:
            "shown" or "hidden" indicating resulting state

        Raises:
            ValueError: If terminal doesn't exist or is invalid
        """
        terminal = self.terminals.get(project_name)
        if not terminal:
            raise ValueError(f"No scratchpad terminal found for project: {project_name}")

        # Validate terminal
        if not await self.validate_terminal(project_name):
            raise ValueError(f"Scratchpad terminal invalid for project: {project_name}")

        # Get current state
        state = await self.get_terminal_state(project_name)

        if state == "visible":
            # Hide to scratchpad
            await self.sway.command(f'[con_mark="{terminal.mark}"] move scratchpad')
            self.logger.debug(f"Hid terminal for project '{project_name}'")
            return "hidden"
        else:
            # Show from scratchpad
            await self.sway.command(f'[con_mark="{terminal.mark}"] scratchpad show')
            terminal.mark_shown()
            self.logger.debug(f"Showed terminal for project '{project_name}'")
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

    async def cleanup_invalid_terminals(self) -> int:
        """
        Remove invalid terminals from state (dead processes, missing windows).

        Returns:
            Count of terminals cleaned up
        """
        projects_to_remove = []

        for project_name in list(self.terminals.keys()):
            if not await self.validate_terminal(project_name):
                projects_to_remove.append(project_name)

        self.logger.info(f"Cleaned up {len(projects_to_remove)} invalid terminal(s): {projects_to_remove}")

        return len(projects_to_remove)

    async def list_terminals(self) -> List[ScratchpadTerminal]:
        """
        List all tracked scratchpad terminals.

        Returns:
            List of ScratchpadTerminal instances
        """
        return list(self.terminals.values())
