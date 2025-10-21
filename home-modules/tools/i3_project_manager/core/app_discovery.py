"""Application discovery and window class detection.

This module provides tools for:
1. Discovering installed applications via desktop files
2. Extracting window class information from desktop files
3. Automated window class detection by launching apps in isolation
4. Interactive classification wizard
"""

import asyncio
import configparser
import json
import logging
import os
import re
import shutil
import subprocess
import tempfile
import time
from contextlib import contextmanager
from dataclasses import dataclass
from datetime import datetime, timedelta
from pathlib import Path
from typing import Dict, List, Optional, Set, Tuple, Generator

from i3_project_manager.models.detection import DetectionResult


@dataclass
class DesktopApp:
    """Represents an application from a .desktop file."""

    name: str
    exec_command: str
    desktop_file: Path
    wm_class: Optional[str] = None
    icon: Optional[str] = None
    categories: List[str] = None
    terminal: bool = False
    no_display: bool = False

    def __post_init__(self):
        if self.categories is None:
            self.categories = []


class AppDiscovery:
    """Discover and classify applications on the system."""

    DESKTOP_DIRS = [
        Path("/run/current-system/sw/share/applications"),
        Path.home() / ".local/share/applications",
        Path("/usr/share/applications"),
        Path("/usr/local/share/applications"),
    ]

    def __init__(self):
        """Initialize app discovery."""
        self.apps: Dict[str, DesktopApp] = {}

    def discover_all(self) -> List[DesktopApp]:
        """Discover all desktop applications on the system.

        Returns:
            List of DesktopApp objects
        """
        self.apps = {}

        for desktop_dir in self.DESKTOP_DIRS:
            if not desktop_dir.exists():
                continue

            for desktop_file in desktop_dir.glob("*.desktop"):
                try:
                    app = self._parse_desktop_file(desktop_file)
                    if app and not app.no_display:
                        # Use name as key, but prefer apps with WM class
                        key = app.name
                        if key not in self.apps or (
                            app.wm_class and not self.apps[key].wm_class
                        ):
                            self.apps[key] = app
                except Exception as e:
                    # Skip invalid desktop files
                    pass

        return sorted(self.apps.values(), key=lambda a: a.name.lower())

    def _parse_desktop_file(self, desktop_file: Path) -> Optional[DesktopApp]:
        """Parse a .desktop file and extract app information.

        Args:
            desktop_file: Path to .desktop file

        Returns:
            DesktopApp object or None if invalid
        """
        try:
            parser = configparser.ConfigParser()
            parser.read(desktop_file)

            if "Desktop Entry" not in parser:
                return None

            entry = parser["Desktop Entry"]

            # Skip if NoDisplay=true
            if entry.get("NoDisplay", "false").lower() == "true":
                return None

            # Skip if Type != Application
            if entry.get("Type", "") != "Application":
                return None

            name = entry.get("Name", desktop_file.stem)
            exec_cmd = entry.get("Exec", "")

            if not exec_cmd:
                return None

            # Clean up exec command (remove %U, %F, etc.)
            exec_cmd = re.sub(r"%[a-zA-Z]", "", exec_cmd).strip()

            wm_class = entry.get("StartupWMClass")
            icon = entry.get("Icon")
            categories = entry.get("Categories", "").split(";")
            categories = [c for c in categories if c]
            terminal = entry.get("Terminal", "false").lower() == "true"

            return DesktopApp(
                name=name,
                exec_command=exec_cmd,
                desktop_file=desktop_file,
                wm_class=wm_class,
                icon=icon,
                categories=categories,
                terminal=terminal,
            )

        except Exception:
            return None

    def get_apps_without_wm_class(self) -> List[DesktopApp]:
        """Get apps that don't have StartupWMClass defined.

        Returns:
            List of apps missing WM class
        """
        return [app for app in self.apps.values() if not app.wm_class]

    def guess_wm_class(self, app: DesktopApp) -> Optional[str]:
        """Guess window class from app name or exec command.

        Many apps use a predictable pattern:
        - Binary name as class (e.g., "firefox" → "firefox")
        - CamelCase binary name (e.g., "code" → "Code")
        - First word of Exec command

        Args:
            app: DesktopApp to guess class for

        Returns:
            Guessed WM class or None
        """
        # Try to extract binary name from exec command
        exec_parts = app.exec_command.split()
        if not exec_parts:
            return None

        binary = exec_parts[0]

        # Remove path if present
        binary = os.path.basename(binary)

        # Common patterns:
        # 1. firefox → firefox
        # 2. code → Code (capitalize)
        # 3. google-chrome → Google-chrome or chromium-browser → Chromium-browser

        # Try exact binary name first
        if binary.islower():
            # Try capitalized version
            return binary.capitalize()
        else:
            # Return as-is
            return binary

    async def detect_wm_class_by_launch(
        self, app: DesktopApp, timeout: float = 5.0
    ) -> Optional[str]:
        """Detect window class by launching app and querying i3.

        This launches the app in the current i3 session and immediately
        queries for new windows. The app is then closed.

        WARNING: This will briefly open the application in your workspace!
        Use detect_wm_class_isolated() for safer automated detection.

        Args:
            app: DesktopApp to detect class for
            timeout: Maximum time to wait for window to appear

        Returns:
            Detected WM class or None
        """
        from .i3_client import I3Client

        i3 = I3Client()
        await i3.connect()

        # Get current window IDs
        tree_before = await i3.get_tree()
        windows_before = self._extract_window_ids(tree_before)

        # Launch app
        process = subprocess.Popen(
            app.exec_command,
            shell=True,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )

        # Wait for new window to appear
        start_time = time.time()
        detected_class = None

        while time.time() - start_time < timeout:
            await asyncio.sleep(0.1)

            tree_after = await i3.get_tree()
            windows_after = self._extract_window_ids(tree_after)

            # Find new windows
            new_windows = windows_after - windows_before

            if new_windows:
                # Get window class from first new window
                for window in tree_after.find_marked():
                    if window.id in new_windows and hasattr(window, "window_class"):
                        detected_class = window.window_class
                        break

                if detected_class:
                    break

        # Close the app
        try:
            process.terminate()
            process.wait(timeout=1.0)
        except:
            process.kill()

        await i3.close()

        return detected_class

    async def detect_wm_class_isolated(
        self, app: DesktopApp, timeout: float = 10.0
    ) -> Optional[str]:
        """Detect window class by launching app in isolated X server.

        This uses Xvfb (virtual framebuffer) to run the app in a headless
        X server, preventing it from appearing in your workspace.

        Requires: xvfb-run, xdotool, xprop

        Args:
            app: DesktopApp to detect class for
            timeout: Maximum time to wait for window

        Returns:
            Detected WM class or None
        """
        # Create a temporary script to run in Xvfb
        script = f"""#!/bin/bash
set -e

# Launch app in background
{app.exec_command} &
APP_PID=$!

# Wait for window to appear (up to {timeout}s)
for i in {{1..{int(timeout * 10)}}}; do
    # Get window ID
    WINDOW_ID=$(xdotool search --pid $APP_PID 2>/dev/null | head -1)

    if [ -n "$WINDOW_ID" ]; then
        # Get window class
        WM_CLASS=$(xprop -id $WINDOW_ID WM_CLASS 2>/dev/null | cut -d'"' -f4)

        if [ -n "$WM_CLASS" ]; then
            echo "$WM_CLASS"
            kill $APP_PID 2>/dev/null || true
            exit 0
        fi
    fi

    sleep 0.1
done

# Cleanup
kill $APP_PID 2>/dev/null || true
exit 1
"""

        try:
            # Write script to temp file
            with tempfile.NamedTemporaryFile(
                mode="w", suffix=".sh", delete=False
            ) as f:
                f.write(script)
                script_path = f.name

            os.chmod(script_path, 0o755)

            # Run with xvfb-run
            result = subprocess.run(
                ["xvfb-run", "-a", script_path],
                capture_output=True,
                text=True,
                timeout=timeout + 2,
            )

            # Clean up script
            os.unlink(script_path)

            if result.returncode == 0:
                wm_class = result.stdout.strip()
                return wm_class if wm_class else None

            return None

        except (subprocess.TimeoutExpired, FileNotFoundError):
            return None
        except Exception:
            return None

    def _extract_window_ids(self, tree) -> Set[int]:
        """Extract all window IDs from i3 tree.

        Args:
            tree: i3 tree object

        Returns:
            Set of window IDs
        """
        ids = set()

        def walk(node):
            if hasattr(node, "id"):
                ids.add(node.id)
            if hasattr(node, "nodes"):
                for child in node.nodes:
                    walk(child)
            if hasattr(node, "floating_nodes"):
                for child in node.floating_nodes:
                    walk(child)

        walk(tree)
        return ids

    def categorize_by_type(self) -> Dict[str, List[DesktopApp]]:
        """Categorize apps by their desktop entry categories.

        Returns:
            Dict mapping category to list of apps
        """
        categorized: Dict[str, List[DesktopApp]] = {}

        for app in self.apps.values():
            for category in app.categories:
                if category not in categorized:
                    categorized[category] = []
                categorized[category].append(app)

        return categorized

    def suggest_classification(self, app: DesktopApp) -> str:
        """Suggest whether app should be scoped or global.

        Heuristics:
        - Terminals, editors, IDEs: scoped
        - Browsers (might have PWAs): check if looks like PWA
        - Media players, system tools: global
        - Development tools: scoped

        Args:
            app: DesktopApp to classify

        Returns:
            "scoped", "global", or "unknown"
        """
        categories = set(c.lower() for c in app.categories)
        name_lower = app.name.lower()
        exec_lower = app.exec_command.lower()

        # Scoped heuristics
        scoped_categories = {
            "terminalemulator",
            "terminal",
            "editor",
            "texteditor",
            "ide",
            "development",
        }
        scoped_keywords = ["terminal", "editor", "vim", "emacs", "code", "vscode"]

        if categories & scoped_categories:
            return "scoped"

        if any(kw in name_lower or kw in exec_lower for kw in scoped_keywords):
            return "scoped"

        # Global heuristics
        global_categories = {
            "audiovideo",
            "audio",
            "video",
            "player",
            "system",
            "utility",
            "settings",
        }
        global_keywords = ["player", "vlc", "mpv", "spotify", "settings", "system"]

        if categories & global_categories:
            return "global"

        if any(kw in name_lower or kw in exec_lower for kw in global_keywords):
            return "global"

        # Browsers need special handling (could have PWAs)
        if "webbrowser" in categories or "browser" in name_lower:
            # Check if it looks like a PWA wrapper
            if "pwa" in name_lower or "pwa" in exec_lower:
                return "global"
            else:
                # Regular browser - could go either way
                return "global"  # Default to global for main browsers

        return "unknown"

    def generate_classification_report(self) -> str:
        """Generate a markdown report of all apps with suggested classifications.

        Returns:
            Markdown formatted report
        """
        lines = ["# Application Classification Report", ""]

        # Apps with WM class
        apps_with_class = [a for a in self.apps.values() if a.wm_class]
        apps_without_class = [a for a in self.apps.values() if not a.wm_class]

        lines.append(f"**Total Applications**: {len(self.apps)}")
        lines.append(f"**With WM Class**: {len(apps_with_class)}")
        lines.append(f"**Without WM Class**: {len(apps_without_class)}")
        lines.append("")

        # Apps with WM class
        lines.append("## Applications with WM Class")
        lines.append("")
        lines.append("| Name | WM Class | Suggested | Categories |")
        lines.append("|------|----------|-----------|------------|")

        for app in sorted(apps_with_class, key=lambda a: a.name.lower()):
            suggestion = self.suggest_classification(app)
            categories = ", ".join(app.categories[:3])
            if len(app.categories) > 3:
                categories += "..."
            lines.append(
                f"| {app.name} | {app.wm_class} | {suggestion} | {categories} |"
            )

        lines.append("")

        # Apps without WM class
        if apps_without_class:
            lines.append("## Applications without WM Class")
            lines.append("")
            lines.append("| Name | Exec | Guessed Class | Suggested |")
            lines.append("|------|------|---------------|-----------|")

            for app in sorted(apps_without_class, key=lambda a: a.name.lower()):
                guessed = self.guess_wm_class(app) or "?"
                suggestion = self.suggest_classification(app)
                exec_short = (
                    app.exec_command[:30] + "..."
                    if len(app.exec_command) > 30
                    else app.exec_command
                )
                lines.append(
                    f"| {app.name} | `{exec_short}` | {guessed} | {suggestion} |"
                )

        return "\n".join(lines)


