"""AppTable widget for the classification wizard.

Provides a virtualized, sortable table displaying discovered applications
with their classification status, suggestions, and confidence scores.
"""

from textual.widgets import DataTable
from textual.reactive import reactive
from typing import Optional, Literal

from i3_project_manager.models.classification import AppClassification


class AppTable(DataTable):
    """Sortable application table with virtual scrolling.

    Displays applications with columns for Name, Class, Scope, Confidence,
    and Suggestion. Supports sorting by clicking column headers and
    virtual scrolling for performance with 1000+ rows.

    Attributes:
        apps: List of AppClassification objects to display
        selected_app: Currently selected app (reactive property)

    FR-109: Virtual scrolling for 1000+ apps
    SC-026: <50ms keyboard response time
    """

    # Reactive property - updates UI when selected app changes
    selected_app: reactive[Optional[AppClassification]] = reactive(None)

    def __init__(
        self,
        apps: list[AppClassification] = None,
        *,
        name: str = "app-table",
        id: str = "app-table",
        classes: str = "",
    ):
        """Initialize the app table.

        Args:
            apps: Initial list of applications to display
            name: Widget name
            id: Widget ID
            classes: CSS classes
        """
        # Enable virtual scrolling for performance (FR-109)
        super().__init__(
            name=name,
            id=id,
            classes=classes,
            zebra_stripes=True,
            cursor_type="row",
            fixed_columns=0,
        )

        self.apps = apps or []
        self._row_keys: list = []  # Store RowKey objects for update_cell
        self._setup_columns()

    def _setup_columns(self):
        """Add column headers to the table."""
        self.add_columns(
            "Name",
            "Class",
            "Status",
            "Confidence",
            "Suggestion",
        )

    def populate(self, apps: list[AppClassification]):
        """Populate table with applications.

        Args:
            apps: List of AppClassification objects to display
        """
        self.apps = apps
        self.clear()
        self._row_keys = []  # Reset row keys

        for app in apps:
            self._add_app_row(app)

    def _add_app_row(self, app: AppClassification):
        """Add a single application row to the table.

        Args:
            app: AppClassification to add
        """
        # Format confidence as percentage
        confidence = (
            f"{app.suggestion_confidence * 100:.0f}%"
            if app.suggestion_confidence > 0
            else "-"
        )

        # Format suggestion
        suggestion = app.suggested_scope if app.suggested_scope else "-"

        # Format status with visual indicator
        status = self._format_status(app.current_scope)

        # Add row and store the RowKey for later updates
        row_key = self.add_row(
            app.app_name,
            app.window_class,
            status,
            confidence,
            suggestion,
        )
        self._row_keys.append(row_key)

    def _format_status(self, scope: Literal["scoped", "global", "unclassified"]) -> str:
        """Format status with visual indicator.

        Args:
            scope: Classification scope

        Returns:
            Formatted status string with emoji/symbol
        """
        status_map = {
            "scoped": "● Scoped",
            "global": "○ Global",
            "unclassified": "? Unknown",
        }
        return status_map.get(scope, scope)

    def update_row(self, row_index: int, app: AppClassification):
        """Update a specific row with new app data.

        Args:
            row_index: Index of row to update
            app: Updated AppClassification
        """
        if row_index < 0 or row_index >= len(self._row_keys):
            return  # Invalid row index

        row_key = self._row_keys[row_index]

        confidence = (
            f"{app.suggestion_confidence * 100:.0f}%"
            if app.suggestion_confidence > 0
            else "-"
        )
        suggestion = app.suggested_scope if app.suggested_scope else "-"
        status = self._format_status(app.current_scope)

        # Update cells using the RowKey
        self.update_cell(row_key, "Name", app.app_name)
        self.update_cell(row_key, "Class", app.window_class)
        self.update_cell(row_key, "Status", status)
        self.update_cell(row_key, "Confidence", confidence)
        self.update_cell(row_key, "Suggestion", suggestion)

    def get_selected_row_index(self) -> Optional[int]:
        """Get the index of the currently selected row.

        Returns:
            Row index or None if no row selected
        """
        if self.cursor_row < 0 or self.cursor_row >= len(self.apps):
            return None
        return self.cursor_row

    def get_selected_app(self) -> Optional[AppClassification]:
        """Get the currently selected application.

        Returns:
            AppClassification or None if no row selected
        """
        row_index = self.get_selected_row_index()
        if row_index is None:
            return None
        return self.apps[row_index]

    def on_data_table_row_highlighted(self, event: DataTable.RowHighlighted):
        """Handle row selection change.

        Updates the selected_app reactive property when cursor moves.

        Args:
            event: Row highlighted event
        """
        row_index = event.cursor_row
        if 0 <= row_index < len(self.apps):
            self.selected_app = self.apps[row_index]
        else:
            self.selected_app = None

    def sort_by_column(self, column: str):
        """Sort table by specified column.

        Args:
            column: Column name to sort by (Name, Class, Status, Confidence)
        """
        # Map column names to sort keys
        sort_keys = {
            "Name": lambda app: app.app_name.lower(),
            "Class": lambda app: app.window_class.lower(),
            "Status": lambda app: app.current_scope,
            "Confidence": lambda app: app.suggestion_confidence,
        }

        if column not in sort_keys:
            return

        # Sort apps
        reverse = column == "Confidence"  # Highest confidence first
        sorted_apps = sorted(self.apps, key=sort_keys[column], reverse=reverse)

        # Repopulate table
        self.populate(sorted_apps)

    def filter_by_status(
        self, status: Literal["all", "scoped", "global", "unclassified"]
    ):
        """Filter table to show only apps with specified status.

        Args:
            status: Status to filter by, or "all" to show all apps
        """
        if status == "all":
            filtered_apps = self.apps
        else:
            filtered_apps = [app for app in self.apps if app.current_scope == status]

        self.populate(filtered_apps)
