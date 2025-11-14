"""
MarkManager Service for Sway Mark Management

Feature 076: Mark-Based App Identification (T003)
Purpose: Manage Sway mark injection, query, and cleanup for window classification
Location: home-modules/desktop/i3-project-event-daemon/services/mark_manager.py
"""

import logging
import time
from typing import Optional
from i3ipc.aio import Connection

from ..layout.models import MarkMetadata, WindowMarkQuery

logger = logging.getLogger(__name__)


class MarkManager:
    """Manages Sway marks for deterministic window identification.

    Feature 076: Mark-Based App Identification
    Provides mark injection, query, and cleanup operations via Sway IPC.
    """

    def __init__(self, sway_connection: Connection):
        """Initialize MarkManager with Sway IPC connection.

        Args:
            sway_connection: i3ipc.aio Connection instance for Sway IPC
        """
        self.sway = sway_connection
        logger.info("MarkManager initialized")

    async def inject_marks(
        self,
        window_id: int,
        app_name: str,
        project: Optional[str] = None,
        workspace: Optional[int] = None,
        scope: Optional[str] = None,
        custom: Optional[dict[str, str]] = None,
    ) -> MarkMetadata:
        """Inject marks onto window via Sway IPC.

        Args:
            window_id: Sway container ID
            app_name: Application name from app-registry
            project: Project context (if scoped app)
            workspace: Workspace number for validation
            scope: "scoped" or "global" classification
            custom: Custom metadata key-value pairs

        Returns:
            MarkMetadata instance with injected marks

        Raises:
            ValueError: If app_name invalid or window_id not found
            Exception: If Sway IPC command fails
        """
        # T006: Validate inputs
        if not app_name or not app_name.strip():
            raise ValueError("app_name cannot be empty")

        if workspace is not None and (workspace < 1 or workspace > 70):
            raise ValueError(f"Workspace must be 1-70, got: {workspace}")

        # Create MarkMetadata instance
        workspace_str = str(workspace) if workspace is not None else None
        mark_metadata = MarkMetadata(
            app=app_name,
            project=project,
            workspace=workspace_str,
            scope=scope,
            custom=custom
        )

        # Generate Sway mark strings
        marks = mark_metadata.to_sway_marks()

        # T046: Performance logging for mark injection
        start_time = time.perf_counter()

        # Inject marks via Sway IPC
        for mark in marks:
            try:
                cmd = f'[con_id={window_id}] mark --add "{mark}"'
                result = await self.sway.command(cmd)
                if not result or not result[0].success:
                    error_msg = result[0].error if result else "Unknown error"
                    raise Exception(f"Failed to inject mark '{mark}': {error_msg}")
            except Exception as e:
                logger.error(f"Failed to inject mark '{mark}' on window {window_id}: {e}")
                raise

        # T046: Log injection performance
        elapsed_ms = (time.perf_counter() - start_time) * 1000
        logger.debug(
            f"Feature 076 Performance: Injected {len(marks)} marks on window {window_id} "
            f"in {elapsed_ms:.2f}ms (target: <15ms for 3 marks)"
        )
        return mark_metadata

    async def get_window_marks(self, window_id: int) -> list[str]:
        """Get all i3pm_* marks for a window.

        Args:
            window_id: Sway container ID

        Returns:
            List of mark strings (e.g., ["i3pm_app:terminal", "i3pm_project:nixos"])

        Raises:
            ValueError: If window_id not found
        """
        # T007: Query Sway tree for window
        tree = await self.sway.get_tree()

        def find_window(node):
            """Recursively search for window by ID."""
            if hasattr(node, 'id') and node.id == window_id:
                return node
            if hasattr(node, 'nodes'):
                for child in node.nodes:
                    found = find_window(child)
                    if found:
                        return found
            if hasattr(node, 'floating_nodes'):
                for child in node.floating_nodes:
                    found = find_window(child)
                    if found:
                        return found
            return None

        window = find_window(tree)
        if not window:
            raise ValueError(f"Window {window_id} not found")

        # Extract and filter i3pm_* marks
        all_marks = window.marks if hasattr(window, 'marks') else []
        i3pm_marks = [mark for mark in all_marks if mark.startswith("i3pm_")]

        return i3pm_marks

    async def get_mark_metadata(self, window_id: int) -> Optional[MarkMetadata]:
        """Get structured mark metadata for a window.

        Args:
            window_id: Sway container ID

        Returns:
            MarkMetadata instance or None if no i3pm_* marks found

        Raises:
            ValueError: If window_id not found or marks malformed
        """
        # T008: Query marks and parse
        marks = await self.get_window_marks(window_id)

        if not marks:
            return None

        try:
            return MarkMetadata.from_sway_marks(marks)
        except Exception as e:
            logger.warning(f"Failed to parse marks for window {window_id}: {e}")
            raise ValueError(f"Malformed marks on window {window_id}: {e}")

    async def find_windows(self, query: WindowMarkQuery) -> list[int]:
        """Find windows matching mark query.

        Args:
            query: WindowMarkQuery with filter criteria

        Returns:
            List of window IDs matching all query filters

        Raises:
            ValueError: If query is empty (no filters)
        """
        # T009: Validate query
        if query.is_empty:
            raise ValueError("Query must have at least one filter")

        # T046: Performance logging for window query
        start_time = time.perf_counter()

        # Query Sway tree
        tree = await self.sway.get_tree()
        matching_windows = []

        def walk_tree(node):
            """Recursively walk tree and collect matching windows."""
            # Check if this is a window node (has pid)
            if hasattr(node, 'pid') and node.pid and node.pid > 0:
                # Extract marks
                marks = node.marks if hasattr(node, 'marks') else []
                i3pm_marks = [mark for mark in marks if mark.startswith("i3pm_")]

                if not i3pm_marks:
                    # No marks - skip
                    pass
                else:
                    # Parse metadata and check if matches query
                    try:
                        metadata = MarkMetadata.from_sway_marks(i3pm_marks)

                        # Check all query filters (AND logic)
                        matches = True
                        if query.app and metadata.app != query.app:
                            matches = False
                        if query.project and metadata.project != query.project:
                            matches = False
                        if query.workspace and metadata.workspace != str(query.workspace):
                            matches = False
                        if query.scope and metadata.scope != query.scope:
                            matches = False
                        if query.custom_key:
                            if not metadata.custom or query.custom_key not in metadata.custom:
                                matches = False
                            elif query.custom_value:
                                if metadata.custom.get(query.custom_key) != query.custom_value:
                                    matches = False

                        if matches:
                            matching_windows.append(node.id)

                    except Exception as e:
                        logger.debug(f"Skipping window {node.id} - failed to parse marks: {e}")

            # Recurse into children
            if hasattr(node, 'nodes'):
                for child in node.nodes:
                    walk_tree(child)
            if hasattr(node, 'floating_nodes'):
                for child in node.floating_nodes:
                    walk_tree(child)

        walk_tree(tree)

        # T046: Log query performance
        elapsed_ms = (time.perf_counter() - start_time) * 1000
        logger.debug(
            f"Feature 076 Performance: Found {len(matching_windows)} windows "
            f"matching query in {elapsed_ms:.2f}ms (target: <20ms for 10 windows)"
        )

        return matching_windows

    async def cleanup_marks(self, window_id: int) -> int:
        """Remove all i3pm_* marks from window.

        Args:
            window_id: Sway container ID

        Returns:
            Number of marks removed

        Raises:
            ValueError: If window_id not found
        """
        # T046: Performance logging for mark cleanup
        start_time = time.perf_counter()

        # T010: Get marks and remove each one
        try:
            marks = await self.get_window_marks(window_id)
        except ValueError:
            # Window not found (may have been destroyed already)
            logger.debug(f"Window {window_id} not found during mark cleanup")
            raise

        removed_count = 0
        for mark in marks:
            try:
                cmd = f'[con_id={window_id}] unmark "{mark}"'
                result = await self.sway.command(cmd)
                if result and result[0].success:
                    removed_count += 1
                else:
                    error_msg = result[0].error if result else "Unknown error"
                    logger.warning(f"Failed to remove mark '{mark}' from window {window_id}: {error_msg}")
            except Exception as e:
                logger.warning(f"Error removing mark '{mark}' from window {window_id}: {e}")

        # T046: Log cleanup performance
        elapsed_ms = (time.perf_counter() - start_time) * 1000
        logger.debug(
            f"Feature 076 Performance: Cleaned up {removed_count} marks from window {window_id} "
            f"in {elapsed_ms:.2f}ms"
        )

        return removed_count

    async def count_instances(
        self,
        app_name: str,
        workspace: Optional[int] = None,
        project: Optional[str] = None
    ) -> int:
        """Count running instances of an app.

        Args:
            app_name: Application name from app-registry
            workspace: Optional workspace filter
            project: Optional project filter

        Returns:
            Number of matching windows
        """
        # T011: Build query and delegate to find_windows
        query = WindowMarkQuery(
            app=app_name,
            workspace=workspace,
            project=project
        )

        try:
            windows = await self.find_windows(query)
            return len(windows)
        except ValueError:
            # Empty query - should not happen since app_name is required
            return 0
