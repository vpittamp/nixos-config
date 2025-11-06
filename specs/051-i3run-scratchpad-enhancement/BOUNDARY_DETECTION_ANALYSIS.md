# i3run Boundary Detection Algorithm - Deep Analysis

**Date**: 2025-11-06
**Feature**: 051-i3run-scratchpad-enhancement
**Source**: `/etc/nixos/docs/budlabs-i3run-c0cc4cc3b3bf7341.txt` lines 825-860
**Language**: Bash (original) → Python (target)

## Executive Summary

The i3run `sendtomouse.sh` function implements an elegant quadrant-based boundary detection algorithm that centers a floating window on the mouse cursor while respecting screen edge constraints. The algorithm uses conditional logic to handle four screen quadrants independently, applying different boundary rules based on which quadrant the cursor occupies.

**Key Insight**: Rather than checking if the window would overflow each edge separately, i3run uses the cursor position (Y and X coordinates) to determine which direction it should constrain the window. This reduces the decision tree from multiple cascading checks to a clean two-pass quadrant analysis.

---

## Algorithm Pseudocode Explained

### Input Variables

```
i3list[WAH]        = Workspace Available Height (in pixels)
i3list[WAW]        = Workspace Available Width  (in pixels)
i3list[TWH]        = Target Window Height       (in pixels)
i3list[TWW]        = Target Window Width        (in pixels)

I3RUN_TOP_GAP      = Top edge gap (default 10px)
I3RUN_BOTTOM_GAP   = Bottom edge gap (default 10px)
I3RUN_LEFT_GAP     = Left edge gap (default 10px)
I3RUN_RIGHT_GAP    = Right edge gap (default 10px)

X, Y               = Mouse cursor absolute position
```

### Step-by-Step Execution

#### **Phase 1: Calculate Constraint Boundaries**

```python
# Maximum position before window would hit bottom/right edges
break_y = workspace_height - (bottom_gap + window_height)
break_x = workspace_width - (right_gap + window_width)
```

These represent the "breaking points" - the maximum top-left coordinates the window can have before its opposite edge touches the gap zone.

**Example**:
- Workspace height: 1080px, Window height: 600px, Bottom gap: 10px
- break_y = 1080 - (10 + 600) = 470px
- This means the window's top edge cannot be lower than 470px, or the bottom would be at 1080px (violating the 10px gap)

#### **Phase 2: Get Mouse Cursor Position**

```bash
eval "$(xdotool getmouselocation --shell)"  # Sets X, Y variables
```

This executes xdotool which returns shell-formatted output like:
```
X=1543
Y=742
```

#### **Phase 3: Calculate Temporary Position (Center on Cursor)**

```python
# Window centered on cursor means cursor is at window center
# To get top-left coordinates, subtract half the window dimensions
tmp_y = cursor_y - (window_height / 2)
tmp_x = cursor_x - (window_width / 2)
```

**Example**:
- Cursor at (800, 400), Window 1000x600
- tmp_x = 800 - (1000/2) = 300
- tmp_y = 400 - (600/2) = 100
- Window's top-left would be (300, 100), cursor at center (800, 400)

#### **Phase 4: Vertical Constraint (Quadrant Analysis - Upper vs Lower)**

The algorithm checks if cursor is above or below the workspace vertical midpoint:

```python
if cursor_y > (workspace_height / 2):
    # Cursor in LOWER half - might overflow BOTTOM edge
    new_y = tmp_y if tmp_y > break_y else break_y
    # Translation: max(tmp_y, break_y) but inverted logic
    # If tmp_y exceeds break_y, it would overflow, so use break_y instead
else:
    # Cursor in UPPER half - might overflow TOP edge
    new_y = tmp_y if tmp_y >= top_gap else top_gap
    # Translation: max(tmp_y, top_gap)
    # If tmp_y is less than top_gap, window would be above gap zone
```

**Interpretation**:
- Lower quadrant: Prefer centered position, but cap at break_y to prevent bottom overflow
- Upper quadrant: Prefer centered position, but ensure window stays below top_gap

#### **Phase 5: Horizontal Constraint (Quadrant Analysis - Left vs Right)**

The algorithm checks if cursor is left or right of the workspace horizontal midpoint:

```python
if cursor_x < (workspace_width / 2):
    # Cursor in LEFT half - might overflow LEFT edge
    new_x = tmp_x if tmp_x >= left_gap else left_gap
    # Translation: max(tmp_x, left_gap)
else:
    # Cursor in RIGHT half - might overflow RIGHT edge
    new_x = tmp_x if tmp_x > break_x else break_x
    # Translation: max(tmp_x, break_x) but inverted logic
```

