"""
Cursor Position Service (Feature 051)

Provides mouse cursor position query with 3-tier fallback strategy:
1. xdotool query (primary, <100ms)
2. Cached position (if <2 seconds old)
3. Workspace center (always available)

Uses xdotool for cross-platform cursor position detection (X11/XWayland).
"""

import asyncio
import logging
import time
from typing import Optional, Dict, Tuple
from pathlib import Path

from ..models.scratchpad_enhancement import CursorPosition, WorkspaceGeometry

logger = logging.getLogger(__name__)


class CursorPositioner:
    """
    Query mouse cursor position with fallback strategies.

    Tier 1: xdotool query (primary method, <100ms)
    Tier 2: Cached position (if recent, <2s old)
    Tier 3: Workspace center (guaranteed fallback)
    """

    def __init__(self, cache_max_age: float = 2.0, query_timeout: float = 0.5):
        """
        Initialize cursor positioner.

        Args:
            cache_max_age: Maximum age in seconds for cached position (default: 2.0)
            query_timeout: Timeout in seconds for xdotool query (default: 0.5)
        """
        self.cache_max_age = cache_max_age
        self.query_timeout = query_timeout

        # Cache
        self._cached_position: Optional[CursorPosition] = None
        self._cache_timestamp: float = 0.0

        # Statistics
        self._stats = {
            "xdotool_success": 0,
            "xdotool_failure": 0,
            "cache_hits": 0,
            "workspace_center_fallback": 0,
        }

    async def get_cursor_position(
        self,
        workspace: WorkspaceGeometry,
        use_cache: bool = True
    ) -> CursorPosition:
        """
        Get current cursor position with 3-tier fallback.

        Args:
            workspace: Current workspace geometry for center fallback
            use_cache: Whether to use cached position if available

        Returns:
            CursorPosition with x, y coordinates and metadata
        """
        # Tier 1: Try xdotool query
        try:
            position = await self._query_dotool()  # Method name kept for compatibility
            if position:
                self._update_cache(position)
                self._stats["xdotool_success"] += 1
                logger.debug(f"Cursor position from xdotool: ({position.x}, {position.y})")
                return position
        except Exception as e:
            logger.warning(f"xdotool query failed: {e}")
            self._stats["xdotool_failure"] += 1

        # Tier 2: Try cached position
        if use_cache and self._is_cache_valid():
            logger.debug(f"Using cached cursor position: ({self._cached_position.x}, {self._cached_position.y})")
            self._stats["cache_hits"] += 1
            return self._cached_position

        # Tier 3: Fallback to workspace center
        logger.info(f"Falling back to workspace center: ({workspace.center_x}, {workspace.center_y})")
        self._stats["workspace_center_fallback"] += 1
        return CursorPosition(
            x=workspace.center_x,
            y=workspace.center_y,
            valid=True,
            source="center",
            timestamp=time.time()
        )

    async def _query_dotool(self) -> Optional[CursorPosition]:
        """
        Query cursor position using xdotool.

        xdotool provides getmouselocation command that returns coordinates.
        Output format: X=500 Y=300 SCREEN=0 WINDOW=12345

        Returns:
            CursorPosition or None if query fails

        Raises:
            asyncio.TimeoutError: If query exceeds timeout
            FileNotFoundError: If xdotool is not installed
        """
        try:
            # Run xdotool getmouselocation
            process = await asyncio.create_subprocess_exec(
                'xdotool',
                'getmouselocation',
                '--shell',
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE
            )

            stdout, stderr = await asyncio.wait_for(
                process.communicate(),
                timeout=self.query_timeout
            )

            if process.returncode != 0:
                logger.error(f"xdotool failed with code {process.returncode}: {stderr.decode()}")
                return None

            # Parse output: X=500\nY=300\nSCREEN=0\nWINDOW=12345
            output = stdout.decode('utf-8', errors='ignore')
            coords = {}
            for line in output.strip().split('\n'):
                if '=' in line:
                    key, value = line.split('=', 1)
                    coords[key] = value

            if 'X' not in coords or 'Y' not in coords:
                logger.error(f"Invalid xdotool output: {output}")
                return None

            return CursorPosition(
                x=int(coords['X']),
                y=int(coords['Y']),
                screen=int(coords.get('SCREEN', '0')),
                window_id=int(coords.get('WINDOW', '0')) if coords.get('WINDOW') else None,
                valid=True,
                source="xdotool",
                timestamp=time.time()
            )

        except asyncio.TimeoutError:
            logger.warning(f"xdotool query timed out after {self.query_timeout}s")
            return None
        except FileNotFoundError:
            logger.error("xdotool not found in PATH - ensure it's installed")
            return None
        except (ValueError, KeyError) as e:
            logger.error(f"Failed to parse xdotool output: {e}")
            return None
        except Exception as e:
            logger.error(f"Unexpected error querying xdotool: {e}")
            return None

    async def _query_cursor_via_sway(self) -> Optional[CursorPosition]:
        """
        Query cursor position via Sway IPC get_seats.

        This is the preferred method for Sway/Wayland, as dotool doesn't
        provide direct cursor position query like xdotool does.

        Returns:
            CursorPosition or None if query fails
        """
        try:
            # Use swaymsg to query seat information
            process = await asyncio.create_subprocess_exec(
                'swaymsg',
                '-t', 'get_seats',
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE
            )

            stdout, stderr = await asyncio.wait_for(
                process.communicate(),
                timeout=self.query_timeout
            )

            if process.returncode != 0:
                logger.error(f"swaymsg failed: {stderr.decode()}")
                return None

            # Parse JSON output
            import json
            seats = json.loads(stdout.decode())

            # Find default seat and extract cursor position
            for seat in seats:
                if 'pointer' in seat and seat['pointer']:
                    # Sway doesn't directly expose cursor coordinates in get_seats
                    # We need to use a different approach
                    logger.warning("Sway IPC doesn't expose cursor coordinates directly")
                    return None

            return None

        except Exception as e:
            logger.error(f"Failed to query cursor via Sway IPC: {e}")
            return None

    def _update_cache(self, position: CursorPosition) -> None:
        """Update cached cursor position."""
        self._cached_position = position
        self._cache_timestamp = time.time()

    def _is_cache_valid(self) -> bool:
        """Check if cached position is still valid."""
        if not self._cached_position:
            return False

        age = time.time() - self._cache_timestamp
        return age < self.cache_max_age

    def get_stats(self) -> Dict[str, int]:
        """Get cursor query statistics."""
        return self._stats.copy()

    def clear_cache(self) -> None:
        """Clear cached cursor position."""
        self._cached_position = None
        self._cache_timestamp = 0.0
        logger.debug("Cursor position cache cleared")


