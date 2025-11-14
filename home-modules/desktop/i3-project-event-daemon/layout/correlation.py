"""Mark-based window correlation for Sway-compatible layout restoration.

Feature 074: Session Management
Tasks T046-T052: Mark-based correlation service for User Story 3

Replaces the broken swallow mechanism with environment variable injection
and mark-based window matching for Sway compatibility.
"""

import asyncio
import logging
import uuid
from typing import Optional

from .models import WindowPlaceholder, RestoreCorrelation, CorrelationStatus

logger = logging.getLogger(__name__)


class MarkBasedCorrelator:
    """Service for correlating restored windows using temporary marks (Feature 074: T046, US3).

    Workflow:
    1. Generate unique restoration mark (i3pm-restore-{8-char-hex})
    2. Inject I3PM_RESTORE_MARK environment variable
    3. Launch application with enhanced environment
    4. Poll Sway tree for window with matching mark
    5. Apply saved geometry to matched window
    6. Remove temporary restoration mark

    This approach replaces the broken swallow mechanism (swaywm/sway#1005)
    with a reliable mark-based correlation strategy.
    """

    def __init__(self, i3_connection):
        """Initialize mark-based correlator.

        Args:
            i3_connection: i3ipc connection instance (sync or async)
        """
        self.i3 = i3_connection

    def generate_restoration_mark(self) -> str:
        """Generate unique restoration mark for window correlation (T047, US3).

        Format: i3pm-restore-{8-char-hex}

        Returns:
            Unique restoration mark string
        """
        mark = f"i3pm-restore-{uuid.uuid4().hex[:8]}"
        logger.debug(f"Generated restoration mark: {mark}")
        return mark

    def inject_mark_env(self, placeholder: WindowPlaceholder, project: str) -> dict[str, str]:
        """Inject I3PM_RESTORE_MARK into environment for window launch (T048, US3).

        Calls placeholder.get_launch_env() which generates restoration mark
        and adds it to environment variables.

        Args:
            placeholder: Window placeholder with launch command
            project: Project name for I3PM_PROJECT env var

        Returns:
            Environment dictionary with I3PM_RESTORE_MARK and I3PM_PROJECT
        """
        env = placeholder.get_launch_env(project)
        logger.debug(
            f"Injected mark environment for {placeholder.window_class}: "
            f"I3PM_RESTORE_MARK={env.get('I3PM_RESTORE_MARK')}"
        )
        return env

    async def wait_for_window_with_mark(
        self,
        mark: str,
        timeout: float = 30.0,
        poll_interval: float = 0.1
    ) -> Optional[int]:
        """Poll Sway tree for window with restoration mark (T049, US3).

        Args:
            mark: Restoration mark to search for
            timeout: Maximum wait time in seconds (default: 30s)
            poll_interval: Time between polls in seconds (default: 0.1s)

        Returns:
            Window ID if found, None if timeout
        """
        logger.debug(f"Waiting for window with mark: {mark} (timeout: {timeout}s)")

        elapsed = 0.0
        while elapsed < timeout:
            # Query Sway tree
            tree = await self._get_tree()

            # Search for window with mark
            window_id = self._find_window_with_mark(tree, mark)
            if window_id:
                logger.info(f"Found window with mark {mark}: window_id={window_id} (elapsed: {elapsed:.2f}s)")
                return window_id

            # Wait before next poll
            await asyncio.sleep(poll_interval)
            elapsed += poll_interval

        logger.warning(f"Timeout waiting for window with mark: {mark} (waited {timeout}s)")
        return None

    async def apply_window_geometry(
        self,
        window_id: int,
        placeholder: WindowPlaceholder
    ) -> None:
        """Apply saved geometry to matched window (T050, US3).

        Args:
            window_id: ID of window to resize/reposition
            placeholder: Window placeholder with saved geometry
        """
        geometry = placeholder.geometry
        logger.debug(
            f"Applying geometry to window {window_id}: "
            f"{geometry.width}x{geometry.height}+{geometry.x}+{geometry.y}"
        )

        try:
            # Move and resize window using i3/Sway IPC commands
            await self._run_command(
                f'[con_id={window_id}] move position {geometry.x} {geometry.y}'
            )
            await self._run_command(
                f'[con_id={window_id}] resize set {geometry.width} {geometry.height}'
            )
            logger.info(f"Successfully applied geometry to window {window_id}")
        except Exception as e:
            logger.error(f"Failed to apply geometry to window {window_id}: {e}")
            raise

    async def remove_restoration_mark(self, window_id: int, mark: str) -> None:
        """Remove temporary restoration mark from window (T051, US3).

        Args:
            window_id: ID of window to unmark
            mark: Restoration mark to remove
        """
        logger.debug(f"Removing restoration mark {mark} from window {window_id}")

        try:
            await self._run_command(f'[con_id={window_id}] unmark {mark}')
            logger.debug(f"Successfully removed mark {mark} from window {window_id}")
        except Exception as e:
            logger.warning(f"Failed to remove mark {mark} from window {window_id}: {e}")
            # Non-fatal - mark will be automatically removed when window closes

    async def correlate_window(
        self,
        placeholder: WindowPlaceholder,
        project: str,
        timeout: float = 30.0
    ) -> RestoreCorrelation:
        """Orchestrate complete window correlation workflow (T052, US3).

        Full workflow:
        1. Generate restoration mark and inject into environment
        2. Launch application with enhanced environment
        3. Wait for window to appear with mark
        4. Apply saved geometry if window found
        5. Remove temporary mark
        6. Return correlation result

        Args:
            placeholder: Window placeholder to restore
            project: Project name for environment
            timeout: Maximum wait time for window appearance

        Returns:
            RestoreCorrelation tracking object with status and timing
        """
        # Use existing restoration mark if already set (and not placeholder value)
        # (Feature 074: restore.py pre-generates marks and passes to AppLauncher)
        has_mark = (
            hasattr(placeholder, 'restoration_mark') and
            placeholder.restoration_mark and
            placeholder.restoration_mark != "i3pm-restore-00000000"  # Exclude placeholder
        )
        if has_mark:
            mark = placeholder.restoration_mark
            logger.debug(f"Using pre-generated restoration mark: {mark}")
        else:
            mark = self.generate_restoration_mark()
            placeholder.restoration_mark = mark
            logger.debug(f"Generated new restoration mark: {mark} (placeholder was: {getattr(placeholder, 'restoration_mark', 'none')})")

        correlation = RestoreCorrelation(
            restoration_mark=mark,
            placeholder=placeholder
        )

        logger.info(
            f"Starting window correlation for {placeholder.window_class} "
            f"(mark: {mark}, timeout: {timeout}s)"
        )

        try:
            # Wait for window to appear
            window_id = await self.wait_for_window_with_mark(mark, timeout)

            if window_id:
                # Window found - apply geometry and cleanup
                await self.apply_window_geometry(window_id, placeholder)
                await self.remove_restoration_mark(window_id, mark)
                correlation.mark_matched(window_id)
                logger.info(
                    f"Window correlation succeeded for {placeholder.window_class}: "
                    f"window_id={window_id}, elapsed={correlation.elapsed_seconds:.2f}s"
                )
            else:
                # Timeout - no window appeared
                correlation.mark_timeout()
                logger.warning(
                    f"Window correlation timed out for {placeholder.window_class}: "
                    f"no window with mark {mark} appeared within {timeout}s"
                )

        except Exception as e:
            # Correlation failed with error
            correlation.mark_failed(str(e))
            logger.error(
                f"Window correlation failed for {placeholder.window_class}: {e}",
                exc_info=True
            )

        return correlation

    # ========================================================================
    # Internal Helper Methods
    # ========================================================================

    async def _get_tree(self):
        """Get i3/Sway window tree (handles both sync and async connections)"""
        # ResilientI3Connection wrapper - access .conn for actual i3ipc connection
        if hasattr(self.i3, 'conn') and self.i3.conn:
            return await self.i3.conn.get_tree()
        else:
            # Direct i3ipc connection (fallback for testing)
            if hasattr(self.i3, 'get_tree'):
                # Sync i3ipc
                return self.i3.get_tree()
            else:
                # Async i3ipc
                return await self.i3.get_tree()

    async def _run_command(self, command: str):
        """Run i3/Sway IPC command (handles both sync and async connections)"""
        # ResilientI3Connection wrapper - access .conn for actual i3ipc connection
        if hasattr(self.i3, 'conn') and self.i3.conn:
            return await self.i3.conn.command(command)
        else:
            # Direct i3ipc connection (fallback for testing)
            if hasattr(self.i3, 'command'):
                # Sync i3ipc
                return self.i3.command(command)
            else:
                # Async i3ipc
                return await self.i3.command(command)

    def _find_window_with_mark(self, node, mark: str) -> Optional[int]:
        """Recursively search tree for window with specific mark.

        Args:
            node: Current tree node to search
            mark: Mark to search for

        Returns:
            Window ID if found, None otherwise
        """
        # Check if this node has the mark
        if hasattr(node, 'marks') and node.marks and mark in node.marks:
            # Check if this is a window (has window ID)
            if hasattr(node, 'window') and node.window and node.window > 0:
                return node.window

        # Recursively search children
        if hasattr(node, 'nodes') and node.nodes:
            for child in node.nodes:
                window_id = self._find_window_with_mark(child, mark)
                if window_id:
                    return window_id

        # Also check floating nodes
        if hasattr(node, 'floating_nodes') and node.floating_nodes:
            for child in node.floating_nodes:
                window_id = self._find_window_with_mark(child, mark)
                if window_id:
                    return window_id

        return None
