# Feature 038: Window State Preservation - Quickstart Guide

**Feature Branch**: `038-create-a-new`
**Status**: ✅ IMPLEMENTED (v1.4.0)
**Created**: 2025-10-25
**Completed**: 2025-10-26

## 🎉 Implementation Complete

Feature 038 is now fully implemented and working! Windows correctly preserve their tiling/floating state and workspace assignments across project switches.

**Latest Version**: v1.4.0 (includes floating state preservation fix)
**Commit**: `287a94b` - Fix scratchpad floating state preservation

## Problem Summary

When switching between projects, windows are moved to the scratchpad to hide them. However, when switching back to the original project, windows are being restored as **floating** even if they were originally **tiled**. This breaks the user's workspace layout and causes confusion.

**Root Cause (v1.0-v1.3)**: State was captured AFTER windows moved to scratchpad, so windows were incorrectly recorded as floating.

**Fix (v1.4.0)**: State preservation now checks for existing saved state and preserves original floating value on subsequent hides.

## Implementation Notes (v1.4.0)

### The Scratchpad Floating Bug

**Problem Discovered**: Windows became floating after being hidden/restored during project switches, even when originally tiled.

**Root Cause Analysis**:
1. i3's `move scratchpad` command ALWAYS makes windows floating
2. State capture happened AFTER window moved to scratchpad (already floating)
3. On subsequent hides, code captured floating state from scratchpad (floating=True)
4. This overwrote the original tiled state (floating=False)

**Solution** (lines 437-448 in `window_filter.py`):
```python
# Check if we already have saved state for this window
saved_state = await workspace_tracker.get_window_workspace(window_id)
if saved_state and not is_original_scratchpad:
    # Preserve original floating state from first capture
    is_floating = saved_state.get("floating", False)
    geometry = saved_state.get("geometry", None)
else:
    # First capture OR window from scratchpad - capture current state
    is_floating = window.floating in ["user_on", "auto_on"]
    # ... capture geometry for floating windows ...
```

**Behavior**:
- **First hide**: Capture current window state (floating=True/False)
- **Subsequent hides**: Preserve original floating state from first capture
- **From scratchpad**: Re-capture current state (special case for manual scratchpad use)

**Inspired by i3run**: Pattern matches the `budlabs-i3run` tool which stores floating state BEFORE scratchpad move and uses `floating enable/disable` on restore.

### Testing Results

✅ **Verified working**:
1. Launch ghostty on nixos (tiled window)
2. Switch to stacks → ghostty hidden with `floating=False` captured
3. Switch back to nixos → ghostty restored as TILED (`floating=user_off`)
4. Daemon logs confirm: `Capturing state floating=False` → `Restoring floating=False`
5. i3 tree shows: `floating=user_off` (tiled ✅)

## Solution Overview

Extend the window state tracking system to capture and restore:
1. **Tiling/Floating state** - Ensure tiled windows stay tiled
2. **Exact workspace number** - Restore to original workspace, not current
3. **Window geometry** - For floating windows, preserve position and size
4. **Scratchpad origin** - Don't restore windows that were originally in scratchpad

## Quick Links

- **Specification**: `/etc/nixos/specs/038-create-a-new/spec.md`
- **Requirements Checklist**: `/etc/nixos/specs/038-create-a-new/checklists/requirements.md`
- **Feature Branch**: `038-create-a-new`

## Implementation Priority

### P1 - Critical (Implement First)
1. **User Story 1**: Preserve Tiled Window State
   - **Impact**: Fixes the core bug making project switching unusable
   - **Test**: Tiled window remains tiled after project switch

2. **User Story 3**: Preserve Workspace Assignment
   - **Impact**: Prevents all windows piling up on current workspace
   - **Test**: Windows return to exact workspace numbers

### P2 - Important (Implement Second)
3. **User Story 2**: Preserve Floating Window State
   - **Impact**: Maintains intentionally floated windows
   - **Test**: Floating window stays floating with same geometry

### P3 - Nice-to-Have (Implement Last)
4. **User Story 4**: Handle Scratchpad Native Windows
   - **Impact**: Edge case for users who use scratchpad manually
   - **Test**: Manually scratchpadded windows stay in scratchpad

## Key Technical Insights

### i3 Command Behavior

**Current (WRONG)**:
```bash
# This causes windows to become floating and appear on current workspace
i3-msg '[id=12345] move workspace current'
```

**Correct Approach**:
```bash
# This preserves tiling/floating state and moves to exact workspace
i3-msg '[id=12345] move workspace number 2'

# For floating windows, additionally restore geometry
i3-msg '[id=12345] floating enable'
i3-msg '[id=12345] move position 100 200'
i3-msg '[id=12345] resize set 800 600'

# For tiled windows, ensure they're tiled
i3-msg '[id=12345] floating disable'
```

### Data Model Extension

