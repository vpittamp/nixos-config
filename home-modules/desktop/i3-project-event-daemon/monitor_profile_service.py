"""Monitor profile service for Feature 083/084.

This module manages monitor profiles and coordinates profile switching:
- Loading profiles from ~/.config/sway/monitor-profiles/
- Reading current profile from monitor-profile.current
- Emitting ProfileEvents for observability
- Coordinating with EwwPublisher for real-time updates
- Feature 084: Hybrid mode support (physical + virtual displays on M1)

Version: 1.1.0 (2025-11-19)
Feature: 083-multi-monitor-window-management, 084-monitor-management-solution
"""

import asyncio
import json
import logging
import socket
import subprocess
import time
from pathlib import Path
from typing import Optional, List, Set
from datetime import datetime

from .models.monitor_profile import (
    MonitorProfile,
    ProfileEvent,
    ProfileEventType,
    HybridMonitorProfile,
    HybridOutputConfig,
    OutputType,
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
        self._hybrid_profiles: dict[str, HybridMonitorProfile] = {}
        self._profile_switch_in_progress: bool = False

        # Feature 084: Detect hybrid mode based on hostname
        self._is_hybrid_mode = socket.gethostname() == "nixos-m1"
        self._active_virtual_outputs: Set[str] = set()

        # Load initial state
        self._load_profiles()
        if self._is_hybrid_mode:
            self._load_hybrid_profiles()
        self._current_profile = self._read_current_profile()

        if self._is_hybrid_mode:
            logger.info("Feature 084: Hybrid mode enabled (M1 with physical + virtual displays)")

    @property
    def is_hybrid_mode(self) -> bool:
        """Check if running in hybrid mode (M1)."""
        return self._is_hybrid_mode

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

    def _load_hybrid_profiles(self) -> None:
        """Load M1 hybrid profile definitions from profiles directory."""
        self._hybrid_profiles = {}

        if not PROFILES_DIR.exists():
            logger.warning(f"Profiles directory not found: {PROFILES_DIR}")
            return

        for profile_path in PROFILES_DIR.glob("*.json"):
            try:
                with open(profile_path) as f:
                    data = json.load(f)
                # Check if this is a hybrid profile (has nested output objects)
                if data.get("outputs") and isinstance(data["outputs"][0], dict) and "type" in data["outputs"][0]:
                    profile = HybridMonitorProfile(**data)
                    self._hybrid_profiles[profile.name] = profile
                    logger.debug(f"Loaded hybrid profile: {profile.name}")
            except Exception as e:
                logger.error(f"Failed to load hybrid profile {profile_path}: {e}")

        logger.info(f"Feature 084: Loaded {len(self._hybrid_profiles)} hybrid profiles")

    def get_hybrid_profile(self, name: str) -> Optional[HybridMonitorProfile]:
        """Get hybrid profile by name."""
        return self._hybrid_profiles.get(name)

    async def create_virtual_output(self, conn) -> Optional[str]:
        """Create a new virtual output using swaymsg IPC.

        Feature 084 T015: Dynamic virtual output creation for hybrid mode.

        Args:
            conn: i3ipc.aio.Connection

        Returns:
            Name of created output (e.g., "HEADLESS-1") or None on failure
        """
        try:
            # Get current outputs before creation
            outputs_before = await conn.get_outputs()
            names_before = {o.name for o in outputs_before}

            # Create new virtual output
            result = await conn.command("create_output")
            if not result or not result[0].success:
                logger.error(f"Failed to create virtual output: {result}")
                return None

            # Get outputs after creation to find the new one
            await asyncio.sleep(0.1)  # Small delay for Sway to register
            outputs_after = await conn.get_outputs()
            names_after = {o.name for o in outputs_after}

            # Find the new output
            new_outputs = names_after - names_before
            if not new_outputs:
                logger.error("create_output succeeded but no new output found")
                return None

            new_output = new_outputs.pop()
            self._active_virtual_outputs.add(new_output)
            logger.info(f"Feature 084: Created virtual output: {new_output}")
            return new_output

        except Exception as e:
            logger.error(f"Failed to create virtual output: {e}")
            return None

    async def configure_output(self, conn, output_config: HybridOutputConfig) -> bool:
        """Configure an output with resolution, position, and scale.

        Feature 084 T016: Configure output mode, position, and scale.

        Args:
            conn: i3ipc.aio.Connection
            output_config: HybridOutputConfig with settings

        Returns:
            True if configured successfully
        """
        try:
            name = output_config.name
            pos = output_config.position

            if output_config.enabled:
                # Enable and configure the output
                # Format: output NAME mode WIDTHxHEIGHT position X,Y scale SCALE
                if output_config.type == OutputType.PHYSICAL:
                    # Physical display (eDP-1) - use Retina resolution
                    cmd = f"output {name} mode {pos.width}x{pos.height}@60Hz position {pos.x},{pos.y} scale {output_config.scale}"
                else:
                    # Virtual display - VNC resolution
                    cmd = f"output {name} mode {pos.width}x{pos.height}@60Hz position {pos.x},{pos.y} scale {output_config.scale}"

                result = await conn.command(cmd)
                if not result or not result[0].success:
                    logger.error(f"Failed to configure output {name}: {result}")
                    return False

                logger.debug(f"Feature 084: Configured output {name}: {pos.width}x{pos.height} at {pos.x},{pos.y} scale {output_config.scale}")
            else:
                # Disable the output
                result = await conn.command(f"output {name} disable")
                if not result or not result[0].success:
                    logger.error(f"Failed to disable output {name}: {result}")
                    return False
                logger.debug(f"Feature 084: Disabled output {name}")

            return True

        except Exception as e:
            logger.error(f"Failed to configure output {output_config.name}: {e}")
            return False

    async def manage_wayvnc_service(self, output_name: str, action: str) -> bool:
        """Start or stop WayVNC service for a virtual output.

        Feature 084: Manage WayVNC services for VNC access.

        Args:
            output_name: Output name (e.g., "HEADLESS-1")
            action: "start" or "stop"

        Returns:
            True if service action succeeded
        """
        try:
            service_name = f"wayvnc@{output_name}.service"
            result = subprocess.run(
                ["systemctl", "--user", action, service_name],
                capture_output=True,
                text=True,
                timeout=10.0
            )

            if result.returncode == 0:
                logger.info(f"Feature 084: {action}ed {service_name}")
                return True
            else:
                logger.warning(f"Failed to {action} {service_name}: {result.stderr}")
                return False

        except Exception as e:
            logger.error(f"Failed to {action} WayVNC service for {output_name}: {e}")
            return False

    async def _send_notification(self, title: str, message: str, urgency: str = "normal") -> None:
        """Send desktop notification.

        Feature 084 T018: Notification on profile switch success/failure.

        Args:
            title: Notification title
            message: Notification body
            urgency: "low", "normal", or "critical"
        """
        try:
            subprocess.run(
                [
                    "notify-send",
                    "-u", urgency,
                    "-a", "i3pm",
                    "-t", "3000",
                    title,
                    message
                ],
                check=False,
                timeout=2.0
            )
        except Exception as e:
            logger.warning(f"Failed to send notification: {e}")

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

        Feature 084: Extended for hybrid mode with virtual output creation.

        Args:
            conn: i3ipc.aio.Connection
            new_profile_name: Name of new profile

        Returns:
            True if handled successfully
        """
        start_time = time.time()
        previous_profile = self._current_profile

        # Feature 084: Check for hybrid profile first
        hybrid_profile = self._hybrid_profiles.get(new_profile_name) if self._is_hybrid_mode else None

        # Validate profile exists (hybrid or standard)
        profile = self._profiles.get(new_profile_name)
        if not profile and not hybrid_profile:
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
            # Feature 084: Handle hybrid mode profile switch
            if hybrid_profile and self._is_hybrid_mode:
                return await self._handle_hybrid_profile_change(
                    conn, hybrid_profile, previous_profile, start_time
                )

            # Standard headless mode profile switch
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

            # T018: Send desktop notification on failure
            await self._send_notification(
                "Profile Switch Failed",
                f"Failed to switch to '{new_profile_name}': {e}",
                "critical"
            )

            return False

        finally:
            self._profile_switch_in_progress = False

    async def _handle_hybrid_profile_change(
        self,
        conn,
        hybrid_profile: HybridMonitorProfile,
        previous_profile: Optional[str],
        start_time: float
    ) -> bool:
        """Handle profile change for hybrid mode (M1).

        Feature 084 T014: Extended handle_profile_change for hybrid mode.

        Args:
            conn: i3ipc.aio.Connection
            hybrid_profile: HybridMonitorProfile to switch to
            previous_profile: Previous profile name
            start_time: Start time for duration tracking

        Returns:
            True if handled successfully
        """
        new_profile_name = hybrid_profile.name

        # Get enabled/disabled outputs
        enabled_outputs = []
        disabled_outputs = []
        virtual_outputs_needed = []

        for output in hybrid_profile.outputs:
            if output.enabled:
                enabled_outputs.append(output.name)
                if output.type == OutputType.VIRTUAL:
                    virtual_outputs_needed.append(output)
            else:
                disabled_outputs.append(output.name)

        # T038: Limit virtual outputs to maximum 2
        if len(virtual_outputs_needed) > 2:
            error_msg = f"Profile {new_profile_name} requests {len(virtual_outputs_needed)} virtual outputs (max 2)"
            logger.error(f"Feature 084 T038: {error_msg}")
            await self._send_notification(
                "Profile Switch Failed",
                error_msg,
                "critical"
            )
            self.emit_event(ProfileEvent.failed(new_profile_name, error_msg))
            return False

        all_changed = enabled_outputs + disabled_outputs

        # Emit start event
        self.emit_event(ProfileEvent.start(
            new_profile_name,
            previous_profile,
            all_changed
        ))

        # Get current outputs from Sway
        current_outputs = await conn.get_outputs()
        current_output_names = {o.name for o in current_outputs}

        # T035: Save previous state for rollback
        previous_output_states = load_output_states()
        rollback_needed = False

        # Stop WayVNC services for outputs we're disabling
        prev_hybrid = self._hybrid_profiles.get(previous_profile) if previous_profile else None
        if prev_hybrid:
            for output in prev_hybrid.outputs:
                if output.type == OutputType.VIRTUAL and output.name not in enabled_outputs:
                    await self.manage_wayvnc_service(output.name, "stop")

        # T035/T037: Wrap critical operations with rollback capability
        try:
            # Create virtual outputs that don't exist yet
            created_outputs = []
            for vout in virtual_outputs_needed:
                if vout.name not in current_output_names:
                    # T037: Retry virtual output creation once on failure
                    created = await self.create_virtual_output(conn)
                    if not created:
                        # Retry once
                        await asyncio.sleep(0.2)
                        created = await self.create_virtual_output(conn)

                    if created:
                        created_outputs.append(created)
                        logger.info(f"Feature 084: Virtual output created for {vout.name}")
                    else:
                        rollback_needed = True
                        raise RuntimeError(f"Failed to create virtual output: {vout.name}")

            # Configure all outputs
            for output in hybrid_profile.outputs:
                success = await self.configure_output(conn, output)
                if not success and output.enabled:
                    rollback_needed = True
                    raise RuntimeError(f"Failed to configure output: {output.name}")

            # Start WayVNC services for enabled virtual outputs
            for vout in virtual_outputs_needed:
                await self.manage_wayvnc_service(vout.name, "start")

        except Exception as e:
            # T035: Rollback on failure
            if rollback_needed and previous_profile:
                logger.warning(f"Feature 084 T035: Rolling back to previous profile {previous_profile}")
                save_output_states(previous_output_states)
                # Stop any started VNC services
                for vout in virtual_outputs_needed:
                    await self.manage_wayvnc_service(vout.name, "stop")

            await self._send_notification(
                "Profile Switch Failed",
                f"Failed to switch to {new_profile_name}: {e}",
                "critical"
            )
            self.emit_event(ProfileEvent.failed(new_profile_name, str(e)))
            raise

        # T022: Migrate workspaces from disabled outputs to eDP-1
        if disabled_outputs:
            await self.migrate_workspaces_from_disabled_outputs(
                conn, disabled_outputs, fallback_output="eDP-1"
            )

        # T021/T024/T025: Reassign workspaces based on profile configuration
        await self.reassign_workspaces(conn, hybrid_profile)

        # Update output-states.json
        states = load_output_states()
        for output in hybrid_profile.outputs:
            states.set_output_enabled(output.name, output.enabled)
        save_output_states(states)

        logger.info(f"Feature 084: Updated output states for hybrid profile {new_profile_name}: "
                   f"enabled={enabled_outputs}, disabled={disabled_outputs}")

        # Update current profile
        self._current_profile = new_profile_name

        # Publish to Eww with hybrid mode flag
        await self.eww_publisher.publish_from_conn(
            conn,
            new_profile_name,
            enabled_outputs,
            is_hybrid_mode=True
        )

        # Emit complete event
        duration_ms = (time.time() - start_time) * 1000
        self.emit_event(ProfileEvent.complete(
            new_profile_name,
            previous_profile,
            all_changed,
            duration_ms
        ))

        # T018: Send success notification
        vnc_count = len(virtual_outputs_needed)
        if vnc_count > 0:
            vnc_ports = ", ".join(
                str(vout.vnc_port) for vout in virtual_outputs_needed if vout.vnc_port
            )
            await self._send_notification(
                "Monitor Profile",
                f"Switched to {new_profile_name}\nVNC ports: {vnc_ports}",
                "normal"
            )
        else:
            await self._send_notification(
                "Monitor Profile",
                f"Switched to {new_profile_name}",
                "normal"
            )

        return True

    def reload_profiles(self) -> None:
        """Reload profiles from disk."""
        self._load_profiles()
        self._current_profile = self._read_current_profile()
        logger.info(f"Reloaded profiles, current: {self._current_profile}")

    async def reassign_workspaces(self, conn, hybrid_profile: HybridMonitorProfile) -> bool:
        """Reassign workspaces to outputs based on profile configuration.

        Feature 084 T021: Workspace distribution across displays.

        Args:
            conn: i3ipc.aio.Connection
            hybrid_profile: HybridMonitorProfile with workspace_assignments

        Returns:
            True if reassignment succeeded
        """
        try:
            # Get current workspaces
            workspaces = await conn.get_workspaces()
            current_ws_outputs = {ws.name: ws.output for ws in workspaces}

            # Build target assignment map from profile
            target_assignments = {}
            for assignment in hybrid_profile.workspace_assignments:
                output = assignment.output
                for ws_num in assignment.workspaces:
                    target_assignments[str(ws_num)] = output

            # T024: Assign PWA workspaces (50+) to VNC outputs
            # Find enabled virtual outputs
            virtual_outputs = [
                out.name for out in hybrid_profile.outputs
                if out.type == OutputType.VIRTUAL and out.enabled
            ]

            if virtual_outputs:
                # Get all workspaces 50+ and distribute across virtual outputs
                for ws in workspaces:
                    try:
                        ws_num = int(ws.name)
                        if ws_num >= 50:
                            # Round-robin distribution across virtual outputs
                            idx = (ws_num - 50) % len(virtual_outputs)
                            target_assignments[ws.name] = virtual_outputs[idx]
                    except ValueError:
                        # Non-numeric workspace name, skip
                        pass

            # Move workspaces to their target outputs
            for ws_name, target_output in target_assignments.items():
                current_output = current_ws_outputs.get(ws_name)
                if current_output and current_output != target_output:
                    await self._move_workspace_to_output(conn, ws_name, target_output)

            logger.info(f"Feature 084: Reassigned workspaces for profile {hybrid_profile.name}")
            return True

        except Exception as e:
            logger.error(f"Failed to reassign workspaces: {e}")
            return False

    async def migrate_workspaces_from_disabled_outputs(
        self,
        conn,
        disabled_outputs: List[str],
        fallback_output: str = "eDP-1"
    ) -> bool:
        """Migrate all workspaces from disabled outputs to fallback.

        Feature 084 T022: Workspace migration for disabled outputs.

        Args:
            conn: i3ipc.aio.Connection
            disabled_outputs: List of output names being disabled
            fallback_output: Output to move workspaces to (default: eDP-1)

        Returns:
            True if migration succeeded
        """
        try:
            workspaces = await conn.get_workspaces()

            for ws in workspaces:
                if ws.output in disabled_outputs:
                    await self._move_workspace_to_output(
                        conn, ws.name, fallback_output, preserve_state=True
                    )
                    logger.debug(f"Feature 084: Migrated workspace {ws.name} "
                                f"from {ws.output} to {fallback_output}")

            return True

        except Exception as e:
            logger.error(f"Failed to migrate workspaces from disabled outputs: {e}")
            return False

    async def _move_workspace_to_output(
        self,
        conn,
        workspace_name: str,
        target_output: str,
        preserve_state: bool = True
    ) -> bool:
        """Move a workspace to a specific output.

        Feature 084 T023: Preserve window state during workspace moves.

        Args:
            conn: i3ipc.aio.Connection
            workspace_name: Name of workspace to move
            target_output: Target output name
            preserve_state: If True, preserve window sizes/positions

        Returns:
            True if move succeeded
        """
        try:
            # T023: To preserve state, we use workspace assignment rather than moving windows
            # Sway's workspace move preserves window arrangements

            # First, focus the workspace
            result = await conn.command(f"workspace {workspace_name}")
            if not result or not result[0].success:
                logger.warning(f"Failed to focus workspace {workspace_name}")
                return False

            # Move the workspace to the target output
            result = await conn.command(f"move workspace to output {target_output}")
            if not result or not result[0].success:
                logger.warning(f"Failed to move workspace {workspace_name} to {target_output}")
                return False

            logger.debug(f"Feature 084: Moved workspace {workspace_name} to {target_output}")
            return True

        except Exception as e:
            logger.error(f"Failed to move workspace {workspace_name}: {e}")
            return False
