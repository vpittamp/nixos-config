"""
Monitoring Panel Data Backend Script

Queries i3pm daemon for window/workspace/project state and outputs JSON for Eww consumption.

Usage:
    python3 -m i3_project_manager.cli.monitoring_data                   # Windows view (default)
    python3 -m i3_project_manager.cli.monitoring_data --mode projects   # Projects view
    python3 -m i3_project_manager.cli.monitoring_data --mode apps       # Apps view
    python3 -m i3_project_manager.cli.monitoring_data --mode events     # Events view
    python3 -m i3_project_manager.cli.monitoring_data --mode health     # Health view
    python3 -m i3_project_manager.cli.monitoring_data --listen          # Stream mode (deflisten)

Output: Single-line JSON to stdout (see contracts/eww-defpoll.md)

Performance: <50ms execution time for typical workload (20-30 windows)

Stream Mode (--listen):
    - Subscribes to Sway window/workspace/output events
    - Outputs JSON on every state change (<100ms latency)
    - Includes heartbeat every 5s to detect stale connections
    - Automatic reconnection with exponential backoff
    - Graceful shutdown on SIGTERM/SIGPIPE
"""

import argparse
import asyncio
import json
import logging
import os
import signal
import subprocess
import sys
import time
from pathlib import Path
from typing import Any, Dict, List, Optional

# Import daemon client from core module
from i3_project_manager.core.daemon_client import DaemonClient, DaemonError

# Import i3ipc for event subscriptions in listen mode
try:
    from i3ipc.aio import Connection as I3Connection
except ImportError:
    I3Connection = None  # Gracefully handle missing i3ipc in one-shot mode

# Configure logging (stderr only - stdout is for JSON)
logging.basicConfig(
    level=logging.INFO,
    format="[%(asctime)s] %(levelname)s: %(message)s",
    stream=sys.stderr
)
logger = logging.getLogger(__name__)

# Shutdown flag for graceful exit
shutdown_requested = False


def handle_shutdown_signal(signum, frame):
    """Handle SIGTERM/SIGINT for graceful shutdown."""
    global shutdown_requested
    logger.info(f"Received signal {signum}, initiating graceful shutdown")
    shutdown_requested = True


def setup_signal_handlers():
    """Configure signal handlers for graceful shutdown."""
    signal.signal(signal.SIGTERM, handle_shutdown_signal)
    signal.signal(signal.SIGINT, handle_shutdown_signal)
    # Handle broken pipe (Eww closes while we're writing)
    signal.signal(signal.SIGPIPE, signal.SIG_DFL)


def get_window_state_classes(window: Dict[str, Any]) -> str:
    """
    Generate space-separated CSS class string for window states.

    This moves conditional class logic from Yuck to Python for:
    - Better testability (Python unit tests)
    - Cleaner Yuck code (no nested ternaries)
    - No Nix escaping issues with empty strings
    - Separation of concerns (data transformation in backend)

    Args:
        window: Window data from daemon (Sway IPC format)

    Returns:
        Space-separated string of CSS classes (e.g., "window-floating window-hidden")
    """
    classes = []

    if window.get("floating", False):
        classes.append("window-floating")
    if window.get("hidden", False):
        classes.append("window-hidden")
    if window.get("focused", False):
        classes.append("window-focused")

    return " ".join(classes)


