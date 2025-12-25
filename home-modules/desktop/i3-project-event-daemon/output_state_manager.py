"""Output state management for headless/virtual displays.

This module manages the output-states.json file that tracks which outputs
should be considered "active" for workspace distribution. This is needed
because headless outputs in Sway cannot be disabled via DPMS or power commands.

File: ~/.config/sway/output-states.json

Version: 1.0.0 (2025-11-19)
"""

import json
import logging
from pathlib import Path
from datetime import datetime
from typing import List, Optional

from .models.monitor_config import OutputStatesFile, OutputState
from .config import atomic_write_json  # Feature 137: Atomic file writes

logger = logging.getLogger(__name__)

# Default state file location
OUTPUT_STATES_PATH = Path.home() / ".config" / "sway" / "output-states.json"


def load_output_states(path: Optional[Path] = None) -> OutputStatesFile:
    """Load output states from file, creating default if not exists.

    Args:
        path: Optional custom path (defaults to ~/.config/sway/output-states.json)

    Returns:
        OutputStatesFile with current states
    """
    state_path = path or OUTPUT_STATES_PATH

    if not state_path.exists():
        logger.info(f"Output states file not found, creating default at {state_path}")
        states = OutputStatesFile()
        save_output_states(states, state_path)
        return states

    try:
        with open(state_path) as f:
            data = json.load(f)

        # Handle both old format (just enabled bool) and new format (OutputState)
        if "outputs" in data:
            # Convert simple bool values to OutputState if needed
            outputs_data = data["outputs"]
            converted_outputs = {}
            for name, value in outputs_data.items():
                if isinstance(value, bool):
                    converted_outputs[name] = {"enabled": value}
                elif isinstance(value, dict):
                    converted_outputs[name] = value
                else:
                    converted_outputs[name] = {"enabled": True}
            data["outputs"] = converted_outputs

        states = OutputStatesFile(**data)
        logger.debug(f"Loaded output states: {[n for n, s in states.outputs.items() if s.enabled]}")
        return states

    except json.JSONDecodeError as e:
        logger.error(f"Invalid JSON in output states file: {e}")
        return OutputStatesFile()
    except Exception as e:
        logger.error(f"Failed to load output states: {e}")
        return OutputStatesFile()


def save_output_states(states: OutputStatesFile, path: Optional[Path] = None) -> bool:
    """Save output states to file.

    Args:
        states: OutputStatesFile to save
        path: Optional custom path

    Returns:
        True if saved successfully
    """
    state_path = path or OUTPUT_STATES_PATH

    try:
        # Update timestamp
        states.last_updated = datetime.now()

        # Serialize using Pydantic v2 compatible method
        if hasattr(states, 'model_dump'):
            data = states.model_dump(mode='json')
        else:
            data = json.loads(states.json())

        # Feature 137: Use atomic write to prevent corruption
        atomic_write_json(state_path, data)

        logger.debug(f"Saved output states to {state_path}")
        return True

    except Exception as e:
        logger.error(f"Failed to save output states: {e}")
        return False


def initialize_output_states(output_names: List[str], path: Optional[Path] = None) -> OutputStatesFile:
    """Initialize output states file with all outputs enabled.

    This should be called on daemon startup to ensure all connected outputs
    have entries in the state file.

    Args:
        output_names: List of output names from Sway
        path: Optional custom path

    Returns:
        Updated OutputStatesFile
    """
    states = load_output_states(path)
    updated = False

    # Add new outputs (default to enabled)
    for name in output_names:
        if name not in states.outputs:
            states.outputs[name] = OutputState(enabled=True)
            logger.info(f"Added new output to state file: {name} (enabled)")
            updated = True

    # Remove outputs that no longer exist
    current_names = set(output_names)
    removed = [name for name in states.outputs if name not in current_names]
    for name in removed:
        del states.outputs[name]
        logger.info(f"Removed stale output from state file: {name}")
        updated = True

    if updated:
        save_output_states(states, path)

    return states


def toggle_output_state(output_name: str, path: Optional[Path] = None) -> bool:
    """Toggle an output's enabled state.

    Args:
        output_name: Name of output to toggle
        path: Optional custom path

    Returns:
        New enabled state (True = enabled, False = disabled)
    """
    states = load_output_states(path)
    new_state = states.toggle_output(output_name)
    save_output_states(states, path)

    logger.info(f"Toggled output {output_name}: {'enabled' if new_state else 'disabled'}")
    return new_state


def get_enabled_outputs(path: Optional[Path] = None) -> List[str]:
    """Get list of enabled output names.

    Args:
        path: Optional custom path

    Returns:
        List of output names that are enabled
    """
    states = load_output_states(path)
    return states.get_enabled_outputs()


def is_output_enabled(output_name: str, path: Optional[Path] = None) -> bool:
    """Check if an output is enabled.

    Args:
        output_name: Name of output to check
        path: Optional custom path

    Returns:
        True if output is enabled (defaults to True for unknown outputs)
    """
    states = load_output_states(path)
    return states.is_output_enabled(output_name)
