# Data Model: Interactive Workspace Menu with Keyboard Navigation

**Feature**: 059-interactive-workspace-menu | **Date**: 2025-11-12 | **Phase**: 1 - Design

## Overview

This document defines the data entities and their relationships for the interactive workspace menu with arrow key navigation, Enter key workspace switching, and Delete key window closing.

---

## Core Entities

### 1. SelectionState

Represents the currently selected item in the preview card during workspace mode navigation.

**Purpose**: Track which workspace heading or window is currently highlighted for user actions (Enter to navigate, Delete to close).

**Attributes**:

| Attribute | Type | Description | Validation |
|-----------|------|-------------|------------|
| `selected_index` | `int \| None` | 0-based position in flattened list of all items (workspace headings + windows) | `0 <= index < total_items` OR `None` if empty |
| `item_type` | `Literal["workspace_heading", "window"]` | Type of selected item | Must be one of two enum values |
| `workspace_num` | `int \| None` | Workspace number (1-70) of selected item | `1 <= workspace_num <= 70` OR `None` if no selection |
| `window_id` | `int \| None` | Sway container ID if selected item is a window | Valid Sway con_id OR `None` if workspace heading |
| `visible` | `bool` | Whether selected item is currently visible in viewport | Default: `True` (GTK auto-scroll assumption) |

**Relationships**:
- `SelectionState` → `PreviewListModel` (1:1 - each preview has one selection state)
- `SelectionState` → `NavigableItem` (N:1 - selection points to one item in list)

**Lifecycle**:
- **Created**: When workspace mode is entered (CapsLock/Ctrl+0 pressed)
- **Updated**: On arrow key press, digit typing (resets to first item), project mode switch
- **Destroyed**: When workspace mode exits (Escape pressed, Enter executed)

**State Transitions**:
```
None (mode inactive)
  → SelectionState(index=0) [mode entry, list non-empty]
  → SelectionState(index=1) [Down arrow]
  → SelectionState(index=0) [Up arrow, circular wrap]
  → None [Escape pressed, mode exit]
```

**Pydantic Model**:

```python
from pydantic import BaseModel, Field, field_validator
from typing import Literal, Optional

class SelectionState(BaseModel):
    """Selection state for interactive workspace menu navigation."""

    selected_index: Optional[int] = Field(
        default=None,
        description="0-based position in flattened item list (None if no selection)"
    )
    item_type: Literal["workspace_heading", "window"] = Field(
        default="workspace_heading",
        description="Type of selected item"
    )
    workspace_num: Optional[int] = Field(
        default=None,
        ge=1,
        le=70,
        description="Workspace number (1-70) of selected item"
    )
    window_id: Optional[int] = Field(
        default=None,
        description="Sway container ID if item is a window"
    )
    visible: bool = Field(
        default=True,
        description="Whether selected item is visible in viewport"
    )

    @field_validator('selected_index')
    @classmethod
    def validate_index_non_negative(cls, v: Optional[int]) -> Optional[int]:
        """Validate selected_index is non-negative if not None."""
        if v is not None and v < 0:
            raise ValueError("selected_index must be non-negative")
        return v

    @field_validator('item_type', mode='after')
    @classmethod
    def validate_window_id_for_window_type(cls, v: str, info) -> str:
        """Validate window_id is present for window item_type."""
        if v == "window" and info.data.get('window_id') is None:
            raise ValueError("window_id required when item_type is 'window'")
        return v

    def is_active(self) -> bool:
        """Check if selection is active (not None)."""
        return self.selected_index is not None

    def is_workspace_heading(self) -> bool:
        """Check if selected item is a workspace heading."""
        return self.item_type == "workspace_heading"

    def is_window(self) -> bool:
        """Check if selected item is a window."""
        return self.item_type == "window"
```

---

### 2. NavigableItem

Represents a single selectable item in the preview card (either a workspace heading or an individual window).