# ============================================================================
# Logger Setup (T043, FR-094)
# ============================================================================

logger = logging.getLogger(__name__)
_detection_log_handler = None


def setup_detection_logging() -> None:
    """Set up file logging for detection operations.

    Creates a file handler that logs detection events to
    ~/.cache/i3pm/detection.log with timestamp, app name,
    detected class, duration, and errors.

    FR-094: Detection event logging
    """
    global _detection_log_handler

    # Avoid duplicate handlers
    if _detection_log_handler is not None:
        return

    # Create log directory
    log_dir = Path.home() / ".cache" / "i3pm"
    log_dir.mkdir(parents=True, exist_ok=True)
    log_file = log_dir / "detection.log"

    # Create file handler with rotation
    handler = logging.FileHandler(log_file, mode='a')
    handler.setLevel(logging.INFO)

    # Format: timestamp | app_name | detected_class | duration | status | error
    formatter = logging.Formatter(
        '%(asctime)s | %(message)s',
        datefmt='%Y-%m-%d %H:%M:%S'
    )
    handler.setFormatter(formatter)

    logger.addHandler(handler)
    logger.setLevel(logging.INFO)
    _detection_log_handler = handler


def log_detection_result(
    app_name: str,
    detected_class: Optional[str],
    duration_sec: float,
    detection_method: str,
    error_message: Optional[str] = None
) -> None:
    """Log a detection result to the detection log file.

    Args:
        app_name: Name of the application
        detected_class: Detected window class (None if failed)
        duration_sec: Time taken for detection in seconds
        detection_method: Method used (xvfb, guess, failed)
        error_message: Error message if detection failed

    FR-094: Structured detection logging
    """
    setup_detection_logging()

    # Format: app_name | detected_class | duration | method | error
    status = "SUCCESS" if detected_class else "FAILED"
    class_str = detected_class if detected_class else "None"
    error_str = f" | {error_message}" if error_message else ""

    logger.info(
        f"{app_name:30} | {class_str:20} | {duration_sec:6.2f}s | {detection_method:10} | {status}{error_str}"
    )


