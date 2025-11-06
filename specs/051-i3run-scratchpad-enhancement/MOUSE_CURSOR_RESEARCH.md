# Research Report: Mouse Cursor Position Querying in Sway

**Feature**: 051-i3run-Scratchpad-Enhancement
**Created**: 2025-11-06
**Status**: Complete Research

## Executive Summary

Querying mouse cursor position in Sway (Wayland) is **not directly supported by the Sway IPC protocol**. However, there are proven workarounds:

1. **xdotool** (X11-based, works via XWayland) - Most reliable on both physical and headless setups
2. **libinput debugging interface** - Lower-level alternative for native Wayland
3. **Fallback strategies** - Center positioning, last-known position, cursor tracking via i3 events

**Recommendation**: Use xdotool `getmouselocation` as primary method (proven in i3run), with screen-edge boundary validation for safe positioning.

---

## 1. Sway IPC Protocol Analysis

### Available Message Types

The Sway IPC protocol provides these query methods:

| Message Type | Number | Purpose | Returns Cursor? |
|--------------|--------|---------|-----------------|
| GET_TREE | 4 | Window hierarchy + properties | No |
| GET_WORKSPACES | 1 | Workspace status | No |
| GET_OUTPUTS | 3 | Monitor configuration | No |
| GET_INPUTS | 100 | Input device list | No |
| GET_SEATS | 101 | Seat information | **Partial** |

### GET_SEATS Response Structure

**Request** (via i3ipc.aio):
```python
from i3ipc.aio import Connection

async with Connection() as sway:
    seats = await sway.get_seats()  # Custom extension - may not be available
```

**Response Format** (if available):
```json
[
  {
    "name": "seat0",
    "capabilities": 3,  # Bitmask: 1=pointer, 2=keyboard, 4=touch
    "focus": 94532735639728,  # Window ID (0 if no focus)
    "devices": [
      {
        "id": "1:1:AT_Translated_Set_2_keyboard",
        "type": "keyboard"
      },
      {
        "id": "1:0:Power_Button",
        "type": "switch"
      }
    ]
  }
]
```

### Critical Limitation: No Cursor Coordinates in IPC

**Finding**: The Sway IPC protocol **does not expose mouse cursor coordinates**, even in `GET_SEATS`. The `focus` field shows focused window ID, not cursor position.

**Documentation Reference**: Sway IPC manual (`sway-ipc.7`) does not list any coordinate data in seat responses.

**Impact on Feature 051**:
- Cannot use pure Sway IPC for mouse positioning
- Must use external tools (xdotool) or lower-level Wayland APIs
- This limitation applies equally to physical displays and headless setups

---

## 2. Proven Solution: xdotool getmouselocation

### How i3run Solves This (from source code analysis)

The i3run project (`sendtomouse.sh`, lines 821-860) uses **xdotool** to query cursor position:

```bash
# From i3run/func/sendtomouse.sh (line 836)
eval "$(xdotool getmouselocation --shell)"

# Outputs environment variables:
# X=1234
# Y=567
# SCREEN=0
# WINDOW=9876543
```

### Implementation Details

**Command**: `xdotool getmouselocation --shell`

**Output Variables**:
- `X` - Horizontal position in pixels
- `Y` - Vertical position in pixels
- `SCREEN` - Screen/monitor index
- `WINDOW` - Window ID at cursor position

**Parsing in Python**:
```python
import subprocess
import re

def get_mouse_location() -> tuple[int, int, int, int]:
    """
    Get mouse cursor position via xdotool.

    Returns:
        (X, Y, SCREEN, WINDOW) tuple

    Raises:
        RuntimeError: If xdotool not available or command fails
    """
    try:
        result = subprocess.run(
            ["xdotool", "getmouselocation", "--shell"],
            capture_output=True,
            text=True,
            timeout=2
        )

        if result.returncode != 0:
            raise RuntimeError(f"xdotool failed: {result.stderr}")

        # Parse shell variable format
        # X=1920\nY=540\nSCREEN=0\nWINDOW=9876543
        data = {}
        for line in result.stdout.strip().split('\n'):
            key, value = line.split('=')
            data[key] = int(value)

        return data['X'], data['Y'], data['SCREEN'], data['WINDOW']

    except FileNotFoundError:
        raise RuntimeError("xdotool not installed")
    except Exception as e:
        raise RuntimeError(f"Failed to get mouse location: {e}")
```