**Purpose**: Unified representation of both workspace headings and window items for flattening into a linear list for circular navigation.

**Attributes**:

| Attribute | Type | Description | Validation |
|-----------|------|-------------|------------|
| `item_type` | `Literal["workspace_heading", "window"]` | Discriminator for item type | Must be one of two enum values |
| `display_text` | `str` | Human-readable text shown in preview card | Non-empty string |
| `workspace_num` | `int` | Workspace number (1-70) | `1 <= workspace_num <= 70` |
| `window_id` | `int \| None` | Sway container ID if item is a window | Valid Sway con_id OR `None` if heading |
| `icon_path` | `str \| None` | Path to icon file for display | Valid file path OR `None` if no icon |
| `position_index` | `int` | 0-based position in flattened list | `0 <= index < total_items` |
| `selectable` | `bool` | Whether item can be selected via arrow keys | Default: `True` |

**Relationships**:
- `NavigableItem` → `PreviewListModel` (N:1 - many items in one list)
- `NavigableItem` → `SelectionState` (1:N - one item may be selected)

**Lifecycle**:
- **Created**: When preview list is rendered (workspace mode entry, digit filtering)
- **Updated**: When list contents change (window closed, workspace filtered)
- **Destroyed**: When preview is hidden (mode exit)

**Pydantic Model**:

```python
from pydantic import BaseModel, Field, field_validator
from typing import Literal, Optional

class NavigableItem(BaseModel):
    """A selectable item in the preview card (workspace heading or window)."""

    item_type: Literal["workspace_heading", "window"] = Field(
        description="Type of navigable item"
    )
    display_text: str = Field(
        min_length=1,
        description="Human-readable text for display"
    )
    workspace_num: int = Field(
        ge=1,
        le=70,
        description="Workspace number (1-70)"
    )
    window_id: Optional[int] = Field(
        default=None,
        description="Sway container ID if item is a window"
    )
    icon_path: Optional[str] = Field(
        default=None,
        description="Path to icon file for display"
    )
    position_index: int = Field(
        ge=0,
        description="0-based position in flattened list"
    )
    selectable: bool = Field(
        default=True,
        description="Whether item can be selected via arrow keys"
    )

    @field_validator('window_id', mode='after')
    @classmethod
    def validate_window_id_required_for_window(cls, v: Optional[int], info) -> Optional[int]:
        """Validate window_id is present when item_type is 'window'."""
        if info.data.get('item_type') == "window" and v is None:
            raise ValueError("window_id required for window item_type")
        return v

    def is_workspace_heading(self) -> bool:
        """Check if item is a workspace heading."""
        return self.item_type == "workspace_heading"

    def is_window(self) -> bool:
        """Check if item is a window."""
        return self.item_type == "window"

    @classmethod
    def from_workspace_heading(
        cls,
        workspace_num: int,
        window_count: int,
        monitor_output: str,
        position_index: int
    ) -> "NavigableItem":
        """Factory: Create NavigableItem from workspace heading data."""
        return cls(
            item_type="workspace_heading",
            display_text=f"WS {workspace_num} ({window_count} windows) - {monitor_output}",
            workspace_num=workspace_num,
            window_id=None,
            icon_path=None,
            position_index=position_index,
            selectable=True
        )

    @classmethod
    def from_window(
        cls,
        window_name: str,
        workspace_num: int,
        window_id: int,
        icon_path: Optional[str],
        position_index: int
    ) -> "NavigableItem":
        """Factory: Create NavigableItem from window data."""
        return cls(
            item_type="window",
            display_text=window_name,
            workspace_num=workspace_num,
            window_id=window_id,
            icon_path=icon_path,
            position_index=position_index,
            selectable=True
        )
```

---

### 3. PreviewListModel

Represents the flattened list of all navigable items (workspace headings + windows) for circular arrow key navigation.