# ============================================================================
# Phase 4: Xvfb-based Window Class Detection (T038-T040)
# ============================================================================
def check_xvfb_available() -> bool:
    """Check if all required X virtual framebuffer tools are available.

    Returns:
        True if Xvfb, xdotool, and xprop are all found in PATH

    FR-083: Check for Xvfb, xdotool, xprop binaries
    """
    required_tools = ["Xvfb", "xdotool", "xprop"]

    for tool in required_tools:
        if shutil.which(tool) is None:
            logger.warning(f"Required tool '{tool}' not found in PATH")
            return False

    return True


def parse_wm_class(xprop_output: str) -> Optional[str]:
    """Extract WM_CLASS from xprop output.

    Args:
        xprop_output: Output from `xprop -id <window_id> WM_CLASS`

    Returns:
        Window class string, or None if parsing failed

    FR-087: Parse WM_CLASS(STRING) = "instance", "class"

    Examples:
        >>> parse_wm_class('WM_CLASS(STRING) = "code", "Code"')
        'Code'
        >>> parse_wm_class('WM_CLASS(STRING) = "firefox", "Firefox"')
        'Firefox'
        >>> parse_wm_class('WM_CLASS: not found')
        None
    """
    # Match pattern: WM_CLASS(STRING) = "instance", "class"
    # We want to extract the second quoted string (the class)
    pattern = r'WM_CLASS\(STRING\)\s*=\s*"[^"]*",\s*"([^"]*)"'

    match = re.search(pattern, xprop_output)
    if match:
        return match.group(1)

    return None


