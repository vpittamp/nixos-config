#!/usr/bin/env python3
"""Enhanced swaybar status generator using i3bar protocol.

Queries system state via D-Bus and outputs JSON status blocks for:
- Volume (PulseAudio/PipeWire)
- Battery (UPower)
- Network (NetworkManager)
- Bluetooth (BlueZ)

Protocol: https://i3wm.org/docs/i3bar-protocol.html
"""

import sys
import json
import time
import logging
import threading
from typing import List, Optional

from blocks.models import StatusBlock, ClickEvent
from blocks.config import Config
from blocks.click_handler import ClickHandler
from blocks import volume, battery, network, bluetooth, system, project, notification

# Setup logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    handlers=[logging.FileHandler('/tmp/swaybar-status-generator.log')]
)
logger = logging.getLogger(__name__)


class StatusGenerator:
    """Main status generator for enhanced swaybar."""

    def __init__(self, config: Config):
        """Initialize status generator.

        Args:
            config: Status generator configuration
        """
        self.config = config
        self.click_handler = ClickHandler(config)
        self.running = True

        # Start click event listener thread
        self.click_thread = threading.Thread(target=self._click_event_listener, daemon=True)
        self.click_thread.start()

        logger.info("Status generator initialized")

    def _print_header(self) -> None:
        """Print i3bar protocol header."""
        header = {"version": 1, "click_events": True}
        print(json.dumps(header))
        print("[")  # Start infinite array
        sys.stdout.flush()

    def _click_event_listener(self) -> None:
        """Listen for click events from stdin in separate thread."""
        logger.info("Click event listener started")
        while self.running:
            try:
                line = sys.stdin.readline()
                if not line:
                    break

                # Skip array start/end markers
                line = line.strip().rstrip(',')
                if line in ['[', ']']:
                    continue

                # Parse click event JSON
                data = json.loads(line)
                event = ClickEvent.from_json(data)
                self.click_handler.handle_click(event)

            except json.JSONDecodeError as e:
                logger.error(f"Failed to parse click event: {e}")
            except Exception as e:
                logger.error(f"Click event listener error: {e}")

    def get_status_blocks(self) -> List[StatusBlock]:
        """Get all status blocks for current state.

        Returns:
            List of status blocks in display order (preserves original system monitor layout)
        """
        blocks = []

        # i3pm Project Indicator (Feature 011 FR-006)
        try:
            project_block = project.create_project_block(self.config)
            if project_block:
                blocks.append(project_block)
        except Exception as e:
            logger.error(f"Failed to get project block: {e}")

        # Feature 057: US5 - System metrics moved to notification center
        # Top bar shows only persistent information (date/time, project, battery, network status)
        # Verbose metrics (load, memory, disk, traffic, temperature) accessible via SwayNC buttons

        # Volume block (enhanced feature)
        try:
            vol_state = volume.get_volume_state()
            if vol_state:
                blocks.append(vol_state.to_status_block(self.config))
        except Exception as e:
            logger.error(f"Failed to get volume block: {e}")

        # Battery block (enhanced feature - only if battery detected)
        if self.config.detect_battery:
            try:
                bat_state = battery.get_battery_state()
                if bat_state:
                    bat_block = bat_state.to_status_block(self.config)
                    if bat_block:  # May be None if battery not present
                        blocks.append(bat_block)
            except Exception as e:
                logger.error(f"Failed to get battery block: {e}")

        # Network WiFi Status (enhanced feature - shows SSID/signal)
        try:
            net_state = network.get_network_state()
            if net_state:
                blocks.append(net_state.to_status_block(self.config))
        except Exception as e:
            logger.error(f"Failed to get network block: {e}")

        # Bluetooth block (enhanced feature - only if bluetooth detected)
        if self.config.detect_bluetooth:
            try:
                bt_state = bluetooth.get_bluetooth_state()
                if bt_state:
                    bt_block = bt_state.to_status_block(self.config)
                    if bt_block:  # May be None if adapter not present
                        blocks.append(bt_block)
            except Exception as e:
                logger.error(f"Failed to get bluetooth block: {e}")

        # Notification block (SwayNC integration)
        try:
            notif_state = notification.get_notification_state()
            if notif_state:
                blocks.append(notif_state.to_status_block(self.config))
        except Exception as e:
            logger.error(f"Failed to get notification block: {e}")

        # Date/Time (always last)
        try:
            datetime_block = system.create_datetime_block(self.config)
            blocks.append(datetime_block)
        except Exception as e:
            logger.error(f"Failed to get datetime block: {e}")

        return blocks

    def run(self) -> None:
        """Main event loop - print status blocks periodically."""
        self._print_header()

        try:
            while self.running:
                # Get current status blocks
                blocks = self.get_status_blocks()

                # Convert to JSON array
                block_json = [block.to_json() for block in blocks]

                # Print JSON array (i3bar protocol)
                print(json.dumps(block_json) + ",")
                sys.stdout.flush()

                # Sleep until next update (use shortest interval)
                time.sleep(self.config.intervals.volume)

        except KeyboardInterrupt:
            logger.info("Shutting down status generator")
        except Exception as e:
            logger.error(f"Fatal error in main loop: {e}", exc_info=True)
        finally:
            self.running = False
            print("]")  # End infinite array
            sys.stdout.flush()


def main():
    """Entry point for status generator."""
    # Load default configuration (TODO: Load from file/env)
    config = Config()

    # Create and run status generator
    generator = StatusGenerator(config)
    generator.run()


if __name__ == "__main__":
    main()
