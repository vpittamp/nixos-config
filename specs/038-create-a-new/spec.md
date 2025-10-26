# Feature Specification: Window State Preservation Across Project Switches

**Feature Branch**: `038-create-a-new`
**Created**: 2025-10-25
**Status**: Draft
**Input**: User description: "create a new feature that addresses the following problem. when we switch projects, it appears that windows are moved to scratchpad, and when we switch back to the project, the window is floating, which is not what we want and is causing the correct filtering logic. review this project @docs/budlabs-i3ass-81e224f956d0eab9.txt, specifically the irun and ikings topics which look to address the nuanced behavior of windows. this logic may help understand some of the issues that we're facing."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Preserve Tiled Window State (Priority: P1)

When I switch away from a project and then switch back, my tiled windows should remain tiled and in their exact previous positions.

**Why this priority**: This is the core issue causing the floating window bug. Windows that were tiled are becoming floating when restored from scratchpad, breaking the entire project switching workflow. This must be fixed for the system to be usable.

**Independent Test**: Can be fully tested by opening a tiled terminal in nixos project, switching to stacks project, then switching back to nixos. Terminal should remain tiled in same position, not floating.

**Acceptance Scenarios**:

1. **Given** a VSCode window is tiled on workspace 2 in the nixos project, **When** I switch to the stacks project and then back to nixos, **Then** VSCode should be tiled on workspace 2 in its original position and size
2. **Given** multiple tiled terminals in a horizontal split on workspace 5, **When** I switch projects and return, **Then** all terminals remain in their tiled split layout with exact same dimensions
3. **Given** a window is fullscreen on workspace 1, **When** I switch projects and return, **Then** the window is still fullscreen on workspace 1

---

### User Story 2 - Preserve Floating Window State (Priority: P2)

When I switch away from a project that has floating windows and then switch back, those windows should remain floating with their exact geometry (position, size).

**Why this priority**: While less critical than the tiled window bug (P1), preserving floating state is important for windows that users intentionally floated. This ensures complete state preservation.

**Independent Test**: Can be fully tested by making a terminal float in the nixos project, moving it to a specific position, switching projects, then switching back. The terminal should remain floating in the exact same position and size.

**Acceptance Scenarios**:

1. **Given** a floating calculator window positioned at coordinates (100, 200) with size 400x300, **When** I switch projects and return, **Then** the calculator is floating at (100, 200) with size 400x300
2. **Given** a floating Ghostty terminal at the top-right corner of the screen, **When** I switch projects and return, **Then** the terminal remains floating at the top-right corner
3. **Given** a window transitions from tiled to floating while the project is active, **When** I switch projects and return, **Then** the window is floating (not reverting to tiled)

---

### User Story 3 - Preserve Workspace Assignment (Priority: P1)

When windows are restored from scratchpad, they should return to their exact workspace number, not just "current workspace".

**Why this priority**: Critical for multi-workspace workflows. Without this, all windows would pile up on the current workspace instead of distributing across their assigned workspaces.

**Independent Test**: Can be fully tested by opening VSCode on WS2 and terminals on WS5 in nixos project, switching to stacks, then switching back while focused on WS1. VSCode should appear on WS2 and terminals on WS5, not all on WS1.

**Acceptance Scenarios**:

1. **Given** VSCode is on workspace 2 and terminal is on workspace 5, **When** I switch projects while focused on workspace 1, then switch back, **Then** VSCode is on workspace 2 and terminal is on workspace 5 (not workspace 1)
2. **Given** 10 windows distributed across workspaces 2, 3, and 5, **When** I switch projects and return, **Then** each window returns to its exact original workspace number
3. **Given** a window manually moved from WS2 to WS7, **When** I switch projects and return, **Then** the window is on WS7 (the manual move is persisted)

---

### User Story 4 - Handle Scratchpad Native Windows (Priority: P3)

Windows that were originally in the scratchpad (not just hidden by project filtering) should remain in scratchpad when restored.

**Why this priority**: Lower priority because scratchpad usage is less common in the i3pm workflow, but still important for users who use scratchpad for quick-access windows.

**Independent Test**: Can be fully tested by moving a window to scratchpad manually (not via project switch), switching projects, then switching back. Window should remain in scratchpad, not restored to a workspace.

**Acceptance Scenarios**:

1. **Given** a notes window manually moved to scratchpad by user, **When** project switches occur, **Then** the notes window remains in scratchpad across all project contexts
2. **Given** a scratchpad window belonging to "nixos" project, **When** I switch to "stacks" then back to "nixos", **Then** the window is still in scratchpad (not auto-restored to a workspace)

---

### Edge Cases

- What happens when a window's workspace no longer exists (workspace was deleted)?
  - Solution: Fall back to assigning window to workspace 1 or current workspace
- What happens when restoring a window to a workspace that's on a different monitor than before?
  - Solution: Allow the window to move to the new monitor if workspace assignments changed via monitor configuration
- What happens when a window is manually moved to a different workspace while a project is active?
  - Solution: The new workspace assignment should be persisted and used for future switches
- What happens when the window geometry (position/size) would place the window offscreen due to monitor changes?
  - Solution: Auto-adjust window position to be on-screen, similar to i3run's gap handling behavior
- What happens when switching projects very rapidly (multiple times per second)?
  - Solution: Window state tracking should handle this gracefully, potentially using the existing worker queue mechanism

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST record the tiling/floating state of each window when it is hidden (moved to scratchpad)
- **FR-002**: System MUST record the exact workspace number for each window when it is hidden
- **FR-003**: System MUST record the window geometry (x, y, width, height) for floating windows
- **FR-004**: System MUST record the window's container position in the tiling tree for tiled windows (to preserve split layouts)
- **FR-005**: System MUST restore windows to their exact previous floating/tiled state when showing them
- **FR-006**: System MUST restore windows to their exact previous workspace when showing them (not "current workspace")
- **FR-007**: System MUST restore floating windows to their exact previous geometry (position and size)
- **FR-008**: System MUST restore tiled windows to appropriate tiling positions (may not be pixel-perfect due to i3 tiling algorithm)
- **FR-009**: System MUST persist window state to disk to survive daemon restarts (extend existing `window-workspace-map.json`)
- **FR-010**: System MUST handle windows that were originally in scratchpad (not moved by project filtering) and keep them in scratchpad

### Key Entities

- **WindowState**: Extended window state information stored in `window-workspace-map.json`
  - Existing attributes: `workspace_number`, `floating`, `project_name`, `app_name`, `window_class`, `last_seen`
  - New attributes: `geometry` (x, y, width, height), `original_scratchpad` (boolean flag), `tiling_position` (optional tree position data)
- **ScratchpadCommand**: i3 command to move window to scratchpad while recording state
- **RestoreCommand**: i3 command to restore window from scratchpad using recorded state

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: 100% of tiled windows remain tiled when switching projects (0% incorrectly become floating)
- **SC-002**: 100% of floating windows remain floating with <10px position/size drift when switching projects
- **SC-003**: 100% of windows return to their assigned workspace number (not current workspace)
- **SC-004**: Window restore operation completes in <50ms per window (maintaining current performance)
- **SC-005**: Zero data loss of window state across daemon restarts (state persisted to disk)
- **SC-006**: System handles rapid project switches (3+ switches per second) without window state corruption

## Implementation Notes

### i3 Scratchpad Behavior Insights

Based on analysis of i3ass documentation (i3run and i3king), key insights about i3 window behavior:

**From i3run (lines 9941-9949)**:
```
Active and not handled by i3fyra     | send to scratchpad
Active and handled by i3fyra         | send container to scratchpad
Handled by i3fyra and hidden         | **show** container
Not handled by i3fyra and hidden     | **show** window
Not on current workspace             | goto workspace and focus window
Not active, not hidden, on workspace | focus window
Not found                            | execute COMMAND
```

**Key takeaway**: i3run distinguishes between "window" and "container" operations. When showing windows from scratchpad, the command used matters:
- `move scratchpad` - hides the window/container
- `scratchpad show` - shows window on **current workspace** (this is the problem!)
- `[id=X] move workspace N` - moves window to specific workspace while preserving state

**Critical insight**: We should NOT use `scratchpad show` for restoration. Instead, use `[id=WINDOW_ID] move workspace WORKSPACE_NUMBER` which preserves the window's tiling/floating state.

**From i3king behavior**:
- i3king applies rules to windows when they are created AND when i3 restarts
- On restart, all windows lose container IDs and marks, so i3king re-matches all windows
- This demonstrates that window state CAN be preserved across significant i3 events

