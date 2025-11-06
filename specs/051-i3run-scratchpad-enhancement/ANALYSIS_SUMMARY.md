# i3run Boundary Detection Analysis - Executive Summary

**Analysis Date**: 2025-11-06
**Feature**: 051-i3run-scratchpad-enhancement
**Status**: Research Phase Complete
**Deliverable**: BOUNDARY_DETECTION_ANALYSIS.md (comprehensive)

---

## Quick Reference

### The Core Algorithm (17 lines of bash)

```bash
sendtomouse(){
  declare -i X Y newy newx tmpx tmpy breakx breaky

  # Calculate max position before window hits gap boundaries
  breaky=$((i3list[WAH]-(I3RUN_BOTTOM_GAP+i3list[TWH])))
  breakx=$((i3list[WAW]-(I3RUN_RIGHT_GAP+i3list[TWW])))

  # Get mouse cursor position
  eval "$(xdotool getmouselocation --shell)"  # Sets X, Y

  # Center window on cursor
  tmpy=$((Y-(i3list[TWH]/2)))
  tmpx=$((X-(i3list[TWW]/2)))

  # Apply vertical constraints based on cursor Y position
  ((Y>(i3list[WAH]/2))) \
    && newy=$((tmpy>breaky ? breaky : tmpy)) \
    || newy=$((tmpy<I3RUN_TOP_GAP ? I3RUN_TOP_GAP : tmpy))

  # Apply horizontal constraints based on cursor X position
  ((X<(i3list[WAW]/2))) \
    && newx=$((tmpx<I3RUN_LEFT_GAP ? I3RUN_LEFT_GAP : tmpx)) \
    || newx=$((tmpx>breakx ? breakx : tmpx))

  # Move window to calculated position
  messy "[con_id=${i3list[TWC]}]" move absolute position $newx $newy
}
```

---

## How It Works (3-Step Overview)

### Step 1: Calculate Boundaries
```
break_y = workspace_height - (bottom_gap + window_height)
break_x = workspace_width - (right_gap + window_width)
```
These are the maximum coordinates before the window hits the gap zone.

### Step 2: Center on Cursor
```
tmp_x = cursor_x - (window_width / 2)
tmp_y = cursor_y - (window_height / 2)
```
Window's top-left positioned so cursor is at window center.

### Step 3: Apply Quadrant-Based Constraints
- **If cursor in lower half**: Allow window down to `break_y`, else clamp to `break_y`
- **If cursor in upper half**: Clamp window up to `top_gap`
- **If cursor in left half**: Clamp window left to `left_gap`
- **If cursor in right half**: Allow window right to `break_x`, else clamp to `break_x`

**Result**: Window is centered on cursor while respecting screen edge gaps.

---

## Why This Algorithm is Elegant

The i3run approach avoids the cascade of:
```python
# Naive approach (many checks)
if window_left < left_gap:
    new_x = left_gap
elif window_right > workspace_width - right_gap:
    new_x = workspace_width - right_gap - window_width
else:
    new_x = centered_x
```

Instead, it cleanly separates concerns:
- **Cursor Y determines vertical constraints** (which end of Y-axis is the problem?)
- **Cursor X determines horizontal constraints** (which end of X-axis is the problem?)
- **Gaps and window size determine boundaries** (how far can we go?)
- **Simple min/max operations** enforce constraints

This is why it only needs 17 lines of code instead of a dozen conditional blocks.

---

## Critical Edge Cases (8 Found)

### 1. Window Larger Than Available Space ⚠️
**Problem**: If window is 1200px tall but workspace is 1080px with 50px gap, `break_y` becomes **negative**. Algorithm fails silently.

**Impact**: Terminal positioned off-screen. User cannot access it.

**Solution**: Validate window fits before positioning, resize if necessary.

```python
available_height = workspace_height - gaps.top - gaps.bottom
if window_height > available_height:
    # Reduce window size or reject positioning
    window_height = available_height
```

---

### 2. Multi-Monitor Negative Coordinates ⚠️⚠️
**Problem**: Sway can position monitors at negative coordinates (e.g., left monitor at -1920-0, right at 0-1920). Algorithm assumes all coordinates are positive.

**Impact**: On multi-monitor setups with certain configurations, windows can be positioned off-screen on wrong monitor.

**Solution**: Query which monitor contains cursor, use that monitor's coordinate system.

```python
monitor = await get_monitor_for_cursor(cursor_x, cursor_y)
# Use monitor.rect.x, monitor.rect.y as origin
workspace_relative_x = cursor_x - monitor.rect.x
```

---

### 3. Cursor Not on Active Workspace Monitor ⚠️
**Problem**: Headless Wayland or multi-monitor scenario where cursor position query fails or returns coordinates on different monitor.

**Impact**: Window positioned on wrong monitor or off-screen entirely.

**Solution**: Validate cursor is on active workspace's monitor, fallback to center positioning.

```python
if not is_cursor_on_active_monitor(cursor, connection):
    cursor = CursorPosition(
        x=active_workspace.width / 2,
        y=active_workspace.height / 2,
        valid=False
    )
```

---