**Current `window-workspace-map.json`**:
```json
{
  "94481823493568": {
    "workspace_number": 2,
    "floating": false,
    "project_name": "nixos",
    "app_name": "vscode",
    "window_class": "Code",
    "last_seen": 1761432863.6978729
  }
}
```

**Extended (NEW)**:
```json
{
  "94481823493568": {
    "workspace_number": 2,
    "floating": false,
    "project_name": "nixos",
    "app_name": "vscode",
    "window_class": "Code",
    "last_seen": 1761432863.6978729,
    "geometry": null,              // NEW: {x, y, width, height} for floating
    "original_scratchpad": false   // NEW: true if was in scratchpad before filtering
  }
}
```

## Files to Modify

### 1. `window_filter.py` - Main Changes

**Location**: `home-modules/desktop/i3-project-event-daemon/services/window_filter.py`

**Hide Windows (Capture State)**:
```python
async def filter_windows_by_project(conn, project_name):
    # ... existing code to get windows ...

    for window in windows:
        # BEFORE hiding, capture full state
        workspace = window.workspace()
        rect = window.rect
        floating = window.floating

        # Save extended state
        window_state = {
            "workspace_number": workspace.num if workspace else 1,
            "floating": floating,
            "geometry": {
                "x": rect.x,
                "y": rect.y,
                "width": rect.width,
                "height": rect.height
            } if floating else None,
            "original_scratchpad": workspace.name == "__i3_scratch" if workspace else False,
            "project_name": window_project,
            "app_name": window.window_class,  # or from I3PM env
            "window_class": window.window_class,
            "last_seen": time.time()
        }

        await save_window_state(window.window, window_state)

        # Hide window
        await conn.command(f'[id={window.window}] move scratchpad')
```

**Show Windows (Restore State)**:
```python
async def filter_windows_by_project(conn, project_name):
    # ... existing code ...

    for window in windows_to_show:
        window_id = window.window

        # Load saved state
        state = await load_window_state(window_id)

        # Skip if originally in scratchpad
        if state.get("original_scratchpad", False):
            continue

        # Restore to exact workspace (NOT current!)
        ws_num = state.get("workspace_number", 1)
        await conn.command(f'[id={window_id}] move workspace number {ws_num}')

        # Restore floating state
        if state.get("floating", False):
            await conn.command(f'[id={window_id}] floating enable')

            # Restore geometry for floating windows
            if state.get("geometry"):
                geom = state["geometry"]
                await conn.command(
                    f'[id={window_id}] move position {geom["x"]} {geom["y"]}'
                )
                await conn.command(
                    f'[id={window_id}] resize set {geom["width"]} {geom["height"]}'
                )
        else:
            # Ensure tiled windows stay tiled
            await conn.command(f'[id={window_id}] floating disable')
```

### 2. `state.py` - Persistence Functions

**Location**: `home-modules/desktop/i3-project-event-daemon/state.py`

**Update Save Function**:
```python
async def save_window_workspace_map(self, window_map: dict) -> None:
    """Save window-workspace mapping to disk (now includes geometry)."""
    # ... existing persistence code, schema automatically supports new fields ...
```

**Update Load Function**:
```python
async def load_window_workspace_map(self) -> dict:
    """Load window-workspace mapping from disk."""
    # ... existing load code with backward compatibility ...
    # Missing 'geometry' defaults to None
    # Missing 'original_scratchpad' defaults to False
```

### 3. `ipc_server.py` - Debugging Support

**Location**: `home-modules/desktop/i3-project-event-daemon/ipc_server.py`

**Update get_window_state handler**:
```python
async def handle_get_window_state(self, request: dict) -> dict:
    """Return window state including geometry for debugging."""
    # ... existing code ...
    return {
        # ... existing fields ...
        "geometry": state.get("geometry"),
        "original_scratchpad": state.get("original_scratchpad", False)
    }
```

## Testing Procedure

### Manual Test - P1 (Critical)

**Setup**:
1. Switch to nixos project: `pswitch nixos`
2. Open VSCode on workspace 2: `code /etc/nixos`
3. Move to workspace 5: `i3-msg 'workspace 5'`
4. Open 2 terminals in horizontal split

**Test**:
1. Switch to stacks project: `pswitch stacks`
   - **Verify**: VSCode and terminals are hidden
2. Switch back to nixos: `pswitch nixos`
   - **Verify**: VSCode is tiled on workspace 2 (NOT floating)
   - **Verify**: Terminals are tiled on workspace 5 in horizontal split (NOT floating)
   - **Verify**: You're still on workspace 5 (windows didn't all appear on current workspace)

**Success Criteria**:
- ✅ 0 windows became floating (all stayed tiled)
- ✅ 100% of windows returned to correct workspace
- ✅ Window layout preserved (splits maintained)

### Manual Test - P2 (Important)