def transform_window(window: Dict[str, Any]) -> Dict[str, Any]:
    """
    Transform daemon window data to Eww-friendly schema.

    Args:
        window: Window data from daemon (Sway IPC format)

    Returns:
        WindowInfo dict matching data-model.md specification
    """
    # Extract app_name from class (preferred) or app_id
    app_name = window.get("class", "")
    if not app_name:
        app_name = window.get("app_id", "unknown")

    # Derive scope from marks - check if any mark starts with "scoped:"
    marks = window.get("marks", [])
    scope = "scoped" if any(str(m).startswith("scoped:") for m in marks) else "global"

    # PWA detection - workspaces 50+ are PWAs per CLAUDE.md specification
    # Note: workspace field may be string (including "scratchpad") or int from daemon
    workspace_raw = window.get("workspace", 1)
    try:
        workspace_num = int(workspace_raw) if workspace_raw else 1
    except (ValueError, TypeError):
        # Handle "scratchpad" or other non-numeric workspace values
        workspace_num = 0
    is_pwa = workspace_num >= 50

    # Generate composite state classes (floating, hidden, focused)
    state_classes = get_window_state_classes(window)

    return {
        "id": window.get("id", 0),
        "app_name": app_name,
        # Truncate title to 50 chars for display performance
        "title": window.get("title", "")[:50],
        "project": window.get("project", ""),
        "scope": scope,
        "icon_path": window.get("icon_path", ""),
        "workspace": workspace_raw,  # Keep original value ("scratchpad", "1", etc.)
        "floating": window.get("floating", False),
        "hidden": window.get("hidden", False),
        "focused": window.get("focused", False),
        "is_pwa": is_pwa,
        "state_classes": state_classes,
    }


def transform_workspace(workspace: Dict[str, Any], monitor_name: str) -> Dict[str, Any]:
    """
    Transform daemon workspace data to Eww-friendly schema.

    Args:
        workspace: Workspace data from daemon
        monitor_name: Parent monitor name

    Returns:
        WorkspaceInfo dict matching data-model.md specification
    """
    windows = workspace.get("windows", [])
    transformed_windows = [transform_window(w) for w in windows]

    return {
        "number": workspace.get("num", workspace.get("number", 1)),
        "name": workspace.get("name", ""),
        "visible": workspace.get("visible", False),
        "focused": workspace.get("focused", False),
        "monitor": monitor_name,
        "window_count": len(transformed_windows),
        "windows": transformed_windows,
    }


def transform_monitor(output: Dict[str, Any]) -> Dict[str, Any]:
    """
    Transform daemon output/monitor data to Eww-friendly schema.

    Args:
        output: Output data from daemon (contains name, active status, workspaces)

    Returns:
        MonitorInfo dict matching data-model.md specification
    """
    monitor_name = output.get("name", "unknown")
    workspaces = output.get("workspaces", [])
    transformed_workspaces = [transform_workspace(ws, monitor_name) for ws in workspaces]

    # Determine if monitor has focused workspace
    has_focused = any(ws["focused"] for ws in transformed_workspaces)

    return {
        "name": monitor_name,
        "active": output.get("active", True),
        "focused": has_focused,
        "workspaces": transformed_workspaces,
    }


def validate_and_count(monitors: List[Dict[str, Any]]) -> Dict[str, int]:
    """
    Validate transformed data and compute summary counts.

    Args:
        monitors: List of transformed MonitorInfo dicts

    Returns:
        Dict with keys: monitor_count, workspace_count, window_count
    """
    monitor_count = len(monitors)
    workspace_count = sum(len(m["workspaces"]) for m in monitors)
    window_count = sum(
        ws["window_count"] for m in monitors for ws in m["workspaces"]
    )

    return {
        "monitor_count": monitor_count,
        "workspace_count": workspace_count,
        "window_count": window_count,
    }


def format_friendly_timestamp(timestamp: float) -> str:
    """
    Format Unix timestamp as friendly relative time.

    Args:
        timestamp: Unix timestamp (seconds since epoch)

    Returns:
        Human-friendly string like "Just now", "5 seconds ago", "2 minutes ago"
    """
    now = time.time()
    diff = int(now - timestamp)

    if diff < 5:
        return "Just now"
    elif diff < 60:
        return f"{diff} seconds ago"
    elif diff < 120:
        return "1 minute ago"
    elif diff < 3600:
        minutes = diff // 60
        return f"{minutes} minutes ago"
    elif diff < 7200:
        return "1 hour ago"
    elif diff < 86400:
        hours = diff // 3600
        return f"{hours} hours ago"
    else:
        days = diff // 86400
        return f"{days} day{'s' if days > 1 else ''} ago"