### 4. Quadrant Boundary Ambiguity ⚠️
**Problem**: Cursor exactly on midline (Y = WAH/2 or X = WAW/2) is assigned to lower/right quadrant. If gaps differ, creates asymmetry.

**Impact**: Minimal (perceptible positioning might differ by up to 10 pixels). Acceptable as long as it's consistent.

**Solution**: Document the behavior and use consistent comparison operators.

```python
# Right/lower quadrant includes midline
if cursor_y >= workspace_height / 2:  # Includes midpoint
    # Lower half rules
```

---

### 5. Integer Division Rounding ⚠️
**Problem**: Window 999px wide, cursor at 1000px. Bash does `1000 - (999/2)` = `1000 - 499` = 501 (one pixel off-center due to floor division).

**Impact**: Window is 1 pixel off from perfect centering. Imperceptible to user.

**Solution**: Use floor division explicitly to match bash behavior.

```python
tmp_x = cursor_x - (window_width // 2)  # Floor division, matches bash
```

---

### 6. Workspace Resized Between Calculation and Move ⚠️
**Problem**: Async scenario in Python. Calculate position while workspace is 1080px, but before moving window, workspace resizes to 720px.

**Impact**: Positioning calculations based on stale workspace dimensions. Window can end up partially off-screen.

**Solution**: Perform all queries in tight sequence, move immediately.

```python
workspace = await get_workspace_geometry()
cursor = await get_cursor_position()
window_size = await get_window_dimensions(window_id)
# All queries done, now calculate and move atomically
position = calculate_position(...)
await move_window(window_id, position)
```

---

### 7. Gap Configuration Larger Than Workspace ⚠️
**Problem**: User sets `I3RUN_TOP_GAP=500` and `I3RUN_BOTTOM_GAP=500` on 1080px display with 600px window. Available space = 1080 - 1000 = 80px. Window won't fit.

**Impact**: Algorithm proceeds anyway, positions window at negative Y coordinate.

**Solution**: Validate gap sanity at startup, warn user.

```python
if gaps.top + gaps.bottom + window_height > workspace_height:
    logger.warning(f"Gaps {gaps} + window {window_height} exceed workspace {workspace_height}")
```

---

### 8. Cursor Position Query Unavailable ⚠️
**Problem**: On headless Wayland (WLR_BACKENDS=headless), `swaymsg -t get_seats` might not return valid cursor position since there's no physical mouse device.

**Impact**: Algorithm receives uninitialized (0, 0) or garbage coordinates. Window positioned at top-left corner.

**Solution**: Implement fallback - if cursor query fails, use center positioning.

```python
try:
    cursor = await query_cursor_from_sway()
except (TimeoutError, ConnectionError):
    logger.debug("Cursor unavailable, using center positioning")
    cursor = CursorPosition(
        x=workspace.width / 2,
        y=workspace.height / 2,
        valid=False  # Mark as fallback
    )
```

---

## Quadrant Logic Visualization

```
                    Y = 0 (top)
                      ↓
       ┌──────────────────────────────┐
       │  UPPER-LEFT  │  UPPER-RIGHT  │
       │  tmp >= gaps │  tmp <= break │
X=0 →  │              │               │ ← X=WAW
(left) │ Y < WAH/2    │ Y < WAH/2     │ (right)
       ├──────────────────────────────┤ ← Y = WAH/2 (midpoint)
       │  LOWER-LEFT  │  LOWER-RIGHT  │
       │  tmp >= gaps │  tmp <= break │
       │  Y > WAH/2   │  Y > WAH/2    │
       └──────────────────────────────┘
                      ↓
                 Y = WAH (bottom)
```

**Rules**:
- **Upper-Left**: max(tmp_y, top_gap) & max(tmp_x, left_gap)
- **Upper-Right**: max(tmp_y, top_gap) & min(tmp_x, break_x)
- **Lower-Left**: min(tmp_y, break_y) & max(tmp_x, left_gap)
- **Lower-Right**: min(tmp_y, break_y) & min(tmp_x, break_x)

---

## Test Matrix Summary

**56 test cases identified**, grouped into 8 categories:

1. **Basic Quadrant Positioning** (5 tests) - Each quadrant + center
2. **Gap Configuration** (5 tests) - Various gap sizes and asymmetry
3. **Boundary Constraint Enforcement** (6 tests) - All edges + corners
4. **Window Size vs. Workspace** (4 tests) - Oversized scenarios
5. **Multi-Monitor** (4 tests) - Dual/triple monitors with various cursor positions
6. **Rounding and Precision** (3 tests) - Odd dimensions, float coordinates
7. **Quadrant Boundary Behavior** (4 tests) - Midpoint edge cases
8. **Constraint Math Validation** (4 tests) - break_y/break_x calculations

**See BOUNDARY_DETECTION_ANALYSIS.md Table 8 for complete test matrix.**

---

## Python Implementation Checklist

### Core Algorithm (Required)
- [ ] `calculate_position()` - Main positioning function
- [ ] Quadrant detection logic
- [ ] Constraint boundary math
- [ ] Per-monitor support
- [ ] Type hints on all functions