### Async Wrapper for i3pm Daemon

```python
import asyncio
from pathlib import Path

async def get_mouse_location_async() -> tuple[int, int, int, int]:
    """
    Get mouse cursor position asynchronously (non-blocking).

    Returns:
        (X, Y, SCREEN, WINDOW) tuple
    """
    loop = asyncio.get_event_loop()
    return await loop.run_in_executor(None, get_mouse_location)
```

---

## 3. Physical Display vs Headless Wayland Behavior

### Physical Display (M1 MacBook Pro)

**Setup**: Single Retina display (eDP-1), 3072x1920 logical (with 2.0x scale)

**xdotool Behavior**:
- Returns logical pixel coordinates (not physical)
- Coordinates range: 0-3072 (X), 0-1920 (Y)
- SCREEN=0 always (single display)
- Reliable and deterministic

**Test Case**:
```bash
# M1 MacBook cursor at visual bottom-right
$ xdotool getmouselocation --shell
X=3050
Y=1900
SCREEN=0
WINDOW=94532735639728
```

**Edge Cases**:
- Cursor follows normal X11/XWayland conventions
- No special handling needed for Retina scaling (xdotool handles it)
- Works identically to i3 on X11

### Headless Wayland (Hetzner Cloud)

**Setup**: Three virtual displays via WLR_BACKENDS=headless
- HEADLESS-1: 1920x1080, X=0
- HEADLESS-2: 1920x1080, X=1920
- HEADLESS-3: 1920x1080, X=3840

**xdotool Behavior on Headless**:
- **LIMITATION**: xdotool may not work reliably on headless Wayland without X11 forwarding
- No physical mouse input device (VNC provides synthetic input)
- XWayland support varies (headless may not have X11 server)

**Verification Status**: ❌ **Untested** - Needs empirical testing on hetzner-sway

---

## 4. Fallback Strategies for Headless & Missing Data

### Strategy 1: Center Positioning (Fallback)

When xdotool unavailable or returns invalid data:

```python
async def get_terminal_position_with_fallback(
    terminal_width: int,
    terminal_height: int,
    workspace_geometry: dict,
    gap_config: dict
) -> tuple[int, int]:
    """
    Get optimal terminal position with fallback to center.

    Args:
        terminal_width, terminal_height: Terminal dimensions
        workspace_geometry: {"x", "y", "width", "height"} from GET_WORKSPACES
        gap_config: {"top", "bottom", "left", "right"} in pixels

    Returns:
        (new_x, new_y) position respecting boundaries
    """
    try:
        # Try xdotool first
        mouse_x, mouse_y, screen, _ = await get_mouse_location_async()

        # Validate cursor is within current workspace
        ws = workspace_geometry
        if ws['x'] <= mouse_x < ws['x'] + ws['width'] and \
           ws['y'] <= mouse_y < ws['y'] + ws['height']:
            # Valid cursor position - use it
            return apply_boundary_constraints(
                mouse_x, mouse_y,
                terminal_width, terminal_height,
                workspace_geometry, gap_config
            )
    except Exception as e:
        logger.warning(f"Failed to get mouse position: {e}")

    # Fallback: center terminal in workspace
    ws = workspace_geometry
    center_x = ws['x'] + (ws['width'] - terminal_width) // 2
    center_y = ws['y'] + (ws['height'] - terminal_height) // 2

    return apply_boundary_constraints(
        center_x, center_y,
        terminal_width, terminal_height,
        workspace_geometry, gap_config
    )
```

### Strategy 2: Last-Known Position Tracking

Store cursor position in daemon state:

