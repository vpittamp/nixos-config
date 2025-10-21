"""Layout manager screen for i3pm TUI.

Manage saved layouts for a project (save, restore, delete, export).
"""

from typing import Optional
from textual.app import ComposeResult
from textual.screen import Screen
from textual.widgets import Header, Footer, Static, Button, DataTable
from textual.containers import Vertical, Horizontal
from textual.binding import Binding

from i3_project_manager.core.models import Project


class LayoutManagerScreen(Screen):
    """TUI screen for managing project layouts.

    Features:
    - List saved layouts for project
    - Save current layout
    - Restore selected layout
    - Delete layout
    - Export layout to file

    Keyboard shortcuts:
    - s: Save current layout
    - r: Restore selected layout
    - d: Delete layout
    - e: Export layout
    - Esc: Return to browser
    """

    BINDINGS = [
        Binding("s", "save_layout", "Save"),
        Binding("r", "restore_layout", "Restore"),
        Binding("d", "delete_layout", "Delete"),
        Binding("e", "export_layout", "Export"),
        Binding("escape", "back", "Back"),
    ]

    def __init__(self, project: Project):
        """Initialize the layout manager for a project.

        Args:
            project: The project to manage layouts for
        """
        super().__init__()
        self._project = project

    def compose(self) -> ComposeResult:
        """Compose the layout manager layout."""
        yield Header()

        with Vertical():
            yield Static(f"Layout Manager: {self._project.name}", classes="title")

            # Layouts table
            yield DataTable(id="layouts_table")

            # Action buttons
            with Horizontal(classes="actions"):
                yield Button("Save Current", id="save_button", variant="success")
                yield Button("Restore Selected", id="restore_button", variant="primary")
                yield Button("Delete", id="delete_button", variant="error")
                yield Button("Export", id="export_button")
                yield Button("Back", id="back_button")

        yield Footer()

    async def on_mount(self) -> None:
        """Initialize the layouts table."""
        table = self.query_one("#layouts_table", DataTable)
        table.add_columns("Name", "Windows", "Workspaces", "Saved")
        table.zebra_stripes = True

        # Load saved layouts
        await self._load_layouts()

    async def _load_layouts(self) -> None:
        """Load saved layouts from project."""
        table = self.query_one("#layouts_table", DataTable)
        table.clear()

        if not self._project.saved_layouts:
            # No layouts saved yet
            table.add_row("No layouts saved", "", "", "")
        else:
            for layout_name in self._project.saved_layouts:
                # TODO: Load layout details from file
                table.add_row(layout_name, "?", "?", "?")

    async def action_save_layout(self) -> None:
        """Save current window layout."""
        # TODO: Implement layout save using LayoutManager
        self.notify("Layout save not yet implemented", severity="warning")

    async def action_restore_layout(self) -> None:
        """Restore selected layout."""
        # TODO: Implement layout restore
        self.notify("Layout restore not yet implemented", severity="warning")

    async def action_delete_layout(self) -> None:
        """Delete selected layout."""
        # TODO: Implement layout delete
        self.notify("Layout delete not yet implemented", severity="warning")

    async def action_export_layout(self) -> None:
        """Export selected layout to file."""
        # TODO: Implement layout export
        self.notify("Layout export not yet implemented", severity="warning")

    async def action_back(self) -> None:
        """Return to browser screen."""
        self.dismiss()

    async def on_button_pressed(self, event: Button.Pressed) -> None:
        """Handle button presses."""
        if event.button.id == "save_button":
            await self.action_save_layout()
        elif event.button.id == "restore_button":
            await self.action_restore_layout()
        elif event.button.id == "delete_button":
            await self.action_delete_layout()
        elif event.button.id == "export_button":
            await self.action_export_layout()
        elif event.button.id == "back_button":
            await self.action_back()
