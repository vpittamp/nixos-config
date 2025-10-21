"""Pattern creation dialog for the classification wizard.

Provides an interactive modal dialog for creating pattern rules from the wizard,
with live preview of matching applications.
"""

from textual.app import ComposeResult
from textual.screen import ModalScreen
from textual.widgets import Button, Input, Label, Select, Static, TextArea
from textual.containers import Horizontal, Vertical, Container
from textual.binding import Binding
from textual.reactive import reactive
from typing import Optional

from i3_project_manager.models.pattern import PatternRule
from i3_project_manager.models.classification import AppClassification


class PatternDialog(ModalScreen):
    """Modal dialog for creating a pattern rule.

    Allows user to:
    - Define pattern (pre-filled with current app's class)
    - Select pattern type (glob/regex/literal)
    - Choose scope (scoped/global)
    - Set priority and description
    - Preview which apps match the pattern
    - Validate and save

    T063: Pattern creation dialog implementation
    Integration with US1 (Advanced Pattern Rules)
    """

    CSS = """
    PatternDialog {
        align: center middle;
    }

    #dialog-container {
        width: 80;
        height: auto;
        background: $surface;
        border: thick $primary;
        padding: 1 2;
    }

    .dialog-title {
        width: 100%;
        content-align: center middle;
        text-style: bold;
        background: $primary;
        color: $text;
        margin-bottom: 1;
        padding: 1;
    }

    .field-row {
        height: auto;
        margin-bottom: 1;
    }

    .field-label {
        width: 20;
        padding: 1 0;
    }

    .field-input {
        width: 1fr;
    }

    #pattern-preview {
        height: 10;
        border: solid $accent;
        padding: 1;
        margin-top: 1;
        margin-bottom: 1;
    }

    .preview-title {
        text-style: bold;
        margin-bottom: 1;
    }

    .match-item {
        color: $success;
    }

    .no-matches {
        color: $warning;
    }

    #button-container {
        height: 3;
        align: center middle;
        margin-top: 1;
    }

    Button {
        margin: 0 1;
    }
    """

    BINDINGS = [
        Binding("escape", "cancel", "Cancel", show=True),
        Binding("ctrl+s", "save", "Save", show=True),
    ]

    # Reactive state
    pattern_value: reactive[str] = reactive("")
    pattern_type: reactive[str] = reactive("glob")
    scope_value: reactive[str] = reactive("scoped")
    preview_matches: reactive[list[str]] = reactive([])

    def __init__(
        self,
        initial_pattern: str = "",
        apps: list[AppClassification] = None,
    ):
        """Initialize pattern dialog.

        Args:
            initial_pattern: Pre-fill pattern (e.g., current app's class)
            apps: All apps for preview matching
        """
        super().__init__()
        self.pattern_value = initial_pattern
        self.apps = apps or []

    def compose(self) -> ComposeResult:
        """Compose the dialog layout."""
        with Container(id="dialog-container"):
            yield Static("Create Pattern Rule", classes="dialog-title")

            # Pattern input with type selector
            with Horizontal(classes="field-row"):
                yield Label("Pattern:", classes="field-label")
                yield Input(
                    value=self.pattern_value,
                    placeholder="e.g., pwa-*, code-*, or .*terminal.*",
                    id="pattern-input",
                    classes="field-input"
                )

            # Pattern type selector
            with Horizontal(classes="field-row"):
                yield Label("Type:", classes="field-label")
                yield Select(
                    options=[
                        ("Glob (*, ?)", "glob"),
                        ("Regex (.*)", "regex"),
                        ("Literal (exact)", "literal"),
                    ],
                    value="glob",
                    id="type-select",
                    classes="field-input"
                )

            # Scope selector
            with Horizontal(classes="field-row"):
                yield Label("Scope:", classes="field-label")
                yield Select(
                    options=[
                        ("Scoped (project-specific)", "scoped"),
                        ("Global (all projects)", "global"),
                    ],
                    value=self.scope_value,
                    id="scope-select",
                    classes="field-input"
                )

            # Priority input
            with Horizontal(classes="field-row"):
                yield Label("Priority:", classes="field-label")
                yield Input(
                    value="0",
                    placeholder="Higher values = higher priority",
                    id="priority-input",
                    classes="field-input"
                )

            # Description
            with Horizontal(classes="field-row"):
                yield Label("Description:", classes="field-label")
                yield Input(
                    value="",
                    placeholder="Optional description",
                    id="description-input",
                    classes="field-input"
                )

            # Preview panel
            yield Static(id="pattern-preview")

            # Buttons
            with Horizontal(id="button-container"):
                yield Button("Save", variant="primary", id="save-button")
                yield Button("Cancel", variant="default", id="cancel-button")

    def on_mount(self) -> None:
        """Initialize dialog when mounted."""
        # Focus pattern input
        self.query_one("#pattern-input", Input).focus()

        # Update preview with initial pattern
        self._update_preview()

    def on_input_changed(self, event: Input.Changed) -> None:
        """Handle input changes."""
        if event.input.id == "pattern-input":
            self.pattern_value = event.value
            self._update_preview()
        elif event.input.id == "priority-input":
            # Validate priority is integer
            try:
                int(event.value) if event.value else 0
            except ValueError:
                event.input.value = "0"

    def on_select_changed(self, event: Select.Changed) -> None:
        """Handle select changes."""
        if event.select.id == "type-select":
            self.pattern_type = str(event.value)
            self._update_preview()
        elif event.select.id == "scope-select":
            self.scope_value = str(event.value)

    def _update_preview(self) -> None:
        """Update preview panel with matching apps."""
        preview_panel = self.query_one("#pattern-preview", Static)

        if not self.pattern_value:
            preview_panel.update("[dim]Enter a pattern to see matches[/dim]")
            return

        # Build pattern string with type prefix
        if self.pattern_type == "glob":
            pattern_str = f"glob:{self.pattern_value}"
        elif self.pattern_type == "regex":
            pattern_str = f"regex:{self.pattern_value}"
        else:
            pattern_str = f"literal:{self.pattern_value}"

        # Try to create pattern rule and match apps
        try:
            pattern_rule = PatternRule(
                pattern=pattern_str,
                scope=self.scope_value,
                priority=0,
                description="",
            )

            # Find matching apps
            matches = []
            for app in self.apps:
                if pattern_rule.matches(app.window_class):
                    matches.append(app.window_class)

            # Update preview
            if matches:
                match_list = "\n".join(f"[green]✓[/green] {m}" for m in matches[:10])
                if len(matches) > 10:
                    match_list += f"\n[dim]... and {len(matches) - 10} more[/dim]"
                preview_panel.update(
                    f"[bold]Matches ({len(matches)} apps):[/bold]\n{match_list}"
                )
                self.preview_matches = matches
            else:
                preview_panel.update("[yellow]⚠ No apps match this pattern[/yellow]")
                self.preview_matches = []

        except ValueError as e:
            # Invalid pattern
            preview_panel.update(f"[red]✗ Invalid pattern:[/red] {e}")
            self.preview_matches = []

    def on_button_pressed(self, event: Button.Pressed) -> None:
        """Handle button clicks."""
        if event.button.id == "save-button":
            self._save_pattern()
        elif event.button.id == "cancel-button":
            self.dismiss(None)

    def action_save(self) -> None:
        """Save pattern (Ctrl+S)."""
        self._save_pattern()

    def action_cancel(self) -> None:
        """Cancel dialog (Escape)."""
        self.dismiss(None)

    def _save_pattern(self) -> None:
        """Validate and save pattern rule."""
        # Get values
        pattern_input = self.query_one("#pattern-input", Input)
        type_select = self.query_one("#type-select", Select)
        scope_select = self.query_one("#scope-select", Select)
        priority_input = self.query_one("#priority-input", Input)
        description_input = self.query_one("#description-input", Input)

        pattern_value = pattern_input.value.strip()
        if not pattern_value:
            self.notify("Pattern cannot be empty", severity="error")
            pattern_input.focus()
            return

        # Build pattern string
        pattern_type = str(type_select.value)
        if pattern_type == "glob":
            pattern_str = f"glob:{pattern_value}"
        elif pattern_type == "regex":
            pattern_str = f"regex:{pattern_value}"
        else:
            pattern_str = f"literal:{pattern_value}"

        # Validate priority
        try:
            priority = int(priority_input.value) if priority_input.value else 0
        except ValueError:
            self.notify("Priority must be an integer", severity="error")
            priority_input.focus()
            return

        # Create pattern rule
        try:
            pattern_rule = PatternRule(
                pattern=pattern_str,
                scope=str(scope_select.value),
                priority=priority,
                description=description_input.value.strip(),
            )

            # Return to wizard
            self.dismiss(pattern_rule)

        except ValueError as e:
            self.notify(f"Invalid pattern: {e}", severity="error")
            pattern_input.focus()