def transform_to_project_view(monitors: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
    """
    Transform monitor-based hierarchy to project-based view.

    Groups all windows by their project association, creating a flat structure:
    projects → windows (with workspace/monitor metadata)

    Args:
        monitors: List of MonitorInfo dicts from transform_monitor()

    Returns:
        List of ProjectInfo dicts with structure:
        [
            {
                "name": "nixos",
                "scope": "scoped",
                "window_count": 5,
                "windows": [...]
            },
            {
                "name": "Global Windows",
                "scope": "global",
                "window_count": 3,
                "windows": [...]
            }
        ]
    """
    # Collect all windows from all monitors/workspaces
    all_windows = []
    for monitor in monitors:
        for workspace in monitor["workspaces"]:
            for window in workspace["windows"]:
                # Add monitor and workspace metadata to window
                window_with_meta = window.copy()
                window_with_meta["monitor_name"] = monitor["name"]
                window_with_meta["workspace_name"] = workspace["name"]
                window_with_meta["workspace_number"] = workspace["number"]
                all_windows.append(window_with_meta)

    # Group windows by project
    projects_dict = {}
    global_windows = []

    for window in all_windows:
        if window["scope"] == "scoped" and window["project"]:
            project_name = window["project"]
            if project_name not in projects_dict:
                projects_dict[project_name] = {
                    "name": project_name,
                    "scope": "scoped",
                    "window_count": 0,
                    "windows": []
                }
            projects_dict[project_name]["windows"].append(window)
            projects_dict[project_name]["window_count"] += 1
        else:
            global_windows.append(window)

    # Convert dict to sorted list (alphabetical by project name)
    projects = sorted(projects_dict.values(), key=lambda p: p["name"].lower())

    # Add global windows as a separate "project" at the end
    if global_windows:
        projects.append({
            "name": "Global Windows",
            "scope": "global",
            "window_count": len(global_windows),
            "windows": global_windows
        })

    return projects


async def query_monitoring_data() -> Dict[str, Any]:
    """
    Query i3pm daemon for monitoring panel data.

    Implements contracts/daemon-query.md specification:
    - Connect to daemon via DaemonClient
    - Call get_window_tree() method
    - Transform response to Eww-friendly schema
    - Handle errors gracefully

    Returns:
        MonitoringPanelState dict with status, monitors, counts, timestamp, error

    Error Handling:
        - Daemon unavailable: Return error state with helpful message
        - Timeout: Return error state with timeout message
        - Unexpected errors: Log and return generic error state
    """
    try:
        # Get daemon socket path from environment (defaults to user runtime dir)
        # Feature 085: Support system service socket path via I3PM_DAEMON_SOCKET env var
        import os
        socket_path_str = os.environ.get("I3PM_DAEMON_SOCKET")
        socket_path = Path(socket_path_str) if socket_path_str else None

        # Create daemon client with 2.0s timeout (per contracts/daemon-query.md)
        client = DaemonClient(socket_path=socket_path, timeout=2.0)

        # Connect to daemon
        await client.connect()

        # Query window tree (monitors → workspaces → windows hierarchy)
        tree_data = await client.get_window_tree()

        # Close connection (stateless pattern per research.md Decision 4)
        await client.close()

        # Transform daemon response to Eww schema
        outputs = tree_data.get("outputs", [])
        monitors = [transform_monitor(output) for output in outputs]

        # Validate and compute summary counts
        counts = validate_and_count(monitors)

        # Transform to project-based view (default view)
        projects = transform_to_project_view(monitors)

        # Get current timestamp for friendly formatting
        current_timestamp = time.time()
        friendly_time = format_friendly_timestamp(current_timestamp)

        # Return success state with project-based view
        return {
            "status": "ok",
            "projects": projects,
            "project_count": len(projects),
            "monitor_count": counts["monitor_count"],
            "workspace_count": counts["workspace_count"],
            "window_count": counts["window_count"],
            "timestamp": current_timestamp,
            "timestamp_friendly": friendly_time,
            "error": None,
        }

    except DaemonError as e:
        # Expected errors: socket not found, timeout, connection lost
        logger.warning(f"Daemon error: {e}")
        error_timestamp = time.time()
        return {
            "status": "error",
            "projects": [],
            "project_count": 0,
            "monitor_count": 0,
            "workspace_count": 0,
            "window_count": 0,
            "timestamp": error_timestamp,
            "timestamp_friendly": format_friendly_timestamp(error_timestamp),
            "error": str(e),
        }

    except Exception as e:
        # Unexpected errors: log for debugging
        logger.error(f"Unexpected error querying daemon: {e}", exc_info=True)
        error_timestamp = time.time()
        return {
            "status": "error",
            "projects": [],
            "project_count": 0,
            "monitor_count": 0,
            "workspace_count": 0,
            "window_count": 0,
            "timestamp": error_timestamp,
            "timestamp_friendly": format_friendly_timestamp(error_timestamp),
            "error": f"Unexpected error: {type(e).__name__}: {e}",
        }


async def query_projects_data() -> Dict[str, Any]:
    """
    Query projects view data.

    Returns project list with metadata and current active project.
    """
    current_timestamp = time.time()
    friendly_time = format_friendly_timestamp(current_timestamp)

    try:
        # Query projects via i3pm CLI
        result = subprocess.run(
            ["i3pm", "project", "list", "--json"],
            capture_output=True,
            text=True,
            timeout=5
        )

        if result.returncode != 0:
            return {
                "status": "error",
                "projects": [],
                "project_count": 0,
                "active_project": None,
                "timestamp": current_timestamp,
                "timestamp_friendly": friendly_time,
                "error": f"i3pm project list failed: {result.stderr}"
            }

        projects_data = json.loads(result.stdout)
        projects = projects_data.get("projects", [])

        # Get active project
        result = subprocess.run(
            ["i3pm", "project", "current"],
            capture_output=True,
            text=True,
            timeout=2
        )
        active_project = result.stdout.strip() if result.returncode == 0 else None

        # Mark active project
        for project in projects:
            project["is_active"] = (project["name"] == active_project)

        return {
            "status": "ok",
            "projects": projects,
            "project_count": len(projects),
            "active_project": active_project,
            "timestamp": current_timestamp,
            "timestamp_friendly": friendly_time,
            "error": None
        }

    except subprocess.TimeoutExpired:
        return {
            "status": "error",
            "projects": [],
            "project_count": 0,
            "active_project": None,
            "timestamp": current_timestamp,
            "timestamp_friendly": friendly_time,
            "error": "i3pm project list timeout"
        }
    except Exception as e:
        return {
            "status": "error",
            "projects": [],
            "project_count": 0,
            "active_project": None,
            "timestamp": current_timestamp,
            "timestamp_friendly": friendly_time,
            "error": f"Projects query failed: {type(e).__name__}: {e}"
        }


async def query_apps_data() -> Dict[str, Any]:
    """
    Query apps view data.

    Returns app registry with configuration and runtime state.
    """
    current_timestamp = time.time()
    friendly_time = format_friendly_timestamp(current_timestamp)

    try:
        # Query app registry via i3pm CLI
        result = subprocess.run(
            ["i3pm", "apps", "list", "--json"],
            capture_output=True,
            text=True,
            timeout=5
        )

        if result.returncode != 0:
            # Fallback: return empty list (apps command might not have --json flag yet)
            apps = []
        else:
            apps_data = json.loads(result.stdout)
            apps = apps_data.get("apps", [])

        # Enhance with runtime state (running instances)
        # Query current windows to match app names
        try:
            client = DaemonClient()
            tree_data = await client.get_window_tree()
            await client.close()

            # Build map of app_name -> window IDs
            app_windows = {}
            for output in tree_data.get("outputs", []):
                for workspace in output.get("workspaces", []):
                    for window in workspace.get("windows", []):
                        app_name = window.get("app_name", "unknown")
                        if app_name not in app_windows:
                            app_windows[app_name] = []
                        app_windows[app_name].append(window.get("id"))

            # Add runtime info to apps
            for app in apps:
                app_name = app.get("name", "")
                app["running_instances"] = len(app_windows.get(app_name, []))
                app["window_ids"] = app_windows.get(app_name, [])

        except Exception as e:
            logger.warning(f"Could not query window state for apps: {e}")
            # Apps will just not have runtime info

        return {
            "status": "ok",
            "apps": apps,
            "app_count": len(apps),
            "timestamp": current_timestamp,
            "timestamp_friendly": friendly_time,
            "error": None
        }

    except Exception as e:
        return {
            "status": "error",
            "apps": [],
            "app_count": 0,
            "timestamp": current_timestamp,
            "timestamp_friendly": friendly_time,
            "error": f"Apps query failed: {type(e).__name__}: {e}"
        }


async def query_health_data() -> Dict[str, Any]:
    """
    Query system health view data.

    Returns daemon status, connection health, and performance metrics.
    """
    current_timestamp = time.time()
    friendly_time = format_friendly_timestamp(current_timestamp)

    health = {
        "daemon_status": "unknown",
        "daemon_uptime": 0,
        "daemon_pid": None,
        "sway_ipc_connected": False,
        "monitor_count": 0,
        "workspace_count": 0,
        "window_count": 0,
        "project_count": 0,
        "errors_24h": 0,
        "warnings_24h": 0,
        "last_error": None
    }

    try:
        # Query daemon status
        result = subprocess.run(
            ["i3pm", "daemon", "status", "--json"],
            capture_output=True,
            text=True,
            timeout=3
        )

        if result.returncode == 0:
            daemon_data = json.loads(result.stdout)
            health["daemon_status"] = daemon_data.get("status", "unknown")
            health["daemon_uptime"] = daemon_data.get("uptime", 0)
            health["daemon_pid"] = daemon_data.get("pid")
            health["sway_ipc_connected"] = daemon_data.get("connected", False)

        # Query window tree for counts
        try:
            client = DaemonClient()
            tree_data = await client.get_window_tree()
            await client.close()

            outputs = tree_data.get("outputs", [])
            health["monitor_count"] = len(outputs)

            for output in outputs:
                workspaces = output.get("workspaces", [])
                health["workspace_count"] += len(workspaces)
                for workspace in workspaces:
                    health["window_count"] += len(workspace.get("windows", []))

        except Exception as e:
            logger.warning(f"Could not query window tree for health: {e}")

        # Query projects count
        result = subprocess.run(
            ["i3pm", "project", "list", "--json"],
            capture_output=True,
            text=True,
            timeout=3
        )

        if result.returncode == 0:
            projects_data = json.loads(result.stdout)
            health["project_count"] = len(projects_data.get("projects", []))

        return {
            "status": "ok",
            "health": health,
            "timestamp": current_timestamp,
            "timestamp_friendly": friendly_time,
            "error": None
        }

    except Exception as e:
        return {
            "status": "error",
            "health": health,
            "timestamp": current_timestamp,
            "timestamp_friendly": friendly_time,
            "error": f"Health query failed: {type(e).__name__}: {e}"
        }


async def stream_monitoring_data():
    """
    Stream monitoring data to stdout on Sway events (deflisten mode).

    Features:
    - Subscribes to window/workspace/output events via i3ipc
    - Outputs JSON on every event (<100ms latency)
    - Heartbeat every 5s to detect stale connections
    - Automatic reconnection with exponential backoff (1s, 2s, 4s, max 10s)
    - Graceful shutdown on SIGTERM/SIGINT/SIGPIPE

    Exit codes:
        0: Graceful shutdown (signal received)
        1: Fatal error (cannot recover)
    """
    if I3Connection is None:
        logger.error("i3ipc.aio module not available - cannot use --listen mode")
        sys.exit(1)

    setup_signal_handlers()
    logger.info("Starting event stream mode (deflisten)")

    reconnect_delay = 1.0  # Start with 1s delay
    max_reconnect_delay = 10.0
    last_update = 0.0
    heartbeat_interval = 5.0

    while not shutdown_requested:
        try:
            logger.info("Connecting to Sway IPC...")
            ipc = await I3Connection().connect()
            logger.info("Connected to Sway IPC")

            # Reset reconnect delay on successful connection
            reconnect_delay = 1.0

            # Query and output initial state
            data = await query_monitoring_data()
            print(json.dumps(data, separators=(",", ":")), flush=True)
            last_update = time.time()
            logger.info("Sent initial state")

            # Subscribe to relevant events
            def on_window_event(ipc, event):
                """Handle window events (new, close, focus, etc.)"""
                asyncio.create_task(refresh_and_output())

            def on_workspace_event(ipc, event):
                """Handle workspace events (focus, init, empty, etc.)"""
                asyncio.create_task(refresh_and_output())

            def on_output_event(ipc, event):
                """Handle output events (monitor connect/disconnect)"""
                asyncio.create_task(refresh_and_output())

            async def refresh_and_output():
                """Query daemon and output updated JSON."""
                nonlocal last_update
                try:
                    data = await query_monitoring_data()
                    print(json.dumps(data, separators=(",", ":")), flush=True)
                    last_update = time.time()
                except Exception as e:
                    logger.warning(f"Error refreshing data: {e}")

            # Register event handlers
            ipc.on('window', on_window_event)
            ipc.on('workspace', on_workspace_event)
            ipc.on('output', on_output_event)

            # Event loop with heartbeat
            while not shutdown_requested:
                # Send heartbeat if no updates in last N seconds
                if time.time() - last_update > heartbeat_interval:
                    logger.debug("Sending heartbeat")
                    await refresh_and_output()

                # Sleep briefly to avoid busy loop
                await asyncio.sleep(0.5)

        except ConnectionError as e:
            logger.warning(f"Connection lost: {e}, reconnecting in {reconnect_delay}s")
            await asyncio.sleep(reconnect_delay)
            # Exponential backoff
            reconnect_delay = min(reconnect_delay * 2, max_reconnect_delay)

        except Exception as e:
            logger.error(f"Unexpected error in stream loop: {e}", exc_info=True)
            await asyncio.sleep(reconnect_delay)
            reconnect_delay = min(reconnect_delay * 2, max_reconnect_delay)

    logger.info("Shutdown complete")
    sys.exit(0)


async def main():
    """
    Main entry point for backend script.

    Modes:
    - windows (default): Window/project hierarchy view
    - projects: Project list view
    - apps: Application registry view
    - health: System health view
    - Stream (--listen): Continuous event stream (deflisten mode)

    Exit codes:
        0: Success (status: "ok" or graceful shutdown)
        1: Error (status: "error" or fatal error)
    """
    # Parse arguments
    parser = argparse.ArgumentParser(description="Monitoring panel data backend")
    parser.add_argument(
        "--mode",
        choices=["windows", "projects", "apps", "health"],
        default="windows",
        help="View mode (default: windows)"
    )
    parser.add_argument(
        "--listen",
        action="store_true",
        help="Stream mode (deflisten) - only works with windows mode"
    )
    args = parser.parse_args()

    # Stream mode (only for windows view)
    if args.listen:
        if args.mode != "windows":
            logger.error("--listen flag only works with windows mode")
            sys.exit(1)
        await stream_monitoring_data()
        return

    # One-shot mode - route to appropriate query function
    try:
        if args.mode == "windows":
            data = await query_monitoring_data()
        elif args.mode == "projects":
            data = await query_projects_data()
        elif args.mode == "apps":
            data = await query_apps_data()
        elif args.mode == "health":
            data = await query_health_data()
        else:
            raise ValueError(f"Unknown mode: {args.mode}")

        # Output single-line JSON (no formatting for Eww parsing performance)
        # Use separators parameter to minimize output size
        print(json.dumps(data, separators=(",", ":")))

        # Exit with appropriate code
        sys.exit(0 if data["status"] == "ok" else 1)

    except Exception as e:
        # Catastrophic failure - output error JSON and exit with error code
        logger.critical(f"Fatal error in main(): {e}", exc_info=True)
        error_timestamp = time.time()
        error_data = {
            "status": "error",
            "data": {},
            "timestamp": error_timestamp,
            "timestamp_friendly": format_friendly_timestamp(error_timestamp),
            "error": f"Fatal error: {type(e).__name__}: {e}",
        }
        print(json.dumps(error_data, separators=(",", ":")))
        sys.exit(1)


if __name__ == "__main__":
    asyncio.run(main())
