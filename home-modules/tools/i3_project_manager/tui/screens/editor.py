"""Project editor screen for i3pm TUI.

Allows editing project configuration with real-time validation.
"""

from pathlib import Path
from typing import Optional
from textual.app import ComposeResult
from textual.screen import Screen
from textual.widgets import Header, Footer, Input, Static, Button, Label
from textual.containers import Vertical, Horizontal, ScrollableContainer
from textual.binding import Binding
from textual.reactive import reactive

from i3_project_manager.core.models import Project
from i3_project_manager.validators.project_validator import ProjectValidator


class ProjectEditorScreen(Screen):
    """TUI screen for editing project configuration.

    Features:
    - Edit basic project information (name, directory, icon, display name)
    - Real-time validation with error display
    - Unsaved changes tracking
    - Save/Cancel actions

    Keyboard shortcuts:
    - Tab: Next field
    - Shift+Tab: Previous field
    - Ctrl+S: Save changes
    - Esc: Cancel (discard changes)
    """

    BINDINGS = [
        Binding("ctrl+s", "save", "Save"),
        Binding("escape", "cancel", "Cancel"),
    ]

    # Reactive attributes
    unsaved_changes: reactive[bool] = reactive(False)
    validation_error: reactive[Optional[str]] = reactive(None)

    def __init__(self, project: Project):
        """Initialize the editor with a project to edit.

        Args:
            project: The project to edit
        """
        super().__init__()
        self._original_project = project
        self._project = project  # Working copy
        self._validator = ProjectValidator()

    def compose(self) -> ComposeResult:
        """Compose the editor layout."""
        yield Header()

        yield Static(f"Edit Project: {self._project.name}", classes="title")

        # Scrollable content area
        with ScrollableContainer():
            yield Label("Basic Information", classes="section-header")

            yield Label("Name:")
            yield Input(
                value=self._project.name,
                placeholder="project-name",
                id="name_input",
            )

            yield Label("Display Name (optional):")
            yield Input(
                value=self._project.display_name or "",
                placeholder="Display Name",
                id="display_name_input",
            )

            yield Label("Icon (optional):")
            yield Input(
                value=self._project.icon or "",
                placeholder="❄️",
                id="icon_input",
            )

            yield Label("Directory:")
            yield Input(
                value=str(self._project.directory),
                placeholder="/path/to/project",
                id="directory_input",
            )

            # Validation error display
            yield Static("", id="validation_error", classes="error")

        # Action buttons
        with Horizontal(classes="actions"):
            yield Button("Save", id="save_button", variant="success")
            yield Button("Cancel", id="cancel_button", variant="default")

        yield Footer()

    async def on_mount(self) -> None:
        """Called when screen is mounted."""
        # Focus the first input
        self.query_one("#name_input", Input).focus()

    async def on_input_changed(self, event: Input.Changed) -> None:
        """Handle input changes for validation and unsaved tracking."""
        self.unsaved_changes = True

        # Perform validation
        input_id = event.input.id
        value = event.value

        try:
            if input_id == "name_input":
                self._validate_name(value)
            elif input_id == "directory_input":
                self._validate_directory(value)

            # Clear validation error if validation passed
            self.validation_error = None

        except ValueError as e:
            self.validation_error = str(e)

    def _validate_name(self, name: str) -> None:
        """Validate project name.

        Args:
            name: The project name to validate

        Raises:
            ValueError: If validation fails
        """
        if not name:
            raise ValueError("Name cannot be empty")

        # Allow alphanumeric, hyphens, and underscores
        if not name.replace("-", "").replace("_", "").isalnum():
            raise ValueError("Name must be alphanumeric (with - or _)")

        # Check for duplicate names (unless editing the same project)
        if name != self._original_project.name:
            config_file = Path.home() / ".config/i3/projects" / f"{name}.json"
            if config_file.exists():
                raise ValueError(f"Project '{name}' already exists")

    def _validate_directory(self, directory: str) -> None:
        """Validate directory exists.

        Args:
            directory: The directory path to validate

        Raises:
            ValueError: If validation fails
        """
        path = Path(directory).expanduser()
        if not path.exists():
            raise ValueError(f"Directory does not exist: {directory}")

        if not path.is_dir():
            raise ValueError(f"Path is not a directory: {directory}")

    def watch_validation_error(self, old: Optional[str], new: Optional[str]) -> None:
        """Update validation error display."""
        error_widget = self.query_one("#validation_error", Static)
        if new:
            error_widget.update(f"⚠️  {new}")
        else:
            error_widget.update("")

    def watch_unsaved_changes(self, old: bool, new: bool) -> None:
        """Update UI to show unsaved changes indicator."""
        # Could update header or save button styling
        pass

    async def on_button_pressed(self, event: Button.Pressed) -> None:
        """Handle button presses."""
        if event.button.id == "save_button":
            await self.action_save()
        elif event.button.id == "cancel_button":
            await self.action_cancel()

    async def action_save(self) -> None:
        """Save the project changes."""
        # Validate all fields before saving
        try:
            name = self.query_one("#name_input", Input).value
            display_name = self.query_one("#display_name_input", Input).value
            icon = self.query_one("#icon_input", Input).value
            directory = self.query_one("#directory_input", Input).value

            # Validate
            self._validate_name(name)
            self._validate_directory(directory)

            # Update project object
            self._project.name = name
            self._project.display_name = display_name if display_name else None
            self._project.icon = icon if icon else None
            self._project.directory = Path(directory).expanduser()

            # Save to disk
            self._project.save()

            # Dismiss screen with updated project
            self.dismiss(self._project)

        except ValueError as e:
            self.validation_error = str(e)
            self.notify(f"Validation error: {e}", severity="error")

    async def action_cancel(self) -> None:
        """Cancel editing and discard changes."""
        if self.unsaved_changes:
            # TODO: Show confirmation dialog
            # For now, just dismiss without saving
            self.notify("Changes discarded", severity="warning")

        self.dismiss(None)
