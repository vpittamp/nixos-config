# Data Model: Eww Interactive Menu Stabilization

**Feature**: 073-eww-menu-stabilization | **Date**: 2025-11-13

## Overview

This document defines the data models and their relationships for the Eww workspace preview menu stabilization feature. All models use Pydantic for validation and type safety (Constitution Principle X).

---

## Core Entities

### 1. WindowAction

Represents an operation that can be performed on a selected window.

**Purpose**: Define available window actions with their keyboard shortcuts, validation rules, and execution handlers.

**Fields**:
```python
from pydantic import BaseModel, Field
from typing import Callable, Optional
from enum import Enum

class ActionType(str, Enum):
    """Types of window actions."""
    CLOSE = "close"
    MOVE = "move"
    FLOAT_TOGGLE = "float_toggle"
    FOCUS = "focus"
    MARK = "mark"
    RESIZE = "resize"  # Future enhancement

class WindowAction(BaseModel):
    """Definition of a window action."""
    action_type: ActionType = Field(..., description="Type of action")
    keyboard_shortcut: str = Field(..., description="Key to trigger action (e.g., 'Delete', 'M', 'F')")
    display_label: str = Field(..., description="Human-readable label for UI (e.g., 'Close', 'Move')")
    requires_sub_mode: bool = Field(default=False, description="Whether action requires sub-mode entry")
    applies_to_headings: bool = Field(default=False, description="Whether action can be performed on workspace headings")
    applies_to_windows: bool = Field(default=True, description="Whether action can be performed on windows")

    class Config:
        frozen = True  # Immutable once created
```

**Validation Rules** (from spec):
- FR-004: Only window actions (not workspace headings) can be closed → `applies_to_headings=False` for close action
- FR-010: Extended actions require specific keyboard shortcuts → `keyboard_shortcut` must be unique
- FR-012: Sub-mode actions must support cancellation → `requires_sub_mode=True` triggers sub-mode logic

**Example Instances**:
```python
CLOSE_ACTION = WindowAction(
    action_type=ActionType.CLOSE,
    keyboard_shortcut="Delete",
    display_label="Close",
    requires_sub_mode=False,
    applies_to_headings=False,
    applies_to_windows=True
)

MOVE_ACTION = WindowAction(
    action_type=ActionType.MOVE,
    keyboard_shortcut="M",
    display_label="Move",
    requires_sub_mode=True,  # Requires workspace number input
    applies_to_headings=False,
    applies_to_windows=True
)

FLOAT_TOGGLE_ACTION = WindowAction(
    action_type=ActionType.FLOAT_TOGGLE,
    keyboard_shortcut="F",
    display_label="Float",
    requires_sub_mode=False,  # Immediate action
    applies_to_headings=False,
    applies_to_windows=True
)
```

**Relationships**:
- Referenced by `SelectionState` to determine available actions
- Referenced by `ActionResult` to track which action was executed
- Referenced by `KeyboardHintManager` to generate help text

---

### 2. SelectionState

Tracks which item is currently selected in the preview menu.

**Purpose**: Maintain selection index, distinguish between workspace headings and windows, track navigation history.

**Fields**:
```python
from pydantic import BaseModel, Field, validator
from typing import Optional, List
from enum import Enum

class SelectionType(str, Enum):
    """Type of selected item."""
    WORKSPACE_HEADING = "workspace_heading"
    WINDOW = "window"

class SelectionState(BaseModel):
    """Current selection state in workspace preview menu."""
    selected_index: int = Field(default=0, ge=0, description="Index of selected item in flattened list")
    selection_type: SelectionType = Field(..., description="Type of selected item")
    workspace_number: Optional[int] = Field(None, description="Workspace number if selected item is a window")
    window_id: Optional[int] = Field(None, description="Sway container ID if selected item is a window")
    total_items: int = Field(..., gt=0, description="Total number of selectable items")
    is_floating: bool = Field(default=False, description="Whether selected window is floating (for context-aware hints)")

    @validator("window_id")
    def window_id_required_for_windows(cls, v, values):
        """Validate that window_id is set when selection_type is WINDOW."""
        if values.get("selection_type") == SelectionType.WINDOW and v is None:
            raise ValueError("window_id required when selection_type is WINDOW")
        return v

    def can_perform_action(self, action: WindowAction) -> bool:
        """Check if the given action can be performed on the current selection."""
        if self.selection_type == SelectionType.WORKSPACE_HEADING:
            return action.applies_to_headings
        return action.applies_to_windows

    class Config:
        frozen = False  # Mutable - selection changes frequently
```

