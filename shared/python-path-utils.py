"""
Feature 106: Portable Flake Root Discovery for Python

This module provides a centralized function for discovering the flake root directory.
Used by Python scripts that need to reference repository files.

Usage:
    from shared.python_path_utils import get_flake_root

    flake_root = get_flake_root()
    config_file = flake_root / "configs" / "my-config.json"
"""

import os
import subprocess
from pathlib import Path


def get_flake_root() -> Path:
    """
    Get the flake root directory using multiple discovery methods.

    Priority:
    1. FLAKE_ROOT environment variable (for CI/CD and manual override)
    2. Git repository detection (for development in git repos/worktrees)
    3. Default fallback to /etc/nixos (for deployed systems without git)

    Returns:
        Path: Absolute path to the flake root directory
    """
    # Priority 1: Environment variable
    flake_root_env = os.environ.get("FLAKE_ROOT")
    if flake_root_env:
        return Path(flake_root_env).resolve()

    # Priority 2: Git repository detection
    try:
        result = subprocess.run(
            ["git", "rev-parse", "--show-toplevel"],
            capture_output=True,
            text=True,
            check=True,
            timeout=5  # Prevent hanging on slow filesystems
        )
        git_root = result.stdout.strip()
        if git_root:
            return Path(git_root).resolve()
    except (subprocess.CalledProcessError, subprocess.TimeoutExpired, FileNotFoundError):
        # Git not available or not in a git repo
        pass

    # Priority 3: Default fallback
    return Path("/etc/nixos")


def get_scripts_dir() -> Path:
    """Get the scripts directory relative to flake root."""
    return get_flake_root() / "scripts"


def get_shared_dir() -> Path:
    """Get the shared directory relative to flake root."""
    return get_flake_root() / "shared"


def get_home_modules_dir() -> Path:
    """Get the home-modules directory relative to flake root."""
    return get_flake_root() / "home-modules"


def get_specs_dir() -> Path:
    """Get the specs directory relative to flake root."""
    return get_flake_root() / "specs"