**Purpose**: Provide a linear list model for O(1) circular navigation while maintaining original grouped structure for rendering.

**Attributes**:

| Attribute | Type | Description | Validation |
|-----------|------|-------------|------------|
| `items` | `List[NavigableItem]` | Flattened list of all workspace headings and windows | Non-empty list for navigation |
| `current_selection_index` | `int \| None` | Index of currently selected item | `0 <= index < len(items)` OR `None` |
| `total_item_count` | `int` | Total number of selectable items | `len(items)` |
| `scroll_position` | `int` | Vertical scroll position in pixels (informational) | `scroll_position >= 0` |

**Relationships**:
- `PreviewListModel` → `NavigableItem` (1:N - contains many items)
- `PreviewListModel` → `SelectionState` (1:1 - has one selection state)

**Derived Properties**:
- `is_empty`: `len(items) == 0`
- `has_selection`: `current_selection_index is not None`
- `selected_item`: `items[current_selection_index]` if valid index

**Lifecycle**:
- **Created**: When workspace mode enters with preview visible
- **Updated**: On arrow navigation, digit filtering, window close
- **Destroyed**: When workspace mode exits

**Pydantic Model**:

```python
from pydantic import BaseModel, Field, computed_field
from typing import List, Optional

class PreviewListModel(BaseModel):
    """Flattened list model for circular navigation through preview items."""

    items: List[NavigableItem] = Field(
        default_factory=list,
        description="Flattened list of workspace headings and windows"
    )
    current_selection_index: Optional[int] = Field(
        default=None,
        description="Index of currently selected item"
    )
    scroll_position: int = Field(
        default=0,
        ge=0,
        description="Vertical scroll position in pixels (informational)"
    )

    @computed_field
    @property
    def total_item_count(self) -> int:
        """Total number of selectable items."""
        return len(self.items)

    @computed_field
    @property
    def is_empty(self) -> bool:
        """Check if list has no items."""
        return len(self.items) == 0

    @computed_field
    @property
    def has_selection(self) -> bool:
        """Check if there is a valid selection."""
        return (self.current_selection_index is not None and
                0 <= self.current_selection_index < len(self.items))

    def get_selected_item(self) -> Optional[NavigableItem]:
        """Get currently selected item."""
        if not self.has_selection:
            return None
        return self.items[self.current_selection_index]

    def navigate_down(self) -> None:
        """Move selection down (circular wrap to first if at last)."""
        if self.is_empty:
            return

        if self.current_selection_index is None:
            self.current_selection_index = 0
        else:
            self.current_selection_index = (self.current_selection_index + 1) % len(self.items)

    def navigate_up(self) -> None:
        """Move selection up (circular wrap to last if at first)."""
        if self.is_empty:
            return

        if self.current_selection_index is None:
            self.current_selection_index = 0
        else:
            self.current_selection_index = (self.current_selection_index - 1) % len(self.items)

    def reset_selection(self) -> None:
        """Reset selection to first item (or None if empty)."""
        self.current_selection_index = 0 if self.items else None

    def clamp_selection(self) -> None:
        """Clamp selection index to valid range after list modification."""
        if not self.items:
            self.current_selection_index = None
        elif self.current_selection_index is None:
            self.current_selection_index = 0
        elif self.current_selection_index >= len(self.items):
            self.current_selection_index = len(self.items) - 1

    @classmethod
    def from_workspace_groups(
        cls,
        workspace_groups: List[dict]  # From Feature 072 workspace_preview_data
    ) -> "PreviewListModel":
        """Factory: Create PreviewListModel from workspace groups."""
        items = []
        position = 0

        for group in workspace_groups:
            # Add workspace heading as first item
            items.append(NavigableItem.from_workspace_heading(
                workspace_num=group['workspace_num'],
                window_count=group['window_count'],
                monitor_output=group['monitor_output'],
                position_index=position
            ))
            position += 1

            # Add windows under this workspace
            for window in group['windows']:
                items.append(NavigableItem.from_window(
                    window_name=window['name'],
                    workspace_num=group['workspace_num'],
                    window_id=window.get('window_id'),  # Sway container ID
                    icon_path=window.get('icon_path'),
                    position_index=position
                ))
                position += 1

        return cls(
            items=items,
            current_selection_index=0 if items else None,
            scroll_position=0
        )
```