@contextmanager
def isolated_xvfb(display_num: int = 99) -> Generator[str, None, None]:
    """Launch isolated Xvfb session for window class detection.

    Args:
        display_num: X display number to use (default: 99)

    Yields:
        DISPLAY string (e.g., ":99") for use with subprocess

    FR-084: Launch isolated Xvfb session
    FR-088: Graceful termination with SIGTERM
    FR-089: SIGKILL if process doesn't exit

    Examples:
        >>> with isolated_xvfb(display_num=99) as display:
        ...     # Launch app with DISPLAY=:99
        ...     subprocess.run(["firefox"], env={"DISPLAY": display})
    """
    display = f":{display_num}"
    xvfb_process = None

    try:
        # Start Xvfb on specified display
        logger.debug(f"Starting Xvfb on display {display}")
        xvfb_process = subprocess.Popen(
            ["Xvfb", display, "-screen", "0", "1024x768x24"],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )

        # Give Xvfb time to start
        time.sleep(0.5)

        # Verify Xvfb is running
        if xvfb_process.poll() is not None:
            raise RuntimeError(f"Xvfb failed to start on display {display}")

        yield display

    finally:
        # Cleanup: Graceful termination with SIGTERM → SIGKILL sequence
        if xvfb_process is not None:
            logger.debug(f"Terminating Xvfb on display {display}")

            # FR-088: Send SIGTERM first
            xvfb_process.terminate()

            # Wait for process to exit (max 2 seconds)
            try:
                xvfb_process.wait(timeout=2.0)
                logger.debug("Xvfb exited cleanly")
            except subprocess.TimeoutExpired:
                # FR-089: SIGKILL if process doesn't exit
                logger.warning("Xvfb did not exit after SIGTERM, sending SIGKILL")
                xvfb_process.kill()
                xvfb_process.wait()


