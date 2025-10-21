"""PropertyDisplay widget for window inspector.

Displays window properties as a key-value table with support for
live updates and visual highlighting of changes.
"""

from textual.widgets import DataTable
from textual.reactive import reactive
from typing import Optional, Dict
import asyncio

from i3_project_manager.models.inspector import WindowProperties


class PropertyDisplay(DataTable):
    """Property display table with change highlighting.

    Displays window properties as key-value pairs in a table format.
    Supports highlighting changed fields in yellow for 200ms to provide
    visual feedback during live mode updates.

    Attributes:
        window_props: Current window properties (reactive)
        highlight_duration: Duration in milliseconds for change highlights

    T075: PropertyDisplay widget implementation
    FR-113: Display all window properties
    FR-120: Live mode with change highlighting
    SC-037: <100ms property updates

    Examples:
        >>> props = WindowProperties(window_id=123, window_class="Code", ...)
        >>> display = PropertyDisplay()
        >>> display.set_properties(props)
    """

    # Reactive property - updates UI when properties change
    window_props: reactive[Optional[WindowProperties]] = reactive(None)

    def __init__(
        self,
        *,
        name: str = "property-display",
        id: str = "property-table",
        classes: str = "",
    ):
        """Initialize property display.

        Args:
            name: Widget name
            id: Widget ID
            classes: CSS classes
        """
        super().__init__(
            name=name,
            id=id,
            classes=classes,
            zebra_stripes=True,
            cursor_type="row",
            show_header=True,
        )

        self._row_keys: Dict[str, object] = {}  # Map property name -> RowKey
        self._highlight_tasks: Dict[str, asyncio.Task] = {}  # Active highlight tasks
        self.highlight_duration = 200  # milliseconds

        self._setup_columns()

    def _setup_columns(self):
        """Add column headers to the table."""
        self.add_columns("Property", "Value")

    def set_properties(self, props: WindowProperties):
        """Set window properties and populate table.

        Args:
            props: WindowProperties to display
        """
        self.window_props = props
        self._populate_table()

    def _populate_table(self):
        """Populate table with current window properties."""
        if not self.window_props:
            return

        # Clear existing rows
        self.clear()
        self._row_keys.clear()

        # Get property dictionary
        prop_dict = self.window_props.to_property_dict()

        # Add each property as a row
        for prop_name, prop_value in prop_dict.items():
            row_key = self.add_row(prop_name, prop_value)
            self._row_keys[prop_name] = row_key

    async def update_property(self, property_name: str, new_value: str):
        """Update a single property value with highlighting.

        Updates the property in the table and flashes yellow highlight
        for visual feedback.

        Args:
            property_name: Name of property to update (e.g., "Title")
            new_value: New value to display

        FR-120: Visual feedback for live updates
        """
        if property_name not in self._row_keys:
            return

        row_key = self._row_keys[property_name]

        # Update the cell value
        self.update_cell(row_key, "Value", new_value)

        # Flash highlight
        await self.flash_highlight(property_name)

    async def flash_highlight(self, property_name: str):
        """Flash yellow highlight on a property row.

        Args:
            property_name: Property to highlight

        Implementation: Add CSS class for 200ms then remove
        """
        if property_name not in self._row_keys:
            return

        # Cancel existing highlight task for this property
        if property_name in self._highlight_tasks:
            self._highlight_tasks[property_name].cancel()

        # Create new highlight task
        async def _do_highlight():
            row_key = self._row_keys[property_name]

            # Add highlight class (CSS will style this)
            # Note: Textual DataTable doesn't have direct row styling,
            # so we update the cell with styled text instead
            current_value = self.get_cell(row_key, "Value")

            # Temporarily style with Rich markup
            highlighted_value = f"[bold yellow on black]{current_value}[/]"
            self.update_cell(row_key, "Value", highlighted_value)

            # Wait for highlight duration
            await asyncio.sleep(self.highlight_duration / 1000)

            # Remove highlight styling
            self.update_cell(row_key, "Value", str(current_value))

        # Start highlight task
        task = asyncio.create_task(_do_highlight())
        self._highlight_tasks[property_name] = task

    def update_from_container(self, container):
        """Update properties from an i3 container object.

        Convenience method for live mode updates from i3 events.

        Args:
            container: i3ipc Container object from event

        FR-120: Live mode property updates
        """
        if not self.window_props:
            return

        # Update window properties object
        if hasattr(container, 'name') and container.name != self.window_props.title:
            self.window_props.title = container.name
            asyncio.create_task(self.update_property("Title", container.name))

        if hasattr(container, 'marks') and container.marks != self.window_props.marks:
            self.window_props.marks = container.marks
            mark_str = self.window_props.format_marks()
            asyncio.create_task(self.update_property("i3 Marks", mark_str))

        if hasattr(container, 'focused') and container.focused != self.window_props.focused:
            self.window_props.focused = container.focused
            focused_str = self.window_props.format_focused()
            asyncio.create_task(self.update_property("Focused", focused_str))

    def get_cell(self, row_key, column_key) -> str:
        """Get cell value by row and column key.

        Args:
            row_key: Row key from add_row()
            column_key: Column name ("Property" or "Value")

        Returns:
            Cell value as string
        """
        # Textual DataTable internal method to get cell value
        # This is a simplified version - actual implementation may differ
        try:
            return str(self.get_cell_at((row_key, column_key)))
        except Exception:
            return ""