---

## Entity Relationships Diagram

```
┌──────────────────────────────────────────────────────────────┐
│                     PreviewListModel                         │
├──────────────────────────────────────────────────────────────┤
│ - items: List[NavigableItem]                                 │
│ - current_selection_index: int | None                        │
│ - scroll_position: int                                       │
│ + total_item_count: int (computed)                           │
│ + is_empty: bool (computed)                                  │
│ + has_selection: bool (computed)                             │
│ + get_selected_item() -> NavigableItem | None                │
│ + navigate_down() -> None                                    │
│ + navigate_up() -> None                                      │
│ + reset_selection() -> None                                  │
│ + clamp_selection() -> None                                  │
└────────────────────┬────────────────────┬────────────────────┘
                     │                    │
                     │ 1:N                │ 1:1
                     ▼                    ▼
    ┌─────────────────────────┐  ┌──────────────────────────┐
    │    NavigableItem        │  │    SelectionState        │
    ├─────────────────────────┤  ├──────────────────────────┤
    │ - item_type: str        │  │ - selected_index: int?   │
    │ - display_text: str     │  │ - item_type: str         │
    │ - workspace_num: int    │  │ - workspace_num: int?    │
    │ - window_id: int?       │  │ - window_id: int?        │
    │ - icon_path: str?       │  │ - visible: bool          │
    │ - position_index: int   │  │ + is_active() -> bool    │
    │ - selectable: bool      │  │ + is_window() -> bool    │
    │ + is_window() -> bool   │  └──────────────────────────┘
    │ + is_workspace_heading()│
    │   -> bool               │
    └─────────────────────────┘
```

---

## JSON Schema for IPC Communication

### Preview Output with Selection State

**Filename**: `contracts/preview-output-schema.json`

```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "title": "PreviewOutputWithSelection",
  "description": "Workspace preview card data with selection state for arrow key navigation",
  "type": "object",
  "required": ["visible", "type", "workspace_groups", "selection_state"],
  "properties": {
    "visible": {
      "type": "boolean",
      "description": "Whether preview card is visible"
    },
    "type": {
      "type": "string",
      "enum": ["all_windows", "filtered_workspace", "project"],
      "description": "Preview mode type"
    },
    "workspace_groups": {
      "type": "array",
      "description": "Grouped workspace data (existing Feature 072 structure)",
      "items": {
        "type": "object",
        "required": ["workspace_num", "workspace_name", "window_count", "windows"],
        "properties": {
          "workspace_num": {"type": "integer", "minimum": 1, "maximum": 70},
          "workspace_name": {"type": "string"},
          "window_count": {"type": "integer", "minimum": 0},
          "monitor_output": {"type": "string"},
          "windows": {
            "type": "array",
            "items": {
              "type": "object",
              "required": ["name", "workspace_num"],
              "properties": {
                "name": {"type": "string"},
                "icon_path": {"type": ["string", "null"]},
                "app_id": {"type": ["string", "null"]},
                "window_class": {"type": ["string", "null"]},
                "window_id": {"type": ["integer", "null"], "description": "Sway container ID"},
                "focused": {"type": "boolean"},
                "selected": {"type": "boolean", "description": "NEW: Arrow key selection state"},
                "workspace_num": {"type": "integer"}
              }
            }
          }
        }
      }
    },
    "selection_state": {
      "type": "object",
      "description": "NEW: Current selection state for arrow key navigation",
      "required": ["selected_index", "item_type", "visible"],
      "properties": {
        "selected_index": {
          "type": ["integer", "null"],
          "minimum": 0,
          "description": "0-based position in flattened item list"
        },
        "item_type": {
          "type": "string",
          "enum": ["workspace_heading", "window"],
          "description": "Type of selected item"
        },
        "workspace_num": {
          "type": ["integer", "null"],
          "minimum": 1,
          "maximum": 70
        },
        "window_id": {
          "type": ["integer", "null"],
          "description": "Sway container ID if item is a window"
        },
        "visible": {
          "type": "boolean",
          "description": "Whether selected item is visible in viewport"
        }
      }
    },
    "total_window_count": {"type": "integer", "minimum": 0},
    "total_workspace_count": {"type": "integer", "minimum": 0}
  }
}
```

