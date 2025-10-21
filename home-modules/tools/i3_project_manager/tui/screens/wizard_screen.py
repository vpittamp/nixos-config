"""Classification wizard screen for bulk app classification.

Provides an interactive TUI for classifying multiple applications with
keyboard shortcuts, filtering, sorting, and undo/redo support.
"""

from textual.app import ComposeResult
from textual.screen import Screen
from textual.widgets import Header, Footer, Static
from textual.containers import Horizontal, Vertical, Container
from textual.binding import Binding
from textual.reactive import reactive
from typing import Optional

from i3_project_manager.models.classification import AppClassification, WizardState
from i3_project_manager.tui.widgets.app_table import AppTable
from i3_project_manager.tui.widgets.detail_panel import DetailPanel


class WizardScreen(Screen):
    """Classification wizard main screen.

    Displays a table of applications with classification status and a detail
    panel showing comprehensive information about the selected app.

    Keyboard Bindings:
    - Arrow keys: Navigate table
    - s: Mark as scoped
    - g: Mark as global
    - u: Mark as unclassified/unknown
    - Space: Toggle selection (multi-select)
    - Shift+A: Accept all suggestions (>90% confidence)
    - Ctrl+Z: Undo last action
    - Ctrl+Y: Redo last undone action
    - Enter: Save and exit
    - Escape: Cancel and exit without saving
    - p: Create pattern rule for selected app
    - d: Detect window class for selected app

    FR-095 through FR-110: All wizard requirements
    T056: WizardScreen implementation
    """

    BINDINGS = [
        Binding("s", "classify_scoped", "Scoped", show=True),
        Binding("g", "classify_global", "Global", show=True),
        Binding("u", "classify_unknown", "Unknown", show=True),
        Binding("space", "toggle_select", "Select", show=True),
        Binding("shift+a", "accept_all", "Accept All", show=True),
        Binding("ctrl+z", "undo", "Undo", show=True),
        Binding("ctrl+y", "redo", "Redo", show=False),
        Binding("enter", "save", "Save", show=True),
        Binding("escape", "cancel", "Cancel", show=True),
        Binding("p", "create_pattern", "Pattern", show=True),
        Binding("d", "detect_class", "Detect", show=True),
        Binding("f", "filter", "Filter", show=False),
        Binding("o", "sort", "Sort", show=False),
    ]

    # Reactive state
    wizard_state: reactive[WizardState] = reactive(WizardState)
    status_message: reactive[str] = reactive("")

    def __init__(self, apps: list[AppClassification]):
        """Initialize the wizard screen.

        Args:
            apps: List of applications to classify
        """
        super().__init__()
        self.wizard_state = WizardState(apps=apps)

    def compose(self) -> ComposeResult:
        """Compose the wizard layout.

        Layout:
        - Header (title bar)
        - Main container:
          - Left: AppTable (70% width)
          - Right: DetailPanel (30% width)
        - Status bar
        - Footer (keybindings)
        """
        yield Header()

        # Main content area with horizontal split
        with Horizontal(id="main-container"):
            # Left side: Application table
            with Vertical(id="table-container", classes="panel"):
                yield Static(
                    f"Applications ({len(self.wizard_state.apps)} total)",
                    id="table-title",
                    classes="panel-title",
                )
                yield AppTable(
                    apps=self.wizard_state.apps,
                    id="app-table",
                )

            # Right side: Detail panel
            with Vertical(id="detail-container", classes="panel"):
                yield Static(
                    "Application Details",
                    id="detail-title",
                    classes="panel-title",
                )
                yield DetailPanel(id="detail-panel")

        # Status bar
        yield Static(
            "Ready • Use arrow keys to navigate, s/g/u to classify",
            id="status-bar",
            classes="status",
        )

        yield Footer()

    def on_mount(self) -> None:
        """Initialize screen when mounted."""
        # Wire up reactive properties
        table = self.query_one("#app-table", AppTable)
        detail = self.query_one("#detail-panel", DetailPanel)

        # Sync table selection to detail panel
        def on_selection_change(app: Optional[AppClassification]):
            detail.set_app(app)

        table.watch(table, "selected_app", on_selection_change)

        # Populate table with initial apps
        table.populate(self.wizard_state.apps)

        # Focus the table
        table.focus()

    def watch_status_message(self, old: str, new: str) -> None:
        """Update status bar when status message changes."""
        if new:
            status_bar = self.query_one("#status-bar", Static)
            status_bar.update(new)

    async def action_classify_scoped(self) -> None:
        """Mark selected app(s) as scoped (FR-101)."""
        await self._classify_selected("scoped")
        self.status_message = "✓ Marked as scoped"

    async def action_classify_global(self) -> None:
        """Mark selected app(s) as global (FR-101)."""
        await self._classify_selected("global")
        self.status_message = "✓ Marked as global"

    async def action_classify_unknown(self) -> None:
        """Mark selected app(s) as unclassified (FR-101)."""
        await self._classify_selected("unclassified")
        self.status_message = "✓ Marked as unclassified"

    async def _classify_selected(self, scope: str) -> None:
        """Apply classification to selected app(s).

        Args:
            scope: Classification scope (scoped, global, unclassified)
        """
        table = self.query_one("#app-table", AppTable)

        # Save undo state before modifying
        self.wizard_state.save_undo_state()

        # Get selected indices (either multi-select or current row)
        if self.wizard_state.selected_indices:
            indices = self.wizard_state.selected_indices
        else:
            row_index = table.get_selected_row_index()
            if row_index is not None:
                indices = {row_index}
            else:
                return

        # Apply classification
        for idx in indices:
            if 0 <= idx < len(self.wizard_state.apps):
                app = self.wizard_state.apps[idx]
                app.classify_as(scope)
                table.update_row(idx, app)

        # Mark changes made
        self.wizard_state.changes_made = True

        # Clear selection after action
        self.wizard_state.selected_indices.clear()

    async def action_toggle_select(self) -> None:
        """Toggle multi-select for current row (FR-100)."""
        table = self.query_one("#app-table", AppTable)
        row_index = table.get_selected_row_index()

        if row_index is None:
            return

        # Toggle selection
        if row_index in self.wizard_state.selected_indices:
            self.wizard_state.selected_indices.remove(row_index)
            self.status_message = f"Deselected ({len(self.wizard_state.selected_indices)} selected)"
        else:
            self.wizard_state.selected_indices.add(row_index)
            self.status_message = f"Selected ({len(self.wizard_state.selected_indices)} selected)"

        # TODO: Visual indicator for selected rows (highlight in table)

    async def action_accept_all(self) -> None:
        """Accept all suggestions with confidence >90% (FR-102)."""
        # Save undo state
        self.wizard_state.save_undo_state()

        accepted_count = 0
        table = self.query_one("#app-table", AppTable)

        for idx, app in enumerate(self.wizard_state.apps):
            if app.suggested_scope and app.suggestion_confidence >= 0.9:
                app.accept_suggestion()
                table.update_row(idx, app)
                accepted_count += 1

        self.wizard_state.changes_made = True
        self.status_message = f"✓ Accepted {accepted_count} high-confidence suggestions"

    async def action_undo(self) -> None:
        """Undo last action (FR-104)."""
        try:
            self.wizard_state.undo()

            # Refresh table
            table = self.query_one("#app-table", AppTable)
            table.populate(self.wizard_state.apps)

            self.status_message = "⟲ Undone"
        except ValueError:
            self.status_message = "Nothing to undo"

    async def action_redo(self) -> None:
        """Redo last undone action (FR-104)."""
        # TODO: Implement redo stack (separate from undo stack)
        self.status_message = "Redo not yet implemented"

    async def action_save(self) -> None:
        """Save classifications and exit (FR-105, FR-106)."""
        if not self.wizard_state.changes_made:
            self.status_message = "No changes to save"
            self.dismiss(None)
            return

        # Return wizard state to parent (WizardApp will handle saving)
        self.dismiss(self.wizard_state)

    async def action_cancel(self) -> None:
        """Cancel wizard without saving."""
        if self.wizard_state.changes_made:
            # TODO: Show confirmation dialog
            pass

        self.dismiss(None)

    async def action_create_pattern(self) -> None:
        """Create pattern rule for selected app (FR-???).

        Integration with US1 (pattern creation from wizard).
        T063: Pattern creation action
        """
        table = self.query_one("#app-table", AppTable)
        app = table.get_selected_app()

        if not app:
            self.status_message = "No app selected"
            return

        # TODO: Open pattern creation dialog
        # - Pre-fill with app.window_class
        # - Show preview of matches
        # - Validate pattern
        # - Add to config on confirm
        self.status_message = f"Pattern creation for '{app.window_class}' not yet implemented"

    async def action_detect_class(self) -> None:
        """Detect window class for selected app using Xvfb (FR-???).

        Integration with US2 (detection from wizard).
        T064: Detection action
        """
        table = self.query_one("#app-table", AppTable)
        app = table.get_selected_app()

        if not app:
            self.status_message = "No app selected"
            return

        # TODO: Trigger Xvfb detection
        # - Show progress spinner
        # - Call detect_window_class_xvfb()
        # - Update app.window_class on success
        # - Refresh table row
        self.status_message = f"Detection for '{app.app_name}' not yet implemented"

    async def action_filter(self) -> None:
        """Cycle through filter options (FR-096).

        T059: Filter implementation
        """
        # Cycle through filters: all → unclassified → scoped → global → all
        filter_cycle = ["all", "unclassified", "scoped", "global"]
        current_index = filter_cycle.index(self.wizard_state.filter_status)
        next_index = (current_index + 1) % len(filter_cycle)
        new_filter = filter_cycle[next_index]

        # Update state
        self.wizard_state.filter_status = new_filter

        # Apply filter to table
        table = self.query_one("#app-table", AppTable)
        filtered_apps = self.wizard_state.get_filtered_apps()
        table.populate(filtered_apps)

        # Update status and title
        count = len(filtered_apps)
        self.status_message = f"Filter: {new_filter} ({count} apps)"

        title = self.query_one("#table-title", Static)
        title.update(f"Applications ({count} {new_filter})")

    async def action_sort(self) -> None:
        """Cycle through sort options (FR-096).

        T059: Sort implementation
        """
        # Cycle through sorts: name → class → status → confidence → name
        sort_cycle = ["name", "class", "status", "confidence"]
        current_index = sort_cycle.index(self.wizard_state.sort_by)
        next_index = (current_index + 1) % len(sort_cycle)
        new_sort = sort_cycle[next_index]

        # Update state
        self.wizard_state.sort_by = new_sort

        # Apply sort to table
        table = self.query_one("#app-table", AppTable)
        filtered_apps = self.wizard_state.get_filtered_apps()
        sorted_apps = self.wizard_state.get_sorted_apps(filtered_apps)
        table.populate(sorted_apps)

        self.status_message = f"Sorted by: {new_sort}"
