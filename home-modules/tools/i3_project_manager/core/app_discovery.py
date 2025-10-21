"""Application discovery and window class detection.

This module provides tools for:
1. Discovering installed applications via desktop files
2. Extracting window class information from desktop files
3. Automated window class detection by launching apps in isolation
4. Interactive classification wizard
"""

import asyncio
import configparser
import os
import re
import subprocess
import tempfile
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Dict, List, Optional, Set, Tuple


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
