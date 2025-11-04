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

    def __init__(self, i3_connection: "Connection", config_dir=None, state_manager=None):
        """Initialize workspace mode manager.

        Args:
            i3_connection: i3ipc async connection for workspace switching
            config_dir: Path to i3 config directory (for ProjectService lazy-loading)
            state_manager: StateManager instance (for ProjectService lazy-loading)
        """
        self._i3 = i3_connection
        self._config_dir = config_dir
        self._state_manager = state_manager
        self._project_service = None  # Lazy-loaded on first use
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

        elapsed_ms = (time.time() - start_time) * 1000
        logger.debug(f"Digit added: {digit}, accumulated: {self._state.accumulated_digits} (took {elapsed_ms:.2f}ms)")

        return self._state.accumulated_digits

    async def add_char(self, char: str) -> str:
        """Add letter to accumulated state for project switching (NEW).

        Args:
            char: Single letter a-z (lowercase)

        Returns:
            Current accumulated characters string

        Raises:
            ValueError: If char is not a-z
            RuntimeError: If mode is not active
        """
        start_time = time.time()

        if not self._state.active:
            raise RuntimeError("Cannot add char: workspace mode not active")

        char_lower = char.lower()
        if not char_lower or char_lower not in "abcdefghijklmnopqrstuvwxyz":
            raise ValueError(f"Invalid char: {char}. Must be a-z")

        self._state.accumulated_chars += char_lower
        self._state.input_type = "project"  # NEW: Mark as project navigation

        elapsed_ms = (time.time() - start_time) * 1000
        logger.debug(f"Char added: {char_lower}, accumulated: {self._state.accumulated_chars} (took {elapsed_ms:.2f}ms)")

        return self._state.accumulated_chars

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

        # Determine action based on input type
        if self._state.input_type == "project":
            return await self._execute_project_switch()
        elif self._state.input_type == "workspace":
            return await self._execute_workspace_switch()
        else:
            # No input (empty)
            logger.info("Execute called with no input, exiting mode without action")
            await self.cancel()
            return None

    async def _execute_workspace_switch(self) -> Dict[str, any]:
        """Execute workspace switch with accumulated digits."""
        workspace = int(self._state.accumulated_digits)
        output = self._get_output_for_workspace(workspace)

        logger.info(f"Executing workspace switch: ws={workspace}, output={output}, mode={self._state.mode_type}")

        start_time = time.time()
        try:
            # Execute workspace switch via i3 IPC
            ipc_start = time.time()
            if self._state.mode_type == "goto":
                await self._i3.command(f"workspace number {workspace}")
            elif self._state.mode_type == "move":
                # Move container + follow user
                await self._i3.command(f"move container to workspace number {workspace}; workspace number {workspace}")
            ipc_elapsed_ms = (time.time() - ipc_start) * 1000

            # Exit mode in Sway (return to default mode)
            await self._i3.command("mode default")

            total_elapsed_ms = (time.time() - start_time) * 1000
            logger.info(f"Workspace switch successful: ws={workspace}, output={output} (took {total_elapsed_ms:.2f}ms)")

            # Record history (Feature 042: US4)
            await self._record_switch(workspace, output, self._state.mode_type)

            # Reset state
            mode_type = self._state.mode_type  # Save for return value
            self._state.reset()

            return {
                "type": "workspace",
                "workspace": workspace,
                "output": output,
                "success": True,
                "mode_type": mode_type
            }

        except Exception as e:
            logger.error(f"Workspace switch failed: {e}")
            # Don't reset state on error - user can retry
            raise

    async def _execute_project_switch(self) -> Dict[str, any]:
        """Execute project switch with accumulated characters (NEW)."""
        if not self._project_service:
            raise RuntimeError("Project switching not available (no project service)")

        # Fuzzy match project from accumulated characters
        matched_project = await self._fuzzy_match_project(self._state.accumulated_chars)

        if not matched_project:
            logger.warning(f"No project found matching '{self._state.accumulated_chars}'")
            # Don't reset - let user retry or cancel
            raise ValueError(f"No project matches '{self._state.accumulated_chars}'")

        logger.info(f"Executing project switch: '{self._state.accumulated_chars}' → '{matched_project}'")

        start_time = time.time()
        try:
            # Switch project via tick event
            await self._i3.command(f'nop "project:switch:{matched_project}"')

            # Exit mode in Sway (return to default mode)
            await self._i3.command("mode default")

            total_elapsed_ms = (time.time() - start_time) * 1000
            logger.info(f"Project switch successful: {matched_project} (took {total_elapsed_ms:.2f}ms)")

            # Reset state
            self._state.reset()

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
        projects = await self._project_service.list_projects()
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

    async def cancel(self) -> None:
        """Cancel workspace mode without action."""
        if not self._state.active:
            logger.debug("Cancel called but mode not active, no-op")
            return

        logger.info("Cancelling workspace mode")

        # Exit mode in Sway (return to default mode)
        await self._i3.command("mode default")

        # Reset all state fields
        self._state.reset()

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
