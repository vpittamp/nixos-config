"""JSON-RPC IPC server for daemon queries.

Exposes daemon state via UNIX socket with systemd socket activation support.
"""

import asyncio
import json
import logging
import os
import socket
from pathlib import Path
from typing import Any, Dict, Optional

from .state import StateManager

logger = logging.getLogger(__name__)


class IPCServer:
    """JSON-RPC IPC server for CLI tool queries."""

    def __init__(self, state_manager: StateManager) -> None:
        """Initialize IPC server.

        Args:
            state_manager: StateManager instance for queries
        """
        self.state_manager = state_manager
        self.server: Optional[asyncio.Server] = None
        self.clients: set[asyncio.StreamWriter] = set()

    @classmethod
    async def from_systemd_socket(cls, state_manager: StateManager) -> "IPCServer":
        """Create IPC server using systemd socket activation.

        Args:
            state_manager: StateManager instance

        Returns:
            IPCServer instance with inherited socket
        """
        server = cls(state_manager)

        # Check if systemd passed us a socket
        listen_fds = int(os.environ.get("LISTEN_FDS", 0))
        if listen_fds > 0:
            # Socket FD starts at 3 (0=stdin, 1=stdout, 2=stderr)
            fd = 3
            logger.info(f"Using systemd socket activation (FD {fd})")

            # Create server from existing socket
            sock = socket.socket(fileno=fd)
            await server.start(sock)
        else:
            logger.warning("No systemd socket provided, creating new socket")
            await server.start(None)

        return server

    async def start(self, sock: Optional[socket.socket] = None) -> None:
        """Start IPC server.

        Args:
            sock: Existing socket to use (from systemd), or None to create new
        """
        if sock:
            # Use provided socket (from systemd)
            self.server = await asyncio.start_unix_server(
                self._handle_client, sock=sock  # type: ignore
            )
        else:
            # Create new socket
            socket_path = Path.home() / ".cache" / "i3-project-daemon" / "ipc.sock"
            socket_path.parent.mkdir(parents=True, exist_ok=True)

            # Remove old socket if it exists
            if socket_path.exists():
                socket_path.unlink()

            self.server = await asyncio.start_unix_server(
                self._handle_client, path=str(socket_path)
            )
            logger.info(f"IPC server listening on {socket_path}")

    async def stop(self) -> None:
        """Stop IPC server and close all connections."""
        if self.server:
            self.server.close()
            await self.server.wait_closed()

        # Close all client connections
        for writer in self.clients:
            writer.close()
            await writer.wait_closed()

        logger.info("IPC server stopped")

    async def _handle_client(
        self, reader: asyncio.StreamReader, writer: asyncio.StreamWriter
    ) -> None:
        """Handle a client connection.

        Args:
            reader: Stream reader for receiving requests
            writer: Stream writer for sending responses
        """
        self.clients.add(writer)
        addr = writer.get_extra_info("peername")
        logger.debug(f"Client connected: {addr}")

        try:
            while True:
                # Read JSON-RPC request
                data = await reader.readline()
                if not data:
                    break

                try:
                    request = json.loads(data.decode())
                    response = await self._handle_request(request)
                    writer.write(json.dumps(response).encode() + b"\n")
                    await writer.drain()

                except json.JSONDecodeError as e:
                    error_response = {
                        "jsonrpc": "2.0",
                        "error": {"code": -32700, "message": "Parse error"},
                        "id": None,
                    }
                    writer.write(json.dumps(error_response).encode() + b"\n")
                    await writer.drain()

        except Exception as e:
            logger.error(f"Error handling client: {e}")

        finally:
            self.clients.remove(writer)
            writer.close()
            await writer.wait_closed()
            logger.debug(f"Client disconnected: {addr}")

    async def _handle_request(self, request: Dict[str, Any]) -> Dict[str, Any]:
        """Handle a JSON-RPC request.

        Args:
            request: JSON-RPC request dictionary

        Returns:
            JSON-RPC response dictionary
        """
        method = request.get("method")
        params = request.get("params", {})
        request_id = request.get("id")

        try:
            # Dispatch to handler method
            if method == "get_status":
                result = await self._get_status()
            elif method == "get_active_project":
                result = await self._get_active_project()
            elif method == "get_projects":
                result = await self._get_projects()
            elif method == "get_windows":
                result = await self._get_windows(params)
            elif method == "switch_project":
                result = await self._switch_project(params)
            elif method == "get_events":
                result = await self._get_events(params)
            elif method == "reload_config":
                result = await self._reload_config()
            else:
                return {
                    "jsonrpc": "2.0",
                    "error": {"code": -32601, "message": f"Method not found: {method}"},
                    "id": request_id,
                }

            return {"jsonrpc": "2.0", "result": result, "id": request_id}

        except Exception as e:
            logger.error(f"Error handling request {method}: {e}")
            return {
                "jsonrpc": "2.0",
                "error": {"code": -32603, "message": str(e)},
                "id": request_id,
            }

    async def _get_status(self) -> Dict[str, Any]:
        """Get daemon status."""
        stats = await self.state_manager.get_stats()
        return {
            "status": "running",
            "connected": self.state_manager.state.is_connected,
            **stats,
        }

    async def _get_active_project(self) -> Dict[str, Any]:
        """Get active project info."""
        project_name = await self.state_manager.get_active_project()
        return {
            "project_name": project_name,
            "is_global": project_name is None,
        }

    async def _get_projects(self) -> Dict[str, Any]:
        """List all projects with window counts."""
        projects = self.state_manager.state.projects
        result = {}

        for name, config in projects.items():
            windows = await self.state_manager.get_windows_by_project(name)
            result[name] = {
                "display_name": config.display_name,
                "icon": config.icon,
                "directory": str(config.directory),
                "window_count": len(windows),
            }

        return {"projects": result}

    async def _get_windows(self, params: Dict[str, Any]) -> Dict[str, Any]:
        """Query windows with filters."""
        project = params.get("project")

        if project:
            windows = await self.state_manager.get_windows_by_project(project)
        else:
            windows = list(self.state_manager.state.window_map.values())

        return {
            "windows": [
                {
                    "window_id": w.window_id,
                    "class": w.window_class,
                    "title": w.window_title,
                    "project": w.project,
                    "workspace": w.workspace,
                }
                for w in windows
            ]
        }

    async def _switch_project(self, params: Dict[str, Any]) -> Dict[str, Any]:
        """Trigger project switch."""
        project_name = params.get("project_name")
        # Trigger via tick event
        # TODO: Implement project switch trigger
        return {"success": True, "message": f"Switched to project: {project_name}"}

    async def _get_events(self, params: Dict[str, Any]) -> Dict[str, Any]:
        """Return recent events for diagnostics."""
        limit = params.get("limit", 100)
        # TODO: Implement event queue
        return {"events": []}

    async def _reload_config(self) -> Dict[str, Any]:
        """Reload project configs from disk."""
        # TODO: Implement config reload
        return {"success": True, "message": "Config reloaded"}
