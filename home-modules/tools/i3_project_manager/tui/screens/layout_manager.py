"""Layout manager screen for i3pm TUI.

Manage saved layouts for a project (save, restore, delete, export).
"""

from typing import Optional
from pathlib import Path
from textual.app import ComposeResult
from textual.screen import Screen
from textual.widgets import Header, Footer, Static, Button, DataTable, Input
from textual.containers import Vertical, Horizontal, Container
from textual.binding import Binding
import i3ipc.aio

from i3_project_manager.core.models import Project
from i3_project_manager.core.layout import (
    LayoutManager,
    LayoutSaveRequest,
    LayoutRestoreRequest,
    LayoutDeleteRequest,
    LayoutExportRequest,
)


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

    CSS_PATH = "layout_manager.tcss"

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
        self._layout_manager: Optional[LayoutManager] = None
        self._i3: Optional[i3ipc.aio.Connection] = None
        self._input_visible = False

    def compose(self) -> ComposeResult:
        """Compose the layout manager layout."""
        yield Header()

        with Vertical():
            yield Static(f"Layout Manager: {self._project.name}", classes="title")

            # Layout name input (hidden by default)
            with Container(id="input_container", classes="hidden"):
                yield Static("Layout name:", id="input_label")
                yield Input(placeholder="my-layout", id="layout_name_input")

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
        # Initialize i3 connection
        self._i3 = i3ipc.aio.Connection()
        await self._i3.connect()

        # Create a simple project manager for layout operations
        class SimpleProjectManager:
            """Minimal project manager for TUI layout operations."""
            def __init__(self, project: Project):
                self._project = project

            async def get_project(self, name: str) -> Project:
                """Get the current project."""
                return self._project

            async def save_project(self, project: Project) -> None:
                """Save project (no-op for TUI)."""
                pass

        project_manager = SimpleProjectManager(self._project)

        # Initialize layout manager
        config_dir = Path.home() / ".config" / "i3"
        self._layout_manager = LayoutManager(self._i3, config_dir, project_manager)

        table = self.query_one("#layouts_table", DataTable)
        table.add_columns("Name", "Windows", "Workspaces", "Saved")
        table.zebra_stripes = True
        table.cursor_type = "row"

        # Load saved layouts
        await self._load_layouts()

    async def _load_layouts(self) -> None:
        """Load saved layouts from project."""
        table = self.query_one("#layouts_table", DataTable)
        table.clear()

        # Get layouts using LayoutManager
        layouts = await self._layout_manager.list_layouts(self._project.name)

        if not layouts:
            # No layouts saved yet
            table.add_row("No layouts saved", "", "", "")
        else:
            for layout_data in layouts:
                table.add_row(
                    layout_data.layout_name,
                    str(layout_data.window_count),
                    str(layout_data.workspace_count),
                    layout_data.saved_at.strftime("%Y-%m-%d %H:%M")
                )

    async def action_save_layout(self) -> None:
        """Save current window layout."""
        # Show input for layout name
        input_container = self.query_one("#input_container")
        input_container.remove_class("hidden")
        input_field = self.query_one("#layout_name_input", Input)
        input_field.focus()

    async def _perform_save(self, layout_name: str) -> None:
        """Perform the actual save operation."""
        try:
            request = LayoutSaveRequest(
                project_name=self._project.name,
                layout_name=layout_name
            )
            response = await self._layout_manager.save_layout(request)

            if response.success:
                self.notify(
                    f"✓ Saved '{layout_name}': {response.windows_captured} windows, "
                    f"{response.workspaces_captured} workspaces",
                    severity="information"
                )
                await self._load_layouts()
            else:
                self.notify(f"✗ Save failed: {response.error}", severity="error")

        except Exception as e:
            self.notify(f"✗ Error saving layout: {e}", severity="error")

        # Hide input
        input_container = self.query_one("#input_container")
        input_container.add_class("hidden")

    async def action_restore_layout(self) -> None:
        """Restore selected layout."""
        table = self.query_one("#layouts_table", DataTable)

        if not table.cursor_row:
            self.notify("No layout selected", severity="warning")
            return

        # Get selected layout name from table
        row_key = table.cursor_row
        try:
            cell_value = table.get_cell(row_key, "Name")
            layout_name = str(cell_value)

            if layout_name == "No layouts saved":
                return

            self.notify(f"Restoring layout '{layout_name}'...", severity="information")

            request = LayoutRestoreRequest(
                project_name=self._project.name,
                layout_name=layout_name
            )
            response = await self._layout_manager.restore_layout(request)

            if response.success:
                self.notify(
                    f"✓ Restored: {response.windows_restored} windows restored, "
                    f"{response.windows_launched} launched ({response.duration:.1f}s)",
                    severity="information"
                )
            else:
                self.notify(f"✗ Restore failed: {response.error}", severity="error")

        except Exception as e:
            self.notify(f"✗ Error restoring layout: {e}", severity="error")

    async def action_delete_layout(self) -> None:
        """Delete selected layout."""
        table = self.query_one("#layouts_table", DataTable)

        if not table.cursor_row:
            self.notify("No layout selected", severity="warning")
            return

        row_key = table.cursor_row
        try:
            cell_value = table.get_cell(row_key, "Name")
            layout_name = str(cell_value)

            if layout_name == "No layouts saved":
                return

            # Delete with confirmation
            request = LayoutDeleteRequest(
                project_name=self._project.name,
                layout_name=layout_name,
                confirmed=True  # Auto-confirm in TUI
            )
            response = await self._layout_manager.delete_layout(request)

            if response.success:
                self.notify(f"✓ Deleted layout '{layout_name}'", severity="information")
                await self._load_layouts()
            else:
                self.notify(f"✗ Delete failed: {response.error}", severity="error")

        except Exception as e:
            self.notify(f"✗ Error deleting layout: {e}", severity="error")

    async def action_export_layout(self) -> None:
        """Export selected layout to file."""
        table = self.query_one("#layouts_table", DataTable)

        if not table.cursor_row:
            self.notify("No layout selected", severity="warning")
            return

        row_key = table.cursor_row
        try:
            cell_value = table.get_cell(row_key, "Name")
            layout_name = str(cell_value)

            if layout_name == "No layouts saved":
                return

            # Export to current directory
            export_path = Path.cwd() / f"{layout_name}.json"

            request = LayoutExportRequest(
                project_name=self._project.name,
                layout_name=layout_name,
                export_path=export_path
            )
            response = await self._layout_manager.export_layout(request)

            if response.success:
                self.notify(
                    f"✓ Exported to {export_path}",
                    severity="information"
                )
            else:
                self.notify(f"✗ Export failed: {response.error}", severity="error")

        except Exception as e:
            self.notify(f"✗ Error exporting layout: {e}", severity="error")

    async def action_back(self) -> None:
        """Return to browser screen."""
        self.dismiss()

    async def on_input_changed(self, event: Input.Changed) -> None:
        """Handle input changes - check for Enter key."""
        # Note: We handle submission via key event instead
        pass

    async def on_key(self, event) -> None:
        """Handle key presses globally."""
        if event.key == "enter":
            # Check if the focused widget is our input field
            focused = self.screen.focused
            if focused and focused.id == "layout_name_input":
                input_field = self.query_one("#layout_name_input", Input)
                layout_name = input_field.value.strip()
                if layout_name:
                    self.notify(f"Saving layout '{layout_name}'...", severity="information")
                    await self._perform_save(layout_name)
                    input_field.value = ""  # Clear input
                else:
                    self.notify("Layout name cannot be empty", severity="warning")
                event.prevent_default()
                event.stop()

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
