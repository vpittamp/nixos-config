# Research: Eww Interactive Menu Stabilization

**Feature**: 073-eww-menu-stabilization | **Date**: 2025-11-13

## Overview

This document captures research findings and technical decisions for stabilizing the Eww workspace preview menu with per-window actions. The primary challenge is Eww's limited native keyboard support due to GTK3 widget focus issues, requiring external keyboard handling via Sway keybindings and daemon IPC.

## Technical Decisions

### Decision 1: Eww Window Type Configuration

**Decision**: Use `windowtype "dock"` instead of `windowtype "normal"` for the Eww workspace preview window.

**Rationale**:
- Eww GTK3 widgets steal keyboard focus when windowtype is "normal", preventing Sway keybindings from firing
- Eww maintainer recommendations and community best practices suggest "dock" windowtype for keyboard-driven overlays
- "dock" windows pass keyboard events through to the window manager without interception
- This aligns with Eww's design philosophy: Eww is for display/rendering, not keyboard input handling

**Alternatives Considered**:
1. **GTK event handlers in Eww** - Rejected because Eww's GTK3 event system is unreliable for keyboard input and requires complex JavaScript event forwarding
2. **Custom input method** - Rejected as unnecessary complexity; Sway keybindings are more reliable and maintainable
3. **Keep "normal" and fix focus** - Rejected because GTK focus management is fragile and would create ongoing maintenance burden

**Implementation Impact**:
- Change `windowtype "normal"` to `windowtype "dock"` in `home-modules/desktop/eww-workspace-bar.nix`
- Existing workspace mode keybindings will continue to work (CapsLock/Ctrl+0, arrow keys, Enter)
- Delete key binding will now fire correctly in Sway when workspace mode is active

**Reference**:
- Eww documentation: https://elkowar.github.io/eww/configuration.html#window-types
- Community discussions on Eww Discord about keyboard input best practices

---

### Decision 2: Action Handler Architecture

**Decision**: Implement window actions as async handler functions in a new `action_handlers.py` module, dispatched from the workspace-preview-daemon's main event loop.

**Rationale**:
- Aligns with existing daemon architecture (async/await patterns, i3ipc.aio)
- Enables proper error handling and user feedback for failed actions
- Maintains <20ms state update latency by using async operations
- Follows Constitution Principle X (Python Development & Testing Standards)

**Alternatives Considered**:
1. **Synchronous handlers with threading** - Rejected because adds complexity and doesn't align with existing i3ipc.aio async patterns
2. **External CLI commands** - Rejected because adds IPC overhead and makes testing more difficult
3. **Inline action logic in daemon** - Rejected because violates single-responsibility principle and makes testing harder

**Handler Design Pattern**:
```python
async def handle_window_close(
    sway_connection: i3ipc.aio.Connection,
    window_id: int,
    debounce_tracker: Dict[int, float]
) -> ActionResult:
    """
    Close a window via Sway IPC.

    Args:
        sway_connection: Active Sway IPC connection
        window_id: Container ID of window to close
        debounce_tracker: Dict mapping window_id to last action timestamp

    Returns:
        ActionResult with success status, latency, and optional error message

    Raises:
        ValueError: If window_id is invalid
        WindowRefusedClose: If window refuses to close (unsaved changes)
    """
    # Debounce check (100ms minimum between operations)
    # Sway IPC close command
    # Verify window closed (query tree after 200ms)
    # Return ActionResult
```

**Key Actions to Implement** (from spec requirements):
- FR-002: `handle_window_close()` - Close selected window with debouncing
- FR-010: `handle_window_move()` - Move window to specified workspace
- FR-010: `handle_window_float_toggle()` - Toggle floating/tiling state
- FR-010: `handle_window_focus()` - Focus window in split container
- FR-010: `handle_window_mark()` - Mark window for later reference

---

### Decision 3: Sub-Mode State Management

**Decision**: Implement sub-modes (move window, resize, mark) as a state machine in a new `sub_mode_manager.py` module with explicit enter/exit transitions.

