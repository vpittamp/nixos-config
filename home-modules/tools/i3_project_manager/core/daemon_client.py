"""Daemon IPC client for communicating with i3-project-event-listener daemon.

This module provides async communication with the existing event-driven daemon
using JSON-RPC 2.0 over Unix domain socket.
"""

import asyncio
import json
import os
from pathlib import Path
from typing import Any, Dict, Optional


class DaemonError(Exception):
    """Exception raised for daemon communication errors."""

    pass


def get_default_socket_path() -> Path:
    """Get default daemon socket path (systemd runtime directory)."""
    runtime_dir = os.environ.get("XDG_RUNTIME_DIR") or f"/run/user/{os.getuid()}"
    return Path(runtime_dir) / "i3-project-daemon" / "ipc.sock"


class DaemonClient:
    """IPC client for i3-project-event-listener daemon.

    Communicates with the daemon using JSON-RPC 2.0 over Unix socket.
    Provides async methods for querying daemon status, events, and windows.
    """

    def __init__(
        self,
        socket_path: Optional[Path] = None,
        timeout: float = 5.0,
    ):
        """Initialize daemon client.

        Args:
            socket_path: Path to daemon Unix socket (default: XDG_RUNTIME_DIR/i3-project-daemon/ipc.sock)
            timeout: Default timeout for requests in seconds
        """
        self.socket_path = socket_path or get_default_socket_path()
        self.timeout = timeout
        self._reader: Optional[asyncio.StreamReader] = None
        self._writer: Optional[asyncio.StreamWriter] = None
        self._request_id = 0

    async def connect(self) -> None:
        """Connect to daemon socket.

        Raises:
            DaemonError: If connection fails
        """
        try:
            self._reader, self._writer = await asyncio.wait_for(
                asyncio.open_unix_connection(str(self.socket_path)),
                timeout=self.timeout,
            )
        except asyncio.TimeoutError:
            raise DaemonError(
                f"Connection timeout: daemon not responding at {self.socket_path}"
            )
        except FileNotFoundError:
            raise DaemonError(
                f"Daemon socket not found: {self.socket_path}\n"
                "Is the daemon running? Check: systemctl --user status i3-project-event-listener"
            )
        except Exception as e:
            raise DaemonError(f"Failed to connect to daemon: {e}")

    async def close(self) -> None:
        """Close connection to daemon."""
        if self._writer:
            self._writer.close()
            await self._writer.wait_closed()
            self._reader = None
            self._writer = None

    async def call(
        self, method: str, params: Optional[Dict[str, Any]] = None
    ) -> Dict[str, Any]:
        """Send JSON-RPC request to daemon.

        Args:
            method: RPC method name
            params: Optional parameters dict

        Returns:
            Response result dict

        Raises:
            DaemonError: If request fails or daemon returns error
        """
        if not self._reader or not self._writer:
            await self.connect()

        self._request_id += 1
        request = {
            "jsonrpc": "2.0",
            "method": method,
            "params": params or {},
            "id": self._request_id,
        }

        try:
            # Send request
            request_json = json.dumps(request) + "\n"
            self._writer.write(request_json.encode())
            await asyncio.wait_for(self._writer.drain(), timeout=self.timeout)

            # Read response
            response_line = await asyncio.wait_for(
                self._reader.readline(), timeout=self.timeout
            )
            response = json.loads(response_line.decode())

            # Check for error
            if "error" in response:
                error = response["error"]
                raise DaemonError(
                    f"Daemon error: {error.get('message', 'Unknown error')}"
                )

            return response.get("result", {})

        except asyncio.TimeoutError:
            raise DaemonError(f"Request timeout: method '{method}' took too long")
        except json.JSONDecodeError as e:
            raise DaemonError(f"Invalid JSON response from daemon: {e}")
        except Exception as e:
            if isinstance(e, DaemonError):
                raise
            raise DaemonError(f"Communication error: {e}")

    async def get_status(self) -> Dict[str, Any]:
        """Get daemon status and active project.

        Returns:
            Status dict with keys:
                - status: str - Status string ("running")
                - connected: bool - Whether daemon is connected to i3
                - uptime_seconds: float - Daemon uptime in seconds
                - active_project: Optional[str] - Active project name
                - window_count: int - Number of tracked windows
                - workspace_count: int - Number of workspaces
                - event_count: int - Total events processed
                - error_count: int - Total errors encountered

        Raises:
            DaemonError: If request fails
        """
        return await self.call("get_status")

    async def get_active_project(self) -> Optional[str]:
        """Get current active project name.

        Returns:
            Active project name, or None if no project active

        Raises:
            DaemonError: If request fails
        """
        status = await self.get_status()
        return status.get("active_project")

    async def get_events(
        self, limit: int = 20, event_type: Optional[str] = None, since_id: Optional[int] = None
    ) -> Dict[str, Any]:
        """Get recent daemon events.

        Args:
            limit: Maximum number of events to return (default 20)
            event_type: Filter by type: "window", "workspace", "tick", "output"
            since_id: Only return events with ID greater than this value

        Returns:
            Events dict with keys:
                - events: List[dict] - Event records
                - total: int - Total event count

        Raises:
            DaemonError: If request fails
        """
        params = {"limit": limit}
        if event_type:
            params["event_type"] = event_type
        if since_id is not None:
            params["since_id"] = since_id

        return await self.call("get_events", params)

    async def get_windows(self, project: Optional[str] = None) -> Dict[str, Any]:
        """Get tracked windows.

        Args:
            project: Optional project name to filter by

        Returns:
            Windows dict with keys:
                - windows: List[dict] - Window records
                - total: int - Total window count

        Raises:
            DaemonError: If request fails
        """
        params = {}
        if project:
            params["project"] = project

        return await self.call("get_windows", params)

    async def get_window_tree(self) -> Dict[str, Any]:
        """Get hierarchical window state tree (monitors → workspaces → windows).

        This queries the daemon for complete window state organized by output and workspace.
        The daemon queries i3 IPC (GET_TREE, GET_WORKSPACES, GET_OUTPUTS) and returns
        a hierarchical structure suitable for tree visualization.

        Returns:
            Window tree dict with keys:
                - outputs: List[dict] - Output/monitor nodes, each containing:
                    - name: str - Output name (e.g., "eDP-1")
                    - active: bool - Whether output is active
                    - rect: dict - Output geometry (x, y, width, height)
                    - workspaces: List[dict] - Workspace nodes, each containing:
                        - number: int - Workspace number
                        - name: str - Workspace name
                        - focused: bool - Whether workspace is focused
                        - visible: bool - Whether workspace is visible
                        - windows: List[dict] - Window nodes with full WindowState data
                - total_windows: int - Total window count across all outputs

        Raises:
            DaemonError: If request fails or daemon not connected to i3

        Example:
            ```python
            async with DaemonClient() as client:
                tree = await client.get_window_tree()
                for output in tree['outputs']:
                    print(f"Monitor: {output['name']}")
                    for ws in output['workspaces']:
                        print(f"  Workspace {ws['number']}: {len(ws['windows'])} windows")
            ```
        """
        return await self.call("get_window_tree")

    async def subscribe_window_events(self):
        """Subscribe to real-time window events from daemon.

        Returns an async iterator that yields window event notifications.
        Events include: new, close, focus, title, move, floating, fullscreen_mode, etc.

        Yields:
            Event dict with keys:
                - event_type: str - Type of event ("window", "workspace", "output")
                - change: str - Specific change ("new", "close", "focus", "title", etc.)
                - window: Optional[dict] - Window data (for window events)
                - workspace: Optional[dict] - Workspace data (for workspace events)
                - output: Optional[dict] - Output data (for output events)
                - timestamp: float - Event timestamp

        Raises:
            DaemonError: If subscription fails

        Example:
            ```python
            async with DaemonClient() as client:
                async for event in client.subscribe_window_events():
                    if event['event_type'] == 'window' and event['change'] == 'new':
                        print(f"New window: {event['window']['class']}")
            ```

        Note:
            This is a long-lived connection. Make sure to handle cancellation properly.
            The iterator will run until the connection is closed or an error occurs.
        """
        if not self._reader or not self._writer:
            await self.connect()

        # Send subscription request
        self._request_id += 1
        request = {
            "jsonrpc": "2.0",
            "method": "subscribe_events",
            "params": {"event_types": ["window", "workspace", "output"]},
            "id": self._request_id,
        }

        try:
            # Send subscription request
            request_json = json.dumps(request) + "\n"
            self._writer.write(request_json.encode())
            await asyncio.wait_for(self._writer.drain(), timeout=self.timeout)

            # Read subscription confirmation
            response_line = await asyncio.wait_for(
                self._reader.readline(), timeout=self.timeout
            )
            response = json.loads(response_line.decode())

            if "error" in response:
                error = response["error"]
                raise DaemonError(
                    f"Subscription failed: {error.get('message', 'Unknown error')}"
                )

            # Now read events continuously
            while True:
                try:
                    event_line = await self._reader.readline()
                    if not event_line:
                        # Connection closed
                        break

                    event = json.loads(event_line.decode())

                    # Skip non-event messages (RPC responses)
                    if "jsonrpc" in event and "method" not in event:
                        continue

                    # Yield event notification
                    if "method" in event and event["method"] == "event":
                        yield event.get("params", {})

                except json.JSONDecodeError:
                    # Skip invalid JSON lines
                    continue
                except asyncio.CancelledError:
                    # Clean cancellation
                    break
                except Exception as e:
                    raise DaemonError(f"Event stream error: {e}")

        except asyncio.TimeoutError:
            raise DaemonError("Subscription timeout")
        except Exception as e:
            if isinstance(e, DaemonError):
                raise
            raise DaemonError(f"Subscription error: {e}")

    async def ping(self) -> bool:
        """Ping daemon to check if it's alive.

        Returns:
            True if daemon responds, False otherwise
        """
        try:
            await self.get_status()
            return True
        except DaemonError:
            return False

    async def __aenter__(self):
        """Async context manager entry."""
        await self.connect()
        return self

    async def __aexit__(self, exc_type, exc_val, exc_tb):
        """Async context manager exit."""
        await self.close()


