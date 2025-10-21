"""Main Textual TUI application for i3pm.

This module provides the interactive TUI interface for managing i3 projects.
The app supports multi-screen navigation with reactive state management.
"""

import asyncio
from typing import Optional
from textual.app import App
from textual.reactive import reactive
from textual.binding import Binding

from i3_project_manager.core.daemon_client import DaemonClient


class I3PMApp(App):
    """Interactive TUI for i3 project management.

    Features:
    - Project browser (default screen)
    - Project editor
    - Project creation wizard
    - Layout manager
    - Monitor dashboard

    Reactive attributes:
    - active_project: Currently active project name
    - daemon_connected: Whether daemon connection is established
    """

    # CSS styling for the app
    CSS = """
    Screen {
        background: $surface;
    }

    Header {
        dock: top;
        height: 3;
        background: $primary;
        color: $text;
        content-align: center middle;
    }

    Footer {
        dock: bottom;
        height: 1;
        background: $panel;
        color: $text-muted;
    }

    .title {
        text-style: bold;
        color: $accent;
    }

    .active-project {
        text-style: bold;
        color: $success;
    }

    .error {
        color: $error;
    }

    .warning {
        color: $warning;
    }

    .success {
        color: $success;
    }
    """

    # Global keybindings
    BINDINGS = [
        Binding("ctrl+c,q", "quit", "Quit", priority=True),
        Binding("ctrl+r", "refresh", "Refresh"),
        Binding("f1,?", "help", "Help"),
    ]

    # Application title
    TITLE = "i3pm - i3 Project Manager"

    # Reactive state
    active_project: reactive[Optional[str]] = reactive(None)
    daemon_connected: reactive[bool] = reactive(False)

    def __init__(self, initial_screen: Optional[str] = None):
        """Initialize the TUI application.

        Args:
            initial_screen: Optional initial screen to show ("browser", "monitor", etc.)
                          Defaults to "browser" if not specified.
        """
        super().__init__()
        self._daemon_client: Optional[DaemonClient] = None
        self._initial_screen = initial_screen or "browser"

    async def on_mount(self) -> None:
        """Called when app is mounted.

        Initializes:
        - Daemon connection
        - Status polling task
        - Default screen (browser)
        """
        # Connect to daemon
        await self._connect_daemon()

        # Start status polling (every 5 seconds) using set_interval
        self.set_interval(5, self._sync_poll_daemon)

        # Push the initial screen based on configuration
        if self._initial_screen == "monitor":
            from i3_project_manager.tui.screens.monitor import MonitorScreen
            await self.push_screen(MonitorScreen())
        else:
            # Default to browser screen
            from i3_project_manager.tui.screens.browser import ProjectBrowserScreen
            await self.push_screen(ProjectBrowserScreen())

    async def _connect_daemon(self) -> None:
        """Establish connection to the daemon."""
        try:
            self._daemon_client = DaemonClient()
            await self._daemon_client.connect()
            self.daemon_connected = True

            # Query initial active project
            status = await self._daemon_client.get_status()
            self.active_project = status.get("active_project")
        except Exception as e:
            self.log.error(f"Failed to connect to daemon: {e}")
            self.daemon_connected = False
            self._daemon_client = None

    def _sync_poll_daemon(self) -> None:
        """Sync wrapper for daemon polling."""
        self.run_worker(self._poll_daemon_status(), exclusive=True)

    async def _poll_daemon_status(self) -> None:
        """Poll daemon status once to update reactive state."""
        if self._daemon_client is None:
            # Try to reconnect
            await self._connect_daemon()
            return

        try:
            status = await self._daemon_client.get_status()
            self.active_project = status.get("active_project")
            self.daemon_connected = True
        except Exception as e:
            self.log.error(f"Daemon status poll failed: {e}")
            self.daemon_connected = False
            self._daemon_client = None

    async def on_unmount(self) -> None:
        """Called when app is unmounted - cleanup resources."""
        # Close daemon connection
        if self._daemon_client:
            await self._daemon_client.close()

    @property
    def daemon_client(self) -> Optional[DaemonClient]:
        """Get the daemon client instance."""
        return self._daemon_client

    def action_quit(self) -> None:
        """Quit the application."""
        self.exit()

    def action_refresh(self) -> None:
        """Refresh the current screen."""
        # The active screen should implement refresh logic
        if hasattr(self.screen, "refresh_data"):
            self.screen.refresh_data()

    def action_help(self) -> None:
        """Show help screen with keyboard shortcuts."""
        # TODO: Implement help screen in future enhancement
        self.notify("Help screen not yet implemented. Press 'q' to quit.", severity="information")


def run_tui() -> int:
    """Run the TUI application.

    Returns:
        Exit code (0 for success, non-zero for errors)
    """
    app = I3PMApp()
    try:
        app.run()
        return 0
    except Exception as e:
        print(f"Error running TUI: {e}")
        return 1