**Rationale**:
- Sub-modes have distinct keyboard behavior (e.g., "M" for move enters sub-mode, numeric keys select workspace, Enter executes)
- State machine pattern provides clear transition logic and error handling
- Enables clean cancellation with Escape key (FR-012)
- Supports visual feedback for sub-mode prompts (FR-011)

**Alternatives Considered**:
1. **Implicit mode switching** - Rejected because makes state tracking difficult and error-prone
2. **Nested event handlers** - Rejected because adds complexity and makes testing harder
3. **Modal dialogs** - Rejected because breaks keyboard-driven workflow and adds latency

**State Machine Design**:
```
States:
- NORMAL: Default state, navigation with arrow keys
- MOVE_WINDOW: Awaiting workspace number input (digits + Enter)
- FLOAT_TOGGLE: Immediate action, return to NORMAL
- MARK_WINDOW: Awaiting mark name input (letters + Enter)

Transitions:
- NORMAL + "M" key → MOVE_WINDOW
- MOVE_WINDOW + digits → Accumulate workspace number
- MOVE_WINDOW + Enter → Execute move, return to NORMAL
- ANY_STATE + Escape → NORMAL
- NORMAL + "F" key → FLOAT_TOGGLE → NORMAL (immediate)
```

**Visual Feedback**:
- Sub-mode prompt overlays in Eww preview card
- Examples: "Move window to workspace: 23_", "Mark window as: _", "Float toggle applied ✓"

---

### Decision 4: Keyboard Shortcut Hints Display

**Decision**: Implement keyboard hint generation in a new `keyboard_hint_manager.py` module, updating Eww defvar `keyboard_hints` with formatted help text.

**Rationale**:
- Improves discoverability for new users (SC-004: 90% discover Delete key within 30 seconds)
- Reduces cognitive load by showing available actions contextually
- Uses existing Eww `defvar` + `eww update` pattern for <20ms latency
- Supports dynamic hints based on selection type (workspace heading vs window)

**Alternatives Considered**:
1. **Static help text in Eww** - Rejected because cannot adapt to selection context
2. **Tooltip on hover** - Rejected because keyboard-driven workflow doesn't use mouse hover
3. **Separate help window** - Rejected because adds complexity and visual clutter

**Hint Format**:
```
Footer text: "↑/↓ Navigate | Enter Select | Delete Close | M Move | F Float | Esc Cancel"

Context-aware variations:
- On workspace heading: "↑/↓ Navigate | Enter Select | : Project | Esc Cancel" (no Delete/Move/Float)
- In MOVE_WINDOW mode: "Type workspace: 23_ | Enter Confirm | Esc Cancel"
- In MARK_WINDOW mode: "Type mark name: my-window_ | Enter Confirm | Esc Cancel"
```

**Update Mechanism**:
```python
async def update_keyboard_hints(
    selection_type: SelectionType,
    sub_mode: SubMode
) -> str:
    """Generate keyboard hint text based on current state."""
    hints = []

    if sub_mode == SubMode.NORMAL:
        hints.extend(["↑/↓ Navigate", "Enter Select"])
        if selection_type == SelectionType.WINDOW:
            hints.extend(["Delete Close", "M Move", "F Float"])
        hints.append(": Project")
        hints.append("Esc Cancel")
    elif sub_mode == SubMode.MOVE_WINDOW:
        hints = ["Type workspace: _", "Enter Confirm", "Esc Cancel"]
    # ... other sub-modes

    hint_text = " | ".join(hints)
    await run_async(["eww", "update", f"keyboard_hints={hint_text}"])
    return hint_text
```

---

### Decision 5: Multi-Action Workflow Support

**Decision**: Keep workspace mode active after window close operations, automatically moving selection to the next logical item (next window or previous if at end).

**Rationale**:
- Enables power users to batch window management tasks efficiently (US2)
- Reduces friction from repeatedly entering/exiting workspace mode
- Follows common GUI file manager patterns (e.g., delete file, selection moves to next)
- Aligns with FR-003: "System MUST keep preview menu open after window close"