class DaemonConnectionPool:
    """Connection pool for daemon clients (reuse connections across CLI calls).

    This avoids creating/destroying connections for every CLI command,
    improving performance for rapid sequential calls.
    """

    def __init__(self, max_idle_time: float = 60.0):
        """Initialize connection pool.

        Args:
            max_idle_time: Maximum time to keep idle connection alive (seconds)
        """
        self._client: Optional[DaemonClient] = None
        self._last_used: float = 0
        self._max_idle_time = max_idle_time

    async def get_client(self) -> DaemonClient:
        """Get a daemon client (reuse existing or create new).

        Returns:
            Connected DaemonClient instance
        """
        import time

        now = time.time()

        # Close stale connection
        if self._client and (now - self._last_used) > self._max_idle_time:
            await self._client.close()
            self._client = None

        # Create new connection if needed
        if not self._client:
            self._client = DaemonClient()
            await self._client.connect()

        self._last_used = now
        return self._client

    async def close(self) -> None:
        """Close pooled connection."""
        if self._client:
            await self._client.close()
            self._client = None


# Global connection pool for CLI commands
_global_pool = DaemonConnectionPool()


async def get_daemon_client() -> DaemonClient:
    """Get a daemon client from global pool.

    This is the recommended way to get a daemon client for CLI commands
    as it reuses connections efficiently.

    Returns:
        Connected DaemonClient instance

    Example:
        ```python
        client = await get_daemon_client()
        status = await client.get_status()
        ```
    """
    return await _global_pool.get_client()
