"""
IPC Server for Sway Configuration Manager

JSON-RPC server for configuration management commands.
"""

import asyncio
import json
import logging
from pathlib import Path
from typing import Any, Dict, Optional

from .errors import (
    ConfigError,
    ErrorCode,
    error_response,
    validate_params,
    ConfigLoadError,
    GitError,
    SwayIPCError
)

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
        Handle JSON-RPC request with comprehensive error handling.

        Feature 047 Phase 8 T060: Structured error codes and recovery suggestions

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
            # Validate request structure
            if not method:
                raise ConfigError(
                    code=ErrorCode.INVALID_REQUEST,
                    message="Missing 'method' field in request",
                    suggestion="Provide 'method' field in JSON-RPC request"
                )

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
                result = {"status": "ok", "daemon": "sway-config-manager"}
            else:
                raise ConfigError(
                    code=ErrorCode.METHOD_NOT_FOUND,
                    message=f"Method not found: {method}",
                    suggestion="Check API documentation for available methods",
                    context={"available_methods": [
                        "config_reload", "config_validate", "config_rollback",
                        "config_get_versions", "config_show", "config_get_conflicts",
                        "config_watch_start", "config_watch_stop", "ping"
                    ]}
                )

            return {
                "jsonrpc": "2.0",
                "result": result,
                "id": request_id
            }

        except ConfigError as e:
            logger.error(f"Config error in {method}: {e.message}")
            return error_response(e, request_id)

        except Exception as e:
            logger.error(f"Unexpected error handling {method}: {e}", exc_info=True)
            return error_response(e, request_id)

    async def _handle_config_reload(self, params: Dict[str, Any]) -> Dict[str, Any]:
        """
        Handle config_reload request with comprehensive error handling.

        Feature 047 Phase 8 T060: Parameter validation and structured errors
        """
        # Validate parameters
        validate_params(
            params,
            required=[],
            optional=["files", "validate_only", "skip_commit"]
        )

        # Check daemon state
        if not self.daemon.reload_manager:
            raise ConfigError(
                code=ErrorCode.RELOAD_MANAGER_NOT_READY,
                message="Reload manager not initialized",
                suggestion="Wait for daemon to fully initialize or restart daemon",
                context={"daemon_state": "reload_manager_missing"}
            )

        files = params.get("files")
        validate_only = params.get("validate_only", False)
        skip_commit = params.get("skip_commit", False)

        # Validate file list if provided
        if files is not None and not isinstance(files, list):
            raise ConfigError(
                code=ErrorCode.INVALID_PARAMS,
                message="'files' parameter must be a list",
                suggestion="Provide file list as array: [\"keybindings.toml\"]"
            )

        try:
            # Use reload manager for two-phase commit
            result = await self.daemon.reload_manager.reload_configuration(
                validate_only=validate_only,
                skip_commit=skip_commit,
                files=files
            )

            return result

        except FileNotFoundError as e:
            raise ConfigLoadError(str(e), "File not found")

        except PermissionError as e:
            raise ConfigError(
                code=ErrorCode.PERMISSION_DENIED,
                message=f"Permission denied: {e}",
                suggestion="Check file permissions or run with appropriate privileges"
            )

        except Exception as e:
            raise ConfigError(
                code=ErrorCode.CONFIG_APPLY_FAILED,
                message=f"Configuration reload failed: {str(e)}",
                suggestion="Check daemon logs for detailed error information"
            )

    async def _handle_config_validate(self, params: Dict[str, Any]) -> Dict[str, Any]:
        """Handle config_validate request."""
        import time
        start_time = time.time()

        files = params.get("files")
        strict = params.get("strict", False)

        # Track which files we're validating
        files_validated = []
        config_dir = self.daemon.loader.config_dir

        # Load configurations
        keybindings = self.daemon.loader.load_keybindings_toml()
        files_validated.append(str(config_dir / "keybindings.toml"))

        window_rules = self.daemon.loader.load_window_rules_json()
        files_validated.append(str(config_dir / "window-rules.json"))

        workspace_assignments = self.daemon.loader.load_workspace_assignments_json()
        files_validated.append(str(config_dir / "workspace-assignments.json"))

        appearance_config = self.daemon.loader.load_appearance_json()
        files_validated.append(str(config_dir / "appearance.json"))

        # Validate
        errors = self.daemon.validator.validate_semantics(
            keybindings, window_rules, workspace_assignments, appearance_config
        )

        # Calculate duration
        duration_ms = int((time.time() - start_time) * 1000)

        return {
            "valid": len(errors) == 0,
            "errors": [e.dict() for e in errors],
            "warnings": [],
            "files_validated": files_validated,
            "validation_duration_ms": duration_ms
        }

    async def _handle_config_rollback(self, params: Dict[str, Any]) -> Dict[str, Any]:
        """
        Handle config_rollback request with comprehensive error handling.

        Feature 047 Phase 8 T060: Parameter validation and structured errors
        """
        # Validate parameters
        validate_params(
            params,
            required=["commit_hash"],
            optional=["reload_after"]
        )

        commit_hash = params["commit_hash"]
        reload_after = params.get("reload_after", True)

        # Validate commit hash format (40 char hex or short 7-8 char)
        if not isinstance(commit_hash, str) or not (7 <= len(commit_hash) <= 40):
            raise ConfigError(
                code=ErrorCode.INVALID_PARAMS,
                message=f"Invalid commit hash: {commit_hash}",
                suggestion="Provide valid git commit hash (7-40 characters)",
                context={"commit_hash": commit_hash}
            )

        try:
            # Rollback to commit
            import time
            start_time = time.time()

            success = self.daemon.rollback.rollback_to_commit(commit_hash)

            if not success:
                raise GitError(
                    operation="rollback",
                    reason=f"Failed to checkout commit {commit_hash[:8]}",
                    suggestion="Check that commit exists with: git log --oneline"
                )

            rollback_duration_ms = int((time.time() - start_time) * 1000)

            # Reload configuration if requested
            if reload_after:
                await self.daemon.load_configuration()

            # Get files changed via git diff
            files_changed = []
            try:
                import subprocess
                result = subprocess.run(
                    ["git", "diff", "--name-only", "HEAD@{1}", "HEAD"],
                    cwd=self.daemon.config_dir,
                    capture_output=True,
                    text=True,
                    check=False
                )
                if result.returncode == 0 and result.stdout:
                    files_changed = result.stdout.strip().split("\n")
            except Exception:
                pass

            return {
                "success": True,
                "message": f"Rolled back to {commit_hash[:8]}",
                "commit_hash": commit_hash,
                "rollback_duration_ms": rollback_duration_ms,
                "files_changed": files_changed
            }

        except subprocess.CalledProcessError as e:
            raise GitError(
                operation="rollback",
                reason=str(e),
                suggestion="Check git repository status: git status"
            )

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
        appearance_config = self.daemon.loader.load_appearance_json()

        result = {}

        if category in ["all", "keybindings"]:
            result["keybindings"] = [kb.dict() for kb in keybindings]

        if category in ["all", "window-rules"]:
            result["window_rules"] = [wr.dict() for wr in window_rules]

        if category in ["all", "workspaces"]:
            result["workspace_assignments"] = [wa.dict() for wa in workspace_assignments]

        if category in ["all", "appearance"] and appearance_config is not None:
            result["appearance"] = appearance_config.model_dump()

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