**Alternatives Considered**:
1. **Exit mode after each action** - Rejected because forces repetitive mode entry/exit for multi-action workflows
2. **Require modifier key to stay in mode** - Rejected because adds cognitive load and breaks workflow momentum
3. **Configurable behavior** - Rejected as unnecessary complexity; staying in mode is always preferable

**Selection Movement Logic**:
```python
async def move_selection_after_close(
    items: List[SelectableItem],
    closed_index: int
) -> int:
    """
    Determine new selection index after closing a window.

    Logic:
    - If items remain after closed_index, select next item (same index)
    - If at end, select previous item (index - 1)
    - If last item closed, exit workspace mode automatically (FR-007)

    Returns:
        New selection index, or -1 if no items remain
    """
    if len(items) == 0:
        return -1  # Trigger mode exit
    if closed_index < len(items):
        return closed_index  # Next item
    return closed_index - 1  # Previous item (at end)
```

---

### Decision 6: Window Close Failure Handling

**Decision**: Detect close failures via Sway IPC tree queries 500ms after close command, show notification explaining failure, keep window in preview list.

**Rationale**:
- Some windows refuse close operations (unsaved changes, critical system windows) - FR-006
- User needs feedback explaining why close failed (actionable error messages)
- Keeping window in list allows user to try alternative actions (save changes, force close)
- 500ms timeout balances responsiveness with X11 processing delays

**Alternatives Considered**:
1. **Force kill on failure** - Rejected as dangerous; could cause data loss
2. **Silent failure** - Rejected because leaves user confused about state
3. **Immediate verification** - Rejected because X11/Wayland processing may not be complete

**Failure Detection Pattern**:
```python
async def verify_window_closed(
    sway_connection: i3ipc.aio.Connection,
    window_id: int,
    timeout_ms: int = 500
) -> Tuple[bool, Optional[str]]:
    """
    Verify a window closed successfully.

    Returns:
        (success: bool, error_message: Optional[str])
    """
    await asyncio.sleep(timeout_ms / 1000.0)

    tree = await sway_connection.get_tree()
    window_still_exists = find_container_by_id(tree, window_id) is not None

    if window_still_exists:
        return (False, "Window refused to close (may have unsaved changes)")
    return (True, None)
```

**User Notification**:
- Use `notify-send` or SwayNC for desktop notifications
- Message: "Window refused to close (may have unsaved changes)"
- Icon: Warning icon from system theme

---

### Decision 7: Performance Optimization - Debouncing

**Decision**: Implement 100ms debounce for rapid Delete key presses using timestamp tracking per window ID.

**Rationale**:
- Prevents race conditions from rapid keypress repetition
- Protects against accidental double-closes
- Aligns with FR-008: "minimum 100ms between operations"
- Minimal user impact (100ms is imperceptible delay)

**Alternatives Considered**:
1. **No debouncing** - Rejected because allows duplicate close attempts and race conditions
2. **Longer debounce (500ms+)** - Rejected because slows down legitimate fast workflows
3. **Global debounce** - Rejected because blocks actions on different windows

**Debounce Implementation**:
```python
from typing import Dict
import time

# Module-level state
last_action_timestamp: Dict[int, float] = {}

async def handle_window_close(
    sway_connection: i3ipc.aio.Connection,
    window_id: int
) -> ActionResult:
    """Close window with debouncing."""
    current_time = time.time()
    last_action_time = last_action_timestamp.get(window_id, 0)

    if current_time - last_action_time < 0.1:  # 100ms debounce
        return ActionResult(
            success=False,
            latency_ms=0,
            error="Action debounced (too fast)"
        )

    last_action_timestamp[window_id] = current_time
    # ... execute close command
```

---

### Decision 8: Testing Strategy

**Decision**: Implement 3-layer testing: Unit tests (pytest), integration tests (pytest + mock Sway), end-to-end tests (sway-test framework).

