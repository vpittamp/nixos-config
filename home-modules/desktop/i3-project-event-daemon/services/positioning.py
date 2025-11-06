"""
Boundary Detection and Terminal Positioning (Feature 051)

Implements i3run's mouse-aware positioning algorithm with quadrant-based
boundary constraints. Prevents terminals from rendering off-screen by
applying configurable gap constraints based on cursor quadrant.

Algorithm phases:
1. Calculate constraint boundaries (break_x, break_y)
2. Get cursor position (via CursorPositioner)
3. Calculate temporary position (center on cursor)
4. Apply vertical constraints based on vertical quadrant
5. Apply horizontal constraints based on horizontal quadrant
6. Return final TerminalPosition
"""

import logging
from typing import Tuple

from ..models.scratchpad_enhancement import (
    WorkspaceGeometry,
    WindowDimensions,
    CursorPosition,
    TerminalPosition,
    GapConfig,
)

logger = logging.getLogger(__name__)


class BoundaryDetectionAlgorithm:
    """
    Mouse-aware window positioning with automatic boundary detection.

    Based on i3run's sendtomouse algorithm with quadrant-based constraints.
    """

    def __init__(self, gaps: GapConfig):
        """
        Initialize boundary detection algorithm.

        Args:
            gaps: Gap configuration for screen edge constraints
        """
        self.gaps = gaps

    def calculate_position(
        self,
        cursor: CursorPosition,
        window: WindowDimensions,
        workspace: WorkspaceGeometry,
    ) -> TerminalPosition:
        """
        Calculate terminal position with boundary constraints.

        Algorithm:
        1. Calculate constraint boundaries
        2. Center window on cursor (temporary position)
        3. Apply vertical constraints based on cursor vertical quadrant
        4. Apply horizontal constraints based on cursor horizontal quadrant

        Args:
            cursor: Current cursor position
            window: Terminal window dimensions
            workspace: Workspace geometry with gaps

        Returns:
            TerminalPosition with final x, y coordinates
        """
        # Phase 1: Calculate constraint boundaries
        break_y = workspace.y_offset + workspace.height - (self.gaps.bottom + window.height)
        break_x = workspace.x_offset + workspace.width - (self.gaps.right + window.width)

        min_y = workspace.y_offset + self.gaps.top
        min_x = workspace.x_offset + self.gaps.left

        logger.debug(
            f"Constraint boundaries: x=[{min_x}, {break_x}], y=[{min_y}, {break_y}]"
        )

        # Phase 2: Calculate temporary position (center on cursor)
        temp_y = cursor.y - (window.height // 2)
        temp_x = cursor.x - (window.width // 2)

        logger.debug(
            f"Temporary position (centered on cursor): ({temp_x}, {temp_y})"
        )

        # Phase 3: Determine cursor quadrants
        vertical_midpoint = workspace.y_offset + (workspace.height // 2)
        horizontal_midpoint = workspace.x_offset + (workspace.width // 2)

        in_lower_half = cursor.y > vertical_midpoint
        in_right_half = cursor.x >= horizontal_midpoint

        logger.debug(
            f"Cursor quadrant: {'lower' if in_lower_half else 'upper'}-"
            f"{'right' if in_right_half else 'left'}"
        )

        # Phase 4: Apply vertical constraint (quadrant-based)
        if in_lower_half:
            # Lower half: constrain bottom edge
            new_y = min(temp_y, break_y) if temp_y > break_y else temp_y
        else:
            # Upper half: constrain top edge
            new_y = max(temp_y, min_y) if temp_y < min_y else temp_y

        # Phase 5: Apply horizontal constraint (quadrant-based)
        if in_right_half:
            # Right half: constrain right edge
            new_x = min(temp_x, break_x) if temp_x > break_x else temp_x
        else:
            # Left half: constrain left edge
            new_x = max(temp_x, min_x) if temp_x < min_x else temp_x

        # Check if position was constrained
        constrained = (new_x != temp_x) or (new_y != temp_y)

        if constrained:
            logger.info(
                f"Position constrained: ({temp_x}, {temp_y}) → ({new_x}, {new_y})"
            )
        else:
            logger.debug(f"Position not constrained: ({new_x}, {new_y})")

        return TerminalPosition(
            x=new_x,
            y=new_y,
            width=window.width,
            height=window.height,
            workspace_num=workspace.workspace_num,
            monitor_name=workspace.monitor_name,
            constrained_by_gaps=constrained,
            cursor_position=cursor,
        )

    def validate_workspace_geometry(self, workspace: WorkspaceGeometry) -> bool:
        """
        Validate that workspace has sufficient space after applying gaps.

        Args:
            workspace: Workspace geometry to validate

        Returns:
            True if workspace has positive available space, False otherwise
        """
        if workspace.available_width <= 0:
            logger.error(
                f"Workspace {workspace.monitor_name} has no available width "
                f"after gaps (width={workspace.width}, "
                f"gaps={self.gaps.left}+{self.gaps.right})"
            )
            return False

        if workspace.available_height <= 0:
            logger.error(
                f"Workspace {workspace.monitor_name} has no available height "
                f"after gaps (height={workspace.height}, "
                f"gaps={self.gaps.top}+{self.gaps.bottom})"
            )
            return False

        return True

    def handle_oversized_window(
        self,
        window: WindowDimensions,
        workspace: WorkspaceGeometry,
    ) -> WindowDimensions:
        """
        Scale window to fit within workspace if it's oversized.

        Args:
            window: Terminal window dimensions
            workspace: Workspace geometry

        Returns:
            Scaled WindowDimensions or original if it fits
        """
        if window.fits_in_workspace(workspace):
            logger.debug(
                f"Window ({window.width}x{window.height}) fits in workspace "
                f"({workspace.available_width}x{workspace.available_height})"
            )
            return window

        scaled = window.scale_to_fit(workspace)
        logger.warning(
            f"Window oversized, scaled from ({window.width}x{window.height}) "
            f"to ({scaled.width}x{scaled.height})"
        )
        return scaled


class MultiMonitorPositioner:
    """
    Position windows across multiple monitors with coordinate translation.

    Handles negative monitor coordinates and ensures windows are positioned
    on the monitor containing the cursor.
    """

    def __init__(self):
        """Initialize multi-monitor positioner."""
        pass

    def find_monitor_for_cursor(
        self,
        cursor: CursorPosition,
        workspaces: list[WorkspaceGeometry],
    ) -> WorkspaceGeometry:
        """
        Find which monitor contains the cursor.

        Args:
            cursor: Current cursor position
            workspaces: List of all workspace geometries

        Returns:
            WorkspaceGeometry for the monitor containing cursor

        Raises:
            ValueError: If cursor is not within any monitor bounds
        """
        for workspace in workspaces:
            if workspace.contains_point(cursor.x, cursor.y):
                logger.debug(
                    f"Cursor at ({cursor.x}, {cursor.y}) is on monitor "
                    f"{workspace.monitor_name}"
                )
                return workspace

        # Fallback: Find closest monitor
        logger.warning(
            f"Cursor at ({cursor.x}, {cursor.y}) not within any monitor, "
            f"using closest"
        )
        return self._find_closest_monitor(cursor, workspaces)

    def _find_closest_monitor(
        self,
        cursor: CursorPosition,
        workspaces: list[WorkspaceGeometry],
    ) -> WorkspaceGeometry:
        """
        Find monitor closest to cursor position.

        Args:
            cursor: Cursor position
            workspaces: List of workspace geometries

        Returns:
            Closest WorkspaceGeometry
        """
        if not workspaces:
            raise ValueError("No workspaces available")

        def distance_to_monitor(ws: WorkspaceGeometry) -> float:
            """Calculate Manhattan distance from cursor to monitor center."""
            return abs(cursor.x - ws.center_x) + abs(cursor.y - ws.center_y)

        closest = min(workspaces, key=distance_to_monitor)
        logger.info(
            f"Using closest monitor: {closest.monitor_name} at "
            f"({closest.center_x}, {closest.center_y})"
        )
        return closest