---

## Data Flow

### 1. Arrow Key Navigation Flow

```
User presses Down arrow
  → Sway keybinding: `i3pm workspace-preview nav down`
  → workspace-preview-daemon receives IPC command
  → PreviewListModel.navigate_down() updates selection_index
  → SelectionState updated with new index, item_type, workspace_num, window_id
  → emit_preview_with_selection() outputs JSON
  → Eww deflisten updates preview card
  → CSS .selected class applied to new item
  → GTK re-renders with highlight (transition: 0.2s)
```

### 2. Enter Key Workspace Navigation Flow

```
User presses Enter
  → Sway keybinding: `i3pm workspace-preview select`
  → workspace-preview-daemon gets current selection
  → If workspace_heading: Send `workspace number <N>` Sway IPC command
  → If window: Send `[con_id=<id>] focus` Sway IPC command
  → Exit workspace mode (clear selection state)
  → Preview card closes
```

### 3. Delete Key Window Close Flow

```
User presses Delete
  → Sway keybinding: `i3pm workspace-preview delete`
  → workspace-preview-daemon gets selected window_id
  → Validate item_type == "window" (no-op if workspace_heading)
  → close_window_with_verification(window_id, timeout=500ms)
    → Send `[con_id=<id>] kill` Sway IPC command
    → Poll tree to verify window closed (50ms intervals, 500ms max)
  → If closed: Remove item from PreviewListModel, clamp selection index
  → If timeout: Show notification "Window close blocked"
  → emit_preview_with_selection() with updated list
  → Eww updates preview (window removed from display)
```

---

## Performance Considerations

### Memory Usage

| Entity | Size (bytes) | Count (50 items) | Total |
|--------|-------------|------------------|-------|
| NavigableItem | ~200 | 50 | ~10 KB |
| SelectionState | ~80 | 1 | ~80 bytes |
| PreviewListModel | ~8 KB | 1 | ~8 KB |
| **Total in-memory** | - | - | **~18 KB** |

**Conclusion**: Negligible memory overhead (<20 KB for 50 items)

### Computational Complexity

| Operation | Complexity | Latency (50 items) |
|-----------|-----------|-------------------|
| navigate_down/up | O(1) | <0.01ms |
| get_selected_item | O(1) | <0.01ms |
| from_workspace_groups | O(n) | ~0.5ms |
| clamp_selection | O(1) | <0.01ms |

**Conclusion**: All navigation operations are O(1), list construction is O(n) but only runs on mode entry/filter change.

---

## Validation Rules Summary

1. **SelectionState**:
   - `selected_index >= 0` OR `None`
   - `workspace_num` in range `[1, 70]` if not `None`
   - `window_id` required if `item_type == "window"`

2. **NavigableItem**:
   - `display_text` non-empty string
   - `workspace_num` in range `[1, 70]`
   - `window_id` required if `item_type == "window"`
   - `position_index >= 0`

3. **PreviewListModel**:
   - `current_selection_index` in range `[0, len(items))` OR `None`
   - `scroll_position >= 0`
   - `items` list may be empty (valid for empty workspace state)

---

**Next**: Create API contracts in `/contracts/` directory.
