"""Theme configuration management for unified bar system.

Feature 057: Unified Bar System with Enhanced Workspace Mode
Provides theme loading, validation, and hot-reload functionality.
"""

import json
import logging
from pathlib import Path
from typing import Optional

from models import ThemeConfig


logger = logging.getLogger(__name__)


def validate_theme_config(theme_data: dict) -> ThemeConfig:
    """Validate theme configuration data against Pydantic model.

    Args:
        theme_data: Raw theme configuration dictionary

    Returns:
        Validated ThemeConfig instance

    Raises:
        ValidationError: If theme data doesn't match schema
        ValueError: If required fields are missing
    """
    try:
        # Pydantic will validate all fields, patterns, and constraints
        theme = ThemeConfig(**theme_data)
        logger.info(f"Theme validation passed: {theme.theme} v{theme.version}")
        return theme
    except Exception as e:
        logger.error(f"Theme validation failed: {e}")
        raise


def load_theme(theme_path: Optional[Path] = None) -> ThemeConfig:
    """Load and validate theme configuration from JSON file.

    Args:
        theme_path: Path to appearance.json file. If None, uses default location.

    Returns:
        Validated ThemeConfig instance

    Raises:
        FileNotFoundError: If theme file doesn't exist
        JSONDecodeError: If theme file contains invalid JSON
        ValidationError: If theme data doesn't match schema
    """
    if theme_path is None:
        # Default location: ~/.config/sway/appearance.json
        theme_path = Path.home() / ".config" / "sway" / "appearance.json"

    if not theme_path.exists():
        raise FileNotFoundError(f"Theme file not found: {theme_path}")

    logger.info(f"Loading theme from: {theme_path}")

    try:
        with open(theme_path, "r") as f:
            theme_data = json.load(f)

        # Validate and return theme
        return validate_theme_config(theme_data)

    except json.JSONDecodeError as e:
        logger.error(f"Invalid JSON in theme file: {e}")
        raise
    except Exception as e:
        logger.error(f"Failed to load theme: {e}")
        raise


def get_color(theme: ThemeConfig, color_name: str, default: str = "#000000") -> str:
    """Get color value from theme with fallback.

    Args:
        theme: Validated ThemeConfig instance
        color_name: Name of color (e.g., "base", "blue", "yellow")
        default: Fallback color if not found (default: black)

    Returns:
        Hex color string (e.g., "#1e1e2e")
    """
    try:
        return getattr(theme.colors, color_name, default)
    except AttributeError:
        logger.warning(f"Color '{color_name}' not found, using default: {default}")
        return default


# Example usage (for testing):
if __name__ == "__main__":
    logging.basicConfig(level=logging.INFO)

    try:
        # Load default theme
        theme = load_theme()
        print(f"Theme loaded: {theme.theme}")
        print(f"Base color: {get_color(theme, 'base')}")
        print(f"Focused color: {get_color(theme, 'blue')}")

    except Exception as e:
        print(f"Error: {e}")
