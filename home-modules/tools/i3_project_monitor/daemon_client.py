"""JSON-RPC client for daemon communication.

Handles connection, reconnection, and JSON-RPC requests to the i3 project daemon.
"""

import asyncio
import json
import logging
import os
from datetime import datetime
from pathlib import Path
from typing import Any, Dict, Optional, AsyncIterator, List

from i3ipc import aio as i3ipc_aio

from .models import ConnectionState, OutputState, WorkspaceAssignment

logger = logging.getLogger(__name__)


class DaemonClient:
    """JSON-RPC client for i3 project daemon communication."""

    def __init__(self, socket_path: Optional[str] = None):
        """Initialize daemon client.

        Args:
            socket_path: Path to daemon Unix socket (default: systemd runtime dir)
        """
        if socket_path is None:
            runtime_dir = os.environ.get("XDG_RUNTIME_DIR", f"/run/user/{os.getuid()}")
            socket_path = f"{runtime_dir}/i3-project-daemon/ipc.sock"

        self.state = ConnectionState(socket_path=socket_path)
        self.reader: Optional[asyncio.StreamReader] = None
        self.writer: Optional[asyncio.StreamWriter] = None
        self.request_id: int = 0

        # i3 IPC connection for direct queries (Feature 018)
        self.i3: Optional[i3ipc_aio.Connection] = None

    async def connect(self) -> None:
        """Connect to daemon socket.

        Raises:
            ConnectionError: If connection fails
        """
        try:
            self.reader, self.writer = await asyncio.open_unix_connection(self.state.socket_path)
            self.state.connected = True
            self.state.last_success_at = datetime.now()
            self.state.connection_attempts = 0
            logger.info(f"Connected to daemon at {self.state.socket_path}")

        except Exception as e:
            self.state.connected = False
            self.state.last_error = str(e)
            self.state.last_failure_at = datetime.now()
            self.state.connection_attempts += 1
            logger.error(f"Failed to connect to daemon: {e}")
            raise ConnectionError(f"Failed to connect to daemon: {e}")

    async def connect_with_retry(self) -> None:
        """Connect to daemon with exponential backoff retry.

        Raises:
            ConnectionError: If all retry attempts fail
        """
        while self.state.should_retry():
            try:
                await self.connect()
                return  # Success
            except ConnectionError:
                if not self.state.should_retry():
                    raise

                delay = self.state.get_retry_delay()
                logger.warning(f"Retry {self.state.connection_attempts}/{self.state.max_retries} in {delay}s...")
                await asyncio.sleep(delay)

        raise ConnectionError(f"Failed to connect after {self.state.max_retries} attempts")

    async def disconnect(self) -> None:
        """Close connection to daemon."""
        if self.writer:
            self.writer.close()
            await self.writer.wait_closed()
            self.writer = None
            self.reader = None

        self.state.connected = False
        logger.info("Disconnected from daemon")

    async def request(self, method: str, params: Optional[Dict[str, Any]] = None) -> Any:
        """Send JSON-RPC request and wait for response.

        Args:
            method: JSON-RPC method name
            params: Optional method parameters

        Returns:
            JSON-RPC result field

        Raises:
            ConnectionError: If not connected or connection lost
            ValueError: If daemon returns error response
        """
        if not self.state.connected or not self.writer or not self.reader:
            raise ConnectionError("Not connected to daemon")

        self.request_id += 1
        request = {
            "jsonrpc": "2.0",
            "method": method,
            "params": params or {},
            "id": self.request_id
        }

        try:
            # Send request
            message = json.dumps(request).encode() + b"\n"
            self.writer.write(message)
            await self.writer.drain()

            # Read response
            data = await self.reader.readline()
            if not data:
                raise ConnectionError("Connection closed by daemon")

            response = json.loads(data.decode())

            # Check for error
            if "error" in response:
                error = response["error"]
                raise ValueError(f"Daemon error {error['code']}: {error['message']}")

            return response.get("result")

        except (ConnectionError, BrokenPipeError, asyncio.IncompleteReadError) as e:
            self.state.connected = False
            self.state.last_error = str(e)
            logger.error(f"Connection lost during request: {e}")
            raise ConnectionError(f"Connection lost: {e}")

    async def get_status(self) -> Dict[str, Any]:
        """Query daemon status.

        Returns:
            Status dictionary from daemon
        """
        return await self.request("get_status")

    async def get_active_project(self) -> Dict[str, Any]:
        """Get active project info.

        Returns:
            Active project dictionary
        """
        return await self.request("get_active_project")

    async def get_projects(self) -> Dict[str, Any]:
        """List all projects.

        Returns:
            Projects dictionary
        """
        return await self.request("get_projects")

    async def get_windows(self, project: Optional[str] = None) -> Dict[str, Any]:
        """Query windows with optional project filter.

        Args:
            project: Optional project name filter

        Returns:
            Windows dictionary
        """
        params = {"project": project} if project else {}
        return await self.request("get_windows", params)

    async def get_events(self, limit: int = 100, event_type: Optional[str] = None) -> Dict[str, Any]:
        """Query recent events.

        Args:
            limit: Maximum number of events to return
            event_type: Optional event type filter (e.g., "window", "workspace")

        Returns:
            Events dictionary with events list and stats
        """
        params = {"limit": limit}
        if event_type:
            params["event_type"] = event_type

        return await self.request("get_events", params)

    async def list_monitors(self) -> Dict[str, Any]:
        """List connected monitor clients.

        Returns:
            Monitors dictionary
        """
        return await self.request("list_monitors")

    async def subscribe_events(self, event_types: Optional[list[str]] = None) -> Dict[str, Any]:
        """Subscribe to event stream.

        Args:
            event_types: Optional list of event types to subscribe to (empty = all)

        Returns:
            Subscription confirmation
        """
        params = {"subscribe": True}
        if event_types:
            params["event_types"] = event_types

        return await self.request("subscribe_events", params)

    async def unsubscribe_events(self) -> Dict[str, Any]:
        """Unsubscribe from event stream.

        Returns:
            Unsubscribe confirmation
        """
        return await self.request("subscribe_events", {"subscribe": False})

    async def stream_events(self) -> AsyncIterator[Dict[str, Any]]:
        """Stream events from daemon after subscribing.

        Yields:
            Event notification dictionaries

        Raises:
            ConnectionError: If not connected
        """
        if not self.state.connected or not self.reader:
            raise ConnectionError("Not connected to daemon")

        logger.info("Starting event stream")

        while True:
            try:
                data = await self.reader.readline()
                if not data:
                    logger.warning("Connection closed by daemon")
                    break

                message = json.loads(data.decode())

                # Handle JSON-RPC notification (no id field)
                if "method" in message and message.get("method") == "event_notification":
                    yield message.get("params", {})

            except (json.JSONDecodeError, asyncio.IncompleteReadError) as e:
                logger.error(f"Error reading event stream: {e}")
                break
            except Exception as e:
                logger.error(f"Unexpected error in event stream: {e}")
                break

        self.state.connected = False
        logger.info("Event stream ended")

    async def connect_i3(self) -> None:
        """Connect to i3 IPC for direct queries (Feature 018).

        This creates a separate i3 IPC connection for querying i3 state directly
        (GET_OUTPUTS, GET_WORKSPACES, GET_TREE) without going through the daemon.

        Raises:
            ConnectionError: If i3 connection fails
        """
        try:
            self.i3 = await i3ipc_aio.Connection().connect()
            logger.info("Connected to i3 IPC")
        except Exception as e:
            logger.error(f"Failed to connect to i3 IPC: {e}")
            raise ConnectionError(f"Failed to connect to i3 IPC: {e}")

    async def disconnect_i3(self) -> None:
        """Disconnect from i3 IPC."""
        if self.i3:
            # i3ipc.aio doesn't have an explicit disconnect, connections are auto-managed
            self.i3 = None
            logger.info("Disconnected from i3 IPC")

    async def get_i3_outputs(self) -> List[OutputState]:
        """Query i3 outputs using GET_OUTPUTS IPC (Feature 018).

        Returns:
            List of OutputState objects from i3

        Raises:
            ConnectionError: If not connected to i3
        """
        if not self.i3:
            await self.connect_i3()

        try:
            outputs = await self.i3.get_outputs()
            return [OutputState.from_i3_output(output) for output in outputs]
        except Exception as e:
            logger.error(f"Failed to get i3 outputs: {e}")
            raise ConnectionError(f"Failed to get i3 outputs: {e}")

    async def get_i3_workspaces(self) -> List[WorkspaceAssignment]:
        """Query i3 workspaces using GET_WORKSPACES IPC (Feature 018).

        Returns:
            List of WorkspaceAssignment objects from i3

        Raises:
            ConnectionError: If not connected to i3
        """
        if not self.i3:
            await self.connect_i3()

        try:
            workspaces = await self.i3.get_workspaces()
            return [WorkspaceAssignment.from_i3_workspace(ws) for ws in workspaces]
        except Exception as e:
            logger.error(f"Failed to get i3 workspaces: {e}")
            raise ConnectionError(f"Failed to get i3 workspaces: {e}")
