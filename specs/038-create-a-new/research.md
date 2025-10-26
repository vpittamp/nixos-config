# Research: Window State Preservation

**Feature**: 038 - Window State Preservation Across Project Switches
**Date**: 2025-10-25
**Status**: Complete

## R001: i3 Window Property API

**Decision**: Use i3ipc.Con properties: `rect`, `floating`, `workspace()`, `window_rect`

**Available Properties** (from i3ipc.Con class):

### Position & Geometry Properties:
- **`rect`**: Rect object with `x`, `y`, `width`, `height` attributes - Outer container rectangle including decorations
- **`window_rect`**: Rect object - Actual window rectangle (inside decorations)
- **`geometry`**: Rect object - Original window geometry before i3 modifications
- **`deco_rect`**: Rect object - Decoration rectangle (titlebar, borders)

### State Properties:
- **`floating`**: str - One of: `"auto_on"`, `"auto_off"`, `"user_on"`, `"user_off"`
- **`focused`**: bool - Whether this container has focus
- **`fullscreen_mode`**: int - 0=not fullscreen, 1=fullscreen on output, 2=global fullscreen
- **`sticky`**: bool - Whether window is sticky (visible on all workspaces)
- **`scratchpad_state`**: str - Scratchpad state information

### Organizational Properties:
- **`marks`**: list[str] - List of marks applied to this window
- **`workspace()`**: method returning workspace Con object or None
- **`window`**: int - X11 window ID

**Scratchpad Detection**:
- **Method**: `workspace.name == "__i3_scratch"` (workspace-based detection)
- **Implementation**: Check if window's workspace name equals scratchpad magic name
- **Already Used**: Current implementation in window_filter.py lines 254-255

**Floating State Detection**:
```python
# Pattern 1 (simple):
is_floating = window.floating in ["user_on", "auto_on"]

# Pattern 2 (robust):
is_floating = window.floating not in ['auto_off', 'no']
```

**Geometry Access**:
```python
# Direct attribute access (recommended):
x = window.rect.x
y = window.rect.y
width = window.rect.width
height = window.rect.height

# For floating windows, use window_rect for actual window size:
width = window.window_rect.width
height = window.window_rect.height
```

**Workspace Access**:
```python
workspace = window.workspace()  # Returns Con object or None
if workspace:
    workspace_name = workspace.name  # e.g., "1", "2", "__i3_scratch"
    workspace_num = workspace.num   # Workspace number
```

**Rationale**:

These properties provide comprehensive state information for window preservation. The i3ipc library is the standard Python wrapper for i3 IPC protocol and provides all necessary properties with proper type handling.

**Alternatives Considered**: None - i3ipc is the only supported library for i3 IPC in Python.

---

## R002: i3 Restoration Commands

**Decision**: Use `[con_id=X] move to workspace number N` followed by floating/geometry commands

**Command Patterns**:

### Tiled Window Restoration
```bash
# Restore to exact workspace (preserves tiling state automatically)
i3-msg '[con_id=WINDOW_ID] move to workspace number WORKSPACE_NUM, floating disable'
```

### Floating Window Restoration
```bash
# Restore to workspace and enable floating
i3-msg '[con_id=WINDOW_ID] move to workspace number WORKSPACE_NUM, floating enable'

# Restore geometry (separate command for clarity)
i3-msg '[con_id=WINDOW_ID] resize set width WIDTH px height HEIGHT px; move position X px Y px'
```

**Key Findings**:

1. **Workspace Move Preserves State**: ✅ `move to workspace number N` preserves the window's current tiling/floating state
2. **Command Chaining**:
   - Comma (`,`) - executes commands sequentially on same window
   - Semicolon (`;`) - executes separate i3 commands
3. **Geometry Commands Only Affect Floating Windows**:
   - `move position X Y` - only works on floating windows
   - `resize set width W height H` - works on both, but tiled windows may be re-tiled
   - Best practice: Set `floating enable` BEFORE applying geometry commands
4. **Position/Size Units**:
   - `px` - pixels (absolute positioning)
   - `ppt` - percentage points (relative)
   - Use `px` for exact geometry preservation

**Current Implementation Status**:

The existing code in `window_filtering.py` (line 615) already uses the **correct workspace restoration pattern**:
```python
f'[con_id="{window_id}"] move to workspace number {workspace_number}, {floating_cmd}'
```

**What's Missing**:

Geometry restoration for floating windows. Need to add:
```python
if floating and geometry:
    geometry_cmd = (
        f'[con_id="{window_id}"] '
        f'resize set width {geometry["width"]} px height {geometry["height"]} px; '
        f'move position {geometry["x"]} px {geometry["y"]} px'
    )
    await conn.command(geometry_cmd)
```

**Rationale**:

Current workspace restoration is correct. Only missing piece is geometry restoration for floating windows, which requires a second i3 command after the window is moved and floating is enabled.

**Alternatives Considered**:

1. **Using `scratchpad show`** - ❌ Rejected: Shows on current workspace, not exact workspace
2. **Using `move workspace current`** - ❌ Rejected: Old buggy pattern that causes piling
3. **Single combined command** - ⚠️ Possible but less maintainable than two-command approach

---

## R003: Scratchpad Detection

**Decision**: Use workspace-based detection: `workspace.name == "__i3_scratch"`

**Detection Method**:
```python
workspace = window.workspace()
in_scratchpad = workspace and workspace.name == "__i3_scratch"
```

**Scratchpad Window Properties**:
- Workspace name is always `"__i3_scratch"`
- Workspace num is -1
- Windows in scratchpad are in floating_nodes list

**Already Implemented**:
Current code in window_filter.py (lines 254-255) already uses this pattern correctly.

**Rationale**:
Workspace-based detection is reliable and already proven in the existing codebase. The scratchpad workspace has a consistent magic name across all i3 installations.

**Alternatives Considered**: None - this is the standard detection method.

---

## R004: Floating Window Edge Cases

**Decision**: Accept i3's default behavior for offscreen windows

**Edge Case: Window Geometry Offscreen**

When restoring a floating window whose saved geometry would place it offscreen (due to monitor changes):

**i3's Default Behavior**:
- i3 automatically adjusts window position to be on-screen
- Windows are moved to nearest valid position within screen bounds
- Window size is preserved unless it exceeds screen dimensions

**Our Approach**:
- Accept i3's auto-adjustment behavior
- Do NOT implement custom bounds checking
- Trust i3 to handle edge cases gracefully

**Test Scenario**:
1. Save floating window at position (2000, 100) on a 2560x1440 monitor
2. Disconnect monitor, use single 1920x1080 monitor
3. Restore window with saved geometry (2000, 100)
4. Expected: i3 moves window to be visible (e.g., 1520, 100 or similar)

**Rationale**:

i3 has built-in logic to prevent windows from being placed offscreen. Implementing custom bounds checking would:
- Duplicate i3's logic
- Risk conflicts with i3's adjustments
- Add unnecessary complexity

Better to trust i3's well-tested auto-adjustment behavior.

**Alternatives Considered**:

1. **Custom bounds checking** - ❌ Rejected: Duplicates i3 logic, adds complexity
2. **Clamping to screen dimensions** - ❌ Rejected: i3 already does this
3. **Storing relative positions (ppt)** - ❌ Rejected: Loses exact pixel positions

---

## R005: Backward Compatibility

**Decision**: Use default values for missing fields (geometry=null, original_scratchpad=false)

**Backward Compatibility Strategy**:

When loading existing `window-workspace-map.json` files that lack new fields:

```python
# Load window state with defaults
window_state = window_map.get(str(window_id), {})

# Apply defaults for new fields (Feature 038)
geometry = window_state.get("geometry", None)  # Default: None
original_scratchpad = window_state.get("original_scratchpad", False)  # Default: False
```

**Migration Path**:

1. **No migration required** - daemon reads old JSON files without errors
2. **Gradual update** - new fields populated on next project switch
3. **Complete after** - one full cycle of project switches updates all windows

**Testing**:

Verified that Python's `dict.get(key, default)` returns default value when key is missing. No code changes needed for backward compatibility.

**Rationale**:

Using sensible defaults ensures:
- Old JSON files continue to work
- No daemon restart required
- No manual migration needed
- State gradually updates during normal usage

**Alternatives Considered**:

1. **Explicit migration script** - ❌ Rejected: Unnecessary, defaults work perfectly
2. **Version field in JSON** - ❌ Rejected: Over-engineering for simple schema extension
3. **Separate files for new data** - ❌ Rejected: Creates fragmentation

---

## Summary

All research questions have been resolved:

- ✅ **R001**: i3 window properties identified and access patterns documented
- ✅ **R002**: i3 restoration commands verified and implementation gaps identified
- ✅ **R003**: Scratchpad detection method confirmed (already implemented)
- ✅ **R004**: Edge case strategy defined (trust i3's auto-adjustment)
- ✅ **R005**: Backward compatibility strategy verified (dict.get() with defaults)

**Key Implementation Insights**:

1. Current workspace restoration logic is **already correct**
2. Only missing piece is **geometry restoration for floating windows**
3. Need to add 2 new fields to JSON schema: `geometry`, `original_scratchpad`
4. Backward compatibility is **automatic** via Python dict.get() defaults
5. No special edge case handling needed - i3 handles offscreen windows gracefully

**Ready for Phase 1**: Design & Contracts implementation
