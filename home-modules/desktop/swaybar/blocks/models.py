"""Core data models for i3bar protocol status blocks and click events."""

from dataclasses import dataclass, asdict
from typing import Optional
from enum import Enum


@dataclass
class StatusBlock:
    """A single status block in the i3bar protocol format.

    See: https://i3wm.org/docs/i3bar-protocol.html
    """

    # Required fields
    full_text: str          # Full text to display (with markup)
    name: str               # Block identifier (volume, battery, network, bluetooth)

    # Optional fields
    short_text: Optional[str] = None      # Abbreviated text for small displays
    color: Optional[str] = None           # Hex color code (#RRGGBB)
    background: Optional[str] = None      # Background color
    border: Optional[str] = None          # Border color
    border_top: int = 0                   # Border width (pixels)
    border_right: int = 0
    border_bottom: int = 0
    border_left: int = 0
    min_width: Optional[int] = None       # Minimum width (pixels or string)
    align: str = "left"                   # Text alignment (left, center, right)
    urgent: bool = False                  # Urgent flag (highlights block)
    separator: bool = True                # Show separator after block
    separator_block_width: int = 15       # Separator width
    markup: str = "pango"                 # Markup type (none, pango)
    instance: Optional[str] = None        # Block instance identifier

    def to_json(self) -> dict:
        """Convert to i3bar protocol JSON format.

        Omits None values and zero integers to minimize JSON output.
        """
        return {
            k: v for k, v in asdict(self).items()
            if v is not None and (not isinstance(v, int) or v != 0 or k in ["border_top", "border_right", "border_bottom", "border_left"])
        }


class MouseButton(Enum):
    """Mouse button codes from i3bar protocol."""
    LEFT = 1
    MIDDLE = 2
    RIGHT = 3
    SCROLL_UP = 4
    SCROLL_DOWN = 5


@dataclass
class ClickEvent:
    """A click event from swaybar (i3bar protocol).

    Sent from swaybar to status generator via stdin when user clicks a status block.
    """

    name: str               # Block name (volume, battery, etc.)
    instance: Optional[str] # Block instance
    button: MouseButton     # Mouse button
    x: int                  # Click X coordinate
    y: int                  # Click Y coordinate

    @classmethod
    def from_json(cls, data: dict) -> 'ClickEvent':
        """Parse from i3bar protocol JSON.

        Args:
            data: Click event JSON dict from swaybar stdin

        Returns:
            ClickEvent instance

        Raises:
            ValueError: If button code is invalid
        """
        return cls(
            name=data["name"],
            instance=data.get("instance"),
            button=MouseButton(data["button"]),
            x=data["x"],
            y=data["y"]
        )