def detect_window_class_xvfb(
    desktop_file: str, timeout: int = 10
) -> DetectionResult:
    """Detect window class by launching app in isolated Xvfb session.

    Args:
        desktop_file: Path to .desktop file
        timeout: Maximum seconds to wait for window (default: 10)

    Returns:
        DetectionResult with detected class or failure details

    FR-084: Launch app in isolated Xvfb
    FR-085: Poll for window with xdotool
    FR-086: 10-second timeout per app
    FR-087: Extract WM_CLASS with xprop
    FR-088: Terminate app with SIGTERM
    FR-089: SIGKILL if app doesn't exit
    FR-094: Log detection results with duration

    Examples:
        >>> result = detect_window_class_xvfb("/usr/share/applications/code.desktop")
        >>> result.detected_class
        'Code'
        >>> result.detection_method
        'xvfb'
    """
    from datetime import datetime

    app_name = Path(desktop_file).stem  # Extract app name from filename
    app_process = None
    detection_start = time.perf_counter()  # FR-094: Track duration

    try:
        with isolated_xvfb(display_num=99) as display:
            # Launch application with isolated DISPLAY
            logger.info(f"Launching {app_name} on display {display}")

            # For now, use gtk-launch to launch .desktop file
            # TODO: Parse .desktop Exec field for more control
            app_process = subprocess.Popen(
                ["gtk-launch", Path(desktop_file).stem],
                env={"DISPLAY": display},
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            )

            # FR-085: Poll for window appearance (FR-086: with timeout)
            start_time = time.time()
            window_id = None

            while time.time() - start_time < timeout:
                try:
                    # Use xdotool to search for any window on this display
                    result = subprocess.run(
                        ["xdotool", "search", "--onlyvisible", "--name", ".*"],
                        env={"DISPLAY": display},
                        capture_output=True,
                        text=True,
                        timeout=1.0,
                    )

                    if result.returncode == 0 and result.stdout.strip():
                        window_id = result.stdout.strip().split("\n")[0]
                        logger.debug(f"Found window ID: {window_id}")
                        break

                except subprocess.TimeoutExpired:
                    pass

                time.sleep(0.2)  # Poll every 200ms

            if window_id is None:
                raise TimeoutError(
                    f"No window appeared within {timeout} seconds"
                )

            # FR-087: Extract WM_CLASS with xprop
            logger.debug(f"Extracting WM_CLASS for window {window_id}")
            xprop_result = subprocess.run(
                ["xprop", "-id", window_id, "WM_CLASS"],
                env={"DISPLAY": display},
                capture_output=True,
                text=True,
                timeout=2.0,
            )

            if xprop_result.returncode != 0:
                raise RuntimeError(
                    f"xprop failed: {xprop_result.stderr}"
                )

            detected_class = parse_wm_class(xprop_result.stdout)

            if detected_class is None:
                raise RuntimeError(
                    f"Failed to parse WM_CLASS from: {xprop_result.stdout}"
                )

            logger.info(
                f"Successfully detected class '{detected_class}' for {app_name}"
            )

            # FR-094: Log successful detection with duration
            duration = time.perf_counter() - detection_start
            log_detection_result(app_name, detected_class, duration, "xvfb")

            return DetectionResult(
                desktop_file=desktop_file,
                app_name=app_name,
                detected_class=detected_class,
                detection_method="xvfb",
                confidence=1.0,
                timestamp=datetime.now().isoformat(),
            )

    except Exception as e:
        error_msg = str(e) if str(e) else type(e).__name__
        logger.error(f"Detection failed for {app_name}: {error_msg}")

        # FR-094: Log failed detection with duration and error
        duration = time.perf_counter() - detection_start
        log_detection_result(app_name, None, duration, "failed", error_msg)

        return DetectionResult(
            desktop_file=desktop_file,
            app_name=app_name,
            detected_class=None,
            detection_method="failed",
            confidence=0.0,
            error_message=error_msg,
            timestamp=datetime.now().isoformat(),
        )

    finally:
        # FR-088, FR-089: Cleanup app process
        if app_process is not None:
            logger.debug(f"Terminating {app_name} process")
            app_process.terminate()

            try:
                app_process.wait(timeout=2.0)
            except subprocess.TimeoutExpired:
                logger.warning(f"{app_name} did not exit, sending SIGKILL")
                app_process.kill()
                app_process.wait()