# TEMPORARY: Use wlr-randr as a workaround until we implement proper cursor tracking
# wlr-randr can give us output information, but not cursor position
# For now, we'll implement a simple cursor position tracker that:
# 1. Tracks last known window focus
# 2. Uses window geometry center as cursor approximation
# 3. Falls back to workspace center if no focused window

class SimpleCursorTracker:
    """
    Simplified cursor position tracker for Wayland.

    Since direct cursor position query is not straightforward in Wayland,
    this tracker uses focused window geometry as a proxy for cursor position.
    """

    def __init__(self):
        self._last_focused_geometry: Optional[Tuple[int, int]] = None

    def update_from_focused_window(self, rect: Dict[str, int]) -> None:
        """
        Update cursor approximation from focused window geometry.

        Args:
            rect: Window rectangle dict with x, y, width, height keys
        """
        center_x = rect['x'] + rect['width'] // 2
        center_y = rect['y'] + rect['height'] // 2
        self._last_focused_geometry = (center_x, center_y)
        logger.debug(f"Updated cursor approximation from focused window: ({center_x}, {center_y})")

    def get_approximate_position(self, workspace: WorkspaceGeometry) -> CursorPosition:
        """
        Get approximate cursor position.

        Args:
            workspace: Workspace geometry for fallback

        Returns:
            CursorPosition based on last focused window or workspace center
        """
        if self._last_focused_geometry:
            x, y = self._last_focused_geometry
            return CursorPosition(
                x=x,
                y=y,
                valid=True,
                source="focused_window",
                timestamp=time.time()
            )

        # Fallback to workspace center
        return CursorPosition(
            x=workspace.center_x,
            y=workspace.center_y,
            valid=True,
            source="workspace_center",
            timestamp=time.time()
        )
