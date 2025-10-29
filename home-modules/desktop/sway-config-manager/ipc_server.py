"""
IPC Server for Sway Configuration Manager

JSON-RPC server for configuration management commands.
"""

import asyncio
import json
import logging
from pathlib import Path
from typing import Any, Dict, Optional

logger = logging.getLogger(__name__)


class IPCServer:
    """JSON-RPC IPC server for configuration management."""

    def __init__(self, daemon):
        """
        Initialize IPC server.

        Args:
            daemon: SwayConfigDaemon instance
        """
        self.daemon = daemon
        self.socket_path = Path.home() / ".cache" / "sway-config-manager" / "ipc.sock"
        self.server: Optional[asyncio.AbstractServer] = None
        self.clients = set()

    async def start(self):
        """Start IPC server."""
        # Ensure socket directory exists
        self.socket_path.parent.mkdir(parents=True, exist_ok=True)

        # Remove existing socket
        if self.socket_path.exists():
            self.socket_path.unlink()

        # Start Unix socket server
        self.server = await asyncio.start_unix_server(
            self._handle_client,
            path=str(self.socket_path)
        )

        logger.info(f"IPC server listening on {self.socket_path}")

    async def stop(self):
        """Stop IPC server."""
        if self.server:
            self.server.close()
            await self.server.wait_closed()

        if self.socket_path.exists():
            self.socket_path.unlink()

        logger.info("IPC server stopped")

    async def _handle_client(self, reader: asyncio.StreamReader, writer: asyncio.StreamWriter):
        """
        Handle client connection.

        Args:
            reader: Stream reader
            writer: Stream writer
        """
        addr = writer.get_extra_info('peername')
        logger.debug(f"Client connected: {addr}")

        self.clients.add(writer)

        try:
            while True:
                # Read JSON-RPC request
                data = await reader.readline()
                if not data:
                    break

                request = json.loads(data.decode())
                response = await self._handle_request(request)

                # Send response
                writer.write((json.dumps(response) + "\n").encode())
                await writer.drain()

        except Exception as e:
            logger.error(f"Client handler error: {e}")
        finally:
            self.clients.remove(writer)
            writer.close()
            await writer.wait_closed()
            logger.debug(f"Client disconnected: {addr}")

    async def _handle_request(self, request: Dict[str, Any]) -> Dict[str, Any]:
        """
        Handle JSON-RPC request.

        Args:
            request: JSON-RPC request dict

        Returns:
            JSON-RPC response dict
        """
        method = request.get("method")
        params = request.get("params", {})
        request_id = request.get("id")

        logger.debug(f"Received request: {method}")

        try:
            # Route to handler
            if method == "config_reload":
                result = await self._handle_config_reload(params)
            elif method == "config_validate":
                result = await self._handle_config_validate(params)
            elif method == "config_rollback":
                result = await self._handle_config_rollback(params)
            elif method == "config_get_versions":
                result = await self._handle_config_get_versions(params)
            elif method == "config_show":
                result = await self._handle_config_show(params)
            elif method == "config_get_conflicts":
                result = await self._handle_config_get_conflicts(params)
            elif method == "config_watch_start":
                result = await self._handle_config_watch_start(params)
            elif method == "config_watch_stop":
                result = await self._handle_config_watch_stop(params)
            elif method == "ping":
                result = {"status": "ok"}
            else:
                return {
                    "jsonrpc": "2.0",
                    "error": {"code": -32601, "message": f"Method not found: {method}"},
                    "id": request_id
                }

            return {
                "jsonrpc": "2.0",
                "result": result,
                "id": request_id
            }

        except Exception as e:
            logger.error(f"Error handling {method}: {e}")
            return {
                "jsonrpc": "2.0",
                "error": {"code": -32603, "message": str(e)},
                "id": request_id
            }

    async def _handle_config_reload(self, params: Dict[str, Any]) -> Dict[str, Any]:
        """Handle config_reload request."""
        files = params.get("files")  # Optional: specific files to reload
        validate_only = params.get("validate_only", False)
        skip_commit = params.get("skip_commit", False)

        if not self.daemon.reload_manager:
            return {
                "success": False,
                "error": "Reload manager not initialized"
            }

        # Use reload manager for two-phase commit
        result = await self.daemon.reload_manager.reload_configuration(
            validate_only=validate_only,
            skip_commit=skip_commit,
            files=files
        )

        return result

    async def _handle_config_validate(self, params: Dict[str, Any]) -> Dict[str, Any]:
        """Handle config_validate request."""
        files = params.get("files")
        strict = params.get("strict", False)

        # Load configurations
        keybindings = self.daemon.loader.load_keybindings_toml()
        window_rules = self.daemon.loader.load_window_rules_json()
        workspace_assignments = self.daemon.loader.load_workspace_assignments_json()

        # Validate
        errors = self.daemon.validator.validate_semantics(
            keybindings, window_rules, workspace_assignments
        )

        return {
            "valid": len(errors) == 0,
            "errors": [e.dict() for e in errors],
            "warnings": []
        }

    async def _handle_config_rollback(self, params: Dict[str, Any]) -> Dict[str, Any]:
        """Handle config_rollback request."""
        commit_hash = params.get("commit_hash")
        no_reload = params.get("no_reload", False)

        if not commit_hash:
            return {"success": False, "error": "commit_hash required"}

        # Rollback to commit
        success = self.daemon.rollback.rollback_to_commit(commit_hash)

        if success and not no_reload:
            # Reload configuration
            await self.daemon.load_configuration()

        return {
            "success": success,
            "commit_hash": commit_hash
        }

    async def _handle_config_get_versions(self, params: Dict[str, Any]) -> Dict[str, Any]:
        """Handle config_get_versions request."""
        limit = params.get("limit", 10)

        versions = self.daemon.rollback.list_versions(limit=limit)

        return {
            "versions": [v.dict() for v in versions]
        }

    async def _handle_config_show(self, params: Dict[str, Any]) -> Dict[str, Any]:
        """Handle config_show request."""
        category = params.get("category", "all")  # keybindings, window-rules, workspaces, all
        sources = params.get("sources", False)
        project = params.get("project")

        # Load current configuration
        keybindings = self.daemon.loader.load_keybindings_toml()
        window_rules = self.daemon.loader.load_window_rules_json()
        workspace_assignments = self.daemon.loader.load_workspace_assignments_json()

        result = {}

        if category in ["all", "keybindings"]:
            result["keybindings"] = [kb.dict() for kb in keybindings]

        if category in ["all", "window-rules"]:
            result["window_rules"] = [wr.dict() for wr in window_rules]

        if category in ["all", "workspaces"]:
            result["workspace_assignments"] = [wa.dict() for wa in workspace_assignments]

        if sources:
            result["conflicts"] = self.daemon.merger.get_conflicts()

        return result

    async def _handle_config_get_conflicts(self, params: Dict[str, Any]) -> Dict[str, Any]:
        """Handle config_get_conflicts request."""
        conflicts = self.daemon.merger.get_conflicts()

        return {
            "conflicts": conflicts
        }

    async def _handle_config_watch_start(self, params: Dict[str, Any]) -> Dict[str, Any]:
        """Handle config_watch_start request."""
        # File watcher will be implemented in Phase 3 (T018)
        return {
            "success": True,
            "message": "File watcher not yet implemented"
        }

    async def _handle_config_watch_stop(self, params: Dict[str, Any]) -> Dict[str, Any]:
        """Handle config_watch_stop request."""
        return {
            "success": True,
            "message": "File watcher not yet implemented"
        }
