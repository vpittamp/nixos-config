"""Monitor profile service for Feature 083.

This module manages monitor profiles and coordinates profile switching:
- Loading profiles from ~/.config/sway/monitor-profiles/
- Reading current profile from monitor-profile.current
- Emitting ProfileEvents for observability
- Coordinating with EwwPublisher for real-time updates

Version: 1.0.0 (2025-11-19)
Feature: 083-multi-monitor-window-management
"""

import json
import logging
import subprocess
import time
from pathlib import Path
from typing import Optional, List
from datetime import datetime

from .models.monitor_profile import (
    MonitorProfile,
    ProfileEvent,
    ProfileEventType,
)
from .output_state_manager import (
    load_output_states,
    save_output_states,
    OUTPUT_STATES_PATH,
)
from .eww_publisher import EwwPublisher

logger = logging.getLogger(__name__)

# Profile configuration paths
SWAY_CONFIG_DIR = Path.home() / ".config" / "sway"
PROFILES_DIR = SWAY_CONFIG_DIR / "monitor-profiles"
CURRENT_PROFILE_FILE = SWAY_CONFIG_DIR / "monitor-profile.current"
DEFAULT_PROFILE_FILE = SWAY_CONFIG_DIR / "monitor-profile.default"


class MonitorProfileService:
    """Service for managing monitor profiles and coordinating switches.

    Owns the output-states.json file and coordinates with EwwPublisher
    for real-time top bar updates.
    """

    def __init__(self, eww_publisher: Optional[EwwPublisher] = None):
        """Initialize profile service.

        Args:
            eww_publisher: Optional EwwPublisher for real-time updates
        """
        self.eww_publisher = eww_publisher or EwwPublisher()
        self._current_profile: Optional[str] = None
        self._profiles: dict[str, MonitorProfile] = {}
        self._profile_switch_in_progress: bool = False

        # Load initial state
        self._load_profiles()
        self._current_profile = self._read_current_profile()

    def _load_profiles(self) -> None:
        """Load all profile definitions from profiles directory."""
        self._profiles = {}

        if not PROFILES_DIR.exists():
            logger.warning(f"Profiles directory not found: {PROFILES_DIR}")
            return

        for profile_path in PROFILES_DIR.glob("*.json"):
            try:
                with open(profile_path) as f:
                    data = json.load(f)
                profile = MonitorProfile(**data)
                self._profiles[profile.name] = profile
                logger.debug(f"Loaded profile: {profile.name}")
            except Exception as e:
                logger.error(f"Failed to load profile {profile_path}: {e}")

        logger.info(f"Loaded {len(self._profiles)} monitor profiles")

    def _read_current_profile(self) -> Optional[str]:
        """Read current profile name from monitor-profile.current."""
        if not CURRENT_PROFILE_FILE.exists():
            # Try default profile
            if DEFAULT_PROFILE_FILE.exists():
                try:
                    return DEFAULT_PROFILE_FILE.read_text().strip()
                except Exception as e:
                    logger.error(f"Failed to read default profile: {e}")
            return None

        try:
            profile_name = CURRENT_PROFILE_FILE.read_text().strip()
            if profile_name in self._profiles:
                return profile_name
            else:
                logger.warning(f"Current profile '{profile_name}' not found, "
                             f"available: {list(self._profiles.keys())}")
                return None
        except Exception as e:
            logger.error(f"Failed to read current profile: {e}")
            return None

    def get_current_profile(self) -> Optional[str]:
        """Get current active profile name."""
        return self._current_profile

    def get_profile(self, name: str) -> Optional[MonitorProfile]:
        """Get profile by name."""
        return self._profiles.get(name)

    def list_profiles(self) -> List[str]:
        """List available profile names."""
        return list(self._profiles.keys())

    def get_enabled_outputs(self) -> List[str]:
        """Get list of enabled outputs for current profile."""
        if not self._current_profile:
            return []

        profile = self._profiles.get(self._current_profile)
        if not profile:
            return []

        return profile.get_enabled_outputs()

    def is_switch_in_progress(self) -> bool:
        """Check if a profile switch is currently in progress."""
        return self._profile_switch_in_progress

    def emit_event(self, event: ProfileEvent) -> None:
        """Emit a profile event for observability.

        Args:
            event: ProfileEvent to emit
        """
        # Log the event
        if event.event_type == ProfileEventType.PROFILE_SWITCH_COMPLETE:
            logger.info(f"Profile switch complete: {event.profile_name} "
                       f"({event.duration_ms:.0f}ms)")
        elif event.event_type == ProfileEventType.PROFILE_SWITCH_FAILED:
            logger.error(f"Profile switch failed: {event.profile_name} - {event.error}")
        else:
            logger.debug(f"Profile event: {event.event_type.value} - {event.profile_name}")

        # TODO: Add to event buffer for i3pm diagnose events

    async def handle_profile_change(self, conn, new_profile_name: str) -> bool:
        """Handle notification that profile has changed.

        Called when daemon detects monitor-profile.current was updated.
        Updates output-states.json and publishes to Eww.

        Args:
            conn: i3ipc.aio.Connection
            new_profile_name: Name of new profile

        Returns:
            True if handled successfully
        """
        start_time = time.time()
        previous_profile = self._current_profile

        # Validate profile exists
        profile = self._profiles.get(new_profile_name)
        if not profile:
            logger.error(f"Profile not found: {new_profile_name}")
            self.emit_event(ProfileEvent.failed(
                new_profile_name,
                f"Profile not found: {new_profile_name}"
            ))
            return False

        # Set switch in progress guard
        if self._profile_switch_in_progress:
            logger.warning("Profile switch already in progress, ignoring")
            return False

        self._profile_switch_in_progress = True

        try:
            # Emit start event
            enabled = profile.get_enabled_outputs()
            disabled = profile.get_disabled_outputs()
            all_changed = enabled + disabled

            self.emit_event(ProfileEvent.start(
                new_profile_name,
                previous_profile,
                all_changed
            ))

            # Update output-states.json
            states = load_output_states()
            for output in profile.outputs:
                states.set_output_enabled(output.name, output.enabled)
            save_output_states(states)

            logger.info(f"Updated output states for profile {new_profile_name}: "
                       f"enabled={enabled}, disabled={disabled}")

            # Update current profile
            self._current_profile = new_profile_name

            # Publish to Eww
            await self.eww_publisher.publish_from_conn(
                conn,
                new_profile_name,
                enabled
            )

            # Emit complete event
            duration_ms = (time.time() - start_time) * 1000
            self.emit_event(ProfileEvent.complete(
                new_profile_name,
                previous_profile,
                all_changed,
                duration_ms
            ))

            return True

        except Exception as e:
            logger.error(f"Profile change failed: {e}")
            self.emit_event(ProfileEvent.failed(
                new_profile_name,
                str(e)
            ))

            # T031: Send desktop notification on failure
            try:
                subprocess.run(
                    [
                        "notify-send",
                        "-u", "critical",
                        "-a", "i3pm",
                        "Profile Switch Failed",
                        f"Failed to switch to profile '{new_profile_name}': {e}"
                    ],
                    check=False,
                    timeout=2.0
                )
            except Exception as notify_err:
                logger.warning(f"Failed to send failure notification: {notify_err}")

            return False

        finally:
            self._profile_switch_in_progress = False

    def reload_profiles(self) -> None:
        """Reload profiles from disk."""
        self._load_profiles()
        self._current_profile = self._read_current_profile()
        logger.info(f"Reloaded profiles, current: {self._current_profile}")