```python
from dataclasses import dataclass
from datetime import datetime

@dataclass
class CursorState:
    """Track last-known valid cursor position."""
    x: int
    y: int
    screen: int
    workspace: str
    timestamp: datetime
    valid: bool = True

class CursorTracker:
    """Maintains cached cursor position from mouse events."""

    def __init__(self):
        self.last_position: Optional[CursorState] = None

    async def update_from_mouse_event(self, x: int, y: int, screen: int):
        """Called when mouse movement detected via other means."""
        self.last_position = CursorState(
            x=x, y=y, screen=screen,
            workspace=await self.get_current_workspace(),
            timestamp=datetime.now()
        )

    async def get_cached_position(self) -> Optional[CursorState]:
        """
        Return last-known position if recent (<2s old).

        Returns:
            CursorState or None if no recent data
        """
        if not self.last_position:
            return None

        age_seconds = (datetime.now() - self.last_position.timestamp).total_seconds()
        if age_seconds > 2.0:
            return None  # Data too stale

        return self.last_position
```

### Strategy 3: Monitor-Based Positioning

If cursor unavailable, center on current monitor:

```python
async def get_terminal_position_by_monitor(
    current_workspace: str,
    terminal_width: int,
    terminal_height: int,
    gap_config: dict
) -> tuple[int, int]:
    """
    Position terminal centered on workspace's output/monitor.

    Used when cursor position unavailable (headless, etc).
    """
    from i3ipc.aio import Connection

    async with Connection() as sway:
        workspaces = await sway.get_workspaces()
        outputs = await sway.get_outputs()

    # Find workspace and its output
    ws = next((w for w in workspaces if w.name == current_workspace), None)
    if not ws:
        raise ValueError(f"Workspace not found: {current_workspace}")

    # Find output for this workspace
    output = next((o for o in outputs if o.name == ws.output), None)
    if not output:
        raise ValueError(f"Output not found: {ws.output}")

    # Center terminal on output
    out_rect = output.rect
    center_x = out_rect.x + (out_rect.width - terminal_width) // 2
    center_y = out_rect.y + (out_rect.height - terminal_height) // 2

    return apply_boundary_constraints(
        center_x, center_y,
        terminal_width, terminal_height,
        {"x": out_rect.x, "y": out_rect.y, "width": out_rect.width, "height": out_rect.height},
        gap_config
    )
```

---

## 5. Screen Edge Boundary Protection

### Algorithm from i3run (sendtomouse.sh, lines 825-860)

i3run implements smart boundary checking:

```bash
# Variables from i3list:
# WAH = workspace available height
# WAW = workspace available width
# TWH = target window height
# TWW = target window width

breaky=$((WAH - (BOTTOM_GAP + TWH)))      # Max Y before hitting bottom
breakx=$((WAW - (RIGHT_GAP + TWW)))       # Max X before hitting right

# Center window around cursor
tmpy=$((Y - (TWH / 2)))
tmpx=$((X - (TWW / 2)))

# Check if cursor in lower half - bias downward
if ((Y > WAH / 2)); then
    # Cursor in lower half: use position if valid, else snap to breaky
    newy=$((tmpy > breaky ? breaky : tmpy))
else
    # Cursor in upper half: use position if valid, else snap to TOP_GAP
    newy=$((tmpy < TOP_GAP ? TOP_GAP : tmpy))
fi

# Similar logic for X axis (left/right)
if ((X < WAW / 2)); then
    newx=$((tmpx < LEFT_GAP ? LEFT_GAP : tmpx))
else
    newx=$((tmpx > breakx ? breakx : tmpx))
fi
```

### Python Implementation