**State Transitions**:
```python
async def move_selection(self, direction: int) -> None:
    """
    Move selection up (-1) or down (+1).

    Args:
        direction: -1 for up, +1 for down

    Raises:
        ValueError: If direction is not -1 or +1
    """
    if direction not in [-1, 1]:
        raise ValueError("direction must be -1 or +1")

    new_index = self.selected_index + direction
    if 0 <= new_index < self.total_items:
        self.selected_index = new_index
    # Wrap around at boundaries
    elif new_index < 0:
        self.selected_index = self.total_items - 1
    else:
        self.selected_index = 0
```

**Relationships**:
- Used by `workspace-preview-daemon` main loop to track current selection
- Referenced by `ActionHandler` to determine target window for actions
- Referenced by `KeyboardHintManager` to generate context-aware hints
- Modified by `SelectionManager.move_selection_after_close()` after window close

---

### 3. KeyboardEventFlow

Maps physical key presses to actions through the event chain.

**Purpose**: Document the event flow from keyboard to daemon to UI update.

**Event Chain** (from spec Key Entities section):
```
User presses key
  ↓
Sway keybinding fires (e.g., Delete in "→ WS" mode)
  ↓
Sway executes CLI command (e.g., workspace-preview-daemon --action close-window)
  ↓
workspace-preview-daemon receives IPC message from i3pm daemon
  ↓
Action handler executes (e.g., handle_window_close)
  ↓
Sway IPC command (e.g., [con_id=<window_id>] kill)
  ↓
Eww UI updates via `eww update` CLI (e.g., remove window from list, update selection)
```

**No explicit model** - This is a conceptual entity documenting the data flow. Implementation uses:
- Sway keybindings (Nix config)
- CLI arguments (parsed by daemon)
- Async function calls (Python daemon)
- Sway IPC messages (i3ipc.aio.Connection)
- Eww update commands (subprocess calls)

---

### 4. SubModeContext

Captures temporary state during multi-step actions.

**Purpose**: Manage sub-mode state (move window, mark window, etc.) with input accumulation and cancel capability.

**Fields**:
```python
from pydantic import BaseModel, Field, validator
from typing import Optional
from enum import Enum

class SubMode(str, Enum):
    """Active sub-mode states."""
    NORMAL = "normal"  # Default state
    MOVE_WINDOW = "move_window"  # Awaiting workspace number input
    MARK_WINDOW = "mark_window"  # Awaiting mark name input
    # Future: RESIZE_WINDOW, etc.

class SubModeContext(BaseModel):
    """State for multi-step window actions."""
    current_mode: SubMode = Field(default=SubMode.NORMAL, description="Currently active sub-mode")
    target_window_id: Optional[int] = Field(None, description="Window ID for action (set when entering sub-mode)")
    accumulated_input: str = Field(default="", description="User input accumulated (workspace digits, mark name)")
    entry_timestamp: Optional[float] = Field(None, description="Time when sub-mode was entered (for timeout)")

    @validator("target_window_id")
    def window_id_required_for_non_normal(cls, v, values):
        """Validate that target_window_id is set when not in NORMAL mode."""
        if values.get("current_mode") != SubMode.NORMAL and v is None:
            raise ValueError("target_window_id required when not in NORMAL mode")
        return v

    def enter_sub_mode(self, mode: SubMode, window_id: int) -> None:
        """
        Enter a sub-mode for a specific window.

        Args:
            mode: Sub-mode to enter (MOVE_WINDOW, MARK_WINDOW, etc.)
            window_id: Target window for the action

        Raises:
            ValueError: If trying to enter NORMAL mode (use reset_to_normal instead)
        """
        if mode == SubMode.NORMAL:
            raise ValueError("Use reset_to_normal() to return to normal mode")

        self.current_mode = mode
        self.target_window_id = window_id
        self.accumulated_input = ""
        self.entry_timestamp = time.time()

    def reset_to_normal(self) -> None:
        """Reset to normal mode (cancel sub-mode)."""
        self.current_mode = SubMode.NORMAL
        self.target_window_id = None
        self.accumulated_input = ""
        self.entry_timestamp = None

    def is_normal(self) -> bool:
        """Check if in normal mode."""
        return self.current_mode == SubMode.NORMAL

    class Config:
        frozen = False  # Mutable - mode changes frequently
```

