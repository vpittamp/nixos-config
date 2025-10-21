"""Full integration testing framework with real applications.

Provides test environment with:
- Real Xvfb X server
- Real i3 window manager
- Real application launching
- Real TUI with Textual
- xdotool for keyboard simulation
"""

import os
import sys
import time
import asyncio
import subprocess
import tempfile
import shutil
from pathlib import Path
from typing import Optional, List, Dict, Any
from dataclasses import dataclass, field
import signal
import psutil


@dataclass
class TestEnvironment:
    """Test environment with real X server and i3."""

    display: str  # e.g., ":99"
    xvfb_process: Optional[subprocess.Popen] = None
    i3_process: Optional[subprocess.Popen] = None
    tui_process: Optional[subprocess.Popen] = None
    temp_dir: Optional[Path] = None
    config_dir: Optional[Path] = None
    launched_apps: List[subprocess.Popen] = field(default_factory=list)

    def __post_init__(self):
        """Set environment variables for test display."""
        os.environ['DISPLAY'] = self.display


class IntegrationTestFramework:
    """Full integration test framework with real applications.

    Manages:
    - Xvfb virtual X server
    - i3 window manager test instance
    - Real application launching
    - Cleanup and teardown
    """

    def __init__(self, display: str = ":99", resolution: str = "1920x1080x24"):
        """Initialize integration test framework.

        Args:
            display: X display number (e.g., ":99")
            resolution: Xvfb resolution
        """
        self.display = display
        self.resolution = resolution
        self.env: Optional[TestEnvironment] = None

    async def setup_environment(self) -> TestEnvironment:
        """Set up complete test environment.

        Returns:
            TestEnvironment with all processes running
        """
        print(f"Setting up integration test environment on {self.display}...")

        # Create temporary directories
        temp_dir = Path(tempfile.mkdtemp(prefix="i3pm_test_"))
        config_dir = temp_dir / "config" / "i3"
        config_dir.mkdir(parents=True)

        # Create subdirectories
        (config_dir / "projects").mkdir()
        (config_dir / "layouts").mkdir()

        # Create app-classes.json
        app_classes = {
            "scoped_classes": ["Ghostty", "Code", "neovide", "Alacritty"],
            "global_classes": ["firefox", "Firefox", "chromium", "Chromium"]
        }
        import json
        with open(config_dir / "app-classes.json", "w") as f:
            json.dump(app_classes, f, indent=2)

        # Create i3 config for testing
        i3_config_dir = temp_dir / ".config" / "i3"
        i3_config_dir.mkdir(parents=True)
        self._create_i3_test_config(i3_config_dir)

        env = TestEnvironment(
            display=self.display,
            temp_dir=temp_dir,
            config_dir=config_dir
        )

        # Set self.env early so _start_i3 can use it for logging
        self.env = env

        # Start Xvfb
        print("  Starting Xvfb...")
        env.xvfb_process = await self._start_xvfb()
        await asyncio.sleep(1)  # Wait for Xvfb to be ready

        # Start i3
        print("  Starting i3 window manager...")
        print(f"    Config: {i3_config_dir / 'config'}")
        print(f"    DISPLAY: {self.display}")
        env.i3_process = await self._start_i3(i3_config_dir)
        await asyncio.sleep(3)  # Wait for i3 to be ready (increased from 2s)

        # Check if i3 process is still running
        if env.i3_process.poll() is not None:
            print(f"    ERROR: i3 process exited with code {env.i3_process.returncode}")
            # Close log file and read contents
            if hasattr(self, 'i3_log_file') and self.i3_log_file:
                self.i3_log_file.close()

            log_file = temp_dir / "i3.log"
            print(f"    Checking for log file: {log_file}")
            print(f"    Log file exists: {log_file.exists()}")
            if log_file.exists():
                print(f"    i3 log contents:")
                log_content = log_file.read_text()
                print(log_content if log_content else "    (empty log file)")
            else:
                print(f"    No log file found at {log_file}")
            raise RuntimeError(f"i3 process terminated unexpectedly (exit code {env.i3_process.returncode})")

        # Verify i3 is running
        if not await self._verify_i3_running():
            # Read log file for diagnostics
            log_file = temp_dir / "i3.log"
            if log_file.exists():
                print(f"    i3 log contents:")
                print(log_file.read_text())
            raise RuntimeError("i3 failed to start")

        print("  Test environment ready!")
        self.env = env
        return env

    def _create_i3_test_config(self, config_dir: Path) -> None:
        """Create minimal i3 config for testing.

        Args:
            config_dir: i3 config directory
        """
        config_content = """# i3 test configuration
# Minimal config for integration testing

# Font for window titles
font pango:monospace 8

# No startup applications
# exec --no-startup-id xss-lock --transfer-sleep-lock -- i3lock --nofork

# No status bar for testing (i3status can hang)
# bar {
#     status_command i3status
# }

# Basic keybindings
bindsym Mod1+Return exec xterm
bindsym Mod1+Shift+q kill
bindsym Mod1+Shift+e exit

# Workspace switching
bindsym Mod1+1 workspace number 1
bindsym Mod1+2 workspace number 2
bindsym Mod1+3 workspace number 3
bindsym Mod1+4 workspace number 4
bindsym Mod1+5 workspace number 5
bindsym Mod1+6 workspace number 6
bindsym Mod1+7 workspace number 7
bindsym Mod1+8 workspace number 8
bindsym Mod1+9 workspace number 9

# Move focused container to workspace
bindsym Mod1+Shift+1 move container to workspace number 1
bindsym Mod1+Shift+2 move container to workspace number 2
bindsym Mod1+Shift+3 move container to workspace number 3
bindsym Mod1+Shift+4 move container to workspace number 4

# Reload configuration
bindsym Mod1+Shift+c reload
"""

        config_file = config_dir / "config"
        with open(config_file, "w") as f:
            f.write(config_content)

    async def _start_xvfb(self) -> subprocess.Popen:
        """Start Xvfb virtual X server.

        Returns:
            Xvfb process
        """
        cmd = [
            "Xvfb",
            self.display,
            "-screen", "0", self.resolution,
            "-ac",  # Disable access control
            "+extension", "GLX",
            "+render",
            "-noreset"
        ]

        process = subprocess.Popen(
            cmd,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            env={**os.environ, 'DISPLAY': self.display}
        )

        return process

    async def _start_i3(self, config_dir: Path) -> subprocess.Popen:
        """Start i3 window manager.

        Args:
            config_dir: i3 config directory

        Returns:
            i3 process
        """
        cmd = [
            "i3",
            "-c", str(config_dir / "config")
            # No debug flag - let i3 start normally in foreground
        ]

        log_file = self.env.temp_dir / "i3.log" if self.env else None
        if log_file:
            self.i3_log_file = open(log_file, "w", buffering=1)  # Line buffered, keep file handle
            print(f"    i3 log: {log_file}")
            log_handle = self.i3_log_file
        else:
            log_handle = subprocess.PIPE

        process = subprocess.Popen(
            cmd,
            stdout=log_handle,
            stderr=subprocess.STDOUT,  # Merge stderr to stdout
            env={**os.environ, 'DISPLAY': self.display}
        )

        return process

    async def _verify_i3_running(self) -> bool:
        """Verify i3 is running and responding.

        Returns:
            True if i3 is running
        """
        try:
            result = subprocess.run(
                ["i3-msg", "-t", "get_version"],
                capture_output=True,
                timeout=5,
                env={**os.environ, 'DISPLAY': self.display}
            )
            if result.returncode == 0:
                print(f"    i3 verification successful: {result.stdout.decode().strip()}")
                return True
            else:
                print(f"    i3 verification failed: returncode={result.returncode}")
                print(f"    stdout: {result.stdout.decode()}")
                print(f"    stderr: {result.stderr.decode()}")
                return False
        except Exception as e:
            print(f"    i3 verification exception: {e}")
            return False

    async def close_all_windows(self) -> None:
        """Close all open windows in i3.

        Uses i3-msg to close all windows gracefully.
        """
        print("  Closing all windows...")

        try:
            # Get all window IDs
            result = subprocess.run(
                ["i3-msg", "-t", "get_tree"],
                capture_output=True,
                text=True,
                env={**os.environ, 'DISPLAY': self.display}
            )

            if result.returncode == 0:
                import json
                tree = json.loads(result.stdout)

                # Find all window nodes
                windows = self._find_windows_in_tree(tree)

                # Close each window
                for window_id in windows:
                    subprocess.run(
                        ["i3-msg", f"[id={window_id}]", "kill"],
                        capture_output=True,
                        env={**os.environ, 'DISPLAY': self.display}
                    )

                print(f"    Closed {len(windows)} windows")
                await asyncio.sleep(0.5)  # Wait for windows to close
        except Exception as e:
            print(f"    Warning: Failed to close windows: {e}")

    def _find_windows_in_tree(self, node: Dict[str, Any]) -> List[int]:
        """Recursively find all window IDs in i3 tree.

        Args:
            node: i3 tree node

        Returns:
            List of window IDs
        """
        windows = []

        # If this node has a window ID, add it
        if node.get("window"):
            windows.append(node["window"])

        # Recursively search child nodes
        for child in node.get("nodes", []):
            windows.extend(self._find_windows_in_tree(child))

        for child in node.get("floating_nodes", []):
            windows.extend(self._find_windows_in_tree(child))

        return windows

    async def launch_application(
        self,
        command: str,
        wait_for_window: bool = True,
        timeout: float = 10.0
    ) -> Optional[subprocess.Popen]:
        """Launch application in test environment.

        Args:
            command: Command to launch
            wait_for_window: Wait for window to appear
            timeout: Timeout for window appearance

        Returns:
            Process handle or None
        """
        print(f"  Launching: {command}")

        process = subprocess.Popen(
            command,
            shell=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            env={**os.environ, 'DISPLAY': self.display}
        )

        if self.env:
            self.env.launched_apps.append(process)

        if wait_for_window:
            # Wait for window to appear
            start_time = time.time()
            while time.time() - start_time < timeout:
                window_count = await self._get_window_count()
                if window_count > 0:
                    print(f"    Window appeared ({window_count} total windows)")
                    break
                await asyncio.sleep(0.2)
            else:
                print(f"    Warning: No window appeared within {timeout}s")

        return process

    async def _get_window_count(self) -> int:
        """Get count of open windows.

        Returns:
            Number of windows
        """
        try:
            result = subprocess.run(
                ["i3-msg", "-t", "get_tree"],
                capture_output=True,
                text=True,
                env={**os.environ, 'DISPLAY': self.display}
            )

            if result.returncode == 0:
                import json
                tree = json.loads(result.stdout)
                windows = self._find_windows_in_tree(tree)
                return len(windows)
        except Exception:
            pass

        return 0

    async def send_keys(self, keys: str, delay: float = 0.1) -> None:
        """Send keyboard input using xdotool.

        Args:
            keys: Keys to send (xdotool format)
            delay: Delay between keys
        """
        cmd = [
            "xdotool",
            "key",
            "--delay", str(int(delay * 1000)),
            keys
        ]

        subprocess.run(
            cmd,
            env={**os.environ, 'DISPLAY': self.display},
            capture_output=True
        )

    async def type_text(self, text: str, delay: float = 0.05) -> None:
        """Type text using xdotool.

        Args:
            text: Text to type
            delay: Delay between characters
        """
        cmd = [
            "xdotool",
            "type",
            "--delay", str(int(delay * 1000)),
            text
        ]

        subprocess.run(
            cmd,
            env={**os.environ, 'DISPLAY': self.display},
            capture_output=True
        )

    async def cleanup(self) -> None:
        """Clean up test environment.

        Kills all processes and removes temp directories.
        """
        if not self.env:
            return

        print("Cleaning up test environment...")

        # Close all windows first
        await self.close_all_windows()

        # Kill launched apps
        print("  Killing launched applications...")
        for process in self.env.launched_apps:
            try:
                process.terminate()
                process.wait(timeout=2)
            except Exception:
                try:
                    process.kill()
                except Exception:
                    pass

        # Kill TUI process
        if self.env.tui_process:
            print("  Stopping TUI...")
            try:
                self.env.tui_process.terminate()
                self.env.tui_process.wait(timeout=2)
            except Exception:
                self.env.tui_process.kill()

        # Kill i3
        if self.env.i3_process:
            print("  Stopping i3...")
            try:
                self.env.i3_process.terminate()
                self.env.i3_process.wait(timeout=2)
            except Exception:
                self.env.i3_process.kill()

        # Kill Xvfb
        if self.env.xvfb_process:
            print("  Stopping Xvfb...")
            try:
                self.env.xvfb_process.terminate()
                self.env.xvfb_process.wait(timeout=2)
            except Exception:
                self.env.xvfb_process.kill()

        # Remove temp directory
        if self.env.temp_dir and self.env.temp_dir.exists():
            print(f"  Removing temp directory: {self.env.temp_dir}")
            shutil.rmtree(self.env.temp_dir, ignore_errors=True)

        self.env = None
        print("Cleanup complete!")

    async def __aenter__(self):
        """Context manager entry."""
        await self.setup_environment()
        return self

    async def __aexit__(self, exc_type, exc_val, exc_tb):
        """Context manager exit."""
        await self.cleanup()
