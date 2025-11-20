"""Eww widget publisher for real-time monitor state updates.

This module provides functions to push monitor state to Eww widgets
via the `eww update` CLI command, achieving <100ms latency.

Version: 1.0.0 (2025-11-19)
Feature: 083-multi-monitor-window-management
"""

import json
import logging
import subprocess
from pathlib import Path
from typing import Optional, List

from .models.monitor_profile import MonitorState, OutputDisplayState

logger = logging.getLogger(__name__)

# Eww configuration directory (eww-top-bar)
EWW_CONFIG_DIR = Path.home() / ".config" / "eww" / "eww-top-bar"

# Eww variable name for monitor state
MONITOR_STATE_VAR = "monitor_state"


def update_eww_variable(variable: str, value: str, config_dir: Optional[Path] = None) -> bool:
    """Push update to Eww widget variable via CLI.

    Uses subprocess with timeout to prevent blocking the daemon event loop.

    Args:
        variable: Eww variable name to update
        value: JSON string value to set
        config_dir: Optional Eww config directory

    Returns:
        True if update succeeded
    """
    eww_config = config_dir or EWW_CONFIG_DIR

    try:
        result = subprocess.run(
            ["eww", "--config", str(eww_config), "update", f"{variable}={value}"],
            check=False,
            capture_output=True,
            timeout=2.0,
            text=True
        )

        if result.returncode != 0:
            logger.warning(f"Eww update failed (exit {result.returncode}): {result.stderr}")
            return False

        logger.debug(f"Updated Eww variable {variable}")
        return True

    except subprocess.TimeoutExpired:
        logger.warning(f"Eww update timeout after 2s for {variable}")
        return False
    except FileNotFoundError:
        logger.error("eww command not found in PATH")
        return False
    except Exception as e:
        logger.error(f"Unexpected error updating Eww: {e}")
        return False


def publish_monitor_state(state: MonitorState, config_dir: Optional[Path] = None) -> bool:
    """Publish monitor state to Eww top bar widget.

    Called when profile changes or output events occur.

    Args:
        state: MonitorState with profile name and output states
        config_dir: Optional Eww config directory

    Returns:
        True if published successfully
    """
    try:
        json_value = state.to_eww_json()
        success = update_eww_variable(MONITOR_STATE_VAR, json_value, config_dir)

        if success:
            logger.info(f"Published monitor state: profile={state.profile_name}, "
                       f"outputs={[o.short_name for o in state.outputs if o.active]}")
        return success

    except Exception as e:
        logger.error(f"Failed to publish monitor state: {e}")
        return False


def build_monitor_state(profile_name: str,
                        enabled_outputs: List[str],
                        all_outputs: List[str],
                        workspace_counts: Optional[dict] = None,
                        is_hybrid_mode: bool = False) -> MonitorState:
    """Build MonitorState from current system state.

    Feature 084 T028: Extended for hybrid mode support.

    Args:
        profile_name: Current profile name
        enabled_outputs: List of enabled output names
        all_outputs: List of all output names (for ordering)
        workspace_counts: Optional dict of output_name -> workspace count
        is_hybrid_mode: If True, use L/V1/V2 naming convention

    Returns:
        MonitorState ready for publishing
    """
    workspace_counts = workspace_counts or {}
    enabled_set = set(enabled_outputs)

    # Build output display states in consistent order
    outputs = []
    for name in sorted(all_outputs):
        active = name in enabled_set
        count = workspace_counts.get(name, 0)
        outputs.append(OutputDisplayState.from_output_name(
            name, active, count, is_hybrid_mode=is_hybrid_mode
        ))

    return MonitorState(
        profile_name=profile_name,
        outputs=outputs,
        mode="hybrid" if is_hybrid_mode else "headless"
    )


async def publish_from_sway_state(conn, profile_name: str,
                                  enabled_outputs: List[str],
                                  is_hybrid_mode: bool = False) -> bool:
    """Build and publish monitor state from live Sway state.

    Queries Sway for workspace counts and publishes to Eww.
    Feature 084 T028: Extended for hybrid mode support.

    Args:
        conn: i3ipc.aio.Connection
        profile_name: Current profile name
        enabled_outputs: List of enabled output names
        is_hybrid_mode: If True, use L/V1/V2 naming convention

    Returns:
        True if published successfully
    """
    try:
        # Get all outputs from Sway
        outputs = await conn.get_outputs()
        all_output_names = [o.name for o in outputs if o.active]

        # Get workspace counts per output
        workspaces = await conn.get_workspaces()
        workspace_counts = {}
        for ws in workspaces:
            output = ws.output
            workspace_counts[output] = workspace_counts.get(output, 0) + 1

        # Build and publish state
        state = build_monitor_state(
            profile_name=profile_name,
            enabled_outputs=enabled_outputs,
            all_outputs=all_output_names,
            workspace_counts=workspace_counts,
            is_hybrid_mode=is_hybrid_mode
        )

        return publish_monitor_state(state)

    except Exception as e:
        logger.error(f"Failed to publish from Sway state: {e}")
        return False


class EwwPublisher:
    """Service class for publishing monitor state to Eww.

    Provides caching and debouncing for efficient updates.
    """

    def __init__(self, config_dir: Optional[Path] = None):
        """Initialize publisher.

        Args:
            config_dir: Optional Eww config directory
        """
        self.config_dir = config_dir or EWW_CONFIG_DIR
        self._last_state: Optional[MonitorState] = None

    def publish(self, state: MonitorState) -> bool:
        """Publish monitor state if changed.

        Args:
            state: MonitorState to publish

        Returns:
            True if published (or no change)
        """
        # Skip if state unchanged
        if self._last_state and self._states_equal(self._last_state, state):
            logger.debug("Monitor state unchanged, skipping publish")
            return True

        success = publish_monitor_state(state, self.config_dir)
        if success:
            self._last_state = state

        return success

    async def publish_from_conn(self, conn, profile_name: str,
                                enabled_outputs: List[str],
                                is_hybrid_mode: bool = False) -> bool:
        """Build and publish state from Sway connection.

        Feature 084 T028: Extended for hybrid mode support.

        Args:
            conn: i3ipc.aio.Connection
            profile_name: Current profile name
            enabled_outputs: List of enabled output names
            is_hybrid_mode: If True, use L/V1/V2 naming convention

        Returns:
            True if published successfully
        """
        return await publish_from_sway_state(
            conn, profile_name, enabled_outputs, is_hybrid_mode
        )

    @staticmethod
    def _states_equal(a: MonitorState, b: MonitorState) -> bool:
        """Check if two monitor states are equal."""
        if a.profile_name != b.profile_name:
            return False
        if len(a.outputs) != len(b.outputs):
            return False
        for ao, bo in zip(a.outputs, b.outputs):
            if ao.name != bo.name or ao.active != bo.active:
                return False
        return True
