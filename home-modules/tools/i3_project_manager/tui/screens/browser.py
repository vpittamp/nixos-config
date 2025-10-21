"""Project browser screen for i3pm TUI.

This is the default/home screen showing all projects with search and filtering.
Users can browse, search, select, and perform actions on projects from here.
"""

from datetime import datetime
from typing import Optional
from textual.app import ComposeResult
from textual.screen import Screen
from textual.widgets import Header, Footer, Input, DataTable, Static
from textual.binding import Binding
from textual.reactive import reactive
from textual.containers import Vertical, Horizontal

from i3_project_manager.core.models import Project


class ProjectBrowserScreen(Screen):
    """Default TUI screen for browsing and selecting projects.

    Features:
    - Search/filter projects by name or directory
    - Sort by name, modified date, or directory
    - Quick actions: switch, edit, delete, layouts
    - Real-time active project indicator

    Keyboard shortcuts:
    - ↑/↓: Navigate table
    - Enter: Switch to project
    - e: Edit project
    - l: Layout manager
    - m: Monitor dashboard
    - n: New project wizard
    - d: Delete project
    - /: Focus search
    - s: Toggle sort
    - q: Quit
    """

    # Keyboard bindings
    BINDINGS = [
        Binding("up,k", "cursor_up", "Up", show=False),
        Binding("down,j", "cursor_down", "Down", show=False),
        Binding("enter", "switch_project", "Switch"),
        Binding("e", "edit_project", "Edit"),
        Binding("l", "layout_manager", "Layouts"),
        Binding("m", "monitor", "Monitor"),
        Binding("n", "new_project", "New"),
        Binding("d", "delete_project", "Delete"),
        Binding("slash", "focus_search", "Search", key_display="/"),
        Binding("escape", "clear_search", "Clear"),
        Binding("s", "toggle_sort", "Sort"),
        Binding("r", "reverse_sort", "Reverse"),
    ]

    # Reactive attributes
    active_project: reactive[Optional[str]] = reactive(None)
    filter_text: reactive[str] = reactive("")
    sort_by: reactive[str] = reactive("modified")
    sort_reverse: reactive[bool] = reactive(False)

    def __init__(self):
        """Initialize the browser screen."""
        super().__init__()
        self._projects: list[Project] = []

    def compose(self) -> ComposeResult:
        """Compose the screen layout."""
        yield Header()

        with Vertical():
            # Status bar showing active project
            yield Static("Loading...", id="status", classes="status-bar")

            # Search input
            yield Input(placeholder="Search projects...", id="search")

            # Projects table
            yield DataTable(id="projects", cursor_type="row")

        yield Footer()

    async def on_mount(self) -> None:
        """Called when screen is mounted - initialize widgets and data."""
        # Set up the DataTable columns
        table = self.query_one("#projects", DataTable)
        table.add_columns("Icon", "Name", "Directory", "Apps", "Layouts", "Modified")
        table.zebra_stripes = True
        table.cursor_type = "row"

        # Load projects and start refresh task
        await self.refresh_data()

        # Start auto-refresh every 5 seconds using Textual's set_interval
        self.set_interval(5, self._sync_refresh)

        # Get active project from app
        if hasattr(self.app, "active_project"):
            self.active_project = self.app.active_project

    def _sync_refresh(self) -> None:
        """Sync wrapper for refresh_data to work with set_interval."""
        self.run_worker(self.refresh_data(), exclusive=True)

    async def refresh_data(self) -> None:
        """Load projects from disk and update table."""
        try:
            # Load all projects
            self._projects = Project.list_all()

            # Apply filter if active
            filtered = self._filter_projects(self._projects)

            # Apply sort
            sorted_projects = self._sort_projects(filtered)

            # Update table
            await self._update_table(sorted_projects)

            # Update status
            await self._update_status()

        except Exception as e:
            self.log.error(f"Failed to load projects: {e}")
            self.notify(f"Error loading projects: {e}", severity="error")

    def _filter_projects(self, projects: list[Project]) -> list[Project]:
        """Filter projects by search text."""
        if not self.filter_text:
            return projects

        filter_lower = self.filter_text.lower()
        return [
            p for p in projects
            if filter_lower in p.name.lower() or filter_lower in str(p.directory).lower()
        ]

    def _sort_projects(self, projects: list[Project]) -> list[Project]:
        """Sort projects by current sort criteria."""
        if self.sort_by == "name":
            key = lambda p: p.name
        elif self.sort_by == "directory":
            key = lambda p: str(p.directory)
        elif self.sort_by == "modified":
            key = lambda p: p.modified_at
        else:
            key = lambda p: p.modified_at

        return sorted(projects, key=key, reverse=self.sort_reverse)

    async def _update_table(self, projects: list[Project]) -> None:
        """Update the DataTable with project data."""
        table = self.query_one("#projects", DataTable)
        table.clear()

        # Track added keys to prevent duplicates
        added_keys = set()

        for project in projects:
            # Skip if we've already added this project name
            if project.name in added_keys:
                self.log.warning(f"Skipping duplicate project: {project.name}")
                continue

            # Calculate relative time for modified_at
            time_diff = datetime.now() - project.modified_at
            if time_diff.days > 0:
                modified_str = f"{time_diff.days}d ago"
            elif time_diff.seconds // 3600 > 0:
                modified_str = f"{time_diff.seconds // 3600}h ago"
            else:
                modified_str = f"{time_diff.seconds // 60}m ago"

            # Truncate directory path
            dir_str = str(project.directory)
            if len(dir_str) > 30:
                dir_str = "..." + dir_str[-27:]

            # Add row with styling for active project
            try:
                styled = project.name == self.active_project
                table.add_row(
                    project.icon or " ",
                    project.display_name or project.name,
                    dir_str,
                    str(len(project.scoped_classes)),
                    str(len(project.saved_layouts)),
                    modified_str,
                    key=project.name,
                )
                added_keys.add(project.name)
            except Exception as e:
                self.log.error(f"Failed to add row for project {project.name}: {e}")
                # Continue adding other projects even if one fails

            # Note: Active project highlighting handled via CSS

    async def _update_status(self) -> None:
        """Update the status bar with active project info."""
        status = self.query_one("#status", Static)

        if self.active_project:
            status.update(f"Active Project: {self.active_project} | {len(self._projects)} projects total")
        else:
            status.update(f"No active project | {len(self._projects)} projects total")

    def watch_active_project(self, old: Optional[str], new: Optional[str]) -> None:
        """Called when active_project changes."""
        # Refresh table to update highlighting
        self.run_worker(self._update_status(), exclusive=True)
        self.run_worker(self.refresh_data(), exclusive=True)

    def watch_filter_text(self, old: str, new: str) -> None:
        """Called when filter_text changes - update filtered results."""
        self.run_worker(self.refresh_data(), exclusive=True)

    def watch_sort_by(self, old: str, new: str) -> None:
        """Called when sort_by changes - re-sort table."""
        self.run_worker(self.refresh_data(), exclusive=True)

    def watch_sort_reverse(self, old: bool, new: bool) -> None:
        """Called when sort_reverse changes - re-sort table."""
        self.run_worker(self.refresh_data(), exclusive=True)

    async def on_input_changed(self, event: Input.Changed) -> None:
        """Handle search input changes."""
        if event.input.id == "search":
            self.filter_text = event.value

    def _get_selected_project(self) -> Optional[Project]:
        """Get the currently selected project from the table."""
        table = self.query_one("#projects", DataTable)
        if table.row_count == 0:
            return None

        # Get the cursor coordinate
        cursor_row = table.cursor_row
        if cursor_row is None or cursor_row < 0:
            return None

        # Get row keys (which are project names in our case)
        try:
            # Get all row keys
            row_keys = list(table.rows.keys())
            if cursor_row >= len(row_keys):
                return None

            # Get the project name from the row key at cursor position
            project_name = row_keys[cursor_row]
            return next((p for p in self._projects if p.name == project_name), None)
        except Exception as e:
            self.log.error(f"Error getting selected project: {e}")
            return None

    async def action_switch_project(self) -> None:
        """Switch to the selected project."""
        project = self._get_selected_project()
        if not project:
            self.notify("No project selected", severity="warning")
            return

        # Send tick event to daemon to switch project
        if hasattr(self.app, "daemon_client") and self.app.daemon_client:
            try:
                from i3_project_manager.core.project import ProjectManager
                pm = ProjectManager(self.app.daemon_client)
                await pm.switch_to_project(project.name)
                self.notify(f"Switched to project: {project.name}", severity="success")

                # Update app state
                self.app.active_project = project.name
                self.active_project = project.name
            except Exception as e:
                self.notify(f"Failed to switch project: {e}", severity="error")
        else:
            self.notify("Daemon not connected", severity="error")

    def action_edit_project(self) -> None:
        """Open the editor for the selected project."""
        project = self._get_selected_project()
        if not project:
            self.notify("No project selected", severity="warning")
            return

        # Push editor screen
        from i3_project_manager.tui.screens.editor import ProjectEditorScreen
        self.app.push_screen(ProjectEditorScreen(project), callback=self._on_editor_closed)

    def _on_editor_closed(self, result: Optional[Project]) -> None:
        """Callback when editor screen is closed."""
        if result:
            self.notify(f"Project '{result.name}' saved", severity="success")
            self.run_worker(self.refresh_data(), exclusive=True)

    def action_layout_manager(self) -> None:
        """Open layout manager for selected project."""
        project = self._get_selected_project()
        if not project:
            self.notify("No project selected", severity="warning")
            return

        # Push layout manager screen
        from i3_project_manager.tui.screens.layout_manager import LayoutManagerScreen
        self.app.push_screen(LayoutManagerScreen(project))

    def action_monitor(self) -> None:
        """Open monitor dashboard."""
        from i3_project_manager.tui.screens.monitor import MonitorScreen
        self.app.push_screen(MonitorScreen())

    def action_new_project(self) -> None:
        """Open project creation wizard."""
        from i3_project_manager.tui.screens.wizard import ProjectWizardScreen
        self.app.push_screen(ProjectWizardScreen(), callback=self._on_wizard_closed)

    def _on_wizard_closed(self, result: Optional[Project]) -> None:
        """Callback when wizard screen is closed."""
        if result:
            self.notify(f"Project '{result.name}' created", severity="success")
            self.run_worker(self.refresh_data(), exclusive=True)

    async def action_delete_project(self) -> None:
        """Delete the selected project after confirmation."""
        project = self._get_selected_project()
        if not project:
            self.notify("No project selected", severity="warning")
            return

        # TODO: Show confirmation dialog before deleting
        # For now, just show a warning
        self.notify(f"Delete confirmation not yet implemented for '{project.name}'", severity="warning")

    def action_focus_search(self) -> None:
        """Focus the search input."""
        search_input = self.query_one("#search", Input)
        search_input.focus()

    def action_clear_search(self) -> None:
        """Clear the search filter."""
        search_input = self.query_one("#search", Input)
        search_input.value = ""
        self.filter_text = ""

    def action_toggle_sort(self) -> None:
        """Toggle between sort modes."""
        if self.sort_by == "modified":
            self.sort_by = "name"
        elif self.sort_by == "name":
            self.sort_by = "directory"
        else:
            self.sort_by = "modified"

        self.notify(f"Sorting by: {self.sort_by}", severity="information")

    def action_reverse_sort(self) -> None:
        """Reverse the sort order."""
        self.sort_reverse = not self.sort_reverse
        order = "descending" if self.sort_reverse else "ascending"
        self.notify(f"Sort order: {order}", severity="information")