**Interpretation**:
- Left quadrant: Prefer centered position, but ensure window is at least left_gap from left edge
- Right quadrant: Prefer centered position, but cap at break_x to prevent right overflow

#### **Phase 6: Execute Positioned Move**

```bash
swaymsg "[con_id=${window_id}]" move absolute position $new_x $new_y
```

---

## Quadrant Logic Visualization

### Four Quadrants of the Workspace

```
┌─────────────────────────────────────────────────────┐
│                                                     │
│    TOP_GAP                                          │
│  ┌─────────────────────────────────────────────┐   │
│  │  UPPER-LEFT QUADRANT  │  UPPER-RIGHT QUA.  │   │
│  │  ──────────────────── │  ──────────────────│   │
│  │  Cursor Y < WAH/2     │  Cursor Y < WAH/2  │   │
│  │  Cursor X < WAW/2     │  Cursor X > WAW/2  │   │
│  │                       │                    │   │
│  │  Window bounds:       │  Window bounds:    │   │
│  │  top >= top_gap       │  top >= top_gap    │   │
│  │  left >= left_gap     │  right < WAW-right_gap│
│  │                       │                    │   │
│  ├─────────────────────────────────────────────┤   │ Midline
│  │  LOWER-LEFT QUADRANT  │  LOWER-RIGHT QUA.  │   │ Y = WAH/2
│  │  ──────────────────── │  ──────────────────│   │
│  │  Cursor Y > WAH/2     │  Cursor Y > WAH/2  │   │
│  │  Cursor X < WAW/2     │  Cursor X > WAW/2  │   │
│  │                       │                    │   │
│  │  Window bounds:       │  Window bounds:    │   │
│  │  bottom < WAH-bot.gap │  bottom < WAH-bot.gap  │
│  │  left >= left_gap     │  right < WAW-right_gap│
│  │                       │                    │   │
│  └─────────────────────────────────────────────┘   │
│  LEFT_GAP               │                RIGHT_GAP │
│                         Midline X = WAW/2           │
└─────────────────────────────────────────────────────┘
```

### Constraint Rules by Quadrant

| Quadrant | Vertical Rule | Horizontal Rule |
|----------|---------------|-----------------|
| **Upper-Left** | `new_y = max(tmp_y, top_gap)` | `new_x = max(tmp_x, left_gap)` |
| **Upper-Right** | `new_y = max(tmp_y, top_gap)` | `new_x = min(tmp_x, break_x)` |
| **Lower-Left** | `new_y = min(tmp_y, break_y)` | `new_x = max(tmp_x, left_gap)` |
| **Lower-Right** | `new_y = min(tmp_y, break_y)` | `new_x = min(tmp_x, break_x)` |

where:
- `break_y = workspace_height - (bottom_gap + window_height)`
- `break_x = workspace_width - (right_gap + window_width)`

---

## Edge Cases & Their Handling

### Edge Case 1: Window Larger Than Available Space

**Scenario**: Terminal configured as 1400x850, but display is 1366x768 with 50px top gap

**Current Behavior**:
```
Available height = 768 - 50 (top gap) - 10 (bottom gap) = 708px
Window height = 850px
break_y = 768 - (10 + 850) = -92  ❌ NEGATIVE!
```

**Problem**: When break_y becomes negative, the constraint logic breaks. Placing window at position 0 would still overflow.

**Bash Behavior**: Integer arithmetic silently produces -92. When comparing `tmp_y > break_y` in a lower quadrant:
```bash
tmp_y=100  # Cursor midpoint: 400 - (850/2) = -25, but let's say we're here
break_y=-92
((100 > -92))  # True, so new_y = 100
# Window top at 100, bottom at 950, OVERFLOWS by 182px!
```

**i3run Limitation**: The original algorithm assumes the window fits within available space. No automatic size reduction logic exists.

**Python Implementation Requirement**:
```python
def calculate_max_size(workspace_height, workspace_width, gaps):
    """Calculate maximum window size that fits within bounds"""
    max_height = workspace_height - gaps.top - gaps.bottom
    max_width = workspace_width - gaps.left - gaps.right

    # Return clamped dimensions
    return (
        min(configured_height, max_height),
        min(configured_width, max_width)
    )
```

---

### Edge Case 2: Mouse Exactly on Quadrant Boundary

**Scenario**: Mouse cursor exactly at `X = workspace_width / 2` or `Y = workspace_height / 2`

