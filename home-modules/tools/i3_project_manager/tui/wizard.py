"""Classification Wizard TUI application.

Interactive terminal UI for bulk application classification with
keyboard shortcuts, suggestions, undo/redo, and atomic saving.
"""

import asyncio
from pathlib import Path
from typing import Optional

from textual.app import App
from textual.reactive import reactive

from i3_project_manager.core.app_discovery import AppDiscovery
from i3_project_manager.core.config import AppClassConfig
from i3_project_manager.models.classification import AppClassification, WizardState
from i3_project_manager.tui.screens.wizard_screen import WizardScreen


class WizardApp(App):
    """Application classification wizard TUI.

    Provides an interactive interface for classifying multiple applications
    with keyboard-driven workflow, smart suggestions, and undo/redo support.

    Features:
    - Async app loading from desktop files (FR-133)
    - Classification suggestions based on categories (T058)
    - Keyboard navigation and shortcuts (FR-099, FR-101)
    - Multi-select for batch operations (FR-100)
    - Undo/redo with state snapshots (FR-104)
    - Atomic save with daemon reload (FR-105, FR-106)
    - External file modification detection (FR-108)

    T057: WizardApp implementation
    """

    CSS = """
    #main-container {
        height: 100%;
        width: 100%;
    }

    #table-container {
        width: 70%;
        border: solid $primary;
    }

    #detail-container {
        width: 30%;
        border: solid $accent;
    }

    .panel {
        padding: 1;
    }

    .panel-title {
        background: $primary;
        color: $text;
        padding: 0 1;
        text-style: bold;
    }

    #status-bar {
        dock: bottom;
        height: 1;
        background: $surface;
        color: $text;
        padding: 0 1;
    }

    AppTable {
        height: 100%;
    }

    DetailPanel {
        height: 100%;
        overflow-y: auto;
    }
    """

    TITLE = "i3pm Classification Wizard"
    SUB_TITLE = "Classify applications as scoped or global"

    # Reactive state
    wizard_state: reactive[Optional[WizardState]] = reactive(None)

    def __init__(
        self,
        *,
        filter_status: str = "all",
        sort_by: str = "name",
        auto_accept: bool = False,
    ):
        """Initialize the wizard app.

        Args:
            filter_status: Initial filter (all, unclassified, scoped, global)
            sort_by: Initial sort field (name, class, status, confidence)
            auto_accept: Auto-accept high-confidence suggestions on launch
        """
        super().__init__()
        self.filter_status = filter_status
        self.sort_by = sort_by
        self.auto_accept = auto_accept
        self.config = AppClassConfig()

    async def on_mount(self) -> None:
        """Load applications and show wizard screen.

        FR-133: Load apps from AppDiscovery
        T057: Async loading
        T062: External file modification detection
        """
        # Show loading message
        self.notify("Loading applications...")

        # Store initial config file mtime for modification detection (T062)
        self._initial_config_mtime = self._get_config_mtime()

        # Load apps in background
        apps = await self._load_applications()

        if not apps:
            # FR-110: Empty state handling
            self.notify(
                "No apps discovered. Run 'i3pm app-classes detect --all-missing' to populate.",
                severity="warning",
                timeout=10,
            )
            self.exit()
            return

        # Push wizard screen
        await self.push_screen(WizardScreen(apps), self._on_wizard_complete)

    async def _load_applications(self) -> list[AppClassification]:
        """Load and classify applications from desktop files.

        Returns:
            List of AppClassification objects with suggestions

        T057: Async loading from AppDiscovery
        T058: Classification suggestion algorithm
        """
        # Discover all desktop apps
        discovery = AppDiscovery()
        desktop_apps = await asyncio.to_thread(discovery.discover_all)

        # Convert to AppClassification with suggestions
        apps = []
        for desktop_app in desktop_apps:
            # Determine current classification
            current_scope = self._get_current_scope(desktop_app.wm_class)

            # Generate suggestion
            suggested_scope, reasoning, confidence = self._suggest_classification(
                desktop_app
            )

            app = AppClassification(
                app_name=desktop_app.name,
                window_class=desktop_app.wm_class or "Unknown",
                desktop_file=str(desktop_app.desktop_file),
                current_scope=current_scope,
                suggested_scope=suggested_scope,
                suggestion_reasoning=reasoning,
                suggestion_confidence=confidence,
                user_modified=False,
            )
            apps.append(app)

        return apps

    def _get_current_scope(
        self, window_class: Optional[str]
    ) -> str:
        """Get current classification scope for a window class.

        Args:
            window_class: WM_CLASS to check

        Returns:
            Current scope: scoped, global, or unclassified
        """
        if not window_class:
            return "unclassified"

        if window_class in self.config.scoped_classes:
            return "scoped"
        elif window_class in self.config.global_classes:
            return "global"
        else:
            return "unclassified"

    def _suggest_classification(
        self, desktop_app
    ) -> tuple[Optional[str], str, float]:
        """Generate classification suggestion for an app.

        Uses category keywords to suggest scoped/global classification.

        Args:
            desktop_app: DesktopApp to analyze

        Returns:
            Tuple of (suggested_scope, reasoning, confidence)

        T058: Classification suggestion algorithm
        """
        categories = desktop_app.categories or []

        # Development tools → scoped
        dev_categories = {
            "Development",
            "IDE",
            "TextEditor",
            "Programming",
            "Debugger",
            "RevisionControl",
        }
        if any(cat in dev_categories for cat in categories):
            return (
                "scoped",
                "Development tool - typically project-scoped",
                0.95,
            )

        # Terminals → scoped
        if "TerminalEmulator" in categories:
            return (
                "scoped",
                "Terminal emulator - typically project-scoped",
                0.90,
            )

        # Browsers → global
        if "WebBrowser" in categories:
            return (
                "global",
                "Web browser - typically global",
                0.85,
            )

        # Communication → global
        comm_categories = {"Chat", "InstantMessaging", "IRCClient", "Email"}
        if any(cat in comm_categories for cat in categories):
            return (
                "global",
                "Communication tool - typically global",
                0.80,
            )

        # Utilities → global
        if "Utility" in categories:
            return (
                "global",
                "Utility application - typically global",
                0.70,
            )

        # Media players → global
        media_categories = {"Audio", "Video", "AudioVideo", "Player"}
        if any(cat in media_categories for cat in categories):
            return (
                "global",
                "Media player - typically global",
                0.75,
            )

        # Office apps → could be either, low confidence
        if "Office" in categories:
            return (
                "scoped",
                "Office application - could be project-specific",
                0.60,
            )

        # No strong signal - no suggestion
        return (None, "No clear classification signal from categories", 0.0)

    def _get_config_mtime(self) -> float:
        """Get modification time of config file.

        Returns:
            File modification timestamp, or 0 if file doesn't exist

        T062: External file modification detection
        """
        config_file = self.config.config_file
        if config_file.exists():
            return config_file.stat().st_mtime
        return 0.0

    def _check_config_modified(self) -> bool:
        """Check if config file was modified externally.

        Returns:
            True if file was modified since wizard started

        T062: FR-108 - External file modification detection
        """
        current_mtime = self._get_config_mtime()
        return current_mtime > self._initial_config_mtime

    async def _on_wizard_complete(
        self, wizard_state: Optional[WizardState]
    ) -> None:
        """Handle wizard completion.

        Saves classifications to config file and reloads daemon.

        Args:
            wizard_state: Final wizard state, or None if cancelled

        T061: Save workflow implementation
        T062: External file modification check before save
        FR-105: Save on Enter
        FR-106: Atomic write with daemon reload
        FR-108: Detect external modifications
        """
        if wizard_state is None:
            self.notify("Cancelled - no changes saved")
            self.exit()
            return

        if not wizard_state.changes_made:
            self.notify("No changes made")
            self.exit()
            return

        # Check for external modifications (T062, FR-108)
        if self._check_config_modified():
            self.notify(
                "Warning: Config file was modified externally. Your changes will overwrite it.",
                severity="warning",
                timeout=5,
            )
            # TODO: Show modal dialog with options: Reload/Merge/Overwrite
            # For now, we proceed with overwrite

        # Save classifications
        try:
            await self._save_classifications(wizard_state.apps)
            self.notify("✓ Classifications saved successfully", severity="information")
            self.exit()
        except Exception as e:
            self.notify(f"Failed to save: {e}", severity="error", timeout=10)

    async def _save_classifications(self, apps: list[AppClassification]) -> None:
        """Save classifications to config file.

        Performs atomic write and reloads daemon.

        Args:
            apps: List of classified apps

        FR-106: Atomic write (temp file + rename)
        FR-123: Daemon reload
        """
        # Update config with new classifications
        for app in apps:
            if not app.user_modified:
                continue

            window_class = app.window_class

            # Remove from both lists first
            if window_class in self.config.scoped_classes:
                self.config.scoped_classes.remove(window_class)
            if window_class in self.config.global_classes:
                self.config.global_classes.remove(window_class)

            # Add to appropriate list
            if app.current_scope == "scoped":
                self.config.scoped_classes.append(window_class)
            elif app.current_scope == "global":
                self.config.global_classes.append(window_class)
            # unclassified = don't add to either list

        # Save config (atomic write in AppClassConfig._save())
        await asyncio.to_thread(self.config._save)

        # Reload daemon
        await self._reload_daemon()

    async def _reload_daemon(self) -> None:
        """Reload i3 project daemon to pick up new classifications.

        FR-082: Daemon reload via i3 tick event
        FR-123: Config reload signal
        """
        import subprocess

        try:
            # Send i3 tick event to reload daemon
            await asyncio.to_thread(
                subprocess.run,
                ["i3-msg", "-q", "tick", "i3pm:reload-config"],
                check=True,
            )
        except subprocess.CalledProcessError as e:
            # Non-fatal - classifications still saved
            self.notify(
                f"Warning: Failed to reload daemon: {e}",
                severity="warning",
                timeout=5,
            )


