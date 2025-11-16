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
from .models import WorkspaceModeState, WorkspaceSwitch, WorkspaceModeEvent, PendingWorkspaceState
# Feature 078: Enhanced Project Selection
from .models.project_filter import FilterState, ProjectListItem

if TYPE_CHECKING:
    from i3ipc.aio import Connection

logger = logging.getLogger(__name__)


class WorkspaceModeManager:
    """Manages workspace mode state in-memory."""

    def __init__(self, i3_connection: "Connection", config_dir=None, state_manager=None, workspace_tracker=None, ipc_server=None):
        """Initialize workspace mode manager.

        Args:
            i3_connection: i3ipc async connection for workspace switching
            config_dir: Path to i3 config directory (for ProjectService lazy-loading)
            state_manager: StateManager instance (for ProjectService lazy-loading)
            workspace_tracker: WorkspaceTracker for window filtering (Feature 037)
            ipc_server: IPCServer instance for broadcasting workspace mode events (Feature 058)
        """
        self._i3 = i3_connection
        self._config_dir = config_dir
        self._state_manager = state_manager
        self._workspace_tracker = workspace_tracker
        self._ipc_server = ipc_server  # Feature 058: IPC event broadcasting
        self._project_service = None  # Lazy-loaded on first use
        self._state = WorkspaceModeState()
        self._history: List[WorkspaceSwitch] = []  # Circular buffer, max 100
        # Feature 078: Enhanced Project Selection
        self._filter_state = FilterState()
        self._all_projects: List[ProjectListItem] = []  # Cached project list

    @property
    def state(self) -> WorkspaceModeState:
        """Get current workspace mode state."""
        return self._state

    @property
    def mode_type(self) -> Optional[str]:
        """Get current mode type (goto/move/None)."""
        return self._state.mode_type

    async def enter_mode(self, mode_type: str) -> None:
        """Enter workspace mode (goto or move).

        Args:
            mode_type: "goto" (navigate to workspace) or "move" (move window + follow)

        Raises:
            ValueError: If mode_type is not "goto" or "move"
        """
        if mode_type not in ("goto", "move"):
            raise ValueError(f"Invalid mode_type: {mode_type}. Must be 'goto' or 'move'")

        logger.info(f"Entering workspace mode: {mode_type}")

        self._state.active = True
        self._state.mode_type = mode_type
        self._state.accumulated_digits = ""
        self._state.entered_at = datetime.now()

        # Refresh output cache from i3 IPC
        await self._refresh_output_cache()

        # Feature 058: Emit enter event (pending_workspace will be None since no digits yet)
        await self._emit_workspace_mode_event("enter")

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
        self._state.input_type = "workspace"  # NEW: Mark as workspace navigation

        # Feature 058: Emit workspace mode event with pending workspace state
        await self._emit_workspace_mode_event("digit")

        elapsed_ms = (time.time() - start_time) * 1000
        logger.debug(f"Digit added: {digit}, accumulated: {self._state.accumulated_digits} (took {elapsed_ms:.2f}ms)")

        return self._state.accumulated_digits

    async def add_char(self, char: str) -> str:
        """Add letter to accumulated state for project switching (NEW).

        Args:
            char: Single letter a-z (lowercase) or ':' to enter project mode

        Returns:
            Current accumulated characters string

        Raises:
            ValueError: If char is not a-z or ':'
            RuntimeError: If mode is not active
        """
        start_time = time.time()

        if not self._state.active:
            raise RuntimeError("Cannot add char: workspace mode not active")

        char_lower = char.lower()

        # Feature 072: Handle ':' as project mode trigger (User Story 3)
        if char == ':':
            # Clear any accumulated digits and switch to project mode
            self._state.accumulated_digits = ""
            self._state.accumulated_chars = ""  # Don't add ':' to chars
            self._state.input_type = "project"

            # Feature 079: Clear project cache to reload from disk on each session
            # This ensures newly created projects (e.g., worktrees) appear immediately
            self._all_projects = []
            logger.debug("Cleared project cache for fresh reload on project mode entry")

            # Emit project mode event to show empty project search UI
            await self._emit_project_mode_event("char")

            elapsed_ms = (time.time() - start_time) * 1000
            logger.debug(f"Project mode entered via ':', accumulated: {self._state.accumulated_chars} (took {elapsed_ms:.2f}ms)")

            return self._state.accumulated_chars

        # Validate regular characters (a-z)
        if not char_lower or char_lower not in "abcdefghijklmnopqrstuvwxyz":
            raise ValueError(f"Invalid char: {char}. Must be a-z or ':'")

        self._state.accumulated_chars += char_lower
        self._state.input_type = "project"  # NEW: Mark as project navigation

        # Emit project mode event with fuzzy-matched project preview
        await self._emit_project_mode_event("char")

        elapsed_ms = (time.time() - start_time) * 1000
        logger.debug(f"Char added: {char_lower}, accumulated: {self._state.accumulated_chars} (took {elapsed_ms:.2f}ms)")

        return self._state.accumulated_chars

    async def backspace(self) -> str:
        """Remove last character from accumulated input.

        Supports both workspace navigation (digits) and project search (chars).

        Returns:
            Updated accumulated string (digits or chars depending on input_type)

        Raises:
            RuntimeError: If mode is not active
        """
        start_time = time.time()

        if not self._state.active:
            raise RuntimeError("Cannot backspace: workspace mode not active")

        # Determine which field to update based on input type
        if self._state.input_type == "project":
            # Remove last char from project search
            if self._state.accumulated_chars:
                self._state.accumulated_chars = self._state.accumulated_chars[:-1]
                await self._emit_project_mode_event("char")
                logger.debug(f"Backspace in project mode, remaining: '{self._state.accumulated_chars}'")
            else:
                logger.debug("Backspace in project mode but no chars to remove")

            elapsed_ms = (time.time() - start_time) * 1000
            logger.debug(f"Backspace completed in project mode (took {elapsed_ms:.2f}ms)")
            return self._state.accumulated_chars
        else:
            # Remove last digit from workspace navigation (input_type is "workspace" or None)
            if self._state.accumulated_digits:
                self._state.accumulated_digits = self._state.accumulated_digits[:-1]
                await self._emit_workspace_mode_event("digit")
                logger.debug(f"Backspace in workspace mode, remaining: '{self._state.accumulated_digits}'")
            else:
                logger.debug("Backspace in workspace mode but no digits to remove")

            elapsed_ms = (time.time() - start_time) * 1000
            logger.debug(f"Backspace completed in workspace mode (took {elapsed_ms:.2f}ms)")
            return self._state.accumulated_digits

    async def execute(self) -> Optional[Dict[str, any]]:
        """Execute workspace switch OR project switch based on input type.

        Returns:
            Dict with result details and success status
            None if no input accumulated (no-op)

        Raises:
            RuntimeError: If mode is not active
        """
        if not self._state.active:
            raise RuntimeError("Cannot execute: workspace mode not active")

        # Feature 059: Emit enter_key_select event for selection-based navigation
        # workspace-preview-daemon will handle navigation if selection exists
        await self._emit_enter_key_select_event()

        # Determine action based on input type
        if self._state.input_type == "project":
            return await self._execute_project_switch()
        elif self._state.input_type == "workspace":
            return await self._execute_workspace_switch()
        else:
            # No input (empty) - Feature 059: workspace-preview-daemon handles selection-based navigation
            logger.info("Execute called with no input, letting workspace-preview-daemon handle selection")
            # Exit mode and reset state
            await self._i3.command("mode default")
            self._state.reset()
            await self._emit_workspace_mode_event("execute")
            return None

    async def _execute_workspace_switch(self) -> Dict[str, any]:
        """Execute workspace switch with accumulated digits.

        Feature 057: Supports workspace-to-monitor move (User Story 3)
        """
        # Parse workspace and optional monitor
        workspace, target_monitor = self._parse_workspace_and_monitor()

        if workspace is None:
            raise ValueError(f"Invalid workspace/monitor: {self._state.accumulated_digits}")

        # Determine output (use parsed monitor if specified, otherwise query Sway)
        if target_monitor:
            output = target_monitor
        else:
            output = await self._get_output_for_workspace(workspace)

        logger.info(f"Executing workspace switch: ws={workspace}, output={output}, mode={self._state.mode_type}, monitor={target_monitor}")

        start_time = time.time()
        try:
            # Execute workspace switch via i3 IPC
            ipc_start = time.time()
            if self._state.mode_type == "goto":
                # Navigate to workspace (standard goto)
                await self._i3.command(f"workspace number {workspace}")

            elif self._state.mode_type == "move":
                if target_monitor:
                    # Feature 057: Move workspace to specified monitor
                    # First focus the workspace, then move it to the target output, then follow
                    await self._i3.command(f"workspace number {workspace}")
                    await self._i3.command(f"move workspace to output {target_monitor}")
                    await self._i3.command(f"workspace number {workspace}")
                    logger.info(f"Moved workspace {workspace} to {target_monitor}")
                else:
                    # No monitor specified in move mode - error or no-op
                    logger.warning(f"Move mode requires monitor (e.g., type '231' for WS 23 to monitor 1)")
                    raise ValueError("Move mode requires 3 digits: workspace (2 digits) + monitor (1 digit)")

            ipc_elapsed_ms = (time.time() - ipc_start) * 1000

            # Exit mode in Sway (return to default mode)
            await self._i3.command("mode default")

            total_elapsed_ms = (time.time() - start_time) * 1000
            logger.info(f"Workspace operation successful: ws={workspace}, output={output} (took {total_elapsed_ms:.2f}ms)")

            # Record history (Feature 042: US4)
            await self._record_switch(workspace, output, self._state.mode_type)

            # Feature 058: Emit execute event BEFORE reset (so workspace-preview-daemon gets pending state)
            await self._emit_workspace_mode_event("execute")

            # Reset state
            mode_type = self._state.mode_type  # Save for return value
            self._state.reset()

            return {
                "type": "workspace",
                "workspace": workspace,
                "output": output,
                "success": True,
                "mode_type": mode_type,
                "target_monitor": target_monitor
            }

        except Exception as e:
            logger.error(f"Workspace operation failed: {e}")
            # Don't reset state on error - user can retry
            raise

    async def _execute_project_switch(self) -> Dict[str, any]:
        """Execute project switch with accumulated characters (NEW)."""
        # Fuzzy match project from accumulated characters (lazy-loads ProjectService)
        matched_project = await self._fuzzy_match_project(self._state.accumulated_chars)

        if not matched_project:
            logger.warning(f"No project found matching '{self._state.accumulated_chars}'")
            # Don't reset - let user retry or cancel
            raise ValueError(f"No project matches '{self._state.accumulated_chars}'")

        logger.info(f"Executing project switch: '{self._state.accumulated_chars}' → '{matched_project}'")

        start_time = time.time()
        try:
            # Switch project directly (Sway doesn't send tick events for nop commands)
            from .handlers import _switch_project
            await _switch_project(matched_project, self._state_manager, self._i3, self._config_dir, self._workspace_tracker)

            # Exit mode in Sway (return to default mode)
            logger.info(f"Project switch complete, exiting workspace mode...")
            mode_result = await self._i3.command("mode default")
            logger.info(f"Mode default command executed: {mode_result}")

            total_elapsed_ms = (time.time() - start_time) * 1000
            logger.info(f"Project switch successful: {matched_project} (took {total_elapsed_ms:.2f}ms)")

            # Emit execute event BEFORE reset (so daemon can close preview with current state)
            await self._emit_project_mode_event("execute")

            # Reset state AFTER emitting event
            self._state.reset()
            logger.info("Workspace mode state reset after project switch")

            return {
                "type": "project",
                "project": matched_project,
                "success": True,
            }

        except Exception as e:
            logger.error(f"Project switch failed: {e}")
            # Don't reset state on error - user can retry
            raise

    async def _fuzzy_match_project(self, chars: str) -> Optional[str]:
        """Find best project match for typed characters.

        Uses priority-based matching:
        1. Exact match (e.g., "nixos" → "nixos")
        2. Prefix match (e.g., "st" → "stacks")
        3. Substring match (e.g., "ix" → "nixos")
        4. First character match for single char (e.g., "s" → first project starting with 's')

        Args:
            chars: Accumulated characters from user input

        Returns:
            Matched project name or None if no match
        """
        if not chars:
            return None

        # Lazy-load ProjectService if needed
        if not self._project_service:
            if not self._config_dir:
                logger.error("Cannot load ProjectService: config_dir not provided")
                return None

            from .services.project_service import ProjectService
            self._project_service = ProjectService(self._config_dir, self._state_manager)
            logger.debug("Lazy-loaded ProjectService for project matching")

        # Get all projects
        projects = self._project_service.list()
        project_names = [p.name.lower() for p in projects]
        chars_lower = chars.lower()

        logger.debug(f"Fuzzy matching '{chars}' against projects: {project_names}")

        # Priority 1: Exact match
        if chars_lower in project_names:
            logger.debug(f"Exact match found: {chars_lower}")
            return chars_lower

        # Priority 2: Prefix match
        prefix_matches = [p for p in project_names if p.startswith(chars_lower)]
        if prefix_matches:
            # Sort alphabetically and return first
            match = sorted(prefix_matches)[0]
            logger.debug(f"Prefix match found: {match} (from {prefix_matches})")
            return match

        # Priority 3: Substring match
        substring_matches = [p for p in project_names if chars_lower in p]
        if substring_matches:
            # Sort alphabetically and return first
            match = sorted(substring_matches)[0]
            logger.debug(f"Substring match found: {match} (from {substring_matches})")
            return match

        # Priority 4: First character match (only for single character input)
        if len(chars_lower) == 1:
            first_char_matches = [p for p in project_names if p.startswith(chars_lower[0])]
            if first_char_matches:
                match = sorted(first_char_matches)[0]
                logger.debug(f"First char match found: {match} (from {first_char_matches})")
                return match

        logger.debug(f"No match found for '{chars}'")
        return None

    async def _load_and_filter_projects(self, query: str = "") -> List[ProjectListItem]:
        """Load all projects and filter by query (Feature 078).

        Uses project_filter_service for fuzzy matching with scoring.

        Args:
            query: Filter query string (empty = all projects)

        Returns:
            Filtered and scored list of ProjectListItem
        """
        # Lazy-load projects on first call
        if not self._all_projects:
            if not self._config_dir:
                logger.error("Cannot load projects: config_dir not provided")
                return []

            try:
                from .project_filter_service import load_all_projects
                self._all_projects = load_all_projects(Path(self._config_dir))
                logger.debug(f"Loaded {len(self._all_projects)} projects for filtering")
            except Exception as e:
                logger.error(f"Failed to load projects: {e}")
                return []

        # Filter using the service
        if query:
            from .project_filter_service import filter_projects
            filtered = filter_projects(self._all_projects, query)
            logger.debug(f"Filtered to {len(filtered)} projects for query '{query}'")
            return filtered
        else:
            # No query - return all projects
            return self._all_projects

    async def _get_project_icon(self, project_name: str) -> str:
        """Get icon for a project by name.

        Args:
            project_name: Project name

        Returns:
            Project icon (emoji or text), defaults to "📁" if not found
        """
        if not project_name:
            return "📁"

        # Lazy-load ProjectService if needed
        if not self._project_service:
            if not self._config_dir:
                logger.error("Cannot load ProjectService: config_dir not provided")
                return "📁"

            from .services.project_service import ProjectService
            self._project_service = ProjectService(self._config_dir, self._state_manager)
            logger.debug("Lazy-loaded ProjectService for project icon lookup")

        # Get all projects and find matching project
        projects = self._project_service.list()
        for project in projects:
            if project.name.lower() == project_name.lower():
                return project.icon

        # Default icon if project not found
        return "📁"

    async def cancel(self) -> None:
        """Cancel workspace mode without action."""
        if not self._state.active:
            logger.debug("Cancel called but mode not active, no-op")
            return

        logger.info("Cancelling workspace mode")

        # Save input type before reset
        input_type = self._state.input_type

        # Exit mode in Sway (return to default mode)
        await self._i3.command("mode default")

        # Reset all state fields
        self._state.reset()

        # Emit cancel event AFTER reset based on mode type (clears UI)
        if input_type == "project":
            await self._emit_project_mode_event("cancel")
        else:
            # workspace mode or no input yet
            await self._emit_workspace_mode_event("cancel")

    async def nav(self, direction: str) -> None:
        """Navigate in workspace preview using arrow or home/end keys.

        Feature 059: Workspace Navigation Event Broadcasting

        Args:
            direction: Navigation direction ("up", "down", "left", "right", "home", "end")

        Raises:
            ValueError: If direction is not one of the valid directions
            RuntimeError: If workspace mode is not active
        """
        if not self._state.active:
            raise RuntimeError("Cannot navigate: workspace mode not active")

        valid_directions = {"up", "down", "left", "right", "home", "end"}
        if direction not in valid_directions:
            raise ValueError(f"Invalid direction: {direction}. Must be one of {valid_directions}")

        # Emit navigation event with direction parameter
        await self._emit_workspace_mode_event("nav", direction=direction)
        logger.info(f"Navigation event emitted: direction={direction}")

    async def delete(self) -> None:
        """Delete (close) the currently selected window in workspace preview.

        Feature 059: Workspace Navigation Event Broadcasting

        Raises:
            RuntimeError: If workspace mode is not active
        """
        if not self._state.active:
            raise RuntimeError("Cannot delete: workspace mode not active")

        # Emit delete event (no additional parameters needed - SelectionManager knows what's selected)
        await self._emit_workspace_mode_event("delete")
        logger.info("Delete event emitted for selected window")

    async def action(self, action: str) -> None:
        """Perform a window action (move, float toggle, mark).

        Feature 073: Per-Window Actions

        Args:
            action: Action type ("m" for move, "f" for float, "shift-m" for mark)

        Raises:
            RuntimeError: If workspace mode is not active
            ValueError: If action is invalid
        """
        if not self._state.active:
            raise RuntimeError("Cannot perform action: workspace mode is not active")

        valid_actions = ["m", "f", "shift-m"]
        if action not in valid_actions:
            raise ValueError(f"Invalid action: {action}. Must be one of {valid_actions}")

        # Emit window_action event with action type
        await self._emit_window_action_event(action)
        logger.info(f"Window action event emitted: {action}")

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
            # Sort outputs by name to ensure consistent PRIMARY/SECONDARY/TERTIARY assignment
            # (HEADLESS-1, HEADLESS-2, HEADLESS-3 instead of random order)
            active_outputs.sort(key=lambda o: o.name)

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

    def _parse_workspace_and_monitor(self) -> tuple[Optional[int], Optional[str]]:
        """Parse accumulated digits into workspace number and optional monitor.

        Feature 057: Workspace-to-Monitor Move (User Story 3)

        Parsing rules:
        - 1 digit: workspace only (e.g., "7" = workspace 7)
        - 2 digits: workspace only (e.g., "23" = workspace 23)
        - 3 digits: workspace + monitor (e.g., "231" = workspace 23, monitor 1 = HEADLESS-1)

        For 3 digits:
        - First 2 digits must be <= 70 (valid workspace)
        - Last digit must be 1-3 (valid monitor for Hetzner)

        Returns:
            (workspace_number, monitor_name) tuple
            - workspace_number: int (1-70) or None if invalid
            - monitor_name: "HEADLESS-1", "HEADLESS-2", "HEADLESS-3", or None if not specified
        """
        digits = self._state.accumulated_digits

        if not digits:
            return (None, None)

        # 1-2 digits: workspace only
        if len(digits) <= 2:
            try:
                workspace = int(digits)
                if 1 <= workspace <= 70:
                    return (workspace, None)
                else:
                    return (None, None)  # Invalid workspace
            except ValueError:
                return (None, None)

        # 3 digits: workspace + monitor
        if len(digits) == 3:
            try:
                # Try parsing first 2 digits as workspace, last digit as monitor
                workspace_str = digits[:2]
                monitor_digit = digits[2]

                workspace = int(workspace_str)
                monitor = int(monitor_digit)

                # Validate workspace (1-70) and monitor (1-3)
                if 1 <= workspace <= 70 and 1 <= monitor <= 3:
                    monitor_name = f"HEADLESS-{monitor}"
                    return (workspace, monitor_name)
                else:
                    return (None, None)  # Invalid workspace or monitor
            except ValueError:
                return (None, None)

        # More than 3 digits: invalid
        return (None, None)

    async def _calculate_pending_workspace(self) -> Optional[PendingWorkspaceState]:
        """Calculate pending workspace state from accumulated digits.

        Feature 058: Workspace Mode Visual Feedback
        Derives PendingWorkspaceState from current accumulated_digits.

        Returns:
            PendingWorkspaceState if valid workspace (1-70), None otherwise
        """
        # No digits accumulated yet
        if not self._state.accumulated_digits:
            return None

        # Feature 057: Parse workspace and optional monitor (for move mode)
        workspace_number, monitor_name = self._parse_workspace_and_monitor()

        if workspace_number is None:
            logger.debug(f"Invalid workspace/monitor in accumulated_digits: {self._state.accumulated_digits}")
            return None

        # Determine target output
        if monitor_name:
            # Move mode with explicit monitor specified
            target_output = monitor_name
        else:
            # Goto mode or move mode without monitor (query Sway for actual location)
            target_output = await self._get_output_for_workspace(workspace_number)

        # Create pending workspace state
        return PendingWorkspaceState(
            workspace_number=workspace_number,
            accumulated_digits=self._state.accumulated_digits,
            mode_type=self._state.mode_type or "goto",  # Default to "goto" if not set
            target_output=target_output
        )

    async def _get_output_for_workspace(self, workspace: int) -> str:
        """Get output name for workspace number.

        First checks if workspace exists in Sway and returns its actual output.
        Falls back to distribution rules if workspace doesn't exist yet:
        - Workspaces 1-2: PRIMARY
        - Workspaces 3-5: SECONDARY
        - Workspaces 6+: TERTIARY

        Args:
            workspace: Workspace number

        Returns:
            Output name (e.g., "eDP-1", "HEADLESS-1")
        """
        try:
            # Query Sway for actual workspace location
            workspaces = await self._i3.get_workspaces()
            for ws in workspaces:
                if ws.num == workspace:
                    # Workspace exists, return its actual output
                    return ws.output
        except Exception as e:
            logger.warning(f"Failed to query workspace location: {e}")

        # Workspace doesn't exist yet, use static distribution rules
        if workspace in (1, 2):
            return self._state.output_cache.get("PRIMARY", "eDP-1")
        elif workspace in (3, 4, 5):
            return self._state.output_cache.get("SECONDARY", "eDP-1")
        else:
            return self._state.output_cache.get("TERTIARY", "eDP-1")

    async def _emit_workspace_mode_event(self, event_type: str, **kwargs) -> None:
        """Emit workspace mode event via IPC with pending workspace state.

        Feature 058: Workspace Mode Visual Feedback
        Feature 059: Navigation Event Broadcasting (added **kwargs support)
        Broadcasts events to sway-workspace-panel for real-time UI updates.

        Args:
            event_type: Type of event ("enter", "digit", "nav", "delete", "cancel", "execute")
            **kwargs: Additional event-specific fields (e.g., direction="down" for nav events)
        """
        if not self._ipc_server:
            logger.debug("IPC server not available, skipping event emission")
            return

        # Calculate pending workspace state (queries Sway for actual workspace location)
        pending_workspace = await self._calculate_pending_workspace()

        # Create event payload (Feature 058: format for workspace panel)
        event_payload = {
            "type": "workspace_mode",
            "payload": {
                "event_type": event_type,
                "pending_workspace": pending_workspace.model_dump() if pending_workspace else None,
                "mode_type": self._state.mode_type,  # Feature 059: T024 - Add mode for move-mode styling
                "timestamp": time.time(),
                **kwargs  # Feature 059: Include additional fields (e.g., direction)
            }
        }

        # Broadcast event asynchronously (non-blocking)
        try:
            asyncio.create_task(
                self._ipc_server.broadcast_event(event_payload)
            )
            logger.debug(f"Emitted workspace_mode event: type={event_type}, pending_ws={pending_workspace.workspace_number if pending_workspace else None}")
        except Exception as e:
            logger.warning(f"Failed to broadcast workspace_mode event: {e}")

    async def _emit_enter_key_select_event(self) -> None:
        """Emit enter key selection event via IPC (Feature 059).

        Notifies workspace-preview-daemon that Enter was pressed for selection-based navigation.
        """
        if not self._ipc_server:
            logger.debug("IPC server not available, skipping enter_key_select event")
            return

        # Create event payload for Feature 059 enter key selection (matches contract schema)
        event_payload = {
            "method": "event",
            "params": {
                "type": "enter_key_select",
                "payload": {
                    "mode": "all_windows" if not self._state.accumulated_digits else "filtered_workspace",
                    "accumulated_digits": self._state.accumulated_digits or "",
                    "timestamp_ms": int(time.time() * 1000)
                }
            }
        }

        # Broadcast event asynchronously (non-blocking)
        try:
            asyncio.create_task(
                self._ipc_server.broadcast_event(event_payload)
            )
            logger.debug(f"Emitted enter_key_select event: mode={event_payload['params']['params']['payload']['mode']}, digits={self._state.accumulated_digits}")
        except Exception as e:
            logger.warning(f"Failed to broadcast enter_key_select event: {e}")

    async def _emit_arrow_key_nav_event(self, direction: str) -> None:
        """Emit arrow key navigation event via IPC (Feature 059).

        Notifies workspace-preview-daemon that Up/Down arrow key was pressed for selection navigation.

        Args:
            direction: "up" or "down"
        """
        if not self._ipc_server:
            logger.debug("IPC server not available, skipping arrow_key_nav event")
            return

        # Create event payload for Feature 059 arrow key navigation (matches contract schema)
        event_payload = {
            "method": "event",
            "params": {
                "type": "arrow_key_nav",
                "payload": {
                    "direction": direction,
                    "mode": "all_windows" if not self._state.accumulated_digits else "filtered_workspace",
                    "timestamp_ms": int(time.time() * 1000)
                }
            }
        }

        # Broadcast event asynchronously (non-blocking)
        try:
            asyncio.create_task(
                self._ipc_server.broadcast_event(event_payload)
            )
            logger.debug(f"Emitted arrow_key_nav event: direction={direction}, mode={event_payload['params']['payload']['mode']}")
        except Exception as e:
            logger.warning(f"Failed to broadcast arrow_key_nav event: {e}")

    async def _emit_delete_key_close_event(self) -> None:
        """Emit delete key close event via IPC (Feature 059).

        Notifies workspace-preview-daemon that Delete key was pressed to close selected window.
        """
        if not self._ipc_server:
            logger.debug("IPC server not available, skipping delete_key_close event")
            return

        # Create event payload for Feature 059 delete key close (matches contract schema)
        event_payload = {
            "method": "event",
            "params": {
                "type": "delete_key_close",
                "payload": {
                    "mode": "all_windows" if not self._state.accumulated_digits else "filtered_workspace",
                    "timestamp_ms": int(time.time() * 1000)
                }
            }
        }

        # Broadcast event asynchronously (non-blocking)
        try:
            asyncio.create_task(
                self._ipc_server.broadcast_event(event_payload)
            )
            logger.debug(f"Emitted delete_key_close event: mode={event_payload['params']['payload']['mode']}")
        except Exception as e:
            logger.warning(f"Failed to broadcast delete_key_close event: {e}")

    async def _emit_window_action_event(self, action: str) -> None:
        """Emit window action event via IPC (Feature 073).

        Notifies workspace-preview-daemon that M/F/Shift+M key was pressed for window actions.

        Args:
            action: Action type ("m" for move, "f" for float, "shift-m" for mark)
        """
        if not self._ipc_server:
            logger.debug("IPC server not available, skipping window_action event")
            return

        # Create event payload for Feature 073 window actions (matches contract schema)
        event_payload = {
            "method": "event",
            "params": {
                "type": "window_action",
                "payload": {
                    "action": action,
                    "mode": "all_windows" if not self._state.accumulated_digits else "filtered_workspace",
                    "timestamp_ms": int(time.time() * 1000)
                }
            }
        }

        # Broadcast event asynchronously (non-blocking)
        try:
            asyncio.create_task(
                self._ipc_server.broadcast_event(event_payload)
            )
            logger.debug(f"Emitted window_action event: action={action}, mode={event_payload['params']['payload']['mode']}")
        except Exception as e:
            logger.warning(f"Failed to broadcast window_action event: {e}")

    async def _emit_home_key_nav_event(self) -> None:
        """Emit Home key navigation event via IPC (Feature 059: T059).

        Notifies workspace-preview-daemon that Home key was pressed to jump to first item.
        """
        if not self._ipc_server:
            logger.debug("IPC server not available, skipping home_key_nav event")
            return

        # Create event payload for Feature 059 Home key navigation
        event_payload = {
            "method": "event",
            "params": {
                "type": "home_key_nav",
                "payload": {
                    "mode": "all_windows" if not self._state.accumulated_digits else "filtered_workspace",
                    "timestamp_ms": int(time.time() * 1000)
                }
            }
        }

        # Broadcast event asynchronously (non-blocking)
        try:
            asyncio.create_task(
                self._ipc_server.broadcast_event(event_payload)
            )
            logger.debug(f"Emitted home_key_nav event: mode={event_payload['params']['payload']['mode']}")
        except Exception as e:
            logger.warning(f"Failed to broadcast home_key_nav event: {e}")

    async def _emit_end_key_nav_event(self) -> None:
        """Emit End key navigation event via IPC (Feature 059: T059).

        Notifies workspace-preview-daemon that End key was pressed to jump to last item.
        """
        if not self._ipc_server:
            logger.debug("IPC server not available, skipping end_key_nav event")
            return

        # Create event payload for Feature 059 End key navigation
        event_payload = {
            "method": "event",
            "params": {
                "type": "end_key_nav",
                "payload": {
                    "mode": "all_windows" if not self._state.accumulated_digits else "filtered_workspace",
                    "timestamp_ms": int(time.time() * 1000)
                }
            }
        }

        # Broadcast event asynchronously (non-blocking)
        try:
            asyncio.create_task(
                self._ipc_server.broadcast_event(event_payload)
            )
            logger.debug(f"Emitted end_key_nav event: mode={event_payload['params']['payload']['mode']}")
        except Exception as e:
            logger.warning(f"Failed to broadcast end_key_nav event: {e}")

    async def _emit_project_mode_event(self, event_type: str) -> None:
        """Emit project mode event via IPC with full filtered project list.

        Feature 078: Enhanced Project Selection in Eww Preview Dialog
        Broadcasts events to workspace-preview-daemon for real-time UI updates.

        Args:
            event_type: Type of event ("enter", "char", "nav", "backspace", "execute", "cancel")
        """
        if not self._ipc_server:
            logger.debug("IPC server not available, skipping event emission")
            return

        # Feature 078: Load and filter projects
        query = self._state.accumulated_chars
        filtered_projects = await self._load_and_filter_projects(query)

        # Update filter state
        self._filter_state.accumulated_chars = query
        self._filter_state.update_projects(filtered_projects)

        # Convert to serializable format for IPC
        projects_payload = []
        for i, project in enumerate(self._filter_state.projects):
            proj_dict = {
                "name": project.name,
                "display_name": project.display_name,
                "icon": project.icon,
                "is_worktree": project.is_worktree,
                "parent_project_name": project.parent_project_name,
                "directory_exists": project.directory_exists,
                "relative_time": project.relative_time,
                "git_status": None,
                "match_score": project.match_score,
                "match_positions": [{"start": mp.start, "end": mp.end} for mp in project.match_positions],
                "selected": (i == self._filter_state.selected_index),
            }
            if project.git_status:
                proj_dict["git_status"] = {
                    "is_clean": project.git_status.is_clean,
                    "ahead_count": project.git_status.ahead_count,
                    "behind_count": project.git_status.behind_count,
                }
            projects_payload.append(proj_dict)

        # Create event payload with full project list (per contract)
        event_payload = {
            "type": "project_mode",
            "payload": {
                "event_type": event_type,
                "accumulated_chars": self._filter_state.accumulated_chars,
                "selected_index": self._filter_state.selected_index,
                "projects": projects_payload,
            }
        }

        # Broadcast event asynchronously (non-blocking)
        try:
            asyncio.create_task(
                self._ipc_server.broadcast_event(event_payload)
            )
            logger.debug(f"Emitted project_mode event: type={event_type}, chars={query}, projects={len(projects_payload)}, selected={self._filter_state.selected_index}")
        except Exception as e:
            logger.warning(f"Failed to broadcast project_mode event: {e}")

    async def _record_switch(self, workspace: int, output: str, mode_type: str) -> None:
        """Record workspace switch in history.

        Args:
            workspace: Workspace number switched to
            output: Output name focused
            mode_type: "goto" or "move"
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