**Current Bash Logic**:
```bash
((X<(i3list[WAW]/2)))  # Is X strictly less than midpoint?
```

**Edge Case**: When X = 1920/2 = 960:
```bash
((960 < 960))  # False → Treated as RIGHT quadrant
```

**Implication**: Boundaries on midpoint are inclusive to one side. This is **acceptable** behavior - consistent rule that avoids gaps between quadrants.

**Python Translation**:
```python
if cursor_x < workspace_width / 2:
    # Left quadrant (includes left edge, excludes midpoint)
else:
    # Right quadrant (includes midpoint and right edge)
```

---

### Edge Case 3: Negative Coordinates (Multiple Monitors)

**Scenario**: Multi-monitor setup where cursor is on right monitor

```
Monitor Layout:
[Primary: 0-1920]  [Secondary: 1920-3840]
                   ↑ Cursor here at X=2500, Y=300
```

**Current Behavior**:
- Cursor position correctly returns `X=2500`
- break_x calculation: `3840 - (10 + 1000) = 2830`
- Window positioned at `new_x = min(2500, 2830) = 2500`
- Window spans X=2500 to X=3500 ✓ **Correct**

**But consider left monitor's secondary monitor**:
```
[Primary: 0-1920]  [Secondary: -1920-0]  (right monitor, negative coords)
                   ↑ Cursor here at X=-200, Y=300
```

**Current Behavior**:
- Cursor at X = -200
- break_x = 0 - (10 + 1000) = -1010
- In right quadrant (X < 0 but not strictly less than -960): `((−200 < −960))` → False
- So: `new_x = min(-200, -1010) = -1010`
- Window positioned at X=-1010, **offscreen** ❌

**Root Cause**: Algorithm assumes:
1. Workspace coordinates are always positive (0, ∞)
2. Cursor position is within workspace bounds

**Multi-Monitor Problem**: Sway can position monitors with negative coordinates or gaps. The algorithm needs to:
1. Query which monitor the cursor is on
2. Use that monitor's coordinate system
3. Apply gaps relative to that monitor, not global workspace

**Python Implementation Requirement**:
```python
async def get_monitor_for_cursor(cursor_x, cursor_y):
    """Find monitor containing cursor position"""
    tree = await connection.get_tree()
    for output in tree.outputs:
        if (output.rect.x <= cursor_x < output.rect.x + output.rect.width and
            output.rect.y <= cursor_y < output.rect.y + output.rect.height):
            return output
    return None  # Fallback to primary monitor
```

---

### Edge Case 4: Off-Screen Cursor Position in Headless Setup

**Scenario**: `swaymsg -t get_seats` returns cursor position, but cursor is not on any monitor (headless Wayland with WLR_BACKENDS=headless)

**Current Behavior**:
- xdotool query fails or returns invalid coordinates
- Bash silently produces uninitialized X, Y variables
- Positioning logic runs with garbage values

**i3run Limitation**: No fallback mechanism. Assumes xdotool always succeeds.

**Python Implementation Requirement**:
```python
async def get_cursor_position():
    """Query mouse cursor with fallback to center"""
    try:
        seat_data = await swaymsg_get_seats()
        cursor = seat_data[0].pointer  # Simplified
        if cursor and is_valid_position(cursor.x, cursor.y):
            return (cursor.x, cursor.y)
    except (IndexError, AttributeError, ConnectionError):
        pass

    # Fallback: center of active workspace
    return get_center_position()
```

---

### Edge Case 5: Integer Division Rounding

**Scenario**: Window dimensions that don't divide evenly

```
Cursor at (1000, 500)
Window 1000x600 (even)
tmp_x = 1000 - (1000/2) = 1000 - 500 = 500 ✓

Cursor at (1000, 500)
Window 999x601 (odd)
tmp_x = 1000 - (999/2) = 1000 - 499.5 = 500.5
```

**Bash Behavior** (declare -i):
```bash
declare -i tmpx
tmpx=$((1000 - (999/2)))  # Integer division: 999/2 = 499
tmpx=$((1000 - 499))      # = 501
```

**Result**: Off-by-one from mathematically perfect centering. Window is 1 pixel to the right of cursor's true center.

**Severity**: Negligible (imperceptible to user), but should be explicit in Python:

```python
def calculate_centered_position(cursor_x, cursor_y, window_width, window_height):
    """Center window on cursor using floor division (match bash behavior)"""
    tmp_x = cursor_x - (window_width // 2)  # Floor division
    tmp_y = cursor_y - (window_height // 2)
    return (tmp_x, tmp_y)
```

---