**Rationale**:
- Aligns with Constitution Principle XIV (Test-Driven Development)
- Unit tests validate business logic quickly (<1s execution)
- Integration tests validate daemon IPC communication
- End-to-end tests validate real Sway window manager behavior
- Follows test pyramid (70% unit, 20% integration, 10% e2e)

**Alternatives Considered**:
1. **Manual testing only** - Rejected because doesn't scale, error-prone, no regression detection
2. **E2E tests only** - Rejected because too slow, fragile, poor test isolation
3. **No mocking** - Rejected because requires running Sway session for all tests

**Test Coverage Targets** (from spec SC-001 through SC-010):
- Unit tests: Action handlers (close, move, float), keyboard hint generation, sub-mode state machine
- Integration tests: Daemon IPC communication, Eww update commands, Sway IPC queries
- E2E tests: Window close success rate (100% target), multi-action workflows (<10s for 5 closes), keyboard hint visibility (<50ms)

**Example sway-test Test Case** (US1 - Reliable Window Close):
```json
{
  "name": "Delete key closes selected window",
  "description": "Validate FR-002: Window closes within 500ms",
  "tags": ["window-actions", "delete-key", "p1"],
  "timeout": 2000,
  "actions": [
    {
      "type": "launch_app_sync",
      "params": {"app_name": "alacritty"}
    },
    {
      "type": "send_ipc_sync",
      "params": {"ipc_command": "mode → WS"}
    },
    {
      "type": "send_key_sync",
      "params": {"key": "Delete"}
    }
  ],
  "expectedState": {
    "windowCount": 0,
    "workspaces": [
      {"num": 1, "windows": []}
    ]
  }
}
```

---

## Integration Points

### Integration 1: Sway Keybindings

**File**: `home-modules/desktop/sway-keybindings.nix`

**Changes Required**:
```nix
# Add to workspace mode keybindings
mode "→ WS" {
  # Existing keybindings (digits, Enter, Escape)
  # ...

  # NEW: Window actions
  bindsym Delete exec workspace-preview-daemon --action close-window
  bindsym m exec workspace-preview-daemon --action enter-move-mode
  bindsym f exec workspace-preview-daemon --action float-toggle
  # bindsym r exec workspace-preview-daemon --action mark-window  # Future: US4
}

# Similar bindings for "⇒ WS" move mode
```

**Rationale**: Sway keybindings dispatch to daemon via IPC, keeping keyboard handling logic centralized.

---

### Integration 2: Eww Widget Configuration

**File**: `home-modules/desktop/eww-workspace-bar.nix`

**Changes Required**:
```nix
# workspace-mode-preview.yuck
(defwindow workspace-mode-preview
  :monitor 0
  :geometry (geometry
    :x "0"
    :y "0"
    :width "100%"
    :height "100%"
    :anchor "center")
  :stacking "overlay"
  :windowtype "dock"  # CHANGE: "normal" → "dock"
  :exclusive false

  (workspace-preview-card))

# workspace-preview-card.yuck
(defvar keyboard_hints "↑/↓ Navigate | Enter Select | Delete Close | Esc Cancel")

(defwidget workspace-preview-card []
  (box :class "preview-card"
       :orientation "v"
       :space-evenly false

    (scroll :height 600
      (box :orientation "v"
        (for workspace in workspaces
          (workspace-section :workspace workspace))))

    ;; NEW: Keyboard hint footer
    (box :class "keyboard-hints"
         :halign "center"
      (label :text keyboard_hints))))
```

**Rationale**: Windowtype "dock" fixes keyboard passthrough, keyboard hints defvar provides <20ms updates.

---

### Integration 3: Workspace Preview Daemon

**File**: `home-modules/tools/sway-workspace-panel/workspace-preview-daemon`