**State Transitions**:
```
NORMAL + "M" key → MOVE_WINDOW (accumulated_input = "", target_window_id = selected window)
MOVE_WINDOW + digit key → MOVE_WINDOW (accumulated_input += digit)
MOVE_WINDOW + Enter → execute move → NORMAL
MOVE_WINDOW + Escape → NORMAL (cancel)
ANY_STATE + Escape → NORMAL (cancel)
```

**Validation Rules** (from spec):
- FR-011: Sub-mode must provide visual feedback → `accumulated_input` shown in Eww prompt
- FR-012: Must support cancellation with Escape → `reset_to_normal()` called on Escape
- Edge case: Invalid input (>70 for workspace) → Ignored, wait for valid input or Escape

**Relationships**:
- Used by `workspace-preview-daemon` to track active sub-mode
- Referenced by `KeyboardHintManager` to generate mode-specific hints
- Modified by action handlers when entering/exiting sub-modes

---

### 5. ActionResult

Outcome of executing a window action.

**Purpose**: Standardize success/failure reporting, track performance metrics, provide actionable error messages.

**Fields**:
```python
from pydantic import BaseModel, Field
from typing import Optional

class ActionResult(BaseModel):
    """Result of executing a window action."""
    success: bool = Field(..., description="Whether action completed successfully")
    action_type: ActionType = Field(..., description="Type of action executed")
    window_id: int = Field(..., description="Target window container ID")
    latency_ms: float = Field(..., ge=0, description="Time taken to execute action (milliseconds)")
    error_message: Optional[str] = Field(None, description="Human-readable error message if failed")
    error_code: Optional[str] = Field(None, description="Machine-readable error code (e.g., 'WINDOW_REFUSED_CLOSE')")

    class Config:
        frozen = True  # Immutable once created
```

**Error Codes**:
```python
class ActionErrorCode(str, Enum):
    """Standard error codes for action failures."""
    WINDOW_REFUSED_CLOSE = "WINDOW_REFUSED_CLOSE"  # Window has unsaved changes
    WINDOW_NOT_FOUND = "WINDOW_NOT_FOUND"  # Window ID invalid or closed
    INVALID_WORKSPACE = "INVALID_WORKSPACE"  # Workspace number out of range (>70)
    DEBOUNCED = "DEBOUNCED"  # Action too fast after previous action
    DAEMON_CONNECTION_FAILED = "DAEMON_CONNECTION_FAILED"  # Cannot connect to Sway IPC
    TIMEOUT = "TIMEOUT"  # Action took too long (>2s)
```

**Example Instances**:
```python
# Success case
SUCCESS_RESULT = ActionResult(
    success=True,
    action_type=ActionType.CLOSE,
    window_id=12345,
    latency_ms=320.5,
    error_message=None,
    error_code=None
)

# Failure case (window refused close)
FAILURE_RESULT = ActionResult(
    success=False,
    action_type=ActionType.CLOSE,
    window_id=12345,
    latency_ms=520.3,
    error_message="Window refused to close (may have unsaved changes)",
    error_code=ActionErrorCode.WINDOW_REFUSED_CLOSE
)

# Debounce case
DEBOUNCE_RESULT = ActionResult(
    success=False,
    action_type=ActionType.CLOSE,
    window_id=12345,
    latency_ms=0.0,
    error_message="Action debounced (too fast)",
    error_code=ActionErrorCode.DEBOUNCED
)
```

**Performance Tracking** (from spec success criteria):
- SC-002: Window close operations must complete within 500ms (p95) → `latency_ms` tracked
- SC-007: Extended actions must complete within 2 seconds → `latency_ms < 2000` validated

**Relationships**:
- Returned by all action handlers (`handle_window_close`, `handle_window_move`, etc.)
- Logged for performance monitoring and debugging
- Error messages shown to user via notifications (FR-006)

---

## Supporting Data Structures

### DebounceTracker

Tracks last action timestamp per window ID for debouncing.

**Purpose**: Prevent rapid duplicate actions within 100ms window (FR-008).