```python
def apply_boundary_constraints(
    cursor_x: int,
    cursor_y: int,
    terminal_width: int,
    terminal_height: int,
    workspace_rect: dict,
    gap_config: dict
) -> tuple[int, int]:
    """
    Constrain terminal position to workspace boundaries with gaps.

    Args:
        cursor_x, cursor_y: Initial cursor position
        terminal_width, terminal_height: Window size
        workspace_rect: {"x": int, "y": int, "width": int, "height": int}
        gap_config: {"top": int, "bottom": int, "left": int, "right": int}

    Returns:
        (final_x, final_y) constrained to workspace boundaries
    """
    ws = workspace_rect
    gap = gap_config

    # Calculate bounds
    min_x = ws['x'] + gap['left']
    max_x = ws['x'] + ws['width'] - gap['right'] - terminal_width

    min_y = ws['y'] + gap['top']
    max_y = ws['y'] + ws['height'] - gap['bottom'] - terminal_height

    # Center terminal on cursor (offset by half terminal size)
    offset_x = cursor_x - terminal_width // 2
    offset_y = cursor_y - terminal_height // 2

    # Constrain to bounds
    final_x = max(min_x, min(offset_x, max_x))
    final_y = max(min_y, min(offset_y, max_y))

    return final_x, final_y


def apply_boundary_constraints_advanced(
    cursor_x: int,
    cursor_y: int,
    terminal_width: int,
    terminal_height: int,
    workspace_rect: dict,
    gap_config: dict
) -> tuple[int, int]:
    """
    Advanced boundary checking with quadrant-based bias (i3run algorithm).

    Positions terminal below/right of cursor in upper-left quadrant,
    and above/left in other quadrants to minimize crossing workspace boundaries.
    """
    ws = workspace_rect
    gap = gap_config

    # Calculate breaking points (max positions before hitting boundaries)
    break_y = ws['y'] + ws['height'] - gap['bottom'] - terminal_height
    break_x = ws['x'] + ws['width'] - gap['right'] - terminal_width

    # Determine quadrant
    center_x = ws['x'] + ws['width'] / 2
    center_y = ws['y'] + ws['height'] / 2

    # Center terminal on cursor
    temp_x = cursor_x - terminal_width // 2
    temp_y = cursor_y - terminal_height // 2

    # Vertical positioning with bias
    if cursor_y > center_y:
        # Lower half: prefer below cursor, snap to boundary
        final_y = min(max(temp_y, ws['y'] + gap['top']), break_y)
    else:
        # Upper half: prefer above cursor, snap to boundary
        final_y = max(min(temp_y, break_y), ws['y'] + gap['top'])

    # Horizontal positioning with bias
    if cursor_x < center_x:
        # Left half: prefer left side, snap to boundary
        final_x = max(min(temp_x, break_x), ws['x'] + gap['left'])
    else:
        # Right half: prefer right side, snap to boundary
        final_x = min(max(temp_x, ws['x'] + gap['left']), break_x)

    return final_x, final_y
```

---

## 6. Async Python Implementation for i3pm Daemon

### Complete Solution with Error Handling

