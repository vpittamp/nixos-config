"""
MarkManager Service for Sway Mark Management

Feature 103: Unified Mark System
Purpose: Manage unified Sway mark injection and queries for window classification
Location: home-modules/desktop/i3-project-event-daemon/services/mark_manager.py

Mark Format: SCOPE:APP_NAME:PROJECT:WINDOW_ID
Examples:
- scoped:terminal:vpittamp/nixos-config:main:12345
- scoped:scratchpad-terminal:myproject:67890
- global:firefox:nixos:99999
"""

import logging
import time
from dataclasses import dataclass
from typing import Optional
from i3ipc.aio import Connection

from ..worktree_utils import build_mark, parse_mark, ParsedMark

logger = logging.getLogger(__name__)


@dataclass
class MarkQuery:
    """Query parameters for finding windows by unified marks.

    Feature 103: Query windows using unified mark format.
    """
    app_name: Optional[str] = None
    project: Optional[str] = None
    scope: Optional[str] = None  # "scoped" or "global"

    @property
    def is_empty(self) -> bool:
        """Check if query has no filters."""
        return self.app_name is None and self.project is None and self.scope is None


class MarkManager:
    """Manages unified Sway marks for window identification.

    Feature 103: Unified Mark System
    Single mark format: SCOPE:APP_NAME:PROJECT:WINDOW_ID
    """

    def __init__(self, sway_connection: Connection):
        """Initialize MarkManager with Sway IPC connection.

        Args:
            sway_connection: i3ipc.aio Connection instance for Sway IPC
        """
        self.sway = sway_connection
        logger.info("[Feature 103] MarkManager initialized with unified mark format")

    async def inject_mark(
        self,
        window_id: int,
        app_name: str,
        project: str,
        scope: str = "scoped",
    ) -> str:
        """Inject unified mark onto window via Sway IPC.

        Feature 103: Single unified mark per window.

        Args:
            window_id: Sway container ID
            app_name: Application name from app-registry (e.g., "terminal", "code")
            project: Project name (simple or qualified, e.g., "vpittamp/nixos-config:main")
            scope: "scoped" or "global" (default: "scoped")

        Returns:
            The injected mark string

        Raises:
            ValueError: If app_name is empty
            Exception: If Sway IPC command fails
        """
        if not app_name or not app_name.strip():
            raise ValueError("app_name cannot be empty")

        if not project or not project.strip():
            raise ValueError("project cannot be empty")

        if scope not in ("scoped", "global"):
            raise ValueError(f"scope must be 'scoped' or 'global', got: {scope}")

        # Build unified mark
        mark = build_mark(scope, app_name, project, window_id)

        start_time = time.perf_counter()

        try:
            cmd = f'[con_id={window_id}] mark --add "{mark}"'
            result = await self.sway.command(cmd)
            if not result or not result[0].success:
                error_msg = result[0].error if result else "Unknown error"
                raise Exception(f"Failed to inject mark '{mark}': {error_msg}")
        except Exception as e:
            logger.error(f"[Feature 103] Failed to inject mark '{mark}' on window {window_id}: {e}")
            raise

        elapsed_ms = (time.perf_counter() - start_time) * 1000
        logger.info(
            f"[Feature 103] Injected unified mark on window {window_id}: {mark} "
            f"({elapsed_ms:.2f}ms)"
        )

        return mark

    async def get_window_mark(self, window_id: int) -> Optional[ParsedMark]:
        """Get parsed unified mark for a window.

        Args:
            window_id: Sway container ID

        Returns:
            ParsedMark if window has unified mark, None otherwise

        Raises:
            ValueError: If window_id not found
        """
        tree = await self.sway.get_tree()

        def find_window(node):
            if hasattr(node, 'id') and node.id == window_id:
                return node
            for child in getattr(node, 'nodes', []):
                found = find_window(child)
                if found:
                    return found
            for child in getattr(node, 'floating_nodes', []):
                found = find_window(child)
                if found:
                    return found
            return None

        window = find_window(tree)
        if not window:
            raise ValueError(f"Window {window_id} not found")

        # Find unified mark (scoped: or global: prefix)
        all_marks = window.marks if hasattr(window, 'marks') else []
        for mark in all_marks:
            parsed = parse_mark(mark, window_id)
            if parsed:
                return parsed

        return None

    async def find_windows(self, query: MarkQuery) -> list[int]:
        """Find windows matching mark query.

        Args:
            query: MarkQuery with filter criteria

        Returns:
            List of window IDs matching all query filters

        Raises:
            ValueError: If query is empty (no filters)
        """
        if query.is_empty:
            raise ValueError("Query must have at least one filter")

        start_time = time.perf_counter()

        tree = await self.sway.get_tree()
        matching_windows = []

        def walk_tree(node):
            if hasattr(node, 'pid') and node.pid and node.pid > 0:
                marks = node.marks if hasattr(node, 'marks') else []

                for mark in marks:
                    parsed = parse_mark(mark, node.id)
                    if not parsed:
                        continue

                    # Check all query filters (AND logic)
                    matches = True
                    if query.app_name and parsed.app_name != query.app_name:
                        matches = False
                    if query.project and parsed.project_name != query.project:
                        matches = False
                    if query.scope and parsed.scope != query.scope:
                        matches = False

                    if matches:
                        matching_windows.append(node.id)
                        break  # Found matching mark, no need to check others

            for child in getattr(node, 'nodes', []):
                walk_tree(child)
            for child in getattr(node, 'floating_nodes', []):
                walk_tree(child)

        walk_tree(tree)

        elapsed_ms = (time.perf_counter() - start_time) * 1000
        logger.debug(
            f"[Feature 103] Found {len(matching_windows)} windows matching query "
            f"(app={query.app_name}, project={query.project}, scope={query.scope}) "
            f"in {elapsed_ms:.2f}ms"
        )

        return matching_windows

    async def cleanup_mark(self, window_id: int) -> bool:
        """Remove unified mark from window.

        Args:
            window_id: Sway container ID

        Returns:
            True if mark was removed, False if no mark found

        Raises:
            ValueError: If window_id not found
        """
        start_time = time.perf_counter()

        parsed = await self.get_window_mark(window_id)
        if not parsed:
            return False

        # Reconstruct mark string for removal
        mark = build_mark(parsed.scope, parsed.app_name, parsed.project_name, int(parsed.window_id))

        try:
            cmd = f'[con_id={window_id}] unmark "{mark}"'
            result = await self.sway.command(cmd)
            if result and result[0].success:
                elapsed_ms = (time.perf_counter() - start_time) * 1000
                logger.debug(f"[Feature 103] Removed mark from window {window_id} in {elapsed_ms:.2f}ms")
                return True
            else:
                error_msg = result[0].error if result else "Unknown error"
                logger.warning(f"[Feature 103] Failed to remove mark from window {window_id}: {error_msg}")
                return False
        except Exception as e:
            logger.warning(f"[Feature 103] Error removing mark from window {window_id}: {e}")
            return False

    async def count_instances(
        self,
        app_name: str,
        project: Optional[str] = None
    ) -> int:
        """Count running instances of an app.

        Args:
            app_name: Application name from app-registry
            project: Optional project filter

        Returns:
            Number of matching windows
        """
        query = MarkQuery(app_name=app_name, project=project)

        try:
            windows = await self.find_windows(query)
            return len(windows)
        except ValueError:
            return 0