**Changes Required**:
```python
# Main event loop
async def handle_workspace_mode_event(event: Dict[str, Any]):
    """Handle workspace mode IPC events from i3pm daemon."""
    action = event.get("action")

    if action == "close-window":
        await handle_window_close_action()
    elif action == "enter-move-mode":
        await enter_sub_mode(SubMode.MOVE_WINDOW)
    elif action == "float-toggle":
        await handle_float_toggle_action()
    # ... other actions

async def handle_window_close_action():
    """Execute window close action with debouncing and verification."""
    selected_window_id = get_selected_window_id()

    result = await action_handlers.handle_window_close(
        sway_connection=sway,
        window_id=selected_window_id,
        debounce_tracker=window_action_timestamps
    )

    if not result.success:
        await show_notification(result.error)
        return

    # Move selection to next item
    new_index = await move_selection_after_close(
        items=current_preview_items,
        closed_index=current_selection_index
    )

    if new_index == -1:
        await exit_workspace_mode()  # Last window closed
    else:
        await update_selection(new_index)
        await update_preview_ui()
```

**Rationale**: Centralized action dispatch with clear error handling and state management.

---

## Risk Mitigation

### Risk 1: Eww Windowtype Change Breaks Existing Behavior

**Likelihood**: Low | **Impact**: High

**Mitigation**:
- Test windowtype "dock" on all platforms (Hetzner, M1 Mac) before merging
- Verify existing keybindings (CapsLock, Ctrl+0, arrow keys, Enter) still work
- Document rollback procedure (revert windowtype to "normal")

**Test Cases**:
- Basic navigation (arrow keys, Enter) - must work
- Workspace mode entry/exit (CapsLock, Escape) - must work
- Multi-monitor preview (Feature 057) - must not break

---

### Risk 2: Window Close Verification Timeout Too Short/Long

**Likelihood**: Medium | **Impact**: Medium

**Mitigation**:
- Start with conservative 500ms timeout (from FR-002 requirement)
- Add configurable timeout in daemon config if needed
- Monitor close operation latency in production (p95 metric from SC-002)

**Fallback**:
- If 500ms too short, increase to 1000ms (still meets <2s constraint from SC-007)
- If 500ms too long, decrease to 200ms (but verify window close completion)

---

### Risk 3: Sub-Mode State Machine Complexity

**Likelihood**: Low | **Impact**: Medium

**Mitigation**:
- Keep state machine simple (max 5 states initially)
- Comprehensive unit tests for state transitions
- Explicit Escape key cancellation from all states (FR-012)

**Simplification Strategy**:
- Start with 3 sub-modes: MOVE_WINDOW, FLOAT_TOGGLE (immediate), MARK_WINDOW
- Defer RESIZE and other complex sub-modes to future enhancements

---

## Open Questions

### Question 1: Should floating/tiling toggle be immediate or require confirmation?

**Status**: Resolved

**Resolution**: Immediate action (no confirmation) - float toggle is non-destructive and easily reversible. Matches Sway's native `Mod+Shift+Space` behavior.

---

### Question 2: How to handle project navigation (":") from workspace mode?

**Status**: Resolved

**Resolution**: Defer to existing project search implementation (US5, Priority P3). Already handled by workspace-preview-daemon in Feature 072.

---

## References

- **Eww Documentation**: https://elkowar.github.io/eww/
- **i3ipc-python Documentation**: https://i3ipc-python.readthedocs.io/
- **Sway IPC Protocol**: https://github.com/swaywm/sway/blob/master/sway/sway-ipc.7.scd
- **Feature 059 (Interactive Workspace Menu)**: /etc/nixos/specs/059-interactive-workspace-menu/
- **Feature 072 (Unified Workspace Switcher)**: /etc/nixos/specs/072-unified-workspace-switcher/
- **Constitution Principle X (Python Development)**: /.specify/memory/constitution.md
- **Constitution Principle XIV (Test-Driven Development)**: /.specify/memory/constitution.md
- **Constitution Principle XV (Sway Test Framework)**: /.specify/memory/constitution.md

---

**Research Complete**: 2025-11-13 | **Next Phase**: Phase 1 - Data Model & Contracts
