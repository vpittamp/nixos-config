"""
Pytest configuration and shared fixtures for environment variable-based window matching tests.

This module provides shared test fixtures for:
- Sway IPC connection management
- /proc filesystem access helpers
- Test process lifecycle management
- Cleanup utilities
"""

import pytest
import asyncio
import os
import signal
import subprocess
from pathlib import Path
from typing import List, Dict, Optional
from i3ipc.aio import Connection


@pytest.fixture(scope="session")
def event_loop():
    """Create an event loop for the entire test session."""
    loop = asyncio.get_event_loop_policy().new_event_loop()
    yield loop
    loop.close()


@pytest.fixture
async def sway_connection():
    """
    Provide async Sway IPC connection for tests.

    Yields:
        Connection: Async i3ipc connection to Sway/i3
    """
    conn = await Connection(auto_reconnect=True).connect()
    yield conn
    conn.main_quit()


@pytest.fixture
async def validate_environment_coverage_func():
    """
    Provide validate_environment_coverage function for tests.

    Returns:
        Callable that validates environment coverage given a Sway connection
    """
    # Import here to avoid circular imports
    import sys
    from pathlib import Path

    # Add daemon module to path
    daemon_path = Path(__file__).parent.parent.parent / "daemon"
    if str(daemon_path) not in sys.path:
        sys.path.insert(0, str(daemon_path))

    from window_environment import validate_environment_coverage

    return validate_environment_coverage


@pytest.fixture
def app_registry():
    """
    Provide mock app registry for tests.

    Returns:
        Dict with registered application information
    """
    return {
        "vscode": {"name": "vscode", "scope": "scoped", "command": "code"},
        "terminal": {"name": "terminal", "scope": "scoped", "command": "ghostty"},
        "firefox": {"name": "firefox", "scope": "global", "command": "firefox"},
        "claude-pwa": {"name": "claude-pwa", "scope": "scoped", "command": "firefoxpwa"},
        "youtube-pwa": {"name": "youtube-pwa", "scope": "global", "command": "firefoxpwa"},
    }


@pytest.fixture
def test_processes():
    """
    Track and cleanup test processes.

    Yields:
        List[subprocess.Popen]: List of spawned test processes

    Cleanup:
        Terminates all spawned processes after test completes
    """
    processes: List[subprocess.Popen] = []

    yield processes

    # Cleanup: terminate all test processes
    for proc in processes:
        try:
            proc.terminate()
            try:
                proc.wait(timeout=5)
            except subprocess.TimeoutExpired:
                proc.kill()
                proc.wait()
        except ProcessLookupError:
            pass  # Process already terminated


@pytest.fixture
def launch_test_process(test_processes):
    """
    Helper to launch test process with environment variables.

    Args:
        test_processes: Fixture to track processes for cleanup

    Returns:
        Callable that launches process with environment and registers for cleanup

    Example:
        proc = launch_test_process(
            ["sleep", "60"],
            env_vars={"I3PM_APP_ID": "test-123", "I3PM_APP_NAME": "test-app"}
        )
    """
    def _launch(cmd: List[str], env_vars: Optional[Dict[str, str]] = None) -> subprocess.Popen:
        """Launch process with custom environment variables."""
        env = os.environ.copy()
        if env_vars:
            env.update(env_vars)

        proc = subprocess.Popen(
            cmd,
            env=env,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL
        )
        test_processes.append(proc)
        return proc

    return _launch


@pytest.fixture
def read_process_environ_helper():
    """
    Helper to read /proc/<pid>/environ for testing.

    Returns:
        Callable that reads and parses /proc/<pid>/environ

    Example:
        env_vars = read_process_environ_helper(12345)
        assert env_vars["PATH"] is not None
    """
    def _read_environ(pid: int) -> Dict[str, str]:
        """Read and parse /proc/<pid>/environ."""
        try:
            environ_path = Path(f"/proc/{pid}/environ")
            if not environ_path.exists():
                return {}

            # Read binary data
            with open(environ_path, "rb") as f:
                data = f.read()

            # Decode with ignore errors for non-UTF8 bytes
            text = data.decode("utf-8", errors="ignore")

            # Parse key=value pairs separated by null bytes
            env_dict = {}
            for line in text.split("\0"):
                if "=" in line:
                    key, value = line.split("=", 1)
                    env_dict[key] = value

            return env_dict
        except (FileNotFoundError, PermissionError, OSError):
            return {}

    return _read_environ


@pytest.fixture
async def find_windows_by_class_helper(sway_connection):
    """
    Helper to find windows by window class using Sway IPC.

    Args:
        sway_connection: Async Sway IPC connection

    Returns:
        Callable that searches window tree for matching class

    Example:
        windows = await find_windows_by_class_helper("Code")
        assert len(windows) > 0
    """
    async def _find_windows(window_class: str) -> List:
        """Find all windows matching the given window class."""
        tree = await sway_connection.get_tree()

        def find_windows_recursive(node, matches):
            """Recursively search tree for windows matching class."""
            # Check if this is a window node with matching class
            if node.type == "con" and node.window:
                if hasattr(node, "window_class") and node.window_class == window_class:
                    matches.append(node)
                elif hasattr(node, "app_id") and node.app_id == window_class:
                    matches.append(node)

            # Recurse into children
            if hasattr(node, "nodes"):
                for child in node.nodes:
                    find_windows_recursive(child, matches)
            if hasattr(node, "floating_nodes"):
                for child in node.floating_nodes:
                    find_windows_recursive(child, matches)

        matches = []
        find_windows_recursive(tree, matches)
        return matches

    return _find_windows


@pytest.fixture
def cleanup_test_windows(sway_connection):
    """
    Helper to cleanup test windows after test completion.

    Yields:
        Callable to close windows by ID

    Example:
        # Register window for cleanup
        cleanup_test_windows(window_id)
    """
    window_ids = []

    def _register_window(window_id: int):
        """Register window ID for cleanup."""
        window_ids.append(window_id)

    yield _register_window

    # Cleanup: close all registered windows
    async def _cleanup():
        for window_id in window_ids:
            try:
                await sway_connection.command(f'[con_id="{window_id}"] kill')
            except Exception:
                pass  # Window may already be closed

    # Run cleanup
    asyncio.run(_cleanup())
