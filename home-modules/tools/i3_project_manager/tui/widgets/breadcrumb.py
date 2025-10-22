"""Breadcrumb navigation widget for hierarchical navigation.

Provides visual breadcrumb navigation showing current screen location.
Supports click-to-navigate for mouse users.
"""

from dataclasses import dataclass
from typing import List, Optional, Callable
from textual.app import ComposeResult
from textual.widget import Widget
from textual.widgets import Label, Static
from textual.containers import Horizontal
from textual.reactive import reactive
from textual.message import Message


@dataclass
class BreadcrumbPath:
    """Breadcrumb path segment."""

    label: str  # Display text (e.g., "Projects", "NixOS", "Edit")
    screen_name: Optional[str] = None  # Screen to navigate to when clicked (None = not clickable)
    screen_args: dict = None  # Arguments to pass to screen

    def __post_init__(self):
        """Initialize default values."""
        if self.screen_args is None:
            self.screen_args = {}

    def __str__(self) -> str:
        """String representation."""
        return self.label


class BreadcrumbWidget(Widget):
    """Breadcrumb navigation widget.

    Shows hierarchical navigation path with clickable segments.

    Example:
        Projects > NixOS > Layouts

    Supports:
    - Click to navigate to parent screens (FR-026)
    - Visual separator between segments
    - Current segment highlighting
    - Dynamic path updates

    Attributes:
        path (List[BreadcrumbPath]): Current navigation path
    """

    DEFAULT_CSS = """
    BreadcrumbWidget {
        height: 1;
        width: 100%;
        background: $panel;
        padding: 0 1;
    }

    BreadcrumbWidget .breadcrumb-container {
        height: 1;
        width: auto;
    }

    BreadcrumbWidget .breadcrumb-segment {
        color: $text-muted;
        background: transparent;
    }

    BreadcrumbWidget .breadcrumb-segment-clickable {
        color: $accent;
        background: transparent;
    }

    BreadcrumbWidget .breadcrumb-segment-clickable:hover {
        color: $accent-lighten-2;
        text-style: underline;
    }

    BreadcrumbWidget .breadcrumb-segment-current {
        color: $text;
        background: transparent;
        text-style: bold;
    }

    BreadcrumbWidget .breadcrumb-separator {
        color: $text-muted;
        background: transparent;
    }
    """

    # Reactive path for automatic UI updates
    path: reactive[List[BreadcrumbPath]] = reactive([], always_update=True)

    class BreadcrumbClicked(Message):
        """Message emitted when breadcrumb segment is clicked."""

        def __init__(self, segment: BreadcrumbPath) -> None:
            """Initialize message.

            Args:
                segment: The clicked breadcrumb segment
            """
            super().__init__()
            self.segment = segment

    def __init__(
        self,
        initial_path: List[BreadcrumbPath] = None,
        *,
        name: Optional[str] = None,
        id: Optional[str] = None,
        classes: Optional[str] = None
    ):
        """Initialize breadcrumb widget.

        Args:
            initial_path: Initial navigation path
            name: Widget name
            id: Widget ID
            classes: CSS classes
        """
        super().__init__(name=name, id=id, classes=classes)
        if initial_path:
            self.path = initial_path

    def compose(self) -> ComposeResult:
        """Compose breadcrumb UI."""
        yield Horizontal(classes="breadcrumb-container", id="breadcrumb-container")

    def watch_path(self, old_path: List[BreadcrumbPath], new_path: List[BreadcrumbPath]) -> None:
        """React to path changes by rebuilding breadcrumb display.

        Args:
            old_path: Previous path
            new_path: New path
        """
        self._rebuild_breadcrumbs()

    def _rebuild_breadcrumbs(self) -> None:
        """Rebuild breadcrumb display from current path."""
        # Don't rebuild if not mounted yet
        if not self.is_mounted:
            return

        try:
            container = self.query_one("#breadcrumb-container", Horizontal)
        except Exception:
            # Container not ready yet
            return

        container.remove_children()

        if not self.path:
            # Empty breadcrumb - show nothing
            return

        # Build breadcrumb segments
        for i, segment in enumerate(self.path):
            is_last = (i == len(self.path) - 1)

            # Create segment label
            if segment.screen_name and not is_last:
                # Clickable segment
                label = BreadcrumbSegment(
                    segment.label,
                    segment,
                    classes="breadcrumb-segment-clickable"
                )
            elif is_last:
                # Current segment (not clickable)
                label = Static(
                    segment.label,
                    classes="breadcrumb-segment-current"
                )
            else:
                # Non-clickable segment
                label = Static(
                    segment.label,
                    classes="breadcrumb-segment"
                )

            container.mount(label)

            # Add separator if not last segment
            if not is_last:
                separator = Static(" > ", classes="breadcrumb-separator")
                container.mount(separator)

    def set_path(self, path: List[BreadcrumbPath]) -> None:
        """Set navigation path.

        Args:
            path: New navigation path
        """
        self.path = path

    def append_segment(self, segment: BreadcrumbPath) -> None:
        """Append segment to current path.

        Args:
            segment: Segment to append
        """
        new_path = self.path.copy()
        new_path.append(segment)
        self.path = new_path

    def pop_segment(self) -> Optional[BreadcrumbPath]:
        """Remove last segment from path.

        Returns:
            The removed segment, or None if path was empty
        """
        if not self.path:
            return None

        new_path = self.path.copy()
        removed = new_path.pop()
        self.path = new_path
        return removed

    def go_to_root(self) -> None:
        """Reset path to first segment only."""
        if self.path:
            self.path = [self.path[0]]

    def get_current_segment(self) -> Optional[BreadcrumbPath]:
        """Get current (last) segment.

        Returns:
            Current segment or None if path is empty
        """
        return self.path[-1] if self.path else None


class BreadcrumbSegment(Static):
    """Clickable breadcrumb segment."""

    def __init__(
        self,
        label: str,
        segment: BreadcrumbPath,
        *,
        classes: Optional[str] = None
    ):
        """Initialize clickable segment.

        Args:
            label: Display label
            segment: Associated breadcrumb path segment
            classes: CSS classes
        """
        super().__init__(label, classes=classes)
        self.segment = segment

    async def on_click(self) -> None:
        """Handle click event by posting message to parent."""
        # Find parent BreadcrumbWidget and post message
        breadcrumb = self.ancestors.filter(BreadcrumbWidget).first()
        if breadcrumb:
            breadcrumb.post_message(
                BreadcrumbWidget.BreadcrumbClicked(self.segment)
            )