### Current Implementation Issues

**Current code in `window_filter.py` (lines 244-246)**:
```python
if in_scratchpad:
    # Restore from scratchpad to current workspace
    await conn.command(f'[id={window_id}] move workspace current')
```

**Problems**:
1. Uses `move workspace current` instead of `move workspace NUMBER` - causes windows to pile up on current workspace
2. Doesn't check or restore the window's floating state
3. Doesn't preserve window geometry for floating windows

### Proposed Solution

**Step 1**: Extend `window-workspace-map.json` schema to include:
```json
{
  "94481823493568": {
    "workspace_number": 2,
    "floating": false,
    "project_name": "nixos",
    "app_name": "vscode",
    "window_class": "Code",
    "last_seen": 1761432863.6978729,
    "geometry": null,  // NEW: null for tiled, {x, y, width, height} for floating
    "original_scratchpad": false  // NEW: true if window was in scratchpad before project filtering
  }
}
```

**Step 2**: When hiding windows (`filter_windows_by_project`), capture full state:
```python
# Query window state before hiding
workspace = window.workspace()
rect = window.rect  # i3ipc provides x, y, width, height
floating = window.floating

# Store in window-workspace-map.json
window_state = {
    "workspace_number": workspace.num,
    "floating": floating,
    "geometry": {"x": rect.x, "y": rect.y, "width": rect.width, "height": rect.height} if floating else None,
    "original_scratchpad": workspace.name == "__i3_scratch",
    # ... existing fields
}

# Save to disk
await save_window_state(window_id, window_state)

# Hide window
await conn.command(f'[id={window_id}] move scratchpad')
```

**Step 3**: When restoring windows, use exact state:
```python
# Load state from window-workspace-map.json
window_state = await load_window_state(window_id)

# Don't restore windows that were originally in scratchpad
if window_state.get("original_scratchpad", False):
    logger.debug(f"Window {window_id} was originally in scratchpad, leaving hidden")
    return

# Restore to exact workspace (not current!)
workspace_num = window_state.get("workspace_number", 1)
await conn.command(f'[id={window_id}] move workspace number {workspace_num}')

# Restore floating state and geometry
if window_state.get("floating", False) and window_state.get("geometry"):
    geom = window_state["geometry"]
    await conn.command(f'[id={window_id}] floating enable')
    await conn.command(
        f'[id={window_id}] move position {geom["x"]} {geom["y"]}; '
        f'resize set {geom["width"]} {geom["height"]}'
    )
else:
    # Ensure window is tiled (in case it was accidentally floated)
    await conn.command(f'[id={window_id}] floating disable')
```

### Files to Modify

1. **`home-modules/desktop/i3-project-event-daemon/services/window_filter.py`**
   - Modify `filter_windows_by_project()` to capture full window state before hiding
   - Modify restoration logic to use exact workspace and floating state

2. **`home-modules/desktop/i3-project-event-daemon/state.py`**
   - Extend `save_window_workspace_map()` to include geometry and floating state
   - Extend `load_window_workspace_map()` to read new fields

3. **`home-modules/desktop/i3-project-event-daemon/ipc_server.py`**
   - Update `get_window_state()` handler to include geometry information for debugging

### Testing Strategy

**Manual Testing**:
1. Open tiled VSCode on WS2 in nixos project
2. Open floating calculator at (100, 200)
3. Open tiled terminals in split layout on WS5
4. Switch to stacks project → verify all windows hidden
5. Switch back to nixos → verify:
   - VSCode is tiled on WS2
   - Calculator is floating at (100, 200)
   - Terminals are tiled in split on WS5

**Automated Testing** (future):
- Could extend `i3-project-test` framework to validate window state preservation
- Compare window tree before/after project switch using i3 IPC `GET_TREE`

### Performance Considerations

- Reading window state: Already reading i3 tree, adding geometry is negligible
- Saving to disk: Batch writes to `window-workspace-map.json` (already done)
- Restoring windows: 2-3 i3 commands per window (negligible, <5ms total)
- Expected impact: <10ms overhead per project switch for 10 windows

### Compatibility Notes

- This change is backward compatible with existing `window-workspace-map.json` files
- Missing `geometry` or `original_scratchpad` fields will default to sensible values (null/false)
- No changes to daemon API or CLI commands required
