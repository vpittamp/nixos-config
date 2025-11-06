"""Click event handler for status bar interactions."""

import subprocess
import logging
from typing import Optional
from .models import ClickEvent, MouseButton
from .config import Config

logger = logging.getLogger(__name__)


class ClickHandler:
    """Handles click events from swaybar and launches appropriate handlers."""

    def __init__(self, config: Config):
        """Initialize click handler with configuration.

        Args:
            config: Status generator configuration
        """
        self.config = config

    def handle_click(self, event: ClickEvent) -> None:
        """Process a click event and launch appropriate handler.

        Args:
            event: Click event from swaybar
        """
        logger.debug(f"Click event: {event.name} button={event.button.value}")

        if event.name == "project":
            self._handle_project_click(event)
        elif event.name == "volume":
            self._handle_volume_click(event)
        elif event.name == "network":
            self._handle_network_click(event)
        elif event.name == "bluetooth":
            self._handle_bluetooth_click(event)
        elif event.name == "battery":
            self._handle_battery_click(event)
        elif event.name == "notification":
            self._handle_notification_click(event)
        elif event.name == "datetime":
            self._handle_datetime_click(event)
        else:
            logger.warning(f"Unknown block name: {event.name}")

    def _handle_project_click(self, event: ClickEvent) -> None:
        """Handle project indicator block clicks (Feature 011 FR-007, FR-008).

        - Left click: Open project switcher (walker project selector)
        - Right click: Clear active project
        """
        if event.button == MouseButton.LEFT:
            # FR-007: Click project indicator to open project switcher
            self._launch_command("walker --modules projects")
        elif event.button == MouseButton.RIGHT:
            # FR-008: Right-click to clear active project
            self._launch_command("i3pm project clear")

    def _handle_volume_click(self, event: ClickEvent) -> None:
        """Handle volume block clicks.

        - Left click: Launch volume mixer (pavucontrol)
        - Scroll up: Increase volume 5%
        - Scroll down: Decrease volume 5%
        """
        if event.button == MouseButton.LEFT:
            self._launch_command(self.config.click_handlers.volume)
        elif event.button == MouseButton.SCROLL_UP:
            self._run_pactl("set-sink-volume @DEFAULT_SINK@ +5%")
        elif event.button == MouseButton.SCROLL_DOWN:
            self._run_pactl("set-sink-volume @DEFAULT_SINK@ -5%")

    def _handle_network_click(self, event: ClickEvent) -> None:
        """Handle network block clicks.

        - Left click: Launch network manager
        """
        if event.button == MouseButton.LEFT:
            self._launch_command(self.config.click_handlers.network)

    def _handle_bluetooth_click(self, event: ClickEvent) -> None:
        """Handle bluetooth block clicks.

        - Left click: Launch bluetooth manager
        """
        if event.button == MouseButton.LEFT:
            self._launch_command(self.config.click_handlers.bluetooth)

    def _handle_battery_click(self, event: ClickEvent) -> None:
        """Handle battery block clicks.

        - Left click: Show detailed power stats (if handler configured)
        """
        if event.button == MouseButton.LEFT and self.config.click_handlers.battery:
            self._launch_command(self.config.click_handlers.battery)

    def _handle_notification_click(self, event: ClickEvent) -> None:
        """Handle notification block clicks.

        - Left click: Toggle SwayNC control center
        - Right click: Toggle Do Not Disturb
        """
        if event.button == MouseButton.LEFT:
            # Toggle control center with swaync-client -t (toggle) -sw (show window)
            self._launch_command("swaync-client -t -sw")
        elif event.button == MouseButton.RIGHT:
            # Toggle Do Not Disturb with swaync-client -d (toggle dnd) -sw (show window)
            self._launch_command("swaync-client -d -sw")

    def _handle_datetime_click(self, event: ClickEvent) -> None:
        """Handle datetime block clicks.

        - Left click: Launch calendar application
        """
        if event.button == MouseButton.LEFT:
            calendar_cmd = getattr(self.config.click_handlers, 'calendar', None)
            if calendar_cmd:
                self._launch_command(calendar_cmd)

    def _launch_command(self, command: str) -> None:
        """Launch external command in detached subprocess.

        Args:
            command: Command to execute (e.g., "pavucontrol")
        """
        if not command:
            logger.debug("No handler configured, skipping")
            return

        try:
            # Launch command in background (detached from status generator)
            subprocess.Popen(
                command.split(),
                start_new_session=True,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL
            )
            logger.info(f"Launched: {command}")
        except Exception as e:
            logger.error(f"Failed to launch {command}: {e}")

    def _run_pactl(self, args: str) -> None:
        """Run pactl command for volume control.

        Args:
            args: Arguments to pactl (e.g., "set-sink-volume @DEFAULT_SINK@ +5%")
        """
        try:
            subprocess.run(
                ["pactl"] + args.split(),
                check=True,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.PIPE,
                timeout=2
            )
            logger.debug(f"Executed: pactl {args}")
        except subprocess.TimeoutExpired:
            logger.error(f"pactl command timed out: {args}")
        except subprocess.CalledProcessError as e:
            logger.error(f"pactl command failed: {e.stderr.decode()}")
        except Exception as e:
            logger.error(f"Failed to run pactl {args}: {e}")