### Edge Case 6: Rapid Window Resizes Between Calculation and Execution

**Scenario**: Daemon calculates position for 1000x600 terminal, but between calculation and `move` command, user resizes window to 800x400

**Current Behavior**:
- Position calculation assumed 1000x600
- break_y calculated based on 600px height
- But window is actually 800px, so actual bottom edge is now beyond break_y
- Window still overflows despite "corrected" positioning

**i3run Limitation**: No re-validation before executing move command. Assumes window dimensions are stable.

**Python Implementation Requirement**:
```python
async def position_and_move(window_id, target_position):
    """Get current window dimensions before moving"""
    tree = await connection.get_tree()
    window = find_window(tree, window_id)

    # Recalculate position with actual current dimensions
    adjusted_position = apply_constraints(
        target_position,
        window.rect.width,      # ACTUAL dimensions
        window.rect.height
    )

    await move_window(window_id, adjusted_position)
```

---

### Edge Case 7: Asynchronous State Inconsistency

**Scenario**: In multi-workspace setup, workspace gets destroyed or resized between queries

```python
# Query workspace dimensions
workspace_height = 1080

# ... async I/O delay, workspace gets resized to 720 ...

# Calculate position using stale dimensions
break_y = 1080 - 600 = 480  # Based on old height!

# Window ends up partially off-screen on new 720px workspace
```

**i3run Limitation**: Bash implementation is synchronous, no async race conditions. Python must guard against this.

**Python Implementation Requirement**:
```python
async def position_with_consistency_check(window_id):
    """Ensure positioning uses consistent workspace state"""
    workspace_height = await get_workspace_height()

    # Perform ALL dimension queries in tight sequence
    cursor_x, cursor_y = await get_cursor_position()
    window_width, window_height = await get_window_dimensions(window_id)

    # Single atomic calculation
    position = calculate_position(
        cursor_x, cursor_y,
        window_width, window_height,
        workspace_height
    )

    # Move immediately (minimal window for state change)
    await move_window(window_id, position)
```

---

### Edge Case 8: Gap Configuration Validation

**Scenario**: User sets gaps larger than workspace

```
I3RUN_TOP_GAP = 500
I3RUN_BOTTOM_GAP = 500
Workspace height = 1080
Window height = 600

Available = 1080 - 500 - 500 = 80px
Window height = 600px
❌ IMPOSSIBLE TO FIT
```

**Current Behavior**: Algorithm proceeds anyway
```
break_y = 1080 - (500 + 600) = -20
Any tmp_y < 0, so new_y = -20  # Top of window OFF-SCREEN
```

**i3run Limitation**: No validation of gap sanity. Assumes user configures reasonable values.

**Python Implementation Requirement**:
```python
def validate_gaps(workspace_height, workspace_width, window_height, window_width, gaps):
    """Warn if gaps make window positioning impossible"""
    available_height = workspace_height - gaps.top - gaps.bottom
    available_width = workspace_width - gaps.left - gaps.right

    if available_height < window_height:
        logger.warning(
            f"Window height {window_height}px exceeds "
            f"available space {available_height}px. "
            f"Terminal will be resized."
        )
        return False

    return True
```

---

## Known Limitations of i3run Algorithm

### 1. **No Explicit Window Size Constraints**
The algorithm doesn't reduce window size if it exceeds available space. Feature 051 specification requires automatic size adjustment (FR-007).

### 2. **Single Workspace Assumption**
Algorithm treats entire screen as single coordinate system. Doesn't account for:
- Multiple monitors with negative coordinates
- Per-monitor gaps vs. global gaps
- Monitor-specific window constraints

### 3. **Cursor Position Validity Not Checked**
Algorithm assumes `xdotool getmouselocation` always succeeds and returns valid coordinates. No fallback if cursor position unavailable (problematic on headless Wayland).

### 4. **No State Persistence Logic**
Algorithm is stateless - it calculates position fresh each time. If called during `hide`, position changes aren't saved for later `show` operation.

### 5. **Integer Arithmetic Side Effects**
Division in bash `((999/2))` uses floor division silently. Window can be off-center by 1 pixel without warning.

### 6. **Quadrant Boundary Ambiguity**
Cursor exactly on midline is assigned to right/lower quadrant. If gaps differ on left/right, this creates asymmetry.

### 7. **No Handling of Workspace Layout Changes**
If workspace is resized between calculation and window move, positioning can become invalid.

---

## Test Case Matrix for Python Implementation

### Test Group 1: Basic Quadrant Positioning

