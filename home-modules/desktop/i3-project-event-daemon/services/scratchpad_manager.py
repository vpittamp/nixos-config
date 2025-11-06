"""
Scratchpad Terminal Manager

Manages lifecycle and state of project-scoped scratchpad terminals.
Enhanced with Feature 051: Mouse-aware positioning with boundary detection.
"""

import asyncio
import logging
import os
from pathlib import Path
from typing import Dict, List, Optional
import psutil

from i3ipc.aio import Connection

from ..models.scratchpad import ScratchpadTerminal
from ..models.scratchpad_enhancement import (
    GapConfig,
    WorkspaceGeometry,
    WindowDimensions,
    CursorPosition,
    TerminalPosition,
    SummonMode,
    ScratchpadState,
)
from .cursor_positioner import CursorPositioner
from .positioning import BoundaryDetectionAlgorithm, MultiMonitorPositioner


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

        # Feature 051: Mouse-aware positioning components
        self.gap_config = GapConfig.from_environment()
        self.summon_mode = SummonMode.from_environment()
        self.cursor_positioner = CursorPositioner()
        self.boundary_algo = BoundaryDetectionAlgorithm(self.gap_config)
        self.multi_monitor = MultiMonitorPositioner()

        self.logger.info(
            f"Initialized scratchpad manager with Feature 051 enhancements: "
            f"gaps={self.gap_config.top}/{self.gap_config.bottom}/{self.gap_config.left}/{self.gap_config.right}, "
            f"summon_mode={self.summon_mode.behavior.value}, "
            f"mouse_positioning={'enabled' if self.summon_mode.mouse_positioning_enabled else 'disabled'}"
        )

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
                    # Move to scratchpad immediately and then show it
                    await self.sway.command(f'[con_id={window.id}] move scratchpad')
                    await self.sway.command(f'[con_mark="{mark}"] scratchpad show')
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

        Enhanced with Feature 051: Mouse-aware positioning with boundary detection
        and workspace summoning (US3).

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
            # T036: Capture state before hiding
            await self.save_state_to_marks(project_name, terminal)

            # Hide to scratchpad
            await self.sway.command(f'[con_mark="{terminal.mark}"] move scratchpad')
            self.logger.debug(f"Hid terminal for project '{project_name}'")
            return "hidden"
        else:
            # FEATURE 051: Hide any visible scratchpad terminals from other projects first
            await self._hide_other_project_terminals(project_name)

            # T037: Attempt to restore state from marks
            saved_state = await self.restore_state_from_marks(project_name, terminal)

            # T030: Conditional summoning logic based on workspace mode
            terminal_workspace = await self.get_terminal_workspace(project_name)
            current_workspace = await self.get_current_workspace_geometry()

            if terminal_workspace and terminal_workspace != current_workspace.workspace_num:
                # Terminal is on different workspace
                if self.summon_mode.behavior.value == "summon":
                    # Summon mode: Move terminal to current workspace (T028, T031, T033)
                    await self._summon_to_current_workspace(project_name, terminal)
                else:
                    # Goto mode: Switch to terminal's workspace (T032)
                    await self._goto_terminal_workspace(project_name, terminal, terminal_workspace)
            else:
                # Terminal is on current workspace or hidden, just show with positioning
                await self._show_terminal_with_positioning(project_name, terminal)

            # T037: Apply saved state if available (after showing)
            # Only restore floating/tiling state, NOT position when mouse positioning is active
            if saved_state:
                # Don't restore position if mouse positioning is enabled
                # (we just calculated a new position based on cursor)
                restore_position = not self.summon_mode.mouse_positioning_enabled
                await self.apply_state_to_window(terminal, saved_state, restore_position=restore_position)

                if restore_position:
                    self.logger.info(
                        f"Restored saved state for project '{project_name}': "
                        f"floating={saved_state.floating}, pos=({saved_state.x},{saved_state.y})"
                    )
                else:
                    self.logger.info(
                        f"Restored floating state for project '{project_name}': "
                        f"floating={saved_state.floating} (position from mouse cursor)"
                    )

            terminal.mark_shown()
            return "shown"

    async def _show_terminal_with_positioning(
        self,
        project_name: str,
        terminal: ScratchpadTerminal
    ) -> None:
        """
        Show terminal with mouse-aware positioning.

        T018: Integrate positioning calculation into show workflow.

        Args:
            project_name: Project identifier
            terminal: Terminal to show
        """
        # Show from scratchpad first (brings to current workspace)
        await self.sway.command(f'[con_mark="{terminal.mark}"] scratchpad show')

        # If mouse positioning is disabled, use center positioning (legacy behavior)
        if not self.summon_mode.mouse_positioning_enabled:
            await self.sway.command(f'[con_mark="{terminal.mark}"] move position center')
            self.logger.debug(f"Showed terminal for project '{project_name}' at center (mouse positioning disabled)")
            return

        try:
            # Query current workspace geometry
            workspace = await self.get_current_workspace_geometry()

            # Calculate mouse cursor position
            cursor = await self.calculate_mouse_position(workspace)

            # Validate cursor is on active workspace
            if not await self.validate_cursor_on_active_workspace(cursor, workspace):
                self.logger.warning(f"Cursor outside workspace, using center fallback")
                await self.sway.command(f'[con_mark="{terminal.mark}"] move position center')
                return

            # Get current window dimensions from Sway (or use defaults)
            tree = await self.sway.get_tree()
            window = tree.find_by_id(terminal.window_id)
            if window and window.rect:
                window_dims = WindowDimensions(
                    width=window.rect.width,
                    height=window.rect.height
                )
            else:
                window_dims = WindowDimensions()  # Default 1000x600

            # Apply boundary constraints
            position = await self.apply_boundary_constraints(cursor, window_dims, workspace)

            # Apply calculated position to window
            await self.sway.command(position.to_sway_command(terminal.window_id))

            # Ensure floating mode (mouse positioning requires floating)
            await self.sway.command(f'[con_id={terminal.window_id}] floating enable')

            self.logger.info(
                f"Showed terminal for project '{project_name}' at ({position.x}, {position.y}) "
                f"[{position.width}x{position.height}] on {position.monitor_name} "
                f"(cursor_source={cursor.source}, constrained={position.constrained_by_gaps})"
            )

        except Exception as e:
            self.logger.error(f"Failed to apply mouse positioning for {project_name}: {e}", exc_info=True)
            # Fallback to center positioning
            await self.sway.command(f'[con_mark="{terminal.mark}"] move position center')
            self.logger.warning(f"Fell back to center positioning for project '{project_name}'")

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

    async def _hide_other_project_terminals(self, current_project: str) -> int:
        """
        Hide visible scratchpad terminals from other projects.

        Ensures only one project's scratchpad terminal is visible at a time.

        Args:
            current_project: The project that will be shown (don't hide this one)

        Returns:
            Number of terminals hidden
        """
        hidden_count = 0

        for project_name, terminal in list(self.terminals.items()):
            # Skip the project we're about to show
            if project_name == current_project:
                continue

            # Check if this terminal is currently visible
            state = await self.get_terminal_state(project_name)
            if state == "visible":
                # Save state before hiding
                await self.save_state_to_marks(project_name, terminal)

                # Hide to scratchpad
                await self.sway.command(f'[con_mark="{terminal.mark}"] move scratchpad')
                self.logger.info(
                    f"Auto-hid scratchpad terminal for project '{project_name}' "
                    f"(switching to '{current_project}')"
                )
                hidden_count += 1

        return hidden_count

    # ========================================================================
    # Feature 051: Mouse-Aware Positioning Methods
    # ========================================================================

    async def get_current_workspace_geometry(self) -> WorkspaceGeometry:
        """
        Query current workspace geometry from Sway IPC.

        Returns:
            WorkspaceGeometry for the currently focused workspace

        Raises:
            RuntimeError: If unable to determine current workspace
        """
        # Get focused workspace
        tree = await self.sway.get_tree()
        focused_workspace = tree.find_focused().workspace()

        if not focused_workspace:
            raise RuntimeError("Unable to determine focused workspace")

        # Get output (monitor) containing this workspace
        outputs = await self.sway.get_outputs()
        output = None
        for o in outputs:
            if o.current_workspace == focused_workspace.name:
                output = o
                break

        if not output:
            raise RuntimeError(f"Unable to find output for workspace {focused_workspace.name}")

        # Extract workspace number from name (e.g., "1" from "1" or "1:term")
        try:
            workspace_num = int(focused_workspace.name.split(":")[0])
        except (ValueError, AttributeError):
            workspace_num = 1

        return WorkspaceGeometry(
            width=output.rect.width,
            height=output.rect.height,
            x_offset=output.rect.x,
            y_offset=output.rect.y,
            workspace_num=workspace_num,
            monitor_name=output.name,
            gaps=self.gap_config,
        )

    async def get_all_workspace_geometries(self) -> List[WorkspaceGeometry]:
        """
        Query all workspace geometries for multi-monitor positioning.

        Returns:
            List of WorkspaceGeometry for all active outputs
        """
        outputs = await self.sway.get_outputs()
        geometries = []

        for output in outputs:
            if not output.active:
                continue

            # Get current workspace on this output
            workspaces = await self.sway.get_workspaces()
            workspace = None
            for ws in workspaces:
                if ws.output == output.name and ws.visible:
                    workspace = ws
                    break

            if not workspace:
                continue

            # Extract workspace number
            try:
                workspace_num = int(workspace.name.split(":")[0])
            except (ValueError, AttributeError):
                workspace_num = 1

            geometries.append(
                WorkspaceGeometry(
                    width=output.rect.width,
                    height=output.rect.height,
                    x_offset=output.rect.x,
                    y_offset=output.rect.y,
                    workspace_num=workspace_num,
                    monitor_name=output.name,
                    gaps=self.gap_config,
                )
            )

        return geometries

    async def calculate_mouse_position(self, workspace: WorkspaceGeometry) -> CursorPosition:
        """
        Calculate current mouse cursor position with fallback.

        T014: Implement async calculate_mouse_position method.

        Args:
            workspace: Current workspace geometry for fallback

        Returns:
            CursorPosition with x, y coordinates and metadata
        """
        return await self.cursor_positioner.get_cursor_position(workspace)

    async def apply_boundary_constraints(
        self,
        cursor: CursorPosition,
        window: WindowDimensions,
        workspace: WorkspaceGeometry,
    ) -> TerminalPosition:
        """
        Apply boundary constraints to calculate final position.

        T015: Implement async apply_boundary_constraints method.

        Args:
            cursor: Current cursor position
            window: Terminal window dimensions
            workspace: Workspace geometry

        Returns:
            TerminalPosition with constrained x, y coordinates
        """
        # Validate workspace has sufficient space
        if not self.boundary_algo.validate_workspace_geometry(workspace):
            self.logger.warning(
                f"Workspace {workspace.monitor_name} has insufficient space after gaps, "
                f"using defaults"
            )

        # Handle oversized windows
        window = self.boundary_algo.handle_oversized_window(window, workspace)

        # Calculate position with boundary constraints
        position = self.boundary_algo.calculate_position(cursor, window, workspace)

        self.logger.debug(
            f"Calculated terminal position: ({position.x}, {position.y}) "
            f"[{position.width}x{position.height}] on {position.monitor_name} "
            f"(constrained={position.constrained_by_gaps})"
        )

        return position

    async def validate_cursor_on_active_workspace(
        self,
        cursor: CursorPosition,
        workspace: WorkspaceGeometry,
    ) -> bool:
        """
        Validate cursor is within active workspace bounds.

        T019: Add position validation for cursor on active workspace.

        Args:
            cursor: Cursor position to validate
            workspace: Current workspace geometry

        Returns:
            True if cursor is within workspace bounds, False otherwise
        """
        is_valid = cursor.is_in_workspace(workspace)

        if not is_valid:
            self.logger.warning(
                f"Cursor at ({cursor.x}, {cursor.y}) is outside workspace "
                f"{workspace.monitor_name} bounds "
                f"[{workspace.x_offset},{workspace.y_offset}] "
                f"[{workspace.width}x{workspace.height}]"
            )

        return is_valid

    # ========================================================================
    # Feature 051 User Story 4: State Persistence
    # ========================================================================

    async def save_state_to_marks(
        self,
        project_name: str,
        terminal: ScratchpadTerminal
    ) -> bool:
        """
        Save terminal state to Sway marks for persistence.

        T034: Implement save_state_to_marks method.
        T038: Implement Sway IPC mark commands.
        T040: Add timestamp and staleness tracking.

        Args:
            project_name: Project identifier
            terminal: Terminal to save state for

        Returns:
            True if state saved successfully, False otherwise
        """
        try:
            # Query current window state from Sway
            tree = await self.sway.get_tree()
            window = tree.find_by_id(terminal.window_id)

            if not window:
                self.logger.warning(f"Cannot save state: Window {terminal.window_id} not found")
                return False

            # Extract current state
            is_floating = window.type == "floating_con" or (window.parent and window.parent.type == "floating_con")
            workspace = window.workspace()
            workspace_num = 1
            monitor_name = "unknown"

            if workspace:
                try:
                    workspace_num = int(workspace.name.split(":")[0])
                except (ValueError, AttributeError):
                    workspace_num = 1

                # Find monitor name
                outputs = await self.sway.get_outputs()
                for output in outputs:
                    if output.current_workspace == workspace.name:
                        monitor_name = output.name
                        break

            # Create state model
            state = ScratchpadState(
                project_name=project_name,
                floating=is_floating,
                x=window.rect.x,
                y=window.rect.y,
                width=window.rect.width,
                height=window.rect.height,
                workspace_num=workspace_num,
                monitor_name=monitor_name,
            )

            # Serialize to mark string
            state_mark = state.to_mark_string()

            # Remove old state mark if exists (T041: handle legacy marks)
            old_marks = [m for m in window.marks if m.startswith("scratchpad_state:")]
            for old_mark in old_marks:
                await self.sway.command(f'[con_id={window.id}] unmark "{old_mark}"')

            # Apply new state mark
            await self.sway.command(f'[con_id={window.id}] mark "{state_mark}"')

            self.logger.debug(
                f"Saved state for project '{project_name}': "
                f"floating={is_floating}, pos=({state.x},{state.y}), "
                f"size=({state.width}x{state.height}), ws={workspace_num}"
            )

            return True

        except Exception as e:
            self.logger.error(f"Failed to save state for project '{project_name}': {e}", exc_info=True)
            return False

    async def restore_state_from_marks(
        self,
        project_name: str,
        terminal: ScratchpadTerminal
    ) -> Optional[ScratchpadState]:
        """
        Restore terminal state from Sway marks.

        T035: Implement restore_state_from_marks method.
        T038: Implement Sway IPC mark commands.
        T040: Add timestamp and staleness tracking.
        T041: Handle legacy marks from Feature 062.

        Args:
            project_name: Project identifier
            terminal: Terminal to restore state for

        Returns:
            ScratchpadState if found and valid, None otherwise
        """
        try:
            # Query window marks from Sway
            tree = await self.sway.get_tree()
            window = tree.find_by_id(terminal.window_id)

            if not window:
                self.logger.warning(f"Cannot restore state: Window {terminal.window_id} not found")
                return None

            # Find state mark
            state_marks = [m for m in window.marks if m.startswith("scratchpad_state:")]

            if not state_marks:
                # T041: Legacy mark (Feature 062) - no state mark exists
                self.logger.debug(f"No state mark found for project '{project_name}' (legacy terminal)")
                return None

            # Parse most recent state mark (should only be one)
            state_mark = state_marks[0]
            state = ScratchpadState.from_mark_string(state_mark)

            if not state:
                self.logger.warning(f"Failed to parse state mark for project '{project_name}': {state_mark}")
                return None

            # Check if state is stale (T040)
            if state.is_stale(max_age_hours=24):
                self.logger.info(
                    f"State for project '{project_name}' is stale (age > 24h), ignoring"
                )
                return None

            self.logger.debug(
                f"Restored state for project '{project_name}': "
                f"floating={state.floating}, pos=({state.x},{state.y}), "
                f"size=({state.width}x{state.height}), ws={state.workspace_num}"
            )

            return state

        except Exception as e:
            self.logger.error(f"Failed to restore state for project '{project_name}': {e}", exc_info=True)
            return None

    async def apply_state_to_window(
        self,
        terminal: ScratchpadTerminal,
        state: ScratchpadState,
        restore_position: bool = True
    ) -> bool:
        """
        Apply saved state to terminal window.

        T037: Add state restoration on show operation.
        T039: Implement Sway IPC floating state commands.

        Args:
            terminal: Terminal to apply state to
            state: State to apply
            restore_position: Whether to restore position (False when using mouse positioning)

        Returns:
            True if state applied successfully, False otherwise
        """
        try:
            window_id = terminal.window_id

            # T039: Set floating state (always restore this)
            if state.floating:
                await self.sway.command(f'[con_id={window_id}] floating enable')
            else:
                await self.sway.command(f'[con_id={window_id}] floating disable')

            # Apply position and size only if requested (only for floating windows)
            if restore_position and state.floating:
                await self.sway.command(
                    f'[con_id={window_id}] resize set {state.width} {state.height}'
                )
                await self.sway.command(
                    f'[con_id={window_id}] move absolute position {state.x} {state.y}'
                )
                self.logger.debug(
                    f"Applied state to window {window_id}: "
                    f"floating={state.floating}, pos=({state.x},{state.y}), size=({state.width}x{state.height})"
                )
            else:
                self.logger.debug(
                    f"Applied floating state to window {window_id}: floating={state.floating} "
                    f"(position not restored due to mouse positioning)"
                )

            return True

        except Exception as e:
            self.logger.error(f"Failed to apply state to window {terminal.window_id}: {e}", exc_info=True)
            return False

    # ========================================================================
    # Feature 051 User Story 3: Workspace Summoning
    # ========================================================================

    async def get_terminal_workspace(self, project_name: str) -> Optional[int]:
        """
        Get the workspace number where the terminal is currently located.

        T029: Implement workspace detection logic.

        Args:
            project_name: Project identifier

        Returns:
            Workspace number (1-70) or None if terminal is hidden/not found
        """
        terminal = self.terminals.get(project_name)
        if not terminal:
            return None

        # Query Sway tree for window
        tree = await self.sway.get_tree()
        window = tree.find_by_id(terminal.window_id)

        if not window:
            return None

        # Check if in scratchpad
        if window.parent and window.parent.name == "__i3_scratch":
            return None  # Hidden in scratchpad, not on any workspace

        # Find workspace containing this window
        workspace = window.workspace()
        if not workspace:
            return None

        # Extract workspace number from name (e.g., "1" from "1" or "1:term")
        try:
            workspace_num = int(workspace.name.split(":")[0])
            return workspace_num
        except (ValueError, AttributeError):
            return None

    async def _summon_to_current_workspace(
        self,
        project_name: str,
        terminal: ScratchpadTerminal
    ) -> None:
        """
        Summon terminal to current workspace with mouse positioning.

        T028: Create summon_to_workspace method.
        T031: Implement Sway IPC move-to-workspace command.
        T033: Add mouse positioning to summon mode workflow.

        Args:
            project_name: Project identifier
            terminal: Terminal to summon
        """
        # Show from scratchpad first
        await self.sway.command(f'[con_mark="{terminal.mark}"] scratchpad show')

        # Terminal is now visible, apply mouse positioning
        if self.summon_mode.mouse_positioning_enabled:
            try:
                # Query current workspace geometry
                workspace = await self.get_current_workspace_geometry()

                # Calculate mouse cursor position
                cursor = await self.calculate_mouse_position(workspace)

                # Validate cursor is on active workspace
                if not await self.validate_cursor_on_active_workspace(cursor, workspace):
                    self.logger.warning(f"Cursor outside workspace, using center fallback")
                    await self.sway.command(f'[con_mark="{terminal.mark}"] move position center')
                    return

                # Get current window dimensions
                tree = await self.sway.get_tree()
                window = tree.find_by_id(terminal.window_id)
                if window and window.rect:
                    window_dims = WindowDimensions(
                        width=window.rect.width,
                        height=window.rect.height
                    )
                else:
                    window_dims = WindowDimensions()  # Default 1000x600

                # Apply boundary constraints
                position = await self.apply_boundary_constraints(cursor, window_dims, workspace)

                # Apply calculated position to window
                await self.sway.command(position.to_sway_command(terminal.window_id))

                # Ensure floating mode
                await self.sway.command(f'[con_id={terminal.window_id}] floating enable')

                self.logger.info(
                    f"Summoned terminal for project '{project_name}' to workspace {workspace.workspace_num} "
                    f"at ({position.x}, {position.y}) [{position.width}x{position.height}] "
                    f"(cursor_source={cursor.source}, constrained={position.constrained_by_gaps})"
                )

            except Exception as e:
                self.logger.error(f"Failed to apply mouse positioning during summon for {project_name}: {e}", exc_info=True)
                # Fallback to center positioning
                await self.sway.command(f'[con_mark="{terminal.mark}"] move position center')
                self.logger.warning(f"Fell back to center positioning for summoned project '{project_name}'")
        else:
            # Mouse positioning disabled, use center
            await self.sway.command(f'[con_mark="{terminal.mark}"] move position center')
            self.logger.debug(f"Summoned terminal for project '{project_name}' to center (mouse positioning disabled)")

    async def _goto_terminal_workspace(
        self,
        project_name: str,
        terminal: ScratchpadTerminal,
        terminal_workspace: int
    ) -> None:
        """
        Switch to the workspace where the terminal is located.

        T032: Implement Sway IPC switch-to-workspace command.

        Args:
            project_name: Project identifier
            terminal: Terminal to goto
            terminal_workspace: Workspace number where terminal is located
        """
        # Switch to terminal's workspace
        await self.sway.command(f'workspace number {terminal_workspace}')

        # Show terminal from scratchpad
        await self.sway.command(f'[con_mark="{terminal.mark}"] scratchpad show')

        # Apply mouse positioning on the target workspace
        if self.summon_mode.mouse_positioning_enabled:
            try:
                # Query target workspace geometry (now the current workspace)
                workspace = await self.get_current_workspace_geometry()

                # Calculate mouse cursor position
                cursor = await self.calculate_mouse_position(workspace)

                # Validate cursor
                if not await self.validate_cursor_on_active_workspace(cursor, workspace):
                    self.logger.warning(f"Cursor outside workspace, using center fallback")
                    await self.sway.command(f'[con_mark="{terminal.mark}"] move position center')
                    return

                # Get window dimensions
                tree = await self.sway.get_tree()
                window = tree.find_by_id(terminal.window_id)
                if window and window.rect:
                    window_dims = WindowDimensions(
                        width=window.rect.width,
                        height=window.rect.height
                    )
                else:
                    window_dims = WindowDimensions()

                # Apply boundary constraints
                position = await self.apply_boundary_constraints(cursor, window_dims, workspace)

                # Apply position
                await self.sway.command(position.to_sway_command(terminal.window_id))
                await self.sway.command(f'[con_id={terminal.window_id}] floating enable')

                self.logger.info(
                    f"Switched to workspace {terminal_workspace} for project '{project_name}' "
                    f"at ({position.x}, {position.y}) [{position.width}x{position.height}] "
                    f"(cursor_source={cursor.source}, constrained={position.constrained_by_gaps})"
                )

            except Exception as e:
                self.logger.error(f"Failed to apply mouse positioning during goto for {project_name}: {e}", exc_info=True)
                await self.sway.command(f'[con_mark="{terminal.mark}"] move position center')
                self.logger.warning(f"Fell back to center positioning for goto to project '{project_name}'")
        else:
            # Mouse positioning disabled
            await self.sway.command(f'[con_mark="{terminal.mark}"] move position center')
            self.logger.debug(f"Switched to workspace {terminal_workspace} for project '{project_name}' at center")