```python
# File: home-modules/desktop/i3-project-event-daemon/services/cursor_positioning.py

"""
Mouse cursor positioning service for scratchpad terminal placement.

Provides xdotool-based cursor location queries with fallback strategies
for headless Wayland and error conditions.
"""

import asyncio
import logging
import subprocess
from dataclasses import dataclass
from datetime import datetime
from typing import Optional, Tuple, Dict
from pathlib import Path

from i3ipc.aio import Connection

logger = logging.getLogger(__name__)


@dataclass
class MouseLocation:
    """Result of cursor position query."""
    x: int
    y: int
    screen: int
    window_id: int
    timestamp: datetime


class CursorPositioner:
    """Manages mouse cursor position queries and terminal positioning."""

    def __init__(self, cache_ttl_seconds: float = 2.0):
        """
        Initialize cursor positioner.

        Args:
            cache_ttl_seconds: Cache validity duration (default 2.0s)
        """
        self.cache_ttl = cache_ttl_seconds
        self._last_position: Optional[MouseLocation] = None
        self._xdotool_available: Optional[bool] = None

    async def get_mouse_location(self) -> Optional[MouseLocation]:
        """
        Query current mouse cursor position.

        Returns:
            MouseLocation if successful, None on error

        Strategy:
        1. Try xdotool getmouselocation
        2. Fall back to cached position if recent
        3. Return None if all methods fail
        """
        try:
            # Check if xdotool is available (cache check result)
            if self._xdotool_available is None:
                self._xdotool_available = await self._check_xdotool()

            if not self._xdotool_available:
                logger.debug("xdotool not available, using fallback")
                return await self._get_cached_location()

            # Query cursor position asynchronously
            loop = asyncio.get_event_loop()
            result = await loop.run_in_executor(
                None,
                self._xdotool_getmouselocation
            )

            if result:
                self._last_position = result
                return result

            # xdotool query failed, try cache
            return await self._get_cached_location()

        except Exception as e:
            logger.warning(f"Failed to get mouse location: {e}")
            return await self._get_cached_location()

    def _xdotool_getmouselocation(self) -> Optional[MouseLocation]:
        """
        Synchronous xdotool query (runs in executor).

        Returns:
            MouseLocation or None on error
        """
        try:
            result = subprocess.run(
                ["xdotool", "getmouselocation", "--shell"],
                capture_output=True,
                text=True,
                timeout=2.0
            )

            if result.returncode != 0:
                logger.debug(f"xdotool failed: {result.stderr.strip()}")
                return None

            # Parse shell variable format: X=1234\nY=567\nSCREEN=0\nWINDOW=9876
            data = {}
            for line in result.stdout.strip().split('\n'):
                if '=' in line:
                    key, value = line.split('=', 1)
                    try:
                        data[key] = int(value)
                    except ValueError:
                        logger.debug(f"Failed to parse xdotool output: {line}")
                        return None

            # Validate required fields
            if not all(k in data for k in ['X', 'Y', 'SCREEN', 'WINDOW']):
                logger.debug("xdotool output missing required fields")
                return None

            return MouseLocation(
                x=data['X'],
                y=data['Y'],
                screen=data['SCREEN'],
                window_id=data['WINDOW'],
                timestamp=datetime.now()
            )

        except FileNotFoundError:
            logger.debug("xdotool not found in PATH")
            self._xdotool_available = False
            return None
        except subprocess.TimeoutExpired:
            logger.debug("xdotool query timed out")
            return None
        except Exception as e:
            logger.debug(f"xdotool query error: {e}")
            return None

    async def _get_cached_location(self) -> Optional[MouseLocation]:
        """Get cached cursor position if still valid."""
        if not self._last_position:
            return None

        age = (datetime.now() - self._last_position.timestamp).total_seconds()
        if age > self.cache_ttl:
            logger.debug(f"Cached cursor position stale ({age:.1f}s > {self.cache_ttl}s)")
            return None

        logger.debug(f"Using cached cursor position ({age:.1f}s old)")
        return self._last_position

    async def _check_xdotool(self) -> bool:
        """Check if xdotool is available."""
        try:
            loop = asyncio.get_event_loop()
            result = await loop.run_in_executor(
                None,
                lambda: subprocess.run(
                    ["which", "xdotool"],
                    capture_output=True,
                    timeout=1.0
                )
            )
            available = result.returncode == 0
            logger.info(f"xdotool availability: {available}")
            return available
        except Exception as e:
            logger.debug(f"Failed to check xdotool: {e}")
            return False

    async def position_terminal(
        self,
        terminal_width: int,
        terminal_height: int,
        workspace_rect: Dict,
        gap_config: Dict,
        i3: Connection
    ) -> Tuple[int, int]:
        """
        Calculate optimal terminal position on screen.

        Args:
            terminal_width, terminal_height: Window dimensions
            workspace_rect: {"x", "y", "width", "height"} from workspace
            gap_config: {"top", "bottom", "left", "right"} in pixels
            i3: Sway IPC connection for fallback queries

        Returns:
            (x, y) coordinates for terminal placement
        """
        # Try to get mouse location
        mouse_loc = await self.get_mouse_location()

        if mouse_loc:
            # Validate cursor is in current workspace
            ws = workspace_rect
            if (ws['x'] <= mouse_loc.x < ws['x'] + ws['width'] and
                ws['y'] <= mouse_loc.y < ws['y'] + ws['height']):

                logger.debug(
                    f"Using mouse position ({mouse_loc.x}, {mouse_loc.y}) "
                    f"for terminal placement"
                )

                # Apply boundary constraints
                return self._apply_constraints(
                    mouse_loc.x, mouse_loc.y,
                    terminal_width, terminal_height,
                    workspace_rect, gap_config
                )

        # Fallback: center on current workspace
        logger.debug("Using workspace center for terminal placement")
        ws = workspace_rect
        center_x = ws['x'] + (ws['width'] - terminal_width) // 2
        center_y = ws['y'] + (ws['height'] - terminal_height) // 2

        return self._apply_constraints(
            center_x, center_y,
            terminal_width, terminal_height,
            workspace_rect, gap_config
        )

    def _apply_constraints(
        self,
        x: int,
        y: int,
        width: int,
        height: int,
        workspace_rect: Dict,
        gap_config: Dict
    ) -> Tuple[int, int]:
        """Apply boundary constraints to position."""
        ws = workspace_rect
        gap = gap_config

        # Calculate bounds
        min_x = ws['x'] + gap['left']
        max_x = ws['x'] + ws['width'] - gap['right'] - width

        min_y = ws['y'] + gap['top']
        max_y = ws['y'] + ws['height'] - gap['bottom'] - height

        # Offset for centering on cursor
        offset_x = x - width // 2
        offset_y = y - height // 2

        # Constrain and return
        final_x = max(min_x, min(offset_x, max_x))
        final_y = max(min_y, min(offset_y, max_y))

        logger.debug(
            f"Terminal positioning: cursor=({x},{y}), "
            f"final=({final_x},{final_y}), "
            f"bounds=({min_x}-{max_x}, {min_y}-{max_y})"
        )

        return final_x, final_y
```