| Test ID | Scenario | Input | Expected Output |
|---------|----------|-------|-----------------|
| **Q1-1** | Upper-left quadrant, centered | WS 1920x1080, Win 800x600, Mouse (400,200), Gaps 10/10/10/10 | Window at (0, 10) |
| **Q1-2** | Upper-right quadrant, centered | WS 1920x1080, Win 800x600, Mouse (1500,200), Gaps 10/10/10/10 | Window at (1110, 10) |
| **Q1-3** | Lower-left quadrant, centered | WS 1920x1080, Win 800x600, Mouse (400,900), Gaps 10/10/10/10 | Window at (0, 470) |
| **Q1-4** | Lower-right quadrant, centered | WS 1920x1080, Win 800x600, Mouse (1500,900), Gaps 10/10/10/10 | Window at (1110, 470) |
| **Q1-5** | Exact center, any quadrant rules apply | WS 1920x1080, Win 800x600, Mouse (960,540), Gaps 10/10/10/10 | Window at (560, 240) |

### Test Group 2: Gap Configuration Impact

| Test ID | Scenario | Input | Expected Output |
|---------|----------|-------|-----------------|
| **G2-1** | Larger top gap | WS 1920x1080, Win 800x600, Mouse (960,100), Top Gap 50 | Window at (560, 50) |
| **G2-2** | Larger bottom gap | WS 1920x1080, Win 800x600, Mouse (960,1050), Bottom Gap 100 | Window at (560, 470) |
| **G2-3** | Asymmetric gaps | WS 1920x1080, Win 800x600, Mouse (960,540), Gaps 50/20/10/30 | Window at (560, 240) |
| **G2-4** | Zero gaps | WS 1920x1080, Win 800x600, Mouse (960,540), Gaps 0/0/0/0 | Window at (560, 240) |
| **G2-5** | Very large gaps | WS 1920x1080, Win 800x600, Mouse (960,540), Gaps 100/100/100/100 | Window at (560, 240) |

### Test Group 3: Boundary Constraint Enforcement

| Test ID | Scenario | Input | Expected Output |
|---------|----------|-------|-----------------|
| **B3-1** | Touch top boundary | WS 1920x1080, Win 800x600, Mouse (960,50), Gaps 10/10/10/10 | Window at (560, 10) |
| **B3-2** | Touch bottom boundary | WS 1920x1080, Win 800x600, Mouse (960,1070), Gaps 10/10/10/10 | Window at (560, 470) |
| **B3-3** | Touch left boundary | WS 1920x1080, Win 800x600, Mouse (50,540), Gaps 10/10/10/10 | Window at (10, 240) |
| **B3-4** | Touch right boundary | WS 1920x1080, Win 800x600, Mouse (1870,540), Gaps 10/10/10/10 | Window at (1110, 240) |
| **B3-5** | Corner: top-left | WS 1920x1080, Win 800x600, Mouse (10,10), Gaps 10/10/10/10 | Window at (10, 10) |
| **B3-6** | Corner: bottom-right | WS 1920x1080, Win 800x600, Mouse (1910,1070), Gaps 10/10/10/10 | Window at (1110, 470) |

### Test Group 4: Edge Cases - Window Size vs. Workspace

| Test ID | Scenario | Input | Expected Output |
|---------|----------|-------|-----------------|
| **W4-1** | Window fills entire workspace | WS 1920x1080, Win 1920x1080, Mouse (960,540) | Window at (0, 0) |
| **W4-2** | Window larger than workspace (height) | WS 1920x1080, Win 1000x1200, Mouse (960,540) | Window at (460, ???) |
| **W4-3** | Window larger than workspace (width) | WS 1920x1080, Win 2000x600, Mouse (960,540) | Window at (????, 240) |
| **W4-4** | Window equal to available space after gaps | WS 1920x1080, Win 1900x1060, Mouse (960,540), Gaps 10/10/10/10 | Window at (10, 10) |

### Test Group 5: Multi-Monitor Scenarios

| Test ID | Scenario | Input | Expected Output |
|---------|----------|-------|-----------------|
| **M5-1** | Dual monitors, cursor on left | Monitors [0-1920], [1920-3840], Win 800x600, Mouse (400,540) | On left monitor at (0, 240) |
| **M5-2** | Dual monitors, cursor on right | Monitors [0-1920], [1920-3840], Win 800x600, Mouse (2500,540) | On right monitor at (2020, 240) |
| **M5-3** | Dual monitors negative coords, cursor on left | Monitors [-1920-0], [0-1920], Win 800x600, Mouse (-960,540) | On left monitor at (-960, 240) |
| **M5-4** | Three monitors, cursor on secondary | Monitors [0-1920], [1920-3840], [3840-5760], Win 800x600, Mouse (2500,540) | On middle monitor at (2020, 240) |

