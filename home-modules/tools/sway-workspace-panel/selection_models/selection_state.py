"""Pydantic models for Feature 059: Interactive Workspace Menu with Keyboard Navigation.

This module defines data models for managing arrow key navigation and selection state
in the workspace preview card.

Models:
    - SelectionState: Tracks currently selected item (workspace heading or window)
    - NavigableItem: Represents a single selectable item in the preview list
    - PreviewListModel: Flattened list model for circular arrow key navigation
"""
from __future__ import annotations

import sys
from pydantic import BaseModel, Field, field_validator, model_validator, computed_field
from typing import List, Literal, Optional


class SelectionState(BaseModel):
    """Selection state for interactive workspace menu navigation.

    Tracks which workspace heading or window is currently selected for user actions
    (Enter to navigate, Delete to close).
    """

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

    @model_validator(mode='after')
    def validate_window_id_for_window_type(self) -> 'SelectionState':
        """Validate window_id is present for window item_type."""
        if self.item_type == "window" and self.window_id is None:
            raise ValueError("window_id required when item_type is 'window'")
        return self

    def is_active(self) -> bool:
        """Check if selection is active (not None)."""
        return self.selected_index is not None

    def is_workspace_heading(self) -> bool:
        """Check if selected item is a workspace heading."""
        return self.item_type == "workspace_heading"

    def is_window(self) -> bool:
        """Check if selected item is a window."""
        return self.item_type == "window"


class NavigableItem(BaseModel):
    """A selectable item in the preview card (workspace heading or window).

    Unified representation for both workspace headings and window items,
    enabling circular navigation through a flattened list.
    """

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


class PreviewListModel(BaseModel):
    """Flattened list model for circular navigation through preview items.

    Provides O(1) circular navigation while maintaining original grouped
    structure for rendering.
    """

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

    def remove_item(self, item: NavigableItem) -> bool:
        """Remove item from list (Feature 059: T045).

        Args:
            item: NavigableItem to remove

        Returns:
            True if item was found and removed, False otherwise

        Note:
            Window counts are recomputed automatically in _rebuild_workspace_groups_from_items()
        """
        try:
            self.items.remove(item)
            return True
        except ValueError:
            return False

    @classmethod
    def from_workspace_groups(
        cls,
        workspace_groups: List[dict]  # From Feature 072 workspace_preview_data
    ) -> "PreviewListModel":
        """Factory: Create PreviewListModel from workspace groups.

        Args:
            workspace_groups: List of workspace group dicts with structure:
                {
                    'workspace_num': int,
                    'window_count': int,
                    'monitor_output': str,
                    'windows': [{'name': str, 'window_id': int, 'icon_path': str, ...}]
                }

        Returns:
            PreviewListModel with flattened items list and selection at first item
        """
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
                # Skip windows without window_id (defensive coding)
                window_id = window.get('window_id')
                print(f"DEBUG: Creating NavigableItem for window '{window.get('name', 'unknown')}' with window_id={window_id} (type={type(window_id)})", file=sys.stderr)
                if window_id is None:
                    # Log warning and skip this window
                    print(f"WARNING: Skipping window '{window.get('name', 'unknown')}' without window_id", file=sys.stderr)
                    continue

                # Create NavigableItem
                nav_item = NavigableItem.from_window(
                    window_name=window['name'],
                    workspace_num=group['workspace_num'],
                    window_id=window_id,
                    icon_path=window.get('icon_path'),
                    position_index=position
                )
                print(f"DEBUG: Created NavigableItem: type={nav_item.item_type}, window_id={nav_item.window_id}, pos={nav_item.position_index}", file=sys.stderr)
                items.append(nav_item)
                position += 1

        return cls(
            items=items,
            current_selection_index=0 if items else None,
            scroll_position=0
        )