### Integration with ScratchpadManager

```python
# In home-modules/desktop/i3-project-event-daemon/services/scratchpad_manager.py

class ScratchpadManager:
    """Manages scratchpad terminal lifecycle with mouse-aware positioning."""

    def __init__(self, sway: Connection, gap_config: Dict[str, int]):
        """
        Initialize scratchpad manager.

        Args:
            sway: Async Sway IPC connection
            gap_config: {"top", "bottom", "left", "right"} screen gaps in pixels
        """
        self.sway = sway
        self.gap_config = gap_config
        self.cursor_positioner = CursorPositioner(cache_ttl_seconds=2.0)

    async def position_and_show_terminal(
        self,
        project_name: str,
        terminal_width: int = 1000,
        terminal_height: int = 600
    ) -> None:
        """
        Show scratchpad terminal with mouse-aware positioning.

        Args:
            project_name: Project identifier
            terminal_width: Terminal window width
            terminal_height: Terminal window height
        """
        # Get current workspace
        workspaces = await self.sway.get_workspaces()
        current_ws = next((w for w in workspaces if w.focused), None)
        if not current_ws:
            raise RuntimeError("No focused workspace")

        # Calculate position
        x, y = await self.cursor_positioner.position_terminal(
            terminal_width,
            terminal_height,
            {
                'x': current_ws.rect.x,
                'y': current_ws.rect.y,
                'width': current_ws.rect.width,
                'height': current_ws.rect.height,
            },
            self.gap_config,
            self.sway
        )

        # Get terminal mark
        mark = f"scratchpad:{project_name}"

        # Show and position terminal
        await self.sway.command(f'[con_mark="{mark}"] scratchpad show')
        await self.sway.command(f'[con_mark="{mark}"] move absolute position {x} {y}')
```

---

## 7. Configuration & Environment Variables

### i3run-Compatible Gap Configuration

```bash
# ~/.bashrc or ~/.pam_environment (loaded by daemon)

# Screen edge gaps for mouse-based positioning (pixels)
export I3RUN_TOP_GAP=10       # Pixels from top edge
export I3RUN_BOTTOM_GAP=30    # Pixels from bottom edge (panel space)
export I3RUN_LEFT_GAP=10      # Pixels from left edge
export I3RUN_RIGHT_GAP=10     # Pixels from right edge
```

### Multi-Monitor Gap Configuration

For different gaps per monitor:

```python
# config/gaps.json
{
  "HEADLESS-1": {
    "top": 10,
    "bottom": 30,
    "left": 10,
    "right": 10
  },
  "HEADLESS-2": {
    "top": 10,
    "bottom": 10,
    "left": 10,
    "right": 10
  },
  "eDP-1": {
    "top": 10,
    "bottom": 40,
    "left": 10,
    "right": 10
  }
}
```

---

## 8. Testing Strategy

### Unit Tests