### Test Group 6: Rounding and Precision

| Test ID | Scenario | Input | Expected Output |
|---------|----------|-------|-----------------|
| **R6-1** | Odd window width | WS 1920x1080, Win 799x600, Mouse (960,540) | Window at (561, 240) [799//2=399] |
| **R6-2** | Odd window height | WS 1920x1080, Win 800x601, Mouse (960,540) | Window at (560, 240) [601//2=300] |
| **R6-3** | Mouse off-center (float coords) | WS 1920x1080, Win 800x600, Mouse (960.5,540.5), Gaps | Window at (560, 240) [floor division] |

### Test Group 7: Boundary Midpoint Behavior

| Test ID | Scenario | Input | Expected Output |
|---------|----------|-------|-----------------|
| **BM7-1** | Mouse exactly on vertical midline | WS 1920x1080, Win 800x600, Mouse (960,540) | Lower/right rules apply |
| **BM7-2** | Mouse exactly on horizontal midline | WS 1920x1080, Win 800x600, Mouse (960,540) | Lower/right rules apply |
| **BM7-3** | One pixel left of vertical midline | WS 1920x1080, Win 800x600, Mouse (959,540) | Left rules apply |
| **BM7-4** | One pixel above horizontal midline | WS 1920x1080, Win 800x600, Mouse (960,539) | Upper rules apply |

### Test Group 8: Constraint Boundary Math

| Test ID | Scenario | Expected Calculation |
|---------|----------|---------------------|
| **CM8-1** | break_y calculation | 1080 - (10 + 600) = 470 |
| **CM8-2** | break_x calculation | 1920 - (10 + 800) = 1110 |
| **CM8-3** | break_y with 0 window height | 1080 - (10 + 0) = 1070 |
| **CM8-4** | break_y exceeds workspace (window too tall) | 1080 - (10 + 1200) = -130 ← INVALID |

---

## Python Implementation Strategy

### Type-Hinted Function Signatures

```python
from dataclasses import dataclass
from typing import Tuple, Optional
import asyncio
from i3ipc.aio import Connection

@dataclass
class GapConfig:
    """Screen edge gap configuration"""
    top: int = 10
    bottom: int = 10
    left: int = 10
    right: int = 10

    def validate(self, workspace_height: int, workspace_width: int) -> bool:
        """Ensure gaps don't make positioning impossible"""
        return (
            self.top + self.bottom < workspace_height and
            self.left + self.right < workspace_width
        )

@dataclass
class WindowDimensions:
    """Floating window size"""
    width: int
    height: int

@dataclass
class WorkspaceGeometry:
    """Workspace available area"""
    width: int
    height: int
    offset_x: int = 0
    offset_y: int = 0

@dataclass
class CursorPosition:
    """Mouse cursor absolute coordinates"""
    x: float
    y: float
    valid: bool = True

@dataclass
class PositionResult:
    """Final window top-left coordinates"""
    x: int
    y: int
    reason: str  # "centered", "constrained_top", etc.


class BoundaryDetectionAlgorithm:
    """i3run boundary detection implementation"""

    async def calculate_position(
        self,
        cursor: CursorPosition,
        window: WindowDimensions,
        workspace: WorkspaceGeometry,
        gaps: GapConfig
    ) -> PositionResult:
        """
        Calculate window position centered on cursor with boundary constraints.

        Implements i3run quadrant-based positioning algorithm from sendtomouse.sh

        Args:
            cursor: Current mouse cursor position
            window: Target window dimensions
            workspace: Available workspace area
            gaps: Screen edge gap configuration

        Returns:
            PositionResult with final x, y coordinates
        """

        # Phase 1: Calculate constraint boundaries
        break_y = workspace.height - (gaps.bottom + window.height)
        break_x = workspace.width - (gaps.right + window.width)

        # Phase 2: Handle oversized windows
        if break_y < 0 or break_x < 0:
            return await self._handle_oversized_window(
                cursor, window, workspace, gaps
            )

        # Phase 3: Calculate centered position
        tmp_x = int(cursor.x) - (window.width // 2)
        tmp_y = int(cursor.y) - (window.height // 2)

        # Phase 4: Apply vertical constraints (quadrant-based)
        if cursor.y > (workspace.height / 2):
            # Lower half: prefer centered, but constrain to break_y
            new_y = tmp_y if tmp_y <= break_y else break_y
            reason = "lower_constrained" if tmp_y > break_y else "lower_centered"
        else:
            # Upper half: prefer centered, but ensure >= top_gap
            new_y = tmp_y if tmp_y >= gaps.top else gaps.top
            reason = "upper_constrained" if tmp_y < gaps.top else "upper_centered"

        # Phase 5: Apply horizontal constraints (quadrant-based)
        if cursor.x < (workspace.width / 2):
            # Left half: prefer centered, but ensure >= left_gap
            new_x = tmp_x if tmp_x >= gaps.left else gaps.left
            reason += "_left_constrained" if tmp_x < gaps.left else "_left_centered"
        else:
            # Right half: prefer centered, but constrain to break_x
            new_x = tmp_x if tmp_x <= break_x else break_x
            reason += "_right_constrained" if tmp_x > break_x else "_right_centered"

        return PositionResult(
            x=max(0, new_x),  # Clamp to non-negative
            y=max(0, new_y),
            reason=reason
        )

    async def _handle_oversized_window(
        self,
        cursor: CursorPosition,
        window: WindowDimensions,
        workspace: WorkspaceGeometry,
        gaps: GapConfig
    ) -> PositionResult:
        """
        Handle windows that exceed available space.

        Either reduce window size or position at origin with warning.
        """
        available_height = workspace.height - gaps.top - gaps.bottom
        available_width = workspace.width - gaps.left - gaps.right

        # Position at gap boundaries
        new_x = gaps.left if window.width > available_width else (
            cursor.x - (window.width // 2)
        )
        new_y = gaps.top if window.height > available_height else (
            cursor.y - (window.height // 2)
        )

        return PositionResult(
            x=max(gaps.left, new_x),
            y=max(gaps.top, new_y),
            reason="oversized_fallback"
        )

    def get_quadrant(
        self,
        cursor: CursorPosition,
        workspace: WorkspaceGeometry
    ) -> str:
        """
        Determine which quadrant cursor is in.

        Matches i3run behavior: midpoint is exclusive to lower/right.
        """
        vertical = "lower" if cursor.y >= (workspace.height / 2) else "upper"
        horizontal = "right" if cursor.x >= (workspace.width / 2) else "left"
        return f"{vertical}_{horizontal}"
```

### Unit Test Examples

```python
import pytest

class TestBoundaryDetection:
    """Test i3run boundary detection algorithm"""

    @pytest.fixture
    def algorithm(self):
        return BoundaryDetectionAlgorithm()

    @pytest.fixture
    def standard_gaps(self):
        return GapConfig(top=10, bottom=10, left=10, right=10)

    @pytest.mark.asyncio
    async def test_centered_positioning_lower_right(self, algorithm, standard_gaps):
        """Test Q1-4: lower-right quadrant, perfectly centered"""
        result = await algorithm.calculate_position(
            cursor=CursorPosition(x=1500, y=900),
            window=WindowDimensions(width=800, height=600),
            workspace=WorkspaceGeometry(width=1920, height=1080),
            gaps=standard_gaps
        )

        assert result.x == 1110
        assert result.y == 470
        assert "lower_right_centered" in result.reason

    @pytest.mark.asyncio
    async def test_boundary_constraint_top(self, algorithm, standard_gaps):
        """Test B3-1: window touches top boundary"""
        result = await algorithm.calculate_position(
            cursor=CursorPosition(x=960, y=50),
            window=WindowDimensions(width=800, height=600),
            workspace=WorkspaceGeometry(width=1920, height=1080),
            gaps=standard_gaps
        )

        assert result.y == 10  # Constrained to top_gap

    @pytest.mark.asyncio
    async def test_oversized_window_height(self, algorithm, standard_gaps):
        """Test W4-2: window taller than workspace"""
        result = await algorithm.calculate_position(
            cursor=CursorPosition(x=960, y=540),
            window=WindowDimensions(width=1000, height=1200),
            workspace=WorkspaceGeometry(width=1920, height=1080),
            gaps=standard_gaps
        )

        # Should not crash, position at origin with fallback
        assert result.y == standard_gaps.top
        assert "fallback" in result.reason

    @pytest.mark.asyncio
    async def test_quadrant_boundary_midpoint(self, algorithm):
        """Test BM7-1: cursor exactly on midpoint uses lower/right rules"""
        result = await algorithm.calculate_position(
            cursor=CursorPosition(x=960, y=540),
            window=WindowDimensions(width=800, height=600),
            workspace=WorkspaceGeometry(width=1920, height=1080),
            gaps=GapConfig()
        )

        # Midpoint should apply lower/right rules
        assert "lower" in result.reason or "right" in result.reason
```

---

## Recommendations for Python Implementation

### 1. **Validate Gap Configuration at Startup**
```python
async def initialize_positioning(connection: Connection):
    """Validate gap configuration matches workspace"""
    workspace = await get_workspace_geometry(connection)
    gaps = GapConfig.from_env()

    if not gaps.validate(workspace.height, workspace.width):
        logger.warning(
            f"Gap configuration {gaps} exceeds workspace {workspace}. "
            f"Positioning will be constrained."
        )
```

### 2. **Implement Per-Monitor Positioning for Multi-Monitor**
```python
async def calculate_position_multi_monitor(
    cursor: CursorPosition,
    window: WindowDimensions,
    gaps: GapConfig,
    connection: Connection
) -> PositionResult:
    """
    Calculate position on correct monitor for cursor.

    1. Find which monitor cursor is on
    2. Get that monitor's geometry
    3. Apply positioning within that monitor's bounds
    """
    monitor = await get_monitor_for_cursor(cursor, connection)
    workspace = WorkspaceGeometry(
        width=monitor.rect.width,
        height=monitor.rect.height,
        offset_x=monitor.rect.x,
        offset_y=monitor.rect.y
    )

    # Adjust cursor to monitor-relative coordinates
    monitor_relative_cursor = CursorPosition(
        x=cursor.x - workspace.offset_x,
        y=cursor.y - workspace.offset_y,
        valid=True
    )

    result = await algorithm.calculate_position(
        monitor_relative_cursor, window, workspace, gaps
    )

    # Convert back to absolute coordinates
    return PositionResult(
        x=result.x + workspace.offset_x,
        y=result.y + workspace.offset_y,
        reason=result.reason
    )
```

### 3. **Add Cursor Position Validation with Fallback**
```python
async def get_cursor_position_safe(
    connection: Connection,
    workspace: WorkspaceGeometry
) -> CursorPosition:
    """Get cursor position with fallback to center"""
    try:
        # Try Sway IPC
        seats = await swaymsg_get_seats()
        pointer = seats[0].pointer

        # Validate position is within workspace
        if (0 <= pointer.x < workspace.width and
            0 <= pointer.y < workspace.height):
            return CursorPosition(x=pointer.x, y=pointer.y, valid=True)
    except (IndexError, AttributeError):
        pass

    # Fallback: center of workspace
    logger.debug("Cursor position unavailable, using center")
    return CursorPosition(
        x=workspace.width / 2,
        y=workspace.height / 2,
        valid=False
    )
```

### 4. **Store Positioning Metadata in Sway Marks**
```python
class StateManager:
    """Manage window state persistence via Sway marks"""

    def serialize_position(self, position: PositionResult) -> str:
        """Encode position into mark format"""
        return f"scratchpad_pos:x={position.x},y={position.y}"

    async def save_position(
        self,
        connection: Connection,
        window_id: int,
        position: PositionResult
    ):
        """Save position to window mark"""
        mark = self.serialize_position(position)
        await connection.command(f'[con_id={window_id}] mark "{mark}"')

    async def restore_position(
        self,
        connection: Connection,
        window_id: int
    ) -> Optional[PositionResult]:
        """Retrieve saved position from mark"""
        tree = await connection.get_tree()
        window = find_window(tree, window_id)

        if window and window.marks:
            for mark in window.marks:
                if mark.startswith("scratchpad_pos:"):
                    return self.deserialize_position(mark)

        return None
```

---

## Summary

The i3run boundary detection algorithm is elegant in its quadrant-based approach, but has several edge cases that must be handled in the Python implementation:

**Critical Edge Cases to Test**:
1. ✅ Oversized windows (larger than available space)
2. ✅ Multi-monitor with negative coordinates
3. ✅ Cursor on monitor boundary
4. ✅ Headless Wayland with no cursor
5. ✅ Quadrant boundary midpoint behavior
6. ✅ Integer division rounding effects
7. ✅ Workspace resizing between calculation and move
8. ✅ Gap configuration validation

**Python Implementation Checklist**:
- [ ] Type hints for all functions
- [ ] Async/await throughout (no blocking I/O)
- [ ] Unit tests for all 8 test groups
- [ ] Integration tests with Sway IPC
- [ ] Error handling with fallbacks
- [ ] Performance profiling (<50ms positioning)
- [ ] Multi-monitor support
- [ ] State persistence via marks
- [ ] Logging for debugging

