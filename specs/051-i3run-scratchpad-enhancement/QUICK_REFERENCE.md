# i3run Boundary Detection - Quick Reference Guide

## Algorithm at a Glance

**Purpose**: Center floating window on mouse cursor while respecting screen edge gaps.

**Input**: Cursor position (X, Y), Window size (W×H), Workspace size (WAW×WAH), Gaps (T/B/L/R)

**Output**: New position (newx, newy) for window top-left corner

**Logic**: Quadrant-based constraints - where cursor is determines which direction window should be constrained.

---

## 4-Line Math

```python
break_y = workspace_h - (bottom_gap + window_h)    # Max Y before bottom overflow
break_x = workspace_w - (right_gap + window_w)     # Max X before right overflow

tmp_y = cursor_y - (window_h // 2)                  # Center window Y on cursor
tmp_x = cursor_x - (window_w // 2)                  # Center window X on cursor
```

---

## Constraint Rules (Pseudocode)

```python
# VERTICAL: Where is cursor vertically?
if cursor_y > (workspace_h / 2):
    # Lower half - window might overflow BOTTOM
    new_y = tmp_y if tmp_y <= break_y else break_y
else:
    # Upper half - window might overflow TOP
    new_y = tmp_y if tmp_y >= top_gap else top_gap

# HORIZONTAL: Where is cursor horizontally?
if cursor_x < (workspace_w / 2):
    # Left half - window might overflow LEFT
    new_x = tmp_x if tmp_x >= left_gap else left_gap
else:
    # Right half - window might overflow RIGHT
    new_x = tmp_x if tmp_x <= break_x else break_x
```

---

## Visual Example

```
Workspace: 1920×1080, Window: 800×600, Cursor: (1500, 900), Gaps: 10px all sides

Step 1: Calculate boundaries
  break_y = 1080 - (10 + 600) = 470
  break_x = 1920 - (10 + 800) = 1110

Step 2: Center on cursor
  tmp_y = 900 - (600 / 2) = 600
  tmp_x = 1500 - (800 / 2) = 1100

Step 3: Check quadrant - Cursor at (1500, 900)
  cursor_y (900) > workspace_h/2 (540)? YES → Lower half
  cursor_x (1500) < workspace_w/2 (960)? NO → Right half

Step 4: Apply constraints
  Lower half: new_y = tmp_y (600) <= break_y (470)? NO → new_y = 470
  Right half: new_x = tmp_x (1100) <= break_x (1110)? YES → new_x = 1100

Result: Window positioned at (1100, 470)
  Window spans: X=[1100, 1900], Y=[470, 1070]
  Right edge: 1920 - 1900 = 20px (≥ 10px gap) ✓
  Bottom edge: 1080 - 1070 = 10px (≥ 10px gap) ✓
```

---

## Quadrant Lookup Table

| Quadrant | Y Rule | X Rule |
|----------|--------|--------|
| Upper-Left | `max(tmp_y, top_gap)` | `max(tmp_x, left_gap)` |
| Upper-Right | `max(tmp_y, top_gap)` | `min(tmp_x, break_x)` |
| Lower-Left | `min(tmp_y, break_y)` | `max(tmp_x, left_gap)` |
| Lower-Right | `min(tmp_y, break_y)` | `min(tmp_x, break_x)` |

**Key**: Cursor Y determines vertical rule, Cursor X determines horizontal rule.

---

## 8 Edge Cases to Test

| # | Case | Problem | Solution |
|----|------|---------|----------|
| 1 | Window > Space | `break_y` negative | Validate window fits, resize if needed |
| 2 | Multi-monitor negative coords | Window off-screen | Detect monitor containing cursor |
| 3 | Cursor on wrong monitor | Position on wrong monitor | Validate cursor on active workspace |
| 4 | Cursor on quadrant boundary | Asymmetric constraints | Use consistent comparison operators |
| 5 | Integer division rounding | 1px off-center | Use floor division `//` intentionally |
| 6 | Workspace resized between queries | Stale calculations | Query all values in tight sequence |
| 7 | Gap config > workspace | Math breaks | Validate gaps at startup |
| 8 | No cursor position available | Uninitialized coordinates | Fallback to center positioning |

---

## Code Template