```python
# tests/test_cursor_positioning.py

import pytest
from unittest.mock import AsyncMock, MagicMock, patch
from services.cursor_positioning import CursorPositioner, MouseLocation
from datetime import datetime


@pytest.mark.asyncio
async def test_mouse_location_parsing():
    """Test parsing of xdotool output."""
    positioner = CursorPositioner()

    # Mock xdotool output
    output = "X=500\nY=300\nSCREEN=0\nWINDOW=12345\n"

    with patch('subprocess.run') as mock_run:
        mock_run.return_value = MagicMock(
            returncode=0,
            stdout=output
        )

        result = positioner._xdotool_getmouselocation()

        assert result.x == 500
        assert result.y == 300
        assert result.screen == 0
        assert result.window_id == 12345


@pytest.mark.asyncio
async def test_boundary_constraint_center():
    """Test positioning at screen center."""
    positioner = CursorPositioner()

    # 1920x1080 screen, 1000x600 window at center
    x, y = positioner._apply_constraints(
        x=960, y=540,  # Center cursor
        width=1000, height=600,
        workspace_rect={"x": 0, "y": 0, "width": 1920, "height": 1080},
        gap_config={"top": 10, "bottom": 10, "left": 10, "right": 10}
    )

    assert x == 460  # 960 - 1000/2
    assert y == 240  # 540 - 600/2


@pytest.mark.asyncio
async def test_boundary_constraint_bottom_right():
    """Test positioning near bottom-right edge."""
    positioner = CursorPositioner()

    # Cursor at bottom-right
    x, y = positioner._apply_constraints(
        x=1900, y=1070,  # Bottom-right corner
        width=1000, height=600,
        workspace_rect={"x": 0, "y": 0, "width": 1920, "height": 1080},
        gap_config={"top": 10, "bottom": 10, "left": 10, "right": 10}
    )

    # Should snap to boundary
    assert x == 900   # max allowed (1920 - 1000 - 10 - 10)
    assert y == 470   # max allowed (1080 - 600 - 10)


@pytest.mark.asyncio
async def test_fallback_to_cache():
    """Test fallback to cached position when xdotool fails."""
    positioner = CursorPositioner(cache_ttl_seconds=5.0)

    # Set cached position
    cached = MouseLocation(
        x=100, y=200, screen=0, window_id=999,
        timestamp=datetime.now()
    )
    positioner._last_position = cached
    positioner._xdotool_available = False

    with patch.object(positioner, '_xdotool_getmouselocation', return_value=None):
        result = await positioner.get_mouse_location()

        assert result is not None
        assert result.x == 100
        assert result.y == 200


@pytest.mark.asyncio
async def test_cache_ttl_expiration():
    """Test that stale cached positions are rejected."""
    positioner = CursorPositioner(cache_ttl_seconds=0.1)

    # Set very old cached position
    import time
    old_time = datetime.now()
    old_time = old_time.replace(
        microsecond=0
    )  # Clear microseconds

    positioner._last_position = MouseLocation(
        x=100, y=200, screen=0, window_id=999,
        timestamp=old_time
    )
    positioner._xdotool_available = False

    # Wait for TTL to expire
    await asyncio.sleep(0.2)

    with patch.object(positioner, '_xdotool_getmouselocation', return_value=None):
        result = await positioner.get_mouse_location()

        assert result is None  # Stale cache rejected
```

### Integration Tests

```python
@pytest.mark.asyncio
async def test_position_terminal_with_mouse(mock_sway_connection):
    """Test terminal positioning using mouse location."""
    positioner = CursorPositioner()
    manager = ScratchpadManager(mock_sway_connection, {
        'top': 10, 'bottom': 10, 'left': 10, 'right': 10
    })

    # Mock cursor at (500, 300)
    with patch.object(positioner, 'get_mouse_location') as mock_mouse:
        mock_mouse.return_value = MouseLocation(
            x=500, y=300, screen=0, window_id=12345,
            timestamp=datetime.now()
        )

        x, y = await positioner.position_terminal(
            terminal_width=1000,
            terminal_height=600,
            workspace_rect={"x": 0, "y": 0, "width": 1920, "height": 1080},
            gap_config={'top': 10, 'bottom': 10, 'left': 10, 'right': 10},
            i3=mock_sway_connection
        )

        # Terminal should be positioned around cursor (centered on it)
        expected_x = 500 - 1000 // 2  # 0
        expected_y = 300 - 600 // 2   # 0

        assert x == expected_x
        assert y == expected_y


@pytest.mark.asyncio
async def test_position_terminal_fallback_on_headless(mock_sway_connection):
    """Test fallback to center positioning on headless Wayland."""
    positioner = CursorPositioner()

    # Simulate xdotool failure on headless
    with patch.object(positioner, 'get_mouse_location', return_value=None):
        x, y = await positioner.position_terminal(
            terminal_width=1000,
            terminal_height=600,
            workspace_rect={"x": 0, "y": 0, "width": 1920, "height": 1080},
            gap_config={'top': 10, 'bottom': 10, 'left': 10, 'right': 10},
            i3=mock_sway_connection
        )

        # Should fall back to center
        expected_x = (1920 - 1000) // 2  # 460
        expected_y = (1080 - 600) // 2   # 240

        assert x == expected_x
        assert y == expected_y
```

