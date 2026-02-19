"""
Scratchpad Terminal Manager

Manages lifecycle and state of project-scoped scratchpad terminals.
"""

import asyncio
import logging
import os
import shlex
from pathlib import Path
from typing import Any, Dict, List, Optional
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
        self._toggle_lock = asyncio.Lock()  # Prevents race conditions on rapid toggles

    async def launch_terminal(
        self,
        project_name: str,
        working_dir: Path,
        remote_profile: Optional[Dict[str, Any]] = None,
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
        async with self._toggle_lock:
            # First, check for orphaned windows (from daemon restart)
            orphan = await self._find_orphaned_terminal(project_name)
            if orphan:
                self.logger.info(f"Reclaiming orphaned scratchpad for {project_name}")
                self.terminals[project_name] = orphan
                return orphan

            # Validate project doesn't already have a terminal
            if project_name in self.terminals:
                raise ValueError(f"Scratchpad terminal already exists for project: {project_name}")

            remote_enabled = bool(remote_profile and remote_profile.get("enabled"))

            # Validate working directory exists for local mode only.
            if not remote_enabled and (not working_dir.exists() or not working_dir.is_dir()):
                raise ValueError(f"Working directory does not exist: {working_dir}")

            # Feature 101: Mark is created AFTER window appears (needs window_id)
            # We identify the window by I3PM_APP_NAME and I3PM_PROJECT_NAME in environment

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

            if remote_enabled and remote_profile:
                env.update({
                    "I3PM_REMOTE_ENABLED": "true",
                    "I3PM_REMOTE_HOST": str(remote_profile.get("host", "")),
                    "I3PM_REMOTE_USER": str(remote_profile.get("user", "")),
                    "I3PM_REMOTE_PORT": str(remote_profile.get("port", 22)),
                    "I3PM_REMOTE_DIR": str(remote_profile.get("remote_dir", "")),
                })

            self.logger.info(f"Launching scratchpad terminal for project '{project_name}' in {working_dir}")

            # Use Sway exec to launch Ghostty - this ensures proper display server context
            # Sway runs the command in the compositor's environment with correct WAYLAND_DISPLAY etc.
            # This is more reliable than subprocess which requires manual environment setup

            # Build shell command with environment variables and Ghostty launch
            # Export I3PM_* variables so daemon can identify the window
            env_exports = []
            for key, value in env.items():
                if key.startswith('I3PM_'):
                    # Escape single quotes in values
                    safe_value = value.replace("'", "'\\''")
                    env_exports.append(f"export {key}='{safe_value}'")

            env_string = '; '.join(env_exports)

            # Build Ghostty command with tmux session
            # Session name format: scratchpad-{project_name}
            tmux_session_name = f"scratchpad-{project_name}"

            # Scratchpad uses simple tmux session (not devenv)
            # Devenv integration is handled by regular terminal via app-launcher-wrapper.sh
            # -A: attach if exists, create if not
            if remote_enabled and remote_profile:
                remote_host = str(remote_profile.get("host", ""))
                remote_user = str(remote_profile.get("user", ""))
                remote_port = int(remote_profile.get("port", 22))
                remote_dir = str(remote_profile.get("remote_dir", ""))

                if not remote_host or not remote_user or not remote_dir:
                    raise ValueError("Remote scratchpad launch requires host, user, and remote_dir")

                remote_cmd = f"cd {shlex.quote(remote_dir)} && tmux new-session -A -s {shlex.quote(tmux_session_name)}"
                ssh_parts = ["ssh", "-t"]
                if remote_port != 22:
                    ssh_parts.extend(["-p", str(remote_port)])
                ssh_parts.append(f"{remote_user}@{remote_host}")
                ssh_parts.append(remote_cmd)

                ssh_cmd = " ".join(shlex.quote(part) for part in ssh_parts)
                ghostty_cmd = f"ghostty --title='Scratchpad Terminal' -e bash -lc {shlex.quote(ssh_cmd)}"
            else:
                tmux_cmd = f'tmux new-session -A -s {tmux_session_name} -c "{working_dir}"'
                # Wrap tmux in bash to ensure proper execution and environment.
                ghostty_cmd = f"ghostty --title='Scratchpad Terminal' -e bash -c '{tmux_cmd}'"

            # Complete shell command with environment setup
            full_cmd = f"{env_string}; {ghostty_cmd}"

            self.logger.info(f"Launching via Sway exec: {full_cmd[:200]}...")  # Log first 200 chars

            # Execute via Sway IPC - this runs in the compositor's context
            try:
                result = await self.sway.command(f'exec bash -c "{full_cmd}"')
                self.logger.info(f"Sway exec result: {result}")
            except Exception as e:
                raise RuntimeError(f"Failed to execute Sway command: {e}")

            # Wait for window to appear (we don't have a PID anymore, so we search by app_id)
            # Feature 101: Pass project_name to identify the correct window via environment
            window_id = await self._wait_for_terminal_window_by_appid(
                app_id="com.mitchellh.ghostty",
                project_name=project_name,
                timeout=5.0
            )

            if window_id is None:
                raise RuntimeError(f"Terminal window did not appear within timeout for project: {project_name}")

            # Get PID from the window that appeared
            tree = await self.sway.get_tree()
            window = tree.find_by_id(window_id)
            if not window or not window.pid:
                raise RuntimeError(f"Could not get PID for window {window_id}")

            terminal_pid = window.pid

            # Feature 101: Create mark AFTER window appears (unified scoped: format)
            mark = ScratchpadTerminal.create_mark(project_name, window_id)

            # Create terminal model
            terminal = ScratchpadTerminal(
                project_name=project_name,
                pid=terminal_pid,
                window_id=window_id,
                mark=mark,
                working_dir=working_dir,
            )

            # Track in state
            self.terminals[project_name] = terminal

            self.logger.info(f"Scratchpad terminal launched: PID={terminal_pid}, WindowID={window_id}, Project={project_name}")

            return terminal

    async def _wait_for_terminal_window_by_appid(
        self,
        app_id: str,
        project_name: str,
        timeout: float = 5.0,
    ) -> Optional[int]:
        """
        Wait for terminal window to appear by app_id, verify it's the right project, and mark it.

        Used when launching via Sway exec (no PID available).

        Feature 101: Uses I3PM_PROJECT_NAME environment variable to match the specific project.
        Creates mark with unified scoped: format after window is found.

        Args:
            app_id: Application ID to search for (e.g., "com.mitchellh.ghostty")
            project_name: Project name to match against I3PM_PROJECT_NAME
            timeout: Maximum time to wait in seconds

        Returns:
            Window ID if found, None otherwise
        """
        start_time = asyncio.get_event_loop().time()
        seen_windows = set()  # Track windows we've seen

        while asyncio.get_event_loop().time() - start_time < timeout:
            await asyncio.sleep(0.1)  # Poll interval

            # Query Sway tree for windows with matching app_id
            tree = await self.sway.get_tree()
            for window in tree.descendants():
                if window.app_id != app_id:
                    continue

                # Skip if we've already processed this window
                if window.id in seen_windows:
                    continue

                # Feature 101: Check if window already has a scoped mark (our new unified format)
                # Skip windows already marked for any project
                if any(m.startswith("scoped:") for m in window.marks):
                    seen_windows.add(window.id)
                    continue

                # CRITICAL: Check process environment to distinguish scratchpad from regular Ghostty
                # Scratchpad terminals have I3PM_SCRATCHPAD=true and I3PM_APP_NAME=scratchpad-terminal
                # Regular Ghostty terminals have I3PM_APP_NAME=terminal (or no I3PM vars)
                if not window.pid:
                    self.logger.debug(f"Skipping window without PID: ID={window.id}")
                    seen_windows.add(window.id)
                    continue

                try:
                    env = read_process_environ(window.pid)
                    is_scratchpad = env.get("I3PM_SCRATCHPAD") == "true"
                    app_name = env.get("I3PM_APP_NAME", "")
                    env_project = env.get("I3PM_PROJECT_NAME", "")

                    if not is_scratchpad or app_name != "scratchpad-terminal":
                        self.logger.debug(
                            f"Skipping window with wrong env: ID={window.id}, PID={window.pid}, "
                            f"I3PM_SCRATCHPAD={env.get('I3PM_SCRATCHPAD')}, "
                            f"I3PM_APP_NAME={app_name} (expected scratchpad-terminal)"
                        )
                        seen_windows.add(window.id)
                        continue

                    # Feature 101: Match project name from environment
                    if env_project != project_name:
                        self.logger.debug(
                            f"Skipping window with different project: ID={window.id}, "
                            f"I3PM_PROJECT_NAME={env_project} (expected {project_name})"
                        )
                        seen_windows.add(window.id)
                        continue

                except (ProcessLookupError, PermissionError) as e:
                    self.logger.debug(f"Could not read env for PID {window.pid}: {e}")
                    seen_windows.add(window.id)
                    continue

                # Found an unmarked window with matching app_id, correct environment, and project
                self.logger.info(
                    f"Found new scratchpad terminal window: ID={window.id}, PID={window.pid}, "
                    f"name={window.name}, project={project_name}, marks={window.marks}"
                )

                # Feature 101: Create unified scoped: mark with window_id
                mark = ScratchpadTerminal.create_mark(project_name, window.id)

                # Mark the window (floating, size, and centering handled by window rule)
                await self.sway.command(f'[con_id={window.id}] mark {mark}')
                # Move to scratchpad immediately (window rule already made it floating + centered)
                await self.sway.command(f'[con_id={window.id}] move scratchpad')
                # Note: Do NOT show from scratchpad immediately after launch
                # Showing would place the window on the current workspace
                # User should explicitly toggle with i3pm scratchpad toggle to show when ready
                self.logger.info(f"Marked and moved to scratchpad: ID={window.id}, Mark={mark}")
                return window.id

        self.logger.error(
            f"Terminal window with app_id={app_id} not found within {timeout}s. "
            f"Seen {len(seen_windows)} existing {app_id} windows."
        )
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

        # Feature 102 Fix: Record scratchpad toggle trace events
        await self._record_scratchpad_trace_event(
            terminal.window_id,
            f"scratchpad::{'hide' if state == 'visible' else 'show'}",
            f"Scratchpad toggle: {'hiding' if state == 'visible' else 'showing'} for project {project_name}",
            {"project_name": project_name, "prev_state": state}
        )

        if state == "visible":
            # Hide to scratchpad
            await self.sway.command(f'[con_mark="{terminal.mark}"] move scratchpad')
            self.logger.debug(f"Hid terminal for project '{project_name}'")
            return "hidden"
        else:
            # Show from scratchpad
            await self.sway.command(f'[con_mark="{terminal.mark}"] scratchpad show')
            terminal.mark_shown()

            # Feature 125: Resize and position based on dock mode
            await self._position_scratchpad_for_dock_mode(terminal.mark)

            self.logger.debug(f"Showed terminal for project '{project_name}'")
            return "shown"

    async def _record_scratchpad_trace_event(
        self,
        window_id: int,
        event_type: str,
        description: str,
        context: dict
    ) -> None:
        """Record trace event for scratchpad operations.

        Feature 102 Fix: Enables tracing of scratchpad toggle operations.

        Args:
            window_id: Scratchpad window ID
            event_type: Event type string
            description: Human-readable description
            context: Additional context data
        """
        try:
            from .window_tracer import get_tracer, TraceEventType
            tracer = get_tracer()
            if tracer:
                # Map to appropriate trace event type
                trace_type = TraceEventType.SCRATCHPAD_SHOW if "show" in event_type else TraceEventType.SCRATCHPAD_MOVE
                affected = await tracer.record_window_event(window_id, trace_type, description, context)
                if affected:
                    self.logger.debug(f"[Trace] Recorded {event_type} for scratchpad in {len(affected)} trace(s)")
        except Exception as e:
            self.logger.debug(f"[Trace] Error recording scratchpad event: {e}")

    async def _position_scratchpad_for_dock_mode(self, mark: str) -> None:
        """
        Position and resize scratchpad terminal based on monitoring panel dock mode.

        Feature 125: When panel is docked, scratchpad terminal should be centered
        in the remaining available space (excluding the panel width).
        When panel is in overlay mode, use default sizing (1100x550 centered).

        Args:
            mark: Window mark to identify the scratchpad terminal
        """
        try:
            # Read dock mode state file
            state_file = Path.home() / ".local/state/eww-monitoring-panel/dock-mode"
            is_docked = False

            if state_file.exists():
                mode = state_file.read_text().strip()
                is_docked = (mode == "docked")

            # Get workspace rect (accounts for all reserved space: top bar, docked panels, etc.)
            workspaces = await self.sway.get_workspaces()
            focused_ws = None
            for ws in workspaces:
                if ws.focused:
                    focused_ws = ws
                    break

            if not focused_ws:
                self.logger.warning("No focused workspace found for scratchpad positioning")
                return

            # Workspace rect gives us the actual usable area
            ws_x = focused_ws.rect.x
            ws_y = focused_ws.rect.y
            ws_width = focused_ws.rect.width
            ws_height = focused_ws.rect.height

            if is_docked:
                # Docked mode: use workspace rect (already accounts for docked panel)
                # Terminal takes 80% of workspace width, max 1000px
                term_width = min(int(ws_width * 0.8), 1000)
                # Height is 70% of workspace height, max 700px
                term_height = min(int(ws_height * 0.7), 700)
                # Center in workspace area
                center_x = ws_x + (ws_width - term_width) // 2
                center_y = ws_y + (ws_height - term_height) // 2

                self.logger.debug(
                    f"[Feature 125] Docked mode: sizing scratchpad to {term_width}x{term_height} "
                    f"at ({center_x}, {center_y}), workspace={ws_width}x{ws_height}"
                )

                await self.sway.command(
                    f'[con_mark="{mark}"] resize set width {term_width} px height {term_height} px, '
                    f'move position {center_x} px {center_y} px'
                )
            else:
                # Overlay mode: use workspace rect for centering (still accounts for top bar)
                term_width = 1100
                term_height = 550
                # Center in workspace area
                center_x = ws_x + (ws_width - term_width) // 2
                center_y = ws_y + (ws_height - term_height) // 2

                self.logger.debug(
                    f"[Feature 125] Overlay mode: sizing scratchpad to {term_width}x{term_height} "
                    f"at ({center_x}, {center_y}), workspace={ws_width}x{ws_height}"
                )

                await self.sway.command(
                    f'[con_mark="{mark}"] resize set width {term_width} px height {term_height} px, '
                    f'move position {center_x} px {center_y} px'
                )

        except Exception as e:
            self.logger.warning(f"[Feature 125] Error positioning scratchpad: {e}")

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

    async def rediscover_terminals(self) -> int:
        """
        Scan Sway tree for existing scratchpad terminals and rebuild state.

        Called on daemon startup to recover from restarts. This allows the daemon
        to reclaim existing scratchpad terminal windows that were created in a
        previous session but are still running.

        Returns:
            Count of terminals rediscovered
        """
        tree = await self.sway.get_tree()
        rediscovered = 0

        for window in tree.descendants():
            # Find windows with scratchpad terminal marks
            for mark in window.marks:
                if mark.startswith("scoped:scratchpad-terminal:"):
                    # Parse mark: scoped:scratchpad-terminal:{project_name}:{window_id}
                    # Note: project_name may contain colons (e.g., "vpittamp/nixos-config:main")
                    # so we extract window_id from the end and project_name is everything in between
                    suffix = mark[len("scoped:scratchpad-terminal:"):]
                    last_colon = suffix.rfind(":")
                    if last_colon > 0:
                        project_name = suffix[:last_colon]
                        # Skip if already tracked
                        if project_name in self.terminals:
                            continue

                        # Verify process environment
                        if window.pid:
                            try:
                                env = read_process_environ(window.pid)
                                if env.get("I3PM_SCRATCHPAD") == "true":
                                    # Rebuild terminal state
                                    working_dir = Path(env.get("I3PM_WORKING_DIR", str(Path.home())))
                                    terminal = ScratchpadTerminal(
                                        project_name=project_name,
                                        pid=window.pid,
                                        window_id=window.id,
                                        mark=mark,
                                        working_dir=working_dir,
                                    )
                                    self.terminals[project_name] = terminal
                                    rediscovered += 1
                                    self.logger.info(f"Rediscovered scratchpad terminal: {project_name}")
                            except (ProcessLookupError, PermissionError) as e:
                                self.logger.debug(f"Could not verify terminal for rediscovery: {e}")

        if rediscovered > 0:
            self.logger.info(f"Rediscovered {rediscovered} scratchpad terminal(s) on startup")

        return rediscovered

    async def _find_orphaned_terminal(self, project_name: str) -> Optional[ScratchpadTerminal]:
        """
        Find an orphaned scratchpad terminal window for a project.

        An orphan is a window with the correct mark but not tracked in self.terminals.
        This can happen after daemon restart or if tracking state was lost.

        Args:
            project_name: Project identifier to search for

        Returns:
            ScratchpadTerminal if orphan found, None otherwise
        """
        tree = await self.sway.get_tree()

        for window in tree.descendants():
            for mark in window.marks:
                if mark.startswith(f"scoped:scratchpad-terminal:{project_name}:"):
                    # Found orphaned window with matching project
                    if window.pid:
                        try:
                            env = read_process_environ(window.pid)
                            if env.get("I3PM_SCRATCHPAD") == "true":
                                working_dir = Path(env.get("I3PM_WORKING_DIR", str(Path.home())))
                                terminal = ScratchpadTerminal(
                                    project_name=project_name,
                                    pid=window.pid,
                                    window_id=window.id,
                                    mark=mark,
                                    working_dir=working_dir,
                                )
                                self.logger.info(f"Found orphaned scratchpad terminal for {project_name}")
                                return terminal
                        except (ProcessLookupError, PermissionError):
                            pass
        return None
