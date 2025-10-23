"""
Launch Command Discovery Module

Feature 030: Production Readiness
Task T032: Discover launch commands from desktop files
Task T033: Fallback to /proc/PID/cmdline for launch commands

Discovers launch commands for captured windows by:
1. Searching .desktop files for matching WM_CLASS
2. Falling back to /proc/PID/cmdline if desktop file not found
3. Caching results for performance
"""

import logging
import re
from pathlib import Path
from typing import Optional, Dict, List
import configparser

logger = logging.getLogger(__name__)


class LaunchCommandDiscovery:
    """
    Discovers launch commands for applications

    Sources (in priority order):
    1. .desktop files in standard locations
    2. /proc/PID/cmdline (fallback)
    3. Manual overrides (from config)
    """

    def __init__(self):
        """Initialize launch command discovery"""
        self.desktop_dirs = self._get_desktop_file_directories()
        self.cache: Dict[str, str] = {}  # window_class -> launch_command
        self.desktop_file_cache: Dict[str, str] = {}  # window_class -> desktop file path

    def _get_desktop_file_directories(self) -> List[Path]:
        """
        Get standard desktop file directories

        Returns:
            List of paths to search for .desktop files
        """
        directories = []

        # Standard XDG locations
        xdg_data_home = Path.home() / ".local/share/applications"
        xdg_data_dirs = [
            Path("/usr/share/applications"),
            Path("/usr/local/share/applications"),
            Path("/var/lib/flatpak/exports/share/applications"),
        ]

        # Add user directory first (highest priority)
        if xdg_data_home.exists():
            directories.append(xdg_data_home)

        # Add system directories
        for dir_path in xdg_data_dirs:
            if dir_path.exists():
                directories.append(dir_path)

        return directories

    def discover_launch_command(
        self,
        window_class: str,
        window_instance: Optional[str] = None,
        pid: Optional[int] = None,
    ) -> Optional[str]:
        """
        Discover launch command for window

        Args:
            window_class: Window class (WM_CLASS)
            window_instance: Window instance (optional)
            pid: Process ID (optional, for /proc fallback)

        Returns:
            Launch command string or None
        """
        # Check cache first
        cache_key = f"{window_class}:{window_instance or ''}"
        if cache_key in self.cache:
            return self.cache[cache_key]

        # Try desktop file discovery (T032)
        command = self._discover_from_desktop_files(window_class, window_instance)

        # Fall back to /proc/PID/cmdline (T033)
        if not command and pid:
            command = self._discover_from_proc(pid)

        # Cache result
        if command:
            self.cache[cache_key] = command
            logger.debug(f"Discovered launch command for {window_class}: {command}")

        return command

    def _discover_from_desktop_files(
        self,
        window_class: str,
        window_instance: Optional[str] = None,
    ) -> Optional[str]:
        """
        Search .desktop files for matching application

        Matching strategies:
        1. Exact match on StartupWMClass field
        2. Desktop filename matches window_class (case-insensitive)
        3. Desktop filename matches window_instance (case-insensitive)
        4. Exec command contains window_class (case-insensitive)

        Args:
            window_class: Window class to match
            window_instance: Window instance to match

        Returns:
            Exec command from matching desktop file or None
        """
        for desktop_dir in self.desktop_dirs:
            # Search all .desktop files in directory
            for desktop_file in desktop_dir.glob("*.desktop"):
                try:
                    command = self._parse_desktop_file(
                        desktop_file,
                        window_class,
                        window_instance
                    )
                    if command:
                        self.desktop_file_cache[window_class] = str(desktop_file)
                        return command

                except Exception as e:
                    logger.debug(f"Failed to parse {desktop_file}: {e}")
                    continue

        return None

    def _parse_desktop_file(
        self,
        desktop_file: Path,
        window_class: str,
        window_instance: Optional[str] = None,
    ) -> Optional[str]:
        """
        Parse desktop file and check for match

        Args:
            desktop_file: Path to .desktop file
            window_class: Window class to match
            window_instance: Window instance to match

        Returns:
            Exec command if match found, None otherwise
        """
        config = configparser.ConfigParser(strict=False)
        config.read(desktop_file, encoding='utf-8')

        if 'Desktop Entry' not in config:
            return None

        entry = config['Desktop Entry']

        # Get Exec command
        exec_command = entry.get('Exec', '').strip()
        if not exec_command:
            return None

        # Strategy 1: Exact match on StartupWMClass
        startup_wm_class = entry.get('StartupWMClass', '').strip()
        if startup_wm_class and startup_wm_class == window_class:
            return self._clean_exec_command(exec_command)

        # Strategy 2: Desktop filename matches window_class
        filename_stem = desktop_file.stem.lower()
        if filename_stem == window_class.lower():
            return self._clean_exec_command(exec_command)

        # Strategy 3: Desktop filename matches window_instance
        if window_instance and filename_stem == window_instance.lower():
            return self._clean_exec_command(exec_command)

        # Strategy 4: Exec command contains window_class
        exec_lower = exec_command.lower()
        if window_class.lower() in exec_lower:
            return self._clean_exec_command(exec_command)

        return None

    def _clean_exec_command(self, exec_command: str) -> str:
        """
        Clean Exec command from desktop file

        Removes:
        - Field codes (%f, %F, %u, %U, %i, %c, %k)
        - Extra whitespace

        Args:
            exec_command: Raw Exec line from desktop file

        Returns:
            Cleaned command
        """
        # Remove field codes
        # %f: single file, %F: multiple files
        # %u: single URL, %U: multiple URLs
        # %i: --icon <icon>, %c: translated Name
        # %k: location of desktop file
        field_codes = [r'%[fFuUick]', r'--icon\s+\S+']
        for code in field_codes:
            exec_command = re.sub(code, '', exec_command)

        # Remove extra whitespace
        exec_command = ' '.join(exec_command.split())

        return exec_command.strip()

    def _discover_from_proc(self, pid: int) -> Optional[str]:
        """
        Discover launch command from /proc/PID/cmdline

        Args:
            pid: Process ID

        Returns:
            Command line string or None
        """
        cmdline_path = Path(f"/proc/{pid}/cmdline")

        try:
            if not cmdline_path.exists():
                return None

            # Read cmdline (null-separated arguments)
            with open(cmdline_path, 'rb') as f:
                cmdline_bytes = f.read()

            # Convert null-separated to space-separated
            # Filter out empty strings
            args = [
                arg.decode('utf-8', errors='replace')
                for arg in cmdline_bytes.split(b'\0')
                if arg
            ]

            if not args:
                return None

            # Reconstruct command
            command = ' '.join(args)

            # Clean up common patterns
            command = self._clean_proc_command(command)

            return command

        except (IOError, PermissionError) as e:
            logger.debug(f"Failed to read /proc/{pid}/cmdline: {e}")
            return None

    def _clean_proc_command(self, command: str) -> str:
        """
        Clean command line from /proc

        Removes:
        - Python/interpreter prefixes
        - Absolute paths (convert to basename)
        - Script arguments that look like files

        Args:
            command: Raw command from /proc/PID/cmdline

        Returns:
            Cleaned command
        """
        parts = command.split()
        if not parts:
            return command

        # Handle interpreter wrappers (python, bash, etc.)
        interpreters = ['python', 'python3', 'bash', 'sh', 'node', 'ruby', 'perl']
        if any(parts[0].endswith(interp) for interp in interpreters):
            # Keep interpreter + script name
            if len(parts) >= 2:
                # Convert absolute path to basename
                script_path = Path(parts[1])
                return f"{Path(parts[0]).name} {script_path.name}"

        # For direct executables, use basename
        exe_path = Path(parts[0])
        cleaned_parts = [exe_path.name]

        # Keep non-file arguments
        for arg in parts[1:]:
            # Skip arguments that look like file paths
            if arg.startswith('/') or arg.startswith('--'):
                continue
            cleaned_parts.append(arg)

        return ' '.join(cleaned_parts)


# Global instance for caching
_discovery_instance: Optional[LaunchCommandDiscovery] = None


def get_launch_command_discovery() -> LaunchCommandDiscovery:
    """
    Get global launch command discovery instance

    Returns:
        LaunchCommandDiscovery singleton
    """
    global _discovery_instance
    if _discovery_instance is None:
        _discovery_instance = LaunchCommandDiscovery()
    return _discovery_instance


def discover_launch_command(
    window_class: str,
    window_instance: Optional[str] = None,
    pid: Optional[int] = None,
) -> Optional[str]:
    """
    Convenience function to discover launch command

    Args:
        window_class: Window class
        window_instance: Window instance
        pid: Process ID

    Returns:
        Launch command or None
    """
    discovery = get_launch_command_discovery()
    return discovery.discover_launch_command(window_class, window_instance, pid)