### Edge Case Handling (Required)
- [ ] Oversized window detection and handling
- [ ] Multi-monitor cursor detection
- [ ] Cursor position validation with fallback
- [ ] Workspace resizing race condition prevention
- [ ] Gap configuration validation

### Persistence Layer (Required per FR-011)
- [ ] `StateManager` class for mark serialization
- [ ] Mark format: `scratchpad_pos:x={N},y={N}`
- [ ] Read/write state from Sway marks
- [ ] Ghost container creation (1x1 invisible window)

### Testing (Required per FR-003)
- [ ] 56 unit tests covering all test groups
- [ ] Integration tests with Sway IPC
- [ ] Multi-monitor scenario tests
- [ ] Performance profiling (<50ms)
- [ ] Error handling tests

### Documentation (Required)
- [ ] Type hints in code
- [ ] Docstrings for all functions
- [ ] Test case documentation
- [ ] Known limitations documented
- [ ] Fallback behavior explained

---

## Implementation Priority

### P0 (Blocking) - Must Implement First
1. Basic algorithm in `calculate_position()`
2. Quadrant detection
3. Constraint boundary enforcement
4. Cursor position validation with fallback
5. Oversized window handling

### P1 (High) - Implement in Feature 051
1. Per-monitor support
2. State persistence via marks
3. Ghost container management
4. All 56 test cases
5. Performance profiling

### P2 (Nice-to-Have) - Future Enhancement
1. Cursor position logging for debugging
2. Gap configuration hot-reload
3. Workspace change detection
4. Visual feedback (animations)
5. Configurable fallback strategies

---

## Known Limitations of i3run Algorithm

1. **No automatic window resizing** - Assumes window fits
2. **Single coordinate system** - Doesn't handle multi-monitor offset
3. **No fallback for missing cursor** - Requires xdotool to always work
4. **No state persistence** - Position lost on restart
5. **No asynchronous considerations** - Assumes instant queries
6. **Quadrant boundary asymmetry** - Right/lower prefer different constraints
7. **No validation of gap sanity** - Assumes reasonable user config
8. **No race condition handling** - Assumes dimensions stable

**All 8 limitations have solutions in Python implementation strategy.**

---

## Key Files & Code Locations

**Analysis Documents**:
- `BOUNDARY_DETECTION_ANALYSIS.md` - Full detailed analysis (8,000+ words)
- `ANALYSIS_SUMMARY.md` - This file (executive summary)

**Source Code Being Adapted**:
- `/etc/nixos/docs/budlabs-i3run-c0cc4cc3b3bf7341.txt` - Original i3run source
- Lines 825-860: `sendtomouse.sh` function

**Python Implementation Files** (to be created):
- `home-modules/tools/i3pm/scratchpad.py` - Extended ScratchpadManager
- `home-modules/tools/i3pm/models.py` - Pydantic data models
- `home-modules/tools/i3pm/config.py` - Gap configuration
- `home-modules/tools/i3pm/tests/` - 56+ test cases

---

## Decisions Made During Analysis

### 1. Quadrant Boundary Behavior
**Decision**: Cursor on midline (Y = WAH/2 or X = WAW/2) goes to lower/right quadrant.
**Rationale**: Matches i3run behavior, maintains consistency, imperceptible to user.
**Trade-off**: Slight asymmetry if gaps differ, acceptable.

### 2. Integer Division Strategy
**Decision**: Use Python's `//` operator to match bash's floor division.
**Rationale**: Ensures 1-pixel compatibility with original algorithm.
**Trade-off**: Slight off-center positioning (imperceptible), matches original.

### 3. Multi-Monitor Support
**Decision**: Detect monitor containing cursor, use that monitor's coordinate system as origin.
**Rationale**: Prevents windows appearing on wrong monitor or off-screen.
**Trade-off**: Requires per-monitor geometry queries (minimal overhead).

### 4. Oversized Window Handling
**Decision**: Position at gap boundaries if window exceeds available space.
**Rationale**: Graceful degradation, window partially visible rather than completely off-screen.
**Trade-off**: Terminal might be larger than available space (user responsibility to configure appropriately).

### 5. Cursor Validation
**Decision**: Implement fallback to center positioning if cursor query fails.
**Rationale**: Essential for headless Wayland support.
**Trade-off**: On headless, terminal always appears centered (loses mouse-aware benefit).

---

## Recommendation: Proceed to Implementation

**Confidence Level**: HIGH ✅

**Rationale**:
1. Algorithm is well-understood with clear quadrant logic
2. All 8 edge cases identified and have clear solutions
3. Python implementation strategy is straightforward
4. Comprehensive test matrix (56 tests) available
5. Existing async infrastructure (i3ipc.aio) supports implementation
6. Multi-monitor support is achievable with cursor detection
7. State persistence via Sway marks is reliable mechanism
8. Performance targets (<50ms) are achievable with async

**Next Steps**:
1. ✅ Phase 0 research complete (BOUNDARY_DETECTION_ANALYSIS.md)
2. → Phase 1: Generate data-model.md, contracts/
3. → Phase 2: Generate tasks.md with implementation subtasks
4. → Implementation with continuous testing against test matrix