**Structure**:
```python
from typing import Dict
import time

class DebounceTracker:
    """Track last action time per window for debouncing."""

    def __init__(self, debounce_ms: int = 100):
        """
        Initialize debounce tracker.

        Args:
            debounce_ms: Minimum milliseconds between actions on same window
        """
        self._last_action: Dict[int, float] = {}
        self._debounce_ms = debounce_ms

    def can_perform_action(self, window_id: int) -> bool:
        """
        Check if action can be performed on window (debounce check).

        Args:
            window_id: Sway container ID

        Returns:
            True if enough time has passed since last action, False otherwise
        """
        current_time = time.time()
        last_time = self._last_action.get(window_id, 0)
        time_since_last = (current_time - last_time) * 1000  # Convert to ms

        return time_since_last >= self._debounce_ms

    def record_action(self, window_id: int) -> None:
        """
        Record that an action was performed on a window.

        Args:
            window_id: Sway container ID
        """
        self._last_action[window_id] = time.time()

    def clear(self) -> None:
        """Clear all debounce tracking (useful for testing)."""
        self._last_action.clear()
```

---

### KeyboardHints

Generated keyboard shortcut help text.

**Purpose**: Provide context-aware keyboard hints based on selection type and sub-mode (FR-005).

**Structure**:
```python
from typing import List

class KeyboardHints:
    """Generate keyboard shortcut help text."""

    @staticmethod
    def generate_hints(
        selection_state: SelectionState,
        sub_mode_context: SubModeContext,
        available_actions: List[WindowAction]
    ) -> str:
        """
        Generate keyboard hint text based on current state.

        Args:
            selection_state: Current selection
            sub_mode_context: Current sub-mode
            available_actions: Available window actions

        Returns:
            Formatted hint string (e.g., "↑/↓ Navigate | Enter Select | Delete Close | Esc Cancel")
        """
        hints: List[str] = []

        if sub_mode_context.is_normal():
            # Normal mode hints
            hints.append("↑/↓ Navigate")
            hints.append("Enter Select")

            # Context-aware action hints
            for action in available_actions:
                if selection_state.can_perform_action(action):
                    hints.append(f"{action.keyboard_shortcut} {action.display_label}")

            hints.append(": Project")
            hints.append("Esc Cancel")

        elif sub_mode_context.current_mode == SubMode.MOVE_WINDOW:
            # Move window sub-mode
            workspace_input = sub_mode_context.accumulated_input or "_"
            hints.append(f"Type workspace: {workspace_input}")
            hints.append("Enter Confirm")
            hints.append("Esc Cancel")

        elif sub_mode_context.current_mode == SubMode.MARK_WINDOW:
            # Mark window sub-mode
            mark_input = sub_mode_context.accumulated_input or "_"
            hints.append(f"Type mark name: {mark_input}")
            hints.append("Enter Confirm")
            hints.append("Esc Cancel")

        return " | ".join(hints)
```

**Example Outputs**:
```python
# Normal mode, window selected
"↑/↓ Navigate | Enter Select | Delete Close | M Move | F Float | : Project | Esc Cancel"

# Normal mode, workspace heading selected
"↑/↓ Navigate | Enter Select | : Project | Esc Cancel"

# Move window sub-mode, typed "23"
"Type workspace: 23 | Enter Confirm | Esc Cancel"

# Mark window sub-mode, no input yet
"Type mark name: _ | Enter Confirm | Esc Cancel"
```

---

## Data Flow Diagrams

### Window Close Flow

```
User presses Delete key
  ↓
Sway keybinding fires: workspace-preview-daemon --action close-window
  ↓
Daemon receives action request
  ↓
Get current SelectionState
  ↓
Validate window selected (not workspace heading)
  ↓
Check DebounceTracker.can_perform_action(window_id)
  ↓ (if debounced)
  Return ActionResult(success=False, error_code="DEBOUNCED")
  ↓ (if not debounced)
  Record action: DebounceTracker.record_action(window_id)
  ↓
Execute Sway IPC: [con_id=<window_id>] kill
  ↓
Wait 500ms for window close
  ↓
Verify window closed: Query Sway tree
  ↓ (if still exists)
  Return ActionResult(success=False, error_code="WINDOW_REFUSED_CLOSE")
  Show notification to user
  ↓ (if closed successfully)
  Return ActionResult(success=True, latency_ms=<measured>)
  ↓
Update SelectionState: move to next item
  ↓ (if no items remain)
  Exit workspace mode
  ↓ (if items remain)
  Update Eww UI: `eww update workspaces=<new_list>`
  Update keyboard hints: `eww update keyboard_hints=<new_hints>`
```

### Sub-Mode Entry Flow (Move Window)