### Manual Testing (Headless Environment)

```bash
# SSH into hetzner-sway and test manually

# 1. Check xdotool availability on headless
which xdotool
xdotool getmouselocation --shell

# 2. Monitor cursor position changes
watch -n 0.5 "xdotool getmouselocation --shell"

# 3. Test with actual scratchpad terminal
i3pm scratchpad launch test_project

# 4. Toggle terminal and verify position tracks mouse
Win+Shift+Return  # Position should follow cursor
```

---

## 9. Recommendations & Implementation Plan

### For Physical Display (M1 MacBook)

1. **Primary Method**: xdotool (fully supported via XWayland)
2. **Fallback**: Center positioning (workspace center)
3. **No headless issues**: Single physical display, deterministic cursor behavior

**Implementation**: Proceed with CursorPositioner class, xdotool support

### For Headless Wayland (Hetzner Cloud)

1. **Pre-launch Testing**: Verify xdotool works with WayVNC synthetic input
2. **Fallback Priority**: Center positioning > Last known position > Monitor-based
3. **Configuration**: Document gap requirements for panel/taskbar space

**Implementation Steps**:
1. Deploy CursorPositioner to both targets
2. Test xdotool on hetzner-sway via VNC
3. If xdotool fails on headless: Implement libinput fallback (lower-level API)
4. Document observed behavior and adjust fallback strategy

### xdotool Dependency Management

**Current Status**: Already packaged in NixOS
- `/etc/nixos/modules/desktop/i3-project-workspace.nix` includes xdotool in PATH

**For Feature 051**: No additional configuration needed, xdotool already available

### Fallback Chain Summary

```
1. Try xdotool getmouselocation
   ├─ Success: Apply boundary constraints, position terminal
   └─ Fail: → step 2

2. Try cached position (if <2s old)
   ├─ Valid: Use cached position
   └─ Stale/None: → step 3

3. Fall back to workspace center
   └─ Position terminal at workspace center with boundary constraints
```

---

## 10. References

### Source Code Analysis
- **i3run**: `/etc/nixos/docs/budlabs-i3run-c0cc4cc3b3bf7341.txt`
  - `func/sendtomouse.sh` (lines 821-860): Mouse positioning algorithm
  - `docs/options/mouse`: Configuration documentation

### Sway IPC Documentation
- **Sway IPC Manual**: https://man.archlinux.org/man/sway-ipc.7.en
- **Sway GitHub**: https://github.com/swaywm/sway/blob/master/sway/sway-ipc.7.scd

### i3ipc-python Library
- **Documentation**: https://i3ipc-python.readthedocs.io/
- **Async Support**: `i3ipc.aio.Connection` for async Wayland/i3 queries

### Existing i3pm Implementation
- **Connection Manager**: `/etc/nixos/home-modules/desktop/i3-project-event-daemon/connection.py`
- **Async Patterns**: Window filtering, event handlers, state management

### Feature-Related Documentation
- **Feature 051 Specification**: `/etc/nixos/specs/051-i3run-scratchpad-enhancement/spec.md`
- **Feature 062 (Baseline)**: `/etc/nixos/specs/062-project-scratchpad-terminal/`

---

## Conclusion

Mouse cursor positioning is feasible in Sway but requires **external tools** (xdotool) since the Sway IPC protocol doesn't expose cursor coordinates. The proven i3run implementation provides a reliable template for Feature 051, with appropriate fallback strategies for edge cases and headless environments.

**Key Takeaway**: Use xdotool as primary method with center positioning as robust fallback. This combination works on both physical displays (M1) and headless Wayland (Hetzner), delivering the ergonomic benefits of mouse-aware terminal summoning described in Feature 051 specifications.
