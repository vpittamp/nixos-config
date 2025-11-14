"""Terminal working directory tracker for session management.

Tracks and extracts terminal working directories via /proc/{pid}/cwd for session capture/restore.
Feature 074: Session Management - User Story 2 (Terminal CWD Preservation).
"""

import asyncio
import logging
from pathlib import Path
from typing import Optional, Set

logger = logging.getLogger(__name__)


# Terminal window classes to track (Feature 074: US2, T034)
TERMINAL_CLASSES: Set[str] = {
    "ghostty",
    "Alacritty",
    "kitty",
    "foot",
    "WezTerm",
    "org.wezfurlong.wezterm",
    "footclient",
    "Ghostty",
}


class TerminalCwdTracker:
    """Tracks terminal working directories for session management.

    Provides methods to:
    - Extract current working directory from running terminal processes
    - Identify terminal windows by window_class
    - Compute launch directory with fallback chain for restoration

    Feature 074: Session Management - User Story 2 (Terminal CWD Preservation)
    """

    def __init__(self):
        """Initialize terminal CWD tracker."""
        logger.debug("Initialized TerminalCwdTracker")

    async def get_terminal_cwd(self, pid: int) -> Optional[Path]:
        """Get current working directory of a terminal process (T033, US2, Feature 074).

        Reads the /proc/{pid}/cwd symlink to determine the terminal's current directory.
        This is used during layout capture to save terminal working directories.

        Args:
            pid: Process ID of the terminal window

        Returns:
            Path object pointing to terminal's current directory, or None if unavailable

        Raises:
            None - returns None on errors (missing process, permission denied, not a directory)
        """
        if pid <= 0:
            logger.warning(f"Invalid PID {pid}, cannot get terminal cwd")
            return None

        cwd_link = Path(f"/proc/{pid}/cwd")

        try:
            # Use asyncio to avoid blocking on slow symlink resolution
            loop = asyncio.get_event_loop()
            cwd_path = await loop.run_in_executor(None, cwd_link.resolve, True)

            # Verify the resolved path is a directory
            if not cwd_path.is_dir():
                logger.debug(f"Resolved cwd {cwd_path} for PID {pid} is not a directory")
                return None

            logger.debug(f"Successfully resolved terminal cwd for PID {pid}: {cwd_path}")
            return cwd_path

        except FileNotFoundError:
            logger.debug(f"Process {pid} not found or cwd symlink missing")
            return None
        except PermissionError:
            logger.warning(f"Permission denied reading /proc/{pid}/cwd")
            return None
        except OSError as e:
            logger.debug(f"OSError reading cwd for PID {pid}: {e}")
            return None
        except Exception as e:
            logger.error(f"Unexpected error getting cwd for PID {pid}: {e}")
            return None

    def is_terminal_window(self, window_class: str) -> bool:
        """Check if a window class represents a terminal (T035, US2, Feature 074).

        Compares the window class against the TERMINAL_CLASSES set to identify
        terminal windows that should have their working directory tracked.

        Args:
            window_class: The window class from i3/Sway window info

        Returns:
            True if the window is a recognized terminal, False otherwise
        """
        if not window_class:
            return False

        # Check exact match and case-insensitive match for robustness
        is_terminal = window_class in TERMINAL_CLASSES or window_class.lower() in {c.lower() for c in TERMINAL_CLASSES}

        if is_terminal:
            logger.debug(f"Identified terminal window: {window_class}")

        return is_terminal

    def get_launch_cwd(
        self,
        saved_cwd: Optional[Path],
        project_directory: Optional[Path],
        fallback_home: Path = Path.home()
    ) -> Path:
        """Compute launch directory for terminal restoration with fallback chain (T038-T039, US2, Feature 074).

        Uses a three-level fallback strategy:
        1. Original saved cwd (if it exists as a directory)
        2. Project root directory (if configured and exists)
        3. User's home directory (ultimate fallback)

        This ensures terminals always launch in a valid directory even if the
        original working directory was deleted or is unavailable.

        Args:
            saved_cwd: Original working directory from layout capture
            project_directory: Project root directory from configuration
            fallback_home: Final fallback directory (default: $HOME)

        Returns:
            Path object representing the directory to launch the terminal in
        """
        # T039: Fallback chain - original cwd → project root → $HOME

        # Level 1: Try original saved cwd
        if saved_cwd and saved_cwd.is_dir():
            logger.debug(f"Using original saved cwd: {saved_cwd}")
            return saved_cwd
        elif saved_cwd:
            logger.info(f"Original cwd {saved_cwd} no longer exists, falling back")

        # Level 2: Try project root directory
        if project_directory and project_directory.is_dir():
            logger.debug(f"Using project directory as fallback: {project_directory}")
            return project_directory
        elif project_directory:
            logger.warning(f"Project directory {project_directory} doesn't exist, falling back to home")

        # Level 3: Ultimate fallback to $HOME
        logger.debug(f"Using home directory as final fallback: {fallback_home}")
        return fallback_home