def run_wizard(
    filter_status: str = "all",
    sort_by: str = "name",
    auto_accept: bool = False,
) -> int:
    """Run the classification wizard.

    Args:
        filter_status: Initial filter (all, unclassified, scoped, global)
        sort_by: Initial sort field (name, class, status, confidence)
        auto_accept: Auto-accept high-confidence suggestions on launch

    Returns:
        Exit code (0 on success)
    """
    app = WizardApp(
        filter_status=filter_status,
        sort_by=sort_by,
        auto_accept=auto_accept,
    )

    try:
        app.run()
        return 0
    except Exception as e:
        print(f"Error running wizard: {e}")
        return 1


if __name__ == "__main__":
    """Entry point when run as python -m i3_project_manager.tui.wizard"""
    import argparse
    import sys

    parser = argparse.ArgumentParser(description="Interactive application classification wizard")
    parser.add_argument(
        "--filter",
        choices=["all", "unclassified", "scoped", "global"],
        default="all",
        help="Initial filter (default: all)",
    )
    parser.add_argument(
        "--sort",
        choices=["name", "class", "status", "confidence"],
        default="name",
        help="Initial sort field (default: name)",
    )
    parser.add_argument(
        "--auto-accept",
        action="store_true",
        help="Automatically accept high-confidence suggestions on launch",
    )

    args = parser.parse_args()

    sys.exit(
        run_wizard(
            filter_status=args.filter,
            sort_by=args.sort,
            auto_accept=args.auto_accept,
        )
    )