**Setup**:
1. Switch to nixos project
2. Open terminal on workspace 2
3. Make it floating: `i3-msg 'floating toggle'`
4. Move to position (200, 300) and resize to 800x600

**Test**:
1. Switch to stacks project
   - **Verify**: Floating terminal is hidden
2. Switch back to nixos
   - **Verify**: Terminal is floating (NOT tiled)
   - **Verify**: Terminal position is approximately (200, 300) ±10px
   - **Verify**: Terminal size is approximately 800x600 ±10px

**Success Criteria**:
- ✅ Window remained floating
- ✅ Position drift <10px
- ✅ Size drift <10px

## Performance Expectations

- **Capture state per window**: <1ms (reading i3 tree properties)
- **Save to disk**: <5ms (batched JSON write)
- **Restore per window**: <5ms (2-3 i3 commands)
- **Total for 10 windows**: <100ms (imperceptible to user)

## Backward Compatibility

✅ **Fully backward compatible**:
- Existing `window-workspace-map.json` files work without modification
- Missing `geometry` field defaults to `null` (will be added on next project switch)
- Missing `original_scratchpad` field defaults to `false`
- No daemon restart required for schema migration

## Rollout Plan

### Phase 1: P1 Implementation (MVP)
1. Extend data model with `geometry` and `original_scratchpad` fields
2. Modify `filter_windows_by_project()` to capture state before hiding
3. Modify `filter_windows_by_project()` to restore using exact workspace + floating state
4. Test with manual procedure (tiled windows)
5. Deploy and verify in production

### Phase 2: P2 Implementation
1. Add geometry restoration for floating windows
2. Test with manual procedure (floating windows)
3. Deploy and verify in production

### Phase 3: P3 Implementation (Optional)
1. Add `original_scratchpad` detection and handling
2. Test with manually scratchpadded windows
3. Deploy and verify in production

## Success Metrics

After implementation, the following should be true:

- **SC-001**: 100% of tiled windows remain tiled (currently ~0% - all become floating)
- **SC-002**: 100% of floating windows remain floating with <10px drift
- **SC-003**: 100% of windows return to assigned workspace (currently 0% - all go to current)
- **SC-004**: <50ms per window restore operation
- **SC-005**: Zero data loss across daemon restarts
- **SC-006**: Handles 3+ project switches per second without corruption

## Troubleshooting

**Issue**: Windows still becoming floating after implementation (FIXED in v1.4.0)

**Solution**: Update to v1.4.0 or later which includes the scratchpad floating state preservation fix.

**Debug** (if still experiencing issues):
```bash
# Check window state in persistence file (verify floating=false for tiled windows)
cat ~/.config/i3/window-workspace-map.json | jq '.windows[] | {id: .window_class, floating, workspace_number}'

# Check daemon logs during project switch (should see "preserved_state=True")
sudo journalctl -u i3-project-daemon.service --since "1 minute ago" | grep -E "Capturing state|preserved_state"

# Verify state capture shows preserved_state=True on subsequent hides
# Expected output: "Capturing state for window X: ... preserved_state=True"

# Verify restoration uses correct floating state
# Expected output: "Restoring window X to workspace Y, floating=False"
```

**Verify Fix**:
```bash
# 1. Launch tiled window and check state
i3-msg -t get_tree | jq -r '.. | objects | select(.window_properties?.class == "com.mitchellh.ghostty") | "\(.id): floating=\(.floating)"'
# Should show: floating=user_off (tiled)

# 2. Switch projects twice
i3pm project switch stacks
sleep 2
i3pm project switch nixos
sleep 2

# 3. Verify window is still tiled
i3-msg -t get_tree | jq -r '.. | objects | select(.window_properties?.class == "com.mitchellh.ghostty") | "\(.id): floating=\(.floating)"'
# Should STILL show: floating=user_off (tiled ✅)
```

**Issue**: Windows not restoring to correct workspace

**Debug**:
```bash
# Check recorded workspace numbers
cat ~/.config/i3/window-workspace-map.json | jq '.windows[] | {workspace_number, project_name, window_class}'

# Verify workspace exists
i3-msg -t get_workspaces | jq '.[] | .num'
```

## Related Documentation

- **Feature 037**: Mark-based window filtering (provides window identification)
- **Feature 035**: Registry-centric architecture (provides application registry)
- **Feature 015**: Event-driven project management (provides daemon foundation)
- **i3ass Documentation**: `/etc/nixos/docs/budlabs-i3ass-81e224f956d0eab9.txt`

## Questions?

- **Full Specification**: `/etc/nixos/specs/038-create-a-new/spec.md`
- **Requirements Checklist**: `/etc/nixos/specs/038-create-a-new/checklists/requirements.md`
- **Implementation Branch**: `038-create-a-new`

---

**Status**: ✅ IMPLEMENTED (v1.4.0)
**Completion Date**: 2025-10-26
**Next Step**: Feature complete! Monitor for edge cases and refinements.