```
User presses "M" key
  ↓
Sway keybinding fires: workspace-preview-daemon --action enter-move-mode
  ↓
Daemon receives action request
  ↓
Get current SelectionState
  ↓
Validate window selected (not workspace heading)
  ↓
Create SubModeContext:
  - current_mode = SubMode.MOVE_WINDOW
  - target_window_id = selected window ID
  - accumulated_input = ""
  - entry_timestamp = now()
  ↓
Update keyboard hints: "Type workspace: _ | Enter Confirm | Esc Cancel"
  ↓
Update Eww UI: `eww update keyboard_hints=<new_hints>`
  ↓
Wait for digit input or Enter or Escape
  ↓ (digit pressed)
  Append to accumulated_input
  Update hints with new input
  ↓ (Enter pressed)
  Parse workspace number from accumulated_input
  Execute move action
  Reset SubModeContext to NORMAL
  ↓ (Escape pressed)
  Reset SubModeContext to NORMAL
  Update hints to normal mode
```

---

## Validation & Constraints

### Constraint 1: Window ID Validity

**Rule**: Window IDs must exist in Sway tree at time of action execution.

**Validation**:
```python
async def validate_window_exists(
    sway_connection: i3ipc.aio.Connection,
    window_id: int
) -> bool:
    """
    Validate that a window ID exists in Sway tree.

    Args:
        sway_connection: Active Sway IPC connection
        window_id: Container ID to validate

    Returns:
        True if window exists, False otherwise
    """
    tree = await sway_connection.get_tree()
    return find_container_by_id(tree, window_id) is not None
```

---

### Constraint 2: Workspace Number Range

**Rule**: Workspace numbers must be 1-70 (from Feature 042).

**Validation**:
```python
def validate_workspace_number(workspace_num: int) -> bool:
    """
    Validate workspace number is in valid range.

    Args:
        workspace_num: Workspace number to validate

    Returns:
        True if valid (1-70), False otherwise
    """
    return 1 <= workspace_num <= 70
```

---

### Constraint 3: Debounce Timing

**Rule**: Minimum 100ms between actions on same window (FR-008).

**Validation**: Enforced by `DebounceTracker.can_perform_action()` before action execution.

---

### Constraint 4: Action Latency

**Rule**: Window close operations must complete within 500ms (p95), extended actions within 2s (SC-002, SC-007).

**Validation**:
```python
async def execute_action_with_timeout(
    action_handler: Callable,
    timeout_ms: int
) -> ActionResult:
    """
    Execute action with timeout enforcement.

    Args:
        action_handler: Async function to execute
        timeout_ms: Maximum execution time in milliseconds

    Returns:
        ActionResult with success/failure status

    Raises:
        asyncio.TimeoutError: If action exceeds timeout
    """
    try:
        result = await asyncio.wait_for(
            action_handler(),
            timeout=timeout_ms / 1000.0
        )
        return result
    except asyncio.TimeoutError:
        return ActionResult(
            success=False,
            action_type=action_handler.action_type,
            window_id=action_handler.window_id,
            latency_ms=timeout_ms,
            error_message=f"Action timed out after {timeout_ms}ms",
            error_code=ActionErrorCode.TIMEOUT
        )
```

---

## Storage & Persistence

**Storage Model**: All state is **in-memory only** in the workspace-preview-daemon process.

**Rationale**:
- No persistent storage required (selection state, sub-mode context are transient)
- Performance: In-memory access is <1ms, no disk I/O latency
- Simplicity: No database schema, migration scripts, or backup procedures
- Aligns with daemon architecture (event-driven, stateless between workspace mode sessions)

**State Lifecycle**:
- Created: When workspace mode is entered (CapsLock/Ctrl+0)
- Modified: During navigation, action execution, sub-mode transitions
- Destroyed: When workspace mode is exited (Escape, last window closed, navigate to workspace)

**No persistence across daemon restarts** - This is acceptable because:
- Workspace mode is a short-lived interaction (typically <30 seconds)
- User can easily re-enter workspace mode if daemon crashes (rare, <0.1% failure rate from Feature 072)
- Sway IPC is authoritative source of truth for window state (Constitution Principle XI)

---

## References

- **Pydantic Documentation**: https://docs.pydantic.dev/
- **Python Type Hints (PEP 484)**: https://peps.python.org/pep-0484/
- **Sway IPC Protocol**: https://github.com/swaywm/sway/blob/master/sway/sway-ipc.7.scd
- **Constitution Principle X (Python Development)**: /.specify/memory/constitution.md
- **Feature Specification**: spec.md

---

**Data Model Complete**: 2025-11-13 | **Next Phase**: Phase 1 - Quickstart Documentation