```python
async def position_window_at_cursor(
    cursor_x: float,
    cursor_y: float,
    window_width: int,
    window_height: int,
    workspace_width: int,
    workspace_height: int,
    gaps: GapConfig
) -> Tuple[int, int]:
    """
    Calculate window position centered on cursor.

    Args:
        cursor_x, cursor_y: Mouse position in pixels
        window_width, window_height: Window dimensions
        workspace_width, workspace_height: Available space
        gaps: GapConfig(top=10, bottom=10, left=10, right=10)

    Returns:
        (new_x, new_y) - Top-left corner of positioned window
    """

    # Phase 1: Boundaries
    break_y = workspace_height - (gaps.bottom + window_height)
    break_x = workspace_width - (gaps.right + window_width)

    # Phase 2: Center on cursor
    tmp_y = int(cursor_y) - (window_height // 2)
    tmp_x = int(cursor_x) - (window_width // 2)

    # Phase 3: Vertical constraint
    if cursor_y > (workspace_height / 2):
        new_y = tmp_y if tmp_y <= break_y else break_y
    else:
        new_y = tmp_y if tmp_y >= gaps.top else gaps.top

    # Phase 4: Horizontal constraint
    if cursor_x < (workspace_width / 2):
        new_x = tmp_x if tmp_x >= gaps.left else gaps.left
    else:
        new_x = tmp_x if tmp_x <= break_x else break_x

    return (max(0, new_x), max(0, new_y))
```

---

## Testing Checklist

- [ ] All 4 quadrants with centered position
- [ ] Top/bottom/left/right boundary edges
- [ ] All 4 corners
- [ ] Window larger than space
- [ ] Multi-monitor with negative coords
- [ ] Cursor exactly on midline
- [ ] Asymmetric gaps
- [ ] Zero gaps
- [ ] Very large gaps
- [ ] Odd window dimensions

---

## Performance Targets

| Metric | Target | Note |
|--------|--------|------|
| Algorithm calculation | <5ms | Just math, no I/O |
| Cursor query (Sway IPC) | <20ms | Network roundtrip |
| Workspace query | <20ms | Network roundtrip |
| Window move (Sway IPC) | <20ms | Network roundtrip |
| **Total positioning latency** | **<50ms** | Keybinding → visible |

---

## Common Mistakes to Avoid

1. **Forgetting to use monitor-relative coordinates** on multi-monitor
   - Always subtract monitor offset before calculating position

2. **Not handling oversized windows**
   - Algorithm assumes window fits; add validation

3. **Using ceil instead of floor division**
   - Match bash: `window_width // 2` not `math.ceil(window_width / 2)`

4. **No fallback for missing cursor position**
   - Headless Wayland won't have cursor; use center as fallback

5. **Comparing floating-point coordinates directly**
   - Convert to int before comparison to avoid rounding surprises

6. **Not clamping negative coordinates**
   - Always return `(max(0, new_x), max(0, new_y))`

7. **Trusting workspace dimensions don't change**
   - Perform all queries in tight sequence, move immediately

8. **Forgetting to validate gap configuration**
   - Gaps larger than workspace cause negative break values

---

## Formula Reference

```
Available space:
  avail_h = workspace_h - gaps.top - gaps.bottom
  avail_w = workspace_w - gaps.left - gaps.right

Constraint boundaries:
  break_y = workspace_h - (gaps.bottom + window_h)
  break_x = workspace_w - (gaps.right + window_w)

Centered position:
  tmp_y = cursor_y - (window_h // 2)
  tmp_x = cursor_x - (window_w // 2)

Quadrant test (cursor location):
  cursor_in_lower_half = cursor_y >= (workspace_h / 2)
  cursor_in_right_half = cursor_x >= (workspace_w / 2)

Final constraints:
  if cursor_in_lower_half:
    new_y = min(tmp_y, break_y)
  else:
    new_y = max(tmp_y, gaps.top)

  if cursor_in_right_half:
    new_x = min(tmp_x, break_x)
  else:
    new_x = max(tmp_x, gaps.left)
```

---

## Implementation Status

**Phase**: Phase 0 (Research) ✅ **COMPLETE**

**Deliverables**:
- [x] BOUNDARY_DETECTION_ANALYSIS.md (8,500+ words, detailed)
- [x] ANALYSIS_SUMMARY.md (executive summary)
- [x] QUICK_REFERENCE.md (this file)

**Next Phases**:
- [ ] Phase 1: Data models, contracts, user guide
- [ ] Phase 2: Task breakdown and implementation
- [ ] Phase 3: Coding, testing, deployment

---

## Files Reference

**Read These First**:
1. `QUICK_REFERENCE.md` - You are here (2-minute overview)
2. `ANALYSIS_SUMMARY.md` - 10-minute executive summary
3. `BOUNDARY_DETECTION_ANALYSIS.md` - 30-minute deep dive

**Original Source**:
- `/etc/nixos/docs/budlabs-i3run-c0cc4cc3b3bf7341.txt` - Full i3run source code
- Lines 825-860: `sendtomouse.sh` function (17 lines of bash)

**Feature Spec**:
- `/etc/nixos/specs/051-i3run-scratchpad-enhancement/spec.md` - Requirements
- `/etc/nixos/specs/051-i3run-scratchpad-enhancement/plan.md` - Implementation plan