# ============================================================================
# Detection Result Caching (T041, FR-091)
# ============================================================================


def get_cache_path() -> Path:
    """Get path to detection cache file.
    
    Returns:
        Path to ~/.cache/i3pm/detected-classes.json
    
    FR-091: Cache location in user's cache directory
    """
    cache_dir = Path.home() / ".cache" / "i3pm"
    return cache_dir / "detected-classes.json"


def is_cache_valid(cache_timestamp: str) -> bool:
    """Check if cache timestamp is within validity period.

    Args:
        cache_timestamp: ISO format timestamp string

    Returns:
        True if cache is less than 30 days old

    FR-091: 30-day invalidation period
    """
    try:
        cache_time = datetime.fromisoformat(cache_timestamp)
        age = datetime.now() - cache_time
        # Cache is valid if 30 days or less (use .days to ignore sub-day precision)
        return age.days <= 30
    except (ValueError, TypeError):
        # Invalid timestamp format
        return False


def load_detection_cache() -> Optional[Dict]:
    """Load detection cache from disk.
    
    Returns:
        Cache data dict or None if cache doesn't exist or is invalid
    
    FR-091: Load and validate cache file
    """
    cache_path = get_cache_path()
    
    if not cache_path.exists():
        logger.debug("Cache file does not exist")
        return None
    
    try:
        with open(cache_path, "r") as f:
            cache_data = json.load(f)
        
        # Validate cache structure
        if "timestamp" not in cache_data or "cache_version" not in cache_data:
            logger.warning("Cache file missing required fields, treating as invalid")
            return None
        
        # Check if cache is expired
        if not is_cache_valid(cache_data["timestamp"]):
            logger.info("Cache expired (>30 days old)")
            return None
        
        logger.debug(f"Loaded cache with {len(cache_data.get('results', {}))} entries")
        return cache_data
    
    except (json.JSONDecodeError, IOError) as e:
        logger.warning(f"Failed to load cache: {e}")
        return None


