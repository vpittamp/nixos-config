"""Project creation wizard screen for i3pm TUI.

Guides users through creating a new project in 4 steps.
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


class ProjectWizardScreen(Screen):
    """4-step wizard for creating new projects.

    Steps:
    1. Basic info (name, display name, icon, directory)
    2. Application selection (scoped classes)
    3. Auto-launch configuration (optional)
    4. Review and create

    Keyboard shortcuts:
    - Enter: Next step (with validation)
    - Esc: Previous step or cancel
    """

    BINDINGS = [
        Binding("enter", "next_step", "Next"),
        Binding("escape", "previous_step", "Back"),
    ]

    current_step: reactive[int] = reactive(1)

    def __init__(self):
        """Initialize the wizard."""
        super().__init__()
        self._wizard_data = {
            "name": "",
            "display_name": "",
            "icon": "",
            "directory": "",
            "scoped_classes": [],
        }

    def compose(self) -> ComposeResult:
        """Compose the wizard layout."""
        yield Header()

        yield Static("New Project Wizard - Step 1/4", id="wizard_title", classes="title")

        # Scrollable content area
        with ScrollableContainer(id="step_content"):
            yield Label("Name:")
            yield Input(placeholder="project-name", id="name_input")

            yield Label("Display Name (optional):")
            yield Input(placeholder="Display Name", id="display_name_input")

            yield Label("Icon (optional):")
            yield Input(placeholder="❄️", id="icon_input")

            yield Label("Directory:")
            yield Input(placeholder="/path/to/project", id="directory_input")

        # Navigation buttons
        with Horizontal(classes="actions"):
            yield Button("Cancel", id="cancel_button")
            yield Button("Next", id="next_button", variant="success")

        yield Footer()

    def on_mount(self) -> None:
        """Focus the first input when wizard loads."""
        self.query_one("#name_input", Input).focus()

    def watch_current_step(self, old: int, new: int) -> None:
        """Update UI when step changes."""
        title = self.query_one("#wizard_title", Static)
        title.update(f"New Project Wizard - Step {new}/4")

        # TODO: Update step content based on current_step
        # For now, just step 1 (basic info) is shown

    async def action_next_step(self) -> None:
        """Move to next step with validation."""
        if self.current_step == 1:
            # Validate and save step 1 data
            try:
                name = self.query_one("#name_input", Input).value
                if not name:
                    self.notify("Name is required", severity="error")
                    return

                directory = self.query_one("#directory_input", Input).value
                if not directory:
                    self.notify("Directory is required", severity="error")
                    return

                # Check directory exists
                if not Path(directory).expanduser().exists():
                    self.notify(f"Directory does not exist: {directory}", severity="error")
                    return

                # Save data
                self._wizard_data["name"] = name
                self._wizard_data["display_name"] = self.query_one("#display_name_input", Input).value
                self._wizard_data["icon"] = self.query_one("#icon_input", Input).value
                self._wizard_data["directory"] = directory

                # For simplicity, skip to final step (create project)
                await self._create_project()

            except Exception as e:
                self.notify(f"Error: {e}", severity="error")

    async def action_previous_step(self) -> None:
        """Go back to previous step or cancel."""
        if self.current_step == 1:
            # First step, cancel wizard
            self.dismiss(None)
        else:
            self.current_step -= 1

    async def _create_project(self) -> None:
        """Create the project from wizard data."""
        try:
            # Create project object
            project = Project(
                name=self._wizard_data["name"],
                directory=Path(self._wizard_data["directory"]).expanduser(),
                display_name=self._wizard_data["display_name"] or None,
                icon=self._wizard_data["icon"] or None,
                scoped_classes=["Ghostty", "Code"],  # Default scoped classes
                workspace_preferences={},
                auto_launch=[],
                saved_layouts=[],
            )

            # Save project
            project.save()

            # Dismiss with created project
            self.dismiss(project)

        except Exception as e:
            self.notify(f"Failed to create project: {e}", severity="error")

    async def on_button_pressed(self, event: Button.Pressed) -> None:
        """Handle button presses."""
        if event.button.id == "cancel_button":
            self.dismiss(None)
        elif event.button.id == "next_button":
            await self.action_next_step()