def save_detection_cache(results: Dict[str, Dict]) -> None:
    """Save detection results to cache file.
    
    Args:
        results: Dict mapping desktop_file -> detection result dict
    
    FR-091: Save cache with timestamp and version
    """
    cache_path = get_cache_path()
    cache_path.parent.mkdir(parents=True, exist_ok=True)
    
    cache_data = {
        "timestamp": datetime.now().isoformat(),
        "cache_version": "1.0",
        "results": results,
    }
    
    try:
        with open(cache_path, "w") as f:
            json.dump(cache_data, f, indent=2)
        logger.debug(f"Saved cache with {len(results)} entries")
    except IOError as e:
        logger.error(f"Failed to save cache: {e}")


def get_cached_result(desktop_file: str) -> Optional["DetectionResult"]:
    """Get cached detection result for a desktop file.
    
    Args:
        desktop_file: Path to .desktop file
    
    Returns:
        DetectionResult if found in valid cache, None otherwise

    FR-091: Retrieve cached results
    """
    cache_data = load_detection_cache()
    if cache_data is None:
        return None
    
    results = cache_data.get("results", {})
    cached_entry = results.get(desktop_file)
    
    if cached_entry is None:
        return None
    
    # Reconstruct DetectionResult from cached data
    try:
        return DetectionResult(
            desktop_file=cached_entry["desktop_file"],
            app_name=cached_entry["app_name"],
            detected_class=cached_entry.get("detected_class"),
            detection_method=cached_entry["detection_method"],
            confidence=cached_entry["confidence"],
            error_message=cached_entry.get("error_message"),
            timestamp=cached_entry["timestamp"],
        )
    except (KeyError, TypeError) as e:
        logger.warning(f"Invalid cache entry for {desktop_file}: {e}")
        return None


def update_cache_with_result(result: "DetectionResult") -> None:
    """Update cache with a new detection result.
    
    Args:
        result: DetectionResult to add to cache
    
    FR-091: Update cache after successful detection
    """
    # Only cache successful detections
    if result.detection_method == "failed":
        logger.debug(f"Not caching failed detection for {result.desktop_file}")
        return
    
    # Load existing cache or create new one
    cache_data = load_detection_cache()
    if cache_data is None:
        results = {}
    else:
        results = cache_data.get("results", {})
    
    # Add/update this result
    results[result.desktop_file] = {
        "desktop_file": result.desktop_file,
        "app_name": result.app_name,
        "detected_class": result.detected_class,
        "detection_method": result.detection_method,
        "confidence": result.confidence,
        "error_message": result.error_message,
        "timestamp": result.timestamp,
    }
    
    # Save updated cache
    save_detection_cache(results)
    logger.info(f"Cached detection result for {result.desktop_file}: {result.detected_class}")
