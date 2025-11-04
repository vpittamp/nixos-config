"""JSON-RPC IPC server for daemon queries.

Exposes daemon state via UNIX socket with systemd socket activation support.

Updated: 2025-10-22 - Added Deno CLI compatibility (aliases + response formats)
Updated: 2025-10-23 - Added unified event logging for all IPC methods
"""

import asyncio
import json
import logging
import os
import socket
import time
from datetime import datetime
from pathlib import Path
from typing import Any, Dict, Optional

from .state import StateManager
from .window_rules import WindowRule
from .pattern_resolver import classify_window
from .models import EventEntry, EventCorrelation
from . import systemd_query  # Feature 029: systemd journal integration
from .event_correlator import EventCorrelator  # Feature 029: event correlation
from . import window_filtering  # Feature 037: Window filtering utilities

logger = logging.getLogger(__name__)


# JSON-RPC 2.0 Standard Error Codes
PARSE_ERROR = -32700       # Invalid JSON
INVALID_REQUEST = -32600   # Not valid JSON-RPC request
METHOD_NOT_FOUND = -32601  # Method doesn't exist
INVALID_PARAMS = -32602    # Invalid method parameters
INTERNAL_ERROR = -32603    # Server internal error

# Application-specific error codes (Feature 058)
PROJECT_NOT_FOUND = 1001
LAYOUT_NOT_FOUND = 1002
VALIDATION_ERROR = 1003
FILE_IO_ERROR = 1004
I3_IPC_ERROR = 1005


class IPCServer:
    """JSON-RPC IPC server for CLI tool queries."""

    def __init__(
        self,
        state_manager: StateManager,
        event_buffer: Optional[Any] = None,
        i3_connection: Optional[Any] = None,
        window_rules_getter: Optional[callable] = None,
        workspace_tracker: Optional[window_filtering.WorkspaceTracker] = None
    ) -> None:
        """Initialize IPC server.

        Args:
            state_manager: StateManager instance for queries
            event_buffer: EventBuffer instance for event history (Feature 017)
            i3_connection: ResilientI3Connection instance for i3 IPC queries (Feature 018)
            window_rules_getter: Callable that returns current window rules list (Feature 021)
            workspace_tracker: WorkspaceTracker instance for window filtering (Feature 037)
        """
        self.state_manager = state_manager
        self.event_buffer = event_buffer
        self.i3_connection = i3_connection
        self.window_rules_getter = window_rules_getter
        self.workspace_tracker = workspace_tracker
        self.server: Optional[asyncio.Server] = None
        self.clients: set[asyncio.StreamWriter] = set()
        self.subscribed_clients: set[asyncio.StreamWriter] = set()  # Feature 017: Event subscriptions
        self.event_correlator = EventCorrelator()  # Feature 029: Event correlation

    @classmethod
    async def from_systemd_socket(
        cls,
        state_manager: StateManager,
        event_buffer: Optional[Any] = None,
        i3_connection: Optional[Any] = None,
        window_rules_getter: Optional[callable] = None,
        workspace_tracker: Optional[window_filtering.WorkspaceTracker] = None
    ) -> "IPCServer":
        """Create IPC server using systemd socket activation.

        Args:
            state_manager: StateManager instance
            event_buffer: EventBuffer instance for event history (Feature 017)
            i3_connection: ResilientI3Connection instance for i3 IPC queries (Feature 018)
            window_rules_getter: Callable that returns current window rules list (Feature 021)
            workspace_tracker: WorkspaceTracker instance for window filtering (Feature 037)

        Returns:
            IPCServer instance with inherited socket
        """
        server = cls(state_manager, event_buffer, i3_connection, window_rules_getter, workspace_tracker)

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

    def _error_response(self, request_id: Any, code: int, message: str, data: Optional[Dict[str, Any]] = None) -> Dict[str, Any]:
        """Format JSON-RPC error response.

        Args:
            request_id: Request ID from original request
            code: Error code (standard or application-specific)
            message: Error message
            data: Optional additional error data

        Returns:
            JSON-RPC error response dictionary
        """
        error = {"code": code, "message": message}
        if data:
            error["data"] = data
        return {"jsonrpc": "2.0", "error": error, "id": request_id}

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

            # Feature 039 - T110: Security - Set explicit socket permissions
            # Ensure socket is user-only accessible (0600)
            socket_path.chmod(0o600)
            # Ensure parent directory is user-only accessible (0700)
            socket_path.parent.chmod(0o700)

            logger.info(f"IPC server listening on {socket_path} (permissions: 0600)")

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
                    response = await self._handle_request(request, writer)
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
            self.subscribed_clients.discard(writer)  # Remove from subscriptions if subscribed
            writer.close()
            await writer.wait_closed()
            logger.debug(f"Client disconnected: {addr}")

    async def _handle_request(self, request: Dict[str, Any], writer: asyncio.StreamWriter) -> Dict[str, Any]:
        """Handle a JSON-RPC request.

        Args:
            request: JSON-RPC request dictionary
            writer: Stream writer for this client connection

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
                # Return hierarchical tree structure (outputs array)
                tree_result = await self._get_window_tree(params)
                result = tree_result.get("outputs", [])
            elif method == "switch_project":
                result = await self._switch_project(params)
            elif method == "clear_project":
                result = await self._clear_project(params)
            elif method == "get_events":
                # Return events array (not dict with stats) for CLI
                # Unified event system: Return full event data with source field
                events_result = await self._get_events(params)
                result = events_result.get("events", [])
            elif method == "query_systemd_events":
                # Feature 029: T016 - Query systemd journal events
                result = await self._query_systemd_events(params)
            elif method == "get_correlation":
                # Feature 029: T053 - Get correlation by event ID
                result = await self._get_correlation(params)
            elif method == "query_correlations":
                # Feature 029: T053 - Query correlations with filters
                result = await self._query_correlations(params)
            elif method == "list_monitors":
                result = await self._list_monitors()
            elif method == "subscribe_events":
                result = await self._subscribe_events(params, writer)
            elif method == "reload_config":
                result = await self._reload_config()
            elif method == "get_diagnostic_state":
                result = await self._get_diagnostic_state(params)
            elif method == "get_window_rules":
                result = await self._get_window_rules(params)
            elif method == "classify_window":
                result = await self._classify_window(params)
            elif method == "get_window_tree":
                result = await self._get_window_tree(params)

            # Feature 030: Production readiness methods (T016)
            elif method == "daemon.status":
                result = await self._daemon_status()
            elif method == "daemon.events":
                result = await self._daemon_events(params)
            elif method == "daemon.diagnose":
                result = await self._daemon_diagnose(params)
            elif method == "daemon.apps":
                result = await self._daemon_apps(params)
            elif method == "layout.save":
                result = await self._layout_save(params)
            elif method == "layout.restore":
                result = await self._layout_restore(params)
            elif method == "layout.list":
                result = await self._layout_list(params)
            elif method == "layout.delete":
                result = await self._layout_delete(params)
            elif method == "layout.info":
                result = await self._layout_info(params)

            # Feature 033: Workspace-to-monitor mapping methods
            elif method == "get_monitor_config":
                result = await self._get_monitor_config()
            elif method == "validate_monitor_config":
                result = await self._validate_monitor_config(params)
            elif method == "reload_monitor_config":
                result = await self._reload_monitor_config()
            elif method == "reassign_workspaces":
                result = await self._reassign_workspaces(params)
            elif method == "get_monitors":
                result = await self._get_monitors()
            elif method == "get_workspaces":
                result = await self._get_workspaces()
            elif method == "get_system_state":
                result = await self._get_system_state()

            # Feature 037: Window filtering methods
            elif method == "project.hideWindows":
                result = await self._hide_windows(params)
            elif method == "project.restoreWindows":
                result = await self._restore_windows(params)
            elif method == "project.switchWithFiltering":
                result = await self._switch_with_filtering(params)

            # Feature 037 US5: Window visibility methods (T036, T037)
            elif method == "windows.getHidden":
                result = await self._get_hidden_windows(params)
            elif method == "windows.getState":
                result = await self._get_window_state(params)

            # Feature 039: Diagnostic API methods (T087-T092)
            elif method == "health_check":
                result = await self._health_check()
            elif method == "get_window_identity":
                result = await self._get_window_identity_diagnostic(params)
            elif method == "get_window_environment":
                # Feature 058: Phase 3 - Get window environment by PID
                result = await self._get_window_environment(params)
            elif method == "get_workspace_rule":
                result = await self._get_workspace_rule_diagnostic(params)
            elif method == "validate_state":
                result = await self._validate_state_diagnostic()
            elif method == "get_recent_events":
                result = await self._get_recent_events_diagnostic(params)
            elif method == "get_diagnostic_report":
                result = await self._get_diagnostic_report_full(params)

            # Feature 041: IPC Launch Context methods (T010-T012)
            elif method == "notify_launch":
                result = await self._notify_launch(params)
            elif method == "get_launch_stats":
                result = await self._get_launch_stats()
            elif method == "get_pending_launches":
                result = await self._get_pending_launches(params)

            # Feature 042: Workspace mode navigation methods
            elif method == "workspace_mode.digit":
                result = await self._workspace_mode_digit(params)
            elif method == "workspace_mode.execute":
                result = await self._workspace_mode_execute(params)
            elif method == "workspace_mode.cancel":
                result = await self._workspace_mode_cancel(params)
            elif method == "workspace_mode.state":
                result = await self._workspace_mode_state(params)
            elif method == "workspace_mode.history":
                result = await self._workspace_mode_history(params)

            # Feature 058: Project management methods (T030-T033)
            elif method == "project_create":
                result = await self._project_create(params)
            elif method == "project_list":
                result = await self._project_list(params)
            elif method == "project_get":
                result = await self._project_get(params)
            elif method == "project_update":
                result = await self._project_update(params)
            elif method == "project_delete":
                result = await self._project_delete(params)
            elif method == "project_get_active":
                result = await self._project_get_active(params)
            elif method == "project_set_active":
                result = await self._project_set_active(params)

            # Method aliases for Deno CLI compatibility
            elif method == "list_projects":
                # Convert Project objects to array format for CLI (Feature 030)
                projects = self.state_manager.state.projects
                result = [
                    {
                        "name": proj.name,
                        "display_name": proj.display_name,
                        "icon": proj.icon or "",  # Ensure not null
                        "directory": str(proj.directory),
                        "scoped_classes": list(proj.scoped_classes) if proj.scoped_classes else [],
                        "created_at": 1,  # Placeholder: TODO add created_at to Project model
                        "last_used_at": 1,  # Placeholder: TODO add last_used_at tracking
                    }
                    for proj in projects.values()
                ]
            elif method == "get_current_project":
                # Return full project details for app launcher wrapper script
                result = await self._get_active_project()
            elif method == "list_rules":
                # Return rules array adapted to CLI format
                import uuid
                rules_result = await self._get_window_rules(params)
                rules = rules_result.get("rules", [])
                # Adapt format: pattern -> class_pattern, add rule_id and enabled
                result = [
                    {
                        "rule_id": str(uuid.uuid5(uuid.NAMESPACE_DNS, rule["pattern"])),
                        "class_pattern": rule["pattern"],
                        "scope": rule["scope"],
                        "priority": rule["priority"],
                        "enabled": True,  # TODO: Track enabled state
                    }
                    for rule in rules
                ]

            else:
                return {
                    "jsonrpc": "2.0",
                    "error": {"code": -32601, "message": f"Method not found: {method}"},
                    "id": request_id,
                }

            return {"jsonrpc": "2.0", "result": result, "id": request_id}

        except KeyError as e:
            # Missing required parameter
            logger.warning(f"Missing required parameter in {method}: {e}")
            return self._error_response(
                request_id,
                INVALID_PARAMS,
                f"Missing required parameter: {e}",
                {"parameter": str(e)}
            )

        except FileNotFoundError as e:
            # Layout or project file not found
            logger.warning(f"File not found in {method}: {e}")
            error_code = LAYOUT_NOT_FOUND if "layout" in str(e).lower() else PROJECT_NOT_FOUND
            return self._error_response(
                request_id,
                error_code,
                str(e),
                {"path": str(e.filename) if hasattr(e, 'filename') else str(e)}
            )

        except ValueError as e:
            # Pydantic validation error or invalid parameters
            logger.warning(f"Validation error in {method}: {e}")
            return self._error_response(
                request_id,
                VALIDATION_ERROR,
                f"Validation error: {str(e)}",
                {"details": str(e)}
            )

        except OSError as e:
            # File I/O error
            logger.error(f"File I/O error in {method}: {e}")
            return self._error_response(
                request_id,
                FILE_IO_ERROR,
                f"File I/O error: {str(e)}",
                {"errno": e.errno if hasattr(e, 'errno') else None}
            )

        except Exception as e:
            # Unexpected error - check if it's i3 IPC related
            error_type = type(e).__name__
            logger.error(f"Error handling request {method}: {error_type}: {e}")

            # Check if it's an i3ipc exception
            if 'i3ipc' in error_type.lower() or 'connection' in error_type.lower():
                return self._error_response(
                    request_id,
                    I3_IPC_ERROR,
                    "i3 IPC communication error",
                    {"exception": error_type, "details": str(e)}
                )

            # Generic internal error
            return self._error_response(
                request_id,
                INTERNAL_ERROR,
                "Internal server error",
                {"exception": error_type, "details": str(e)}
            )

    async def _log_ipc_event(
        self,
        event_type: str,
        client_pid: Optional[int] = None,
        params: Optional[Dict[str, Any]] = None,
        result_count: Optional[int] = None,
        project_name: Optional[str] = None,
        old_project: Optional[str] = None,
        new_project: Optional[str] = None,
        windows_affected: Optional[int] = None,
        config_type: Optional[str] = None,
        rules_count: Optional[int] = None,
        duration_ms: float = 0.0,
        error: Optional[str] = None,
    ) -> None:
        """Log an IPC event to the event buffer.

        Args:
            event_type: Event type (e.g., "query::status", "project::switch")
            client_pid: Client process ID
            params: Request parameters
            result_count: Number of results returned (for queries)
            project_name: Project name (for project events)
            old_project: Previous project (for switches)
            new_project: New project (for switches)
            windows_affected: Number of windows affected
            config_type: Config type for config events
            rules_count: Number of rules for rule events
            duration_ms: Processing duration
            error: Error message if failed
        """
        if not self.event_buffer:
            return

        entry = EventEntry(
            event_id=self.event_buffer.event_counter,
            event_type=event_type,
            timestamp=datetime.now(),
            source="ipc",
            client_pid=client_pid,
            query_method=event_type if event_type.startswith("query::") else None,
            query_params=params,
            query_result_count=result_count,
            project_name=project_name,
            old_project=old_project,
            new_project=new_project,
            windows_affected=windows_affected,
            config_type=config_type,
            rules_added=rules_count,
            processing_duration_ms=duration_ms,
            error=error,
        )
        await self.event_buffer.add_event(entry)

    async def _get_status(self) -> Dict[str, Any]:
        """Get daemon status."""
        start_time = time.perf_counter()
        error_msg = None

        try:
            stats = await self.state_manager.get_stats()
            result = {
                "status": "running",
                "connected": self.state_manager.state.is_connected,
                "uptime": stats.get("uptime_seconds", 0),  # Rename for CLI
                "active_project": stats.get("active_project"),
                "window_count": stats.get("window_count", 0),
                "workspace_count": stats.get("workspace_count", 0),
                "event_count": stats.get("event_count", 0),
                "error_count": stats.get("error_count", 0),
                "version": "1.0.0",  # TODO: Get from package metadata
                "socket_path": str(self.server.sockets[0].getsockname()) if self.server and self.server.sockets else "/run/user/1000/i3-project-daemon/ipc.sock",
            }
            return result
        except Exception as e:
            error_msg = str(e)
            raise
        finally:
            duration_ms = (time.perf_counter() - start_time) * 1000
            await self._log_ipc_event(
                event_type="query::status",
                duration_ms=duration_ms,
                error=error_msg,
            )

    async def _get_active_project(self) -> Dict[str, Any]:
        """Get active project info with full project details.

        Returns:
            Dictionary with project details or None values if no active project.
            Format matches what the app launcher wrapper script expects.
        """
        project_name = await self.state_manager.get_active_project()

        if project_name is None:
            return {
                "name": None,
                "display_name": None,
                "icon": None,
                "directory": None,
            }

        # Get full project details from state
        projects = self.state_manager.state.projects
        if project_name not in projects:
            logger.warning(f"Active project '{project_name}' not found in state")
            return {
                "name": project_name,
                "display_name": project_name,
                "icon": "",
                "directory": None,
            }

        project = projects[project_name]
        return {
            "name": project.name,
            "display_name": project.display_name,
            "icon": project.icon or "",
            "directory": str(project.directory),
        }

    async def _get_projects(self) -> Dict[str, Any]:
        """List all projects with window counts."""
        start_time = time.perf_counter()
        error_msg = None

        try:
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
        except Exception as e:
            error_msg = str(e)
            raise
        finally:
            duration_ms = (time.perf_counter() - start_time) * 1000
            await self._log_ipc_event(
                event_type="query::projects",
                result_count=len(self.state_manager.state.projects),
                duration_ms=duration_ms,
                error=error_msg,
            )

    async def _get_windows(self, params: Dict[str, Any]) -> Dict[str, Any]:
        """Query windows with filters."""
        start_time = time.perf_counter()
        error_msg = None

        try:
            project = params.get("project")

            if project:
                windows = await self.state_manager.get_windows_by_project(project)
            else:
                windows = list(self.state_manager.state.window_map.values())

            result = {
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
            return result
        except Exception as e:
            error_msg = str(e)
            raise
        finally:
            duration_ms = (time.perf_counter() - start_time) * 1000
            await self._log_ipc_event(
                event_type="query::windows",
                params={"project": params.get("project")} if params.get("project") else None,
                result_count=len(windows) if 'windows' in locals() else 0,
                duration_ms=duration_ms,
                error=error_msg,
            )

    async def _switch_project(self, params: Dict[str, Any]) -> Dict[str, Any]:
        """Switch to a project and return results.

        Args:
            params: Switch parameters with project_name

        Returns:
            Dictionary with previous_project, new_project, windows_hidden, windows_shown
        """
        start_time = time.perf_counter()
        project_name = params.get("project_name")
        error_msg = None

        try:
            if not project_name:
                raise ValueError("project_name parameter is required")

            # Verify project exists
            if project_name not in self.state_manager.state.projects:
                raise ValueError(f"Project not found: {project_name}")

            # Get current project before switch
            previous_project = self.state_manager.state.active_project

            # Count current windows
            all_windows = list(self.state_manager.state.window_map.values())
            scoped_windows = [w for w in all_windows if w.window_class in self.state_manager.state.scoped_classes]

            # Calculate windows that will be hidden (scoped windows from other projects)
            windows_to_hide = len([w for w in scoped_windows if w.project != project_name and w.project is not None])

            # Calculate windows that will be shown (scoped windows from new project)
            windows_to_show = len([w for w in scoped_windows if w.project == project_name])

            # Directly switch the project by updating state
            # Import needed for project switching
            from datetime import datetime
            from .config import save_active_project
            from .models import ActiveProjectState

            await self.state_manager.set_active_project(project_name)

            # Save active project state to disk
            from pathlib import Path
            active_state = ActiveProjectState(
                project_name=project_name,
                activated_at=datetime.now(),
                previous_project=previous_project
            )
            config_dir = Path.home() / ".config" / "i3"
            config_file = config_dir / "active-project.json"
            save_active_project(active_state, config_file)

            logger.info(f"IPC: Switching to project '{project_name}' (from '{previous_project}')")

            # Update window visibility based on new project using mark-based filtering
            logger.debug(f"IPC: Checking i3 connection: i3_connection={self.i3_connection}, conn={self.i3_connection.conn if self.i3_connection else None}")
            if self.i3_connection and self.i3_connection.conn:
                logger.info(f"IPC: Applying mark-based window filtering for project '{project_name}'")
                from .services.window_filter import filter_windows_by_project
                filter_result = await filter_windows_by_project(
                    self.i3_connection.conn,
                    project_name,
                    self.workspace_tracker  # Feature 038: Pass workspace_tracker for state persistence
                )
                windows_to_hide = filter_result.get("hidden", 0)
                windows_to_show = filter_result.get("visible", 0)
                logger.info(
                    f"IPC: Window filtering applied: {windows_to_show} visible, {windows_to_hide} hidden "
                    f"(via mark-based filtering)"
                )
            else:
                logger.warning(f"IPC: Cannot apply filtering - i3 connection not available")

            return {
                "previous_project": previous_project,
                "new_project": project_name,
                "windows_hidden": windows_to_hide,
                "windows_shown": windows_to_show,
            }

        except Exception as e:
            error_msg = str(e)
            raise
        finally:
            duration_ms = (time.perf_counter() - start_time) * 1000
            await self._log_ipc_event(
                event_type="project::switch",
                old_project=previous_project if 'previous_project' in locals() else None,
                new_project=project_name,
                windows_affected=windows_to_hide + windows_to_show if 'windows_to_hide' in locals() else None,
                duration_ms=duration_ms,
                error=error_msg,
            )

    async def _clear_project(self, params: Dict[str, Any]) -> Dict[str, Any]:
        """Clear active project (enter global mode).

        Args:
            params: Clear parameters (currently unused)

        Returns:
            Dictionary with previous_project and windows_shown
        """
        start_time = time.perf_counter()
        error_msg = None

        try:
            # Get current project before clearing
            previous_project = self.state_manager.state.active_project

            if previous_project is None:
                # Already in global mode
                return {
                    "previous_project": None,
                    "windows_shown": 0,
                }

            # Count scoped windows that will be shown when clearing project
            all_windows = list(self.state_manager.state.window_map.values())
            scoped_windows = [w for w in all_windows if w.window_class in self.state_manager.state.scoped_classes]
            windows_to_show = len([w for w in scoped_windows if w.project != previous_project])

            # Directly clear the project by updating state
            from datetime import datetime
            from .config import save_active_project
            from .models import ActiveProjectState

            await self.state_manager.set_active_project(None)

            # Save cleared state to disk
            from pathlib import Path
            active_state = ActiveProjectState(
                project_name=None,
                activated_at=datetime.now(),
                previous_project=previous_project
            )
            config_dir = Path.home() / ".config" / "i3"
            config_file = config_dir / "active-project.json"
            save_active_project(active_state, config_file)

            # Show all scoped windows when clearing project
            if self.i3_connection and self.i3_connection.conn:
                for window in scoped_windows:
                    if window.project != previous_project:
                        # Move hidden windows back from scratchpad
                        await self.i3_connection.conn.command(f'[con_id={window.window_id}] move scratchpad; move workspace current')

            return {
                "previous_project": previous_project,
                "windows_shown": windows_to_show,
            }

        except Exception as e:
            error_msg = str(e)
            raise
        finally:
            duration_ms = (time.perf_counter() - start_time) * 1000
            await self._log_ipc_event(
                event_type="project::clear",
                old_project=previous_project if 'previous_project' in locals() else None,
                new_project=None,
                windows_affected=windows_to_show if 'windows_to_show' in locals() else None,
                duration_ms=duration_ms,
                error=error_msg,
            )

    async def _get_events(self, params: Dict[str, Any]) -> Dict[str, Any]:
        """Return recent events for diagnostics (Feature 017).

        Feature 029: T017 - Extended to support systemd and proc event sources.

        Args:
            params: Query parameters:
                - limit: Maximum events to return (default 100)
                - event_type: Filter by event type
                - source: Filter by source ("i3", "ipc", "daemon", "systemd", "proc", "all")
                - since_id: Return events since this event_id
                - since: Time specification for systemd queries (e.g., "1 hour ago")

        Returns:
            Dictionary with events list and buffer stats
        """
        start_time = time.perf_counter()
        error_msg = None

        try:
            limit = params.get("limit", 100)
            event_type = params.get("event_type")
            source = params.get("source")
            since_id = params.get("since_id")

            # Feature 029: Handle systemd/proc/all sources with unified stream
            if source in ("systemd", "proc", "all"):
                # Unified event stream: merge events from multiple sources
                all_events = []

                # Get buffer events (i3, ipc, daemon, proc)
                # Note: proc events are in event_buffer, not separate storage
                if source in ("all", "proc") or (self.event_buffer and source not in ("systemd",)):
                    if self.event_buffer:
                        buffer_events = self.event_buffer.get_events(
                            limit=limit,
                            event_type=event_type,
                            source=source if source != "all" else None,
                            since_id=since_id
                        )
                        all_events.extend(buffer_events)

                # Get systemd events if requested
                # Feature 029: Run in thread pool to avoid blocking watchdog
                if source in ("systemd", "all"):
                    since = params.get("since", "1 hour ago")
                    systemd_events = await asyncio.to_thread(
                        systemd_query.query_systemd_journal_sync,
                        since=since,
                        limit=limit
                    )
                    all_events.extend(systemd_events)

                # Sort all events by timestamp (chronological order)
                all_events.sort(key=lambda e: e.timestamp)

                # Apply limit after merge
                all_events = all_events[-limit:]

                # Convert to dict
                events_data = self._convert_events_to_dict(all_events)

                return {
                    "events": events_data,
                    "stats": self.event_buffer.get_stats() if self.event_buffer else {
                        "total_events": len(events_data),
                        "buffer_size": 0,
                        "max_size": 0
                    }
                }

            # Original behavior for i3/ipc/daemon sources
            if not self.event_buffer:
                return {"events": [], "stats": {"total_events": 0, "buffer_size": 0, "max_size": 0}}

            # Get events from buffer
            events = self.event_buffer.get_events(limit=limit, event_type=event_type, source=source, since_id=since_id)

            # Convert EventEntry objects to dict
            events_data = self._convert_events_to_dict(events)

            return {
                "events": events_data,
                "stats": self.event_buffer.get_stats()
            }
        except Exception as e:
            error_msg = str(e)
            raise
        finally:
            duration_ms = (time.perf_counter() - start_time) * 1000
            await self._log_ipc_event(
                event_type="query::events",
                params={"limit": params.get("limit"), "event_type": params.get("event_type")},
                result_count=len(events) if 'events' in locals() else 0,
                duration_ms=duration_ms,
                error=error_msg,
            )

    def _convert_events_to_dict(self, events: list) -> list:
        """Convert EventEntry objects to dictionary format for JSON serialization.

        Feature 029: Helper method to handle all event types (i3, ipc, daemon, systemd, proc).

        Args:
            events: List of EventEntry objects

        Returns:
            List of event dictionaries with all relevant fields
        """
        events_data = []
        for e in events:
            event_dict = {
                "event_id": e.event_id,
                "event_type": e.event_type,
                "timestamp": e.timestamp.isoformat(),
                "source": e.source,
                "processing_duration_ms": e.processing_duration_ms,
            }

            # Add i3/window fields if present
            if e.window_id is not None:
                event_dict["window_id"] = e.window_id
            if e.window_class:
                event_dict["window_class"] = e.window_class
            if e.workspace_name:
                event_dict["workspace_name"] = e.workspace_name
            if e.project_name:
                event_dict["project_name"] = e.project_name
            if e.tick_payload:
                event_dict["tick_payload"] = e.tick_payload
            if e.error:
                event_dict["error"] = e.error

            # Feature 029: Add systemd fields if present
            if e.systemd_unit:
                event_dict["systemd_unit"] = e.systemd_unit
            if e.systemd_message:
                event_dict["systemd_message"] = e.systemd_message
            if e.systemd_pid is not None:
                event_dict["systemd_pid"] = e.systemd_pid
            if e.journal_cursor:
                event_dict["journal_cursor"] = e.journal_cursor

            # Feature 029: Add process fields if present (for future US2 implementation)
            if e.process_pid is not None:
                event_dict["process_pid"] = e.process_pid
            if e.process_name:
                event_dict["process_name"] = e.process_name
            if e.process_cmdline:
                event_dict["process_cmdline"] = e.process_cmdline
            if e.process_parent_pid is not None:
                event_dict["process_parent_pid"] = e.process_parent_pid
            if e.process_start_time is not None:
                event_dict["process_start_time"] = int(e.process_start_time.timestamp() * 1000)

            events_data.append(event_dict)

        return events_data

    async def _query_systemd_events(self, params: Dict[str, Any]) -> list:
        """Query systemd journal for application service events (Feature 029: T016).

        Args:
            params: Query parameters:
                - since: Time specification (e.g., "1 hour ago", "today", ISO timestamp) [required]
                - until: Optional end time specification
                - unit_pattern: Optional unit name pattern filter (e.g., "app-*.service")
                - limit: Maximum number of events (default 1000)

        Returns:
            List of event dictionaries with systemd fields

        Example:
            {"since": "1 hour ago", "limit": 100}
            -> [{"event_id": 1, "event_type": "systemd::service::start", ...}, ...]
        """
        start_time = time.perf_counter()
        error_msg = None

        try:
            # Extract parameters
            since = params.get("since", "1 hour ago")
            until = params.get("until")
            unit_pattern = params.get("unit_pattern")
            limit = params.get("limit", 1000)

            # Query systemd journal via systemd_query module
            # Feature 029: Run in thread pool to avoid blocking watchdog
            events = await asyncio.to_thread(
                systemd_query.query_systemd_journal_sync,
                since=since,
                until=until,
                unit_pattern=unit_pattern,
                limit=limit
            )

            # Convert EventEntry objects to dict for JSON serialization
            events_data = [
                {
                    "event_id": e.event_id,
                    "event_type": e.event_type,
                    "timestamp": e.timestamp.isoformat(),
                    "source": e.source,
                    "systemd_unit": e.systemd_unit,
                    "systemd_message": e.systemd_message,
                    "systemd_pid": e.systemd_pid,
                    "journal_cursor": e.journal_cursor,
                    "processing_duration_ms": e.processing_duration_ms,
                }
                for e in events
            ]

            logger.info(f"Queried {len(events_data)} systemd events (since={since})")
            return events_data

        except Exception as e:
            error_msg = str(e)
            logger.error(f"Error querying systemd events: {e}", exc_info=True)
            raise
        finally:
            duration_ms = (time.perf_counter() - start_time) * 1000
            await self._log_ipc_event(
                event_type="query::systemd_events",
                params={"since": params.get("since"), "limit": params.get("limit")},
                result_count=len(events_data) if 'events_data' in locals() else 0,
                duration_ms=duration_ms,
                error=error_msg,
            )

    async def _get_correlation(self, params: Dict[str, Any]) -> Optional[Dict[str, Any]]:
        """Get correlation by event ID (Feature 029: T053).

        Args:
            params: Query parameters:
                - event_id: Event ID to get correlation for [required]

        Returns:
            Correlation dictionary if found, None otherwise

        Example:
            {"event_id": 1234}
            -> {"correlation_id": 1, "parent_event_id": 1234, "confidence_score": 0.85, ...}
        """
        start_time = time.perf_counter()
        error_msg = None
        result = None

        try:
            event_id = params.get("event_id")
            if event_id is None:
                raise ValueError("event_id parameter is required")

            # Check if event is a parent
            correlations = self.event_correlator.get_correlations_by_parent(event_id)
            if correlations:
                correlation = correlations[0]  # Return first (should be only one)
                result = self._correlation_to_dict(correlation)
                return result

            # Check if event is a child
            correlations = self.event_correlator.get_correlations_by_child(event_id)
            if correlations:
                correlation = correlations[0]  # Return first
                result = self._correlation_to_dict(correlation)
                return result

            # No correlation found
            return None

        except Exception as e:
            error_msg = str(e)
            logger.error(f"Error getting correlation: {e}", exc_info=True)
            raise
        finally:
            duration_ms = (time.perf_counter() - start_time) * 1000
            await self._log_ipc_event(
                event_type="query::correlation",
                params={"event_id": params.get("event_id")},
                result_count=1 if result else 0,
                duration_ms=duration_ms,
                error=error_msg,
            )

    async def _query_correlations(self, params: Dict[str, Any]) -> list:
        """Query correlations with filters (Feature 029: T053).

        Args:
            params: Query parameters:
                - correlation_type: Filter by type ("window_to_process", "process_to_subprocess") [optional]
                - min_confidence: Minimum confidence score (0.0-1.0) [optional]
                - limit: Maximum number of correlations (default 100) [optional]

        Returns:
            List of correlation dictionaries

        Example:
            {"min_confidence": 0.7, "limit": 50}
            -> [{"correlation_id": 1, "confidence_score": 0.85, ...}, ...]
        """
        start_time = time.perf_counter()
        error_msg = None

        try:
            correlation_type = params.get("correlation_type")
            min_confidence = params.get("min_confidence", 0.0)
            limit = params.get("limit", 100)

            # Get all correlations from correlator
            all_correlations = list(self.event_correlator.correlations.values())

            # Apply filters
            filtered = all_correlations

            if correlation_type:
                filtered = [c for c in filtered if c.correlation_type == correlation_type]

            if min_confidence > 0:
                filtered = [c for c in filtered if c.confidence_score >= min_confidence]

            # Sort by confidence (highest first)
            filtered.sort(key=lambda c: c.confidence_score, reverse=True)

            # Apply limit
            filtered = filtered[:limit]

            # Convert to dicts
            result = [self._correlation_to_dict(c) for c in filtered]

            logger.info(f"Queried {len(result)} correlations (total: {len(all_correlations)})")
            return result

        except Exception as e:
            error_msg = str(e)
            logger.error(f"Error querying correlations: {e}", exc_info=True)
            raise
        finally:
            duration_ms = (time.perf_counter() - start_time) * 1000
            await self._log_ipc_event(
                event_type="query::correlations",
                params={
                    "type": correlation_type,
                    "min_confidence": min_confidence,
                    "limit": limit
                },
                result_count=len(result) if 'result' in locals() else 0,
                duration_ms=duration_ms,
                error=error_msg,
            )

    def _correlation_to_dict(self, correlation: EventCorrelation) -> Dict[str, Any]:
        """Convert EventCorrelation to dictionary for JSON serialization.

        Args:
            correlation: EventCorrelation instance

        Returns:
            Dictionary representation
        """
        return {
            "correlation_id": correlation.correlation_id,
            "created_at": correlation.created_at.isoformat(),
            "confidence_score": correlation.confidence_score,
            "parent_event_id": correlation.parent_event_id,
            "child_event_ids": correlation.child_event_ids,
            "correlation_type": correlation.correlation_type,
            "time_delta_ms": correlation.time_delta_ms,
            "detection_window_ms": correlation.detection_window_ms,
            "timing_factor": correlation.timing_factor,
            "hierarchy_factor": correlation.hierarchy_factor,
            "name_similarity": correlation.name_similarity,
            "workspace_match": correlation.workspace_match,
        }

    async def _list_monitors(self) -> Dict[str, Any]:
        """List all connected monitor clients (Feature 017).

        Returns:
            Dictionary with list of connected monitors
        """
        monitors = []
        for idx, writer in enumerate(self.clients):
            peer = writer.get_extra_info("peername")
            monitors.append({
                "monitor_id": idx,
                "peer": str(peer),
                "subscribed": writer in self.subscribed_clients
            })

        return {
            "monitors": monitors,
            "total_clients": len(self.clients),
            "subscribed_clients": len(self.subscribed_clients)
        }

    async def _subscribe_events(self, params: Dict[str, Any], writer: asyncio.StreamWriter) -> Dict[str, Any]:
        """Subscribe/unsubscribe from event stream (Feature 017).

        Args:
            params: Subscription parameters (subscribe: bool)
            writer: Stream writer for this client connection

        Returns:
            Subscription confirmation
        """
        subscribe = params.get("subscribe", True)

        if subscribe:
            self.subscribed_clients.add(writer)
            logger.info(f"Client subscribed to events (total subscribers: {len(self.subscribed_clients)})")
        else:
            self.subscribed_clients.discard(writer)
            logger.info(f"Client unsubscribed from events (total subscribers: {len(self.subscribed_clients)})")

        return {
            "success": True,
            "subscribed": subscribe,
            "message": f"Event subscription {'enabled' if subscribe else 'disabled'}",
            "subscriber_count": len(self.subscribed_clients)
        }

    async def broadcast_event(self, event_data: Dict[str, Any]) -> None:
        """Broadcast event notification to all subscribed clients (Feature 017).

        Args:
            event_data: Event data to broadcast
        """
        if not self.subscribed_clients:
            logger.debug(f"No subscribed clients to broadcast to (event: {event_data.get('type')})")
            return

        logger.debug(f"Broadcasting event to {len(self.subscribed_clients)} clients: {event_data}")

        notification = {
            "jsonrpc": "2.0",
            "method": "event_notification",
            "params": event_data
        }
        message = json.dumps(notification).encode() + b"\n"

        # Send to all subscribed clients
        for writer in list(self.subscribed_clients):
            try:
                writer.write(message)
                await writer.drain()
                logger.debug(f"Successfully sent event to client")
            except Exception as e:
                logger.error(f"Failed to broadcast to client: {e}")
                self.subscribed_clients.discard(writer)

    async def broadcast_event_entry(self, event_entry) -> None:
        """Broadcast EventEntry to all subscribed clients (Feature 017: T019).

        Args:
            event_entry: EventEntry instance to broadcast
        """
        # Convert EventEntry to dict for JSON serialization
        # Include all unified event system fields
        event_data = {
            "event_id": event_entry.event_id,
            "event_type": event_entry.event_type,
            "timestamp": event_entry.timestamp.isoformat(),
            "source": event_entry.source,

            # Window event fields
            "window_id": event_entry.window_id,
            "window_class": event_entry.window_class,
            "window_title": event_entry.window_title,
            "window_instance": event_entry.window_instance,
            "workspace_name": event_entry.workspace_name,

            # Project event fields
            "project_name": event_entry.project_name,
            "project_directory": event_entry.project_directory,
            "old_project": event_entry.old_project,
            "new_project": event_entry.new_project,
            "windows_affected": event_entry.windows_affected,

            # Tick event fields
            "tick_payload": event_entry.tick_payload,

            # Output event fields
            "output_name": event_entry.output_name,
            "output_count": event_entry.output_count,

            # Query event fields
            "query_method": event_entry.query_method,
            "query_params": event_entry.query_params,
            "query_result_count": event_entry.query_result_count,

            # Config event fields
            "config_type": event_entry.config_type,
            "rules_added": event_entry.rules_added,
            "rules_removed": event_entry.rules_removed,

            # Daemon event fields
            "daemon_version": event_entry.daemon_version,
            "i3_socket": event_entry.i3_socket,

            # Systemd event fields (Feature 029)
            "systemd_unit": event_entry.systemd_unit,
            "systemd_message": event_entry.systemd_message,
            "systemd_pid": event_entry.systemd_pid,
            "journal_cursor": event_entry.journal_cursor,

            # Process event fields (Feature 029)
            "process_pid": event_entry.process_pid,
            "process_name": event_entry.process_name,
            "process_cmdline": event_entry.process_cmdline,
            "process_parent_pid": event_entry.process_parent_pid,
            "process_start_time": event_entry.process_start_time.isoformat() if hasattr(event_entry.process_start_time, 'isoformat') else event_entry.process_start_time,

            # Processing metadata
            "processing_duration_ms": event_entry.processing_duration_ms,
            "error": event_entry.error,
        }
        await self.broadcast_event(event_data)

    async def _reload_config(self) -> Dict[str, Any]:
        """Reload project configs from disk."""
        start_time = time.perf_counter()
        error_msg = None

        try:
            # TODO: Implement config reload
            return {"success": True, "message": "Config reloaded"}
        except Exception as e:
            error_msg = str(e)
            raise
        finally:
            duration_ms = (time.perf_counter() - start_time) * 1000
            await self._log_ipc_event(
                event_type="config::reload",
                config_type="project_configs",
                duration_ms=duration_ms,
                error=error_msg,
            )

    async def _get_diagnostic_state(self, params: Dict[str, Any]) -> Dict[str, Any]:
        """Get complete diagnostic snapshot (Feature 018).

        Combines daemon state, projects, windows, events, monitors, and i3 tree
        into a single atomic snapshot for diagnostic capture.

        Args:
            params: Query parameters
                - include_events: bool (default True) - Include event buffer
                - event_limit: int (default 500) - Number of events to include
                - include_tree: bool (default True) - Include i3 tree dump
                - include_monitors: bool (default True) - Include monitor client list

        Returns:
            Dictionary with complete diagnostic state
        """
        import time

        start_time = time.perf_counter()

        # Parse parameters
        include_events = params.get("include_events", True)
        event_limit = params.get("event_limit", 500)
        include_tree = params.get("include_tree", True)
        include_monitors = params.get("include_monitors", True)

        # Gather all state in parallel for performance
        daemon_state = await self._get_status()
        projects_data = await self._get_projects()
        windows_data = await self._get_windows({})

        # Optional components
        events_data = {"events": [], "stats": {}}
        if include_events:
            events_data = await self._get_events({"limit": event_limit})

        monitors_data = {"monitors": [], "total_clients": 0, "subscribed_clients": 0}
        if include_monitors:
            monitors_data = await self._list_monitors()

        # i3 tree dump (requires i3 connection)
        i3_tree = None
        if include_tree and self.i3_connection and self.i3_connection.conn:
            try:
                tree = await self.i3_connection.conn.get_tree()
                # Convert i3ipc tree to dict (recursive)
                i3_tree = self._tree_to_dict(tree)
            except Exception as e:
                logger.error(f"Failed to get i3 tree: {e}")
                i3_tree = {"error": str(e)}

        # Calculate capture duration
        end_time = time.perf_counter()
        capture_duration_ms = (end_time - start_time) * 1000

        return {
            "daemon_state": daemon_state,
            "projects": projects_data["projects"],
            "windows": windows_data["windows"],
            "events": events_data["events"],
            "event_stats": events_data.get("stats", {}),
            "monitors": monitors_data["monitors"],
            "monitor_stats": {
                "total_clients": monitors_data["total_clients"],
                "subscribed_clients": monitors_data["subscribed_clients"]
            },
            "i3_tree": i3_tree,
            "capture_duration_ms": round(capture_duration_ms, 2)
        }

    def _tree_to_dict(self, node: Any) -> Dict[str, Any]:
        """Convert i3ipc tree node to dictionary recursively.

        Args:
            node: i3ipc Con (container) node

        Returns:
            Dictionary representation of tree node
        """
        # Convert basic attributes
        result = {
            "id": node.id,
            "name": node.name,
            "type": node.type,
            "border": node.border,
            "current_border_width": node.current_border_width,
            "layout": node.layout,
            "orientation": node.orientation,
            "percent": node.percent,
            "rect": {
                "x": node.rect.x,
                "y": node.rect.y,
                "width": node.rect.width,
                "height": node.rect.height
            },
            "window_rect": {
                "x": node.window_rect.x,
                "y": node.window_rect.y,
                "width": node.window_rect.width,
                "height": node.window_rect.height
            },
            "deco_rect": {
                "x": node.deco_rect.x,
                "y": node.deco_rect.y,
                "width": node.deco_rect.width,
                "height": node.deco_rect.height
            },
            "geometry": {
                "x": node.geometry.x,
                "y": node.geometry.y,
                "width": node.geometry.width,
                "height": node.geometry.height
            },
            "window": node.window,
            "urgent": node.urgent,
            "focused": node.focused,
            "focus": node.focus,
            "nodes": [],
            "floating_nodes": [],
            "marks": node.marks,
            "fullscreen_mode": node.fullscreen_mode,
            "sticky": node.sticky,
            "floating": node.floating,
            "window_class": getattr(node, 'window_class', None),
            "window_instance": getattr(node, 'window_instance', None),
            "window_title": getattr(node.window_properties, 'title', None) if hasattr(node, 'window_properties') and node.window_properties else None
        }

        # Recursively convert child nodes
        if hasattr(node, 'nodes') and node.nodes:
            result["nodes"] = [self._tree_to_dict(child) for child in node.nodes]

        if hasattr(node, 'floating_nodes') and node.floating_nodes:
            result["floating_nodes"] = [self._tree_to_dict(child) for child in node.floating_nodes]

        return result

    async def _get_window_rules(self, params: Dict[str, Any]) -> Dict[str, Any]:
        """Get window rules with optional scope filter (Feature 021: T025).

        Args:
            params: Query parameters with optional scope filter

        Returns:
            Dictionary with rules list and count

        Example:
            Request: {"method": "get_window_rules", "params": {"scope": "scoped"}}
            Response: {"rules": [...], "count": 5}
        """
        start_time = time.perf_counter()
        error_msg = None

        try:
            if not self.window_rules_getter:
                return {"rules": [], "count": 0, "error": "Window rules not available"}

            # Get current window rules
            window_rules = self.window_rules_getter()

            # Apply scope filter if provided
            scope_filter = params.get("scope")
            if scope_filter:
                window_rules = [r for r in window_rules if r.scope == scope_filter]

            # Serialize rules to dict
            rules_data = [
                {
                    "pattern": r.pattern_rule.pattern,
                    "scope": r.scope,
                    "priority": r.priority,
                    "workspace": r.workspace,
                    "description": r.pattern_rule.description,
                    "modifier": r.modifier,
                }
                for r in window_rules
            ]

            return {
                "rules": rules_data,
                "count": len(rules_data),
            }
        except Exception as e:
            error_msg = str(e)
            raise
        finally:
            duration_ms = (time.perf_counter() - start_time) * 1000
            await self._log_ipc_event(
                event_type="query::rules",
                params={"scope": params.get("scope")} if params.get("scope") else None,
                result_count=len(rules_data) if 'rules_data' in locals() else 0,
                duration_ms=duration_ms,
                error=error_msg,
            )

    async def _classify_window(self, params: Dict[str, Any]) -> Dict[str, Any]:
        """Classify a window using the 4-level precedence system (Feature 021: T026).

        Args:
            params: Classification parameters
                - window_class (required): Window WM_CLASS
                - window_title (optional): Window title
                - project_name (optional): Active project name

        Returns:
            Classification result with scope, workspace, source

        Example:
            Request: {"method": "classify_window", "params": {"window_class": "Code", "project_name": "nixos"}}
            Response: {"scope": "scoped", "workspace": null, "source": "project", "matched_pattern": null}
        """
        window_class = params.get("window_class")
        if not window_class:
            raise ValueError("window_class parameter is required")

        window_title = params.get("window_title", "")
        project_name = params.get("project_name")

        # Get active project's scoped classes
        active_project_scoped_classes = None
        if project_name and project_name in self.state_manager.state.projects:
            project = self.state_manager.state.projects[project_name]
            active_project_scoped_classes = project.scoped_classes

        # Get window rules
        window_rules = None
        if self.window_rules_getter:
            window_rules = self.window_rules_getter()

        # Get app classification
        app_classification_scoped = list(self.state_manager.state.scoped_classes)
        app_classification_global = list(self.state_manager.state.global_classes)

        # Classify
        classification = classify_window(
            window_class=window_class,
            window_title=window_title,
            active_project_scoped_classes=active_project_scoped_classes,
            window_rules=window_rules,
            app_classification_patterns=None,  # TODO: Extract from app classification
            app_classification_scoped=app_classification_scoped,
            app_classification_global=app_classification_global,
        )

        return classification.to_json()

    async def _get_window_tree(self, params: Dict[str, Any]) -> Dict[str, Any]:
        """Get hierarchical window state tree (Feature 025: T016).

        Queries i3 IPC for complete window state and organizes it hierarchically:
        outputs → workspaces → windows

        Args:
            params: Query parameters (currently unused, reserved for future filters)

        Returns:
            Window tree dict with keys:
                - outputs: List[dict] - Monitor/output nodes
                - total_windows: int - Total window count

        Raises:
            Exception: If i3 connection unavailable or query fails
        """
        if not self.i3_connection or not self.i3_connection.conn:
            raise Exception("i3 connection not available")

        try:
            # Query i3 IPC for current state
            tree = await self.i3_connection.conn.get_tree()
            workspaces = await self.i3_connection.conn.get_workspaces()
            outputs_list = await self.i3_connection.conn.get_outputs()

            # Build outputs structure
            outputs = []
            total_windows = 0

            for output in outputs_list:
                if not output.active or output.name.startswith("__"):
                    continue  # Skip inactive and special outputs

                # Find current workspace for this output
                current_ws_name = next((ws.name for ws in workspaces if ws.output == output.name and ws.visible), "1")

                output_node = {
                    "name": output.name,
                    "active": output.active,
                    "primary": output.primary,
                    "geometry": {
                        "x": output.rect.x,
                        "y": output.rect.y,
                        "width": output.rect.width,
                        "height": output.rect.height,
                    },
                    "current_workspace": current_ws_name,
                    "workspaces": [],
                }

                # Find workspaces on this output
                for ws in workspaces:
                    if ws.output != output.name:
                        continue

                    workspace_node = {
                        "number": ws.num,
                        "name": ws.name,
                        "focused": ws.focused,
                        "visible": ws.visible,
                        "output": output.name,
                        "windows": [],
                    }

                    # Find windows in this workspace
                    ws_con = self._find_workspace_container(tree, ws.name)
                    if ws_con:
                        windows = self._extract_windows_from_container(ws_con, ws.num, output.name)
                        workspace_node["windows"] = windows
                        total_windows += len(windows)

                    output_node["workspaces"].append(workspace_node)

                outputs.append(output_node)

            return {
                "outputs": outputs,
                "total_windows": total_windows,
            }

        except Exception as e:
            logger.error(f"Failed to get window tree: {e}")
            raise Exception(f"Failed to query i3 window tree: {e}")

    def _find_workspace_container(self, tree, workspace_name: str):
        """Find workspace container in i3 tree by name.

        Args:
            tree: i3 tree root node
            workspace_name: Workspace name to find

        Returns:
            Workspace container node or None
        """
        def search(node):
            if node.type == "workspace" and node.name == workspace_name:
                return node
            for child in (node.nodes + node.floating_nodes):
                result = search(child)
                if result:
                    return result
            return None

        return search(tree)

    def _extract_windows_from_container(self, container, workspace_num: int, output_name: str) -> list:
        """Extract all windows from container recursively.

        Args:
            container: i3 container node
            workspace_num: Workspace number
            output_name: Output name

        Returns:
            List of window dicts with WindowState-compatible structure
        """
        windows = []

        def extract(node, depth=0):
            # Check if this is an actual window (has X11 window ID or Wayland app_id)
            # X11 windows have node.window > 0, Wayland windows have app_id
            is_x11_window = node.window and node.window > 0
            is_wayland_window = hasattr(node, 'app_id') and node.app_id and not node.window

            if is_x11_window or is_wayland_window:
                # Get project from marks (format: project:PROJECT_NAME:WINDOW_ID)
                project = None
                for mark in node.marks:
                    if mark.startswith("project:"):
                        mark_parts = mark.split(":")
                        project = mark_parts[1] if len(mark_parts) >= 2 else None
                        break

                # Get window class (X11 uses window_class, Wayland uses app_id)
                window_class = node.window_class if hasattr(node, 'window_class') and node.window_class else (node.app_id if hasattr(node, 'app_id') else "")

                # Determine classification from daemon state
                classification = "global"
                hidden = False
                if window_class:
                    if project and window_class in self.state_manager.state.scoped_classes:
                        classification = "scoped"
                    # Check if window is hidden (not on visible workspace or project mismatch)
                    active_project = self.state_manager.state.active_project
                    if classification == "scoped" and active_project and project != active_project:
                        hidden = True

                # Format workspace as string (CLI expects "1" or "1:name")
                workspace_name = container.name if container.type == "workspace" else ""
                workspace_str = workspace_name if workspace_name else str(workspace_num)

                # Use node.id for Wayland windows (unique identifier), node.window for X11
                window_id = node.window if is_x11_window else node.id

                # Read I3PM_APP_ID from process environment if PID available
                app_id = None
                if hasattr(node, 'pid') and node.pid:
                    try:
                        from .services.window_filter import read_process_environ
                        env = read_process_environ(node.pid)
                        app_id = env.get("I3PM_APP_ID")
                        if app_id:
                            logger.debug(f"Found I3PM_APP_ID for window {window_id} PID {node.pid}: {app_id}")
                        else:
                            i3pm_keys = [k for k in env.keys() if k.startswith('I3PM')]
                            logger.debug(f"No I3PM_APP_ID for window {window_id} PID {node.pid}, I3PM keys: {i3pm_keys}")
                    except (FileNotFoundError, PermissionError) as e:
                        # Process may have exited or we don't have permission
                        logger.debug(f"Failed to read environ for window {window_id} PID {node.pid}: {e}")
                    except Exception as e:
                        logger.error(f"Unexpected error reading environ for window {window_id} PID {node.pid}: {e}", exc_info=True)

                window_data = {
                    "id": window_id,
                    "pid": node.pid if hasattr(node, 'pid') else None,
                    "app_id": app_id,  # I3PM_APP_ID from process environment
                    "class": window_class,
                    "instance": node.window_instance or "",
                    "title": node.name or "",
                    "workspace": workspace_str,
                    "output": output_name,
                    "marks": node.marks,
                    "floating": node.floating == "user_on",
                    "focused": node.focused,
                    "hidden": hidden,
                    "fullscreen": node.fullscreen_mode > 0,
                    "geometry": {
                        "x": node.rect.x,
                        "y": node.rect.y,
                        "width": node.rect.width,
                        "height": node.rect.height,
                    },
                }
                windows.append(window_data)

            # Recurse into child nodes
            for child in (node.nodes + node.floating_nodes):
                extract(child, depth + 1)

        extract(container)
        return windows

    # ========================================================================
    # Feature 030: Production Readiness Methods (T016)
    # ========================================================================

    async def _daemon_status(self) -> Dict[str, Any]:
        """
        Get comprehensive daemon health and status

        Implements daemon.status JSON-RPC method from daemon-ipc.json

        Feature 030 (T029): Includes recovery status and i3 reconnection stats
        """
        import os
        from .monitoring.health import get_health_metrics

        start_time = time.perf_counter()

        try:
            # Get health metrics
            health = get_health_metrics()
            health.update_resource_usage()

            stats = await self.state_manager.get_stats()

            result = {
                "running": True,
                "uptime_seconds": health.uptime_seconds,
                "pid": os.getpid(),
                "memory_mb": health.memory_rss_mb,
                "event_count": health.total_events_processed,
                "error_count": health.total_errors,
                "last_event_time": datetime.fromtimestamp(health.last_event_time).isoformat() if health.last_event_time else None,
                "i3_connected": health.i3_connected,
                "active_project": stats.get("active_project"),
            }

            # Feature 030 (T029): Add recovery status
            if hasattr(self, 'startup_recovery_result') and self.startup_recovery_result:
                result["recovery"] = {
                    "startup_recovery_performed": True,
                    "startup_recovery_success": self.startup_recovery_result.success,
                    "actions_taken": self.startup_recovery_result.actions_taken,
                    "recovery_timestamp": self.startup_recovery_result.timestamp.isoformat(),
                }
            else:
                result["recovery"] = {
                    "startup_recovery_performed": False,
                }

            # Feature 030 (T029): Add i3 reconnection stats
            if hasattr(self, 'i3_reconnection_manager') and self.i3_reconnection_manager:
                reconnect_stats = self.i3_reconnection_manager.get_stats()
                result["i3_reconnection"] = reconnect_stats
            else:
                result["i3_reconnection"] = {
                    "is_connected": health.i3_connected,
                    "reconnection_count": 0,
                }

            return result

        finally:
            duration_ms = (time.perf_counter() - start_time) * 1000
            await self._log_ipc_event(
                event_type="query::daemon_status",
                duration_ms=duration_ms,
            )

    async def _daemon_events(self, params: Dict[str, Any]) -> Dict[str, Any]:
        """
        Query recent events from circular buffer with filtering

        Implements daemon.events JSON-RPC method from daemon-ipc.json

        Args:
            params: Query parameters
                - source: Filter by event source (i3, systemd, proc, all)
                - event_type: Filter by event type
                - limit: Maximum events to return (default: 20, max: 500)
                - since: ISO timestamp to filter events after
                - correlate: Include correlation analysis
        """
        start_time = time.perf_counter()

        try:
            if not self.event_buffer:
                return {
                    "events": [],
                    "total_events": 0,
                    "buffer_size": 0,
                }

            # Extract parameters
            source_filter = params.get("source", "all")
            event_type_filter = params.get("event_type")
            limit = min(params.get("limit", 20), 500)
            since_str = params.get("since")
            include_correlation = params.get("correlate", False)

            # Parse since timestamp
            since_dt = None
            if since_str:
                try:
                    since_dt = datetime.fromisoformat(since_str.replace('Z', '+00:00'))
                except ValueError:
                    logger.warning(f"Invalid 'since' timestamp: {since_str}")

            # Get events from buffer
            all_events = self.event_buffer.get_events(limit=limit)

            # Apply filters
            filtered_events = []
            for event in all_events:
                # Filter by source
                if source_filter != "all" and event.source != source_filter:
                    continue

                # Filter by event type
                if event_type_filter and event.event_type != event_type_filter:
                    continue

                # Filter by timestamp
                if since_dt and event.timestamp < since_dt:
                    continue

                filtered_events.append(event)

            # Convert to response format
            events_data = []
            for event in filtered_events:
                event_dict = {
                    "event_id": str(event.event_id),
                    "source": event.source,
                    "event_type": event.event_type,
                    "timestamp": event.timestamp.isoformat(),
                    "data": event.to_dict(),  # Include all event data
                }

                # Add correlation if requested
                if include_correlation and event.correlation_id:
                    event_dict["correlation_id"] = str(event.correlation_id)
                    event_dict["confidence_score"] = event.confidence_score

                events_data.append(event_dict)

            result = {
                "events": events_data,
                "total_events": len(self.event_buffer.buffer),
                "buffer_size": self.event_buffer.max_size,
            }

            return result

        finally:
            duration_ms = (time.perf_counter() - start_time) * 1000
            await self._log_ipc_event(
                event_type="query::daemon_events",
                result_count=len(result.get("events", [])),
                params=params,
                duration_ms=duration_ms,
            )

    async def _daemon_diagnose(self, params: Dict[str, Any]) -> Dict[str, Any]:
        """
        Generate comprehensive diagnostic snapshot

        Implements daemon.diagnose JSON-RPC method from daemon-ipc.json

        Args:
            params: Diagnostic options
                - include_events: Include recent event history (default: true)
                - include_i3_tree: Include complete i3 window tree (default: true)
                - include_config: Include current configuration (default: true)
        """
        from .monitoring.diagnostics import generate_diagnostic_snapshot

        start_time = time.perf_counter()

        try:
            # Extract parameters
            include_events = params.get("include_events", True)
            include_i3_tree = params.get("include_i3_tree", True)
            include_config = params.get("include_config", True)

            # Generate snapshot
            snapshot = await generate_diagnostic_snapshot(
                include_i3_tree=include_i3_tree,
                include_events=include_events,
                event_limit=100,
                sanitize=True,
            )

            # Get daemon status
            daemon_status = await self._daemon_status()

            # Build diagnostic result
            result = {
                "timestamp": snapshot.timestamp,
                "daemon_status": daemon_status,
            }

            if include_events:
                result["events"] = snapshot.recent_events

            if include_i3_tree:
                result["i3_tree"] = snapshot.i3_tree
                result["i3_outputs"] = snapshot.i3_outputs
                result["i3_workspaces"] = snapshot.i3_workspaces

            if include_config:
                result["projects"] = snapshot.projects
                result["classification_rules"] = snapshot.classification_rules

            return result

        finally:
            duration_ms = (time.perf_counter() - start_time) * 1000
            await self._log_ipc_event(
                event_type="query::daemon_diagnose",
                params=params,
                duration_ms=duration_ms,
            )

    async def _daemon_apps(self, params: Dict[str, Any]) -> Dict[str, Any]:
        """
        Get applications currently loaded in daemon's memory

        This method reads the application registry file that the daemon loaded
        at startup, providing visibility into what apps the daemon knows about.

        Implements daemon.apps JSON-RPC method

        Returns:
            Dict containing:
                - applications: List of application entries
                - version: Registry version
                - count: Number of applications
                - registry_path: Path to registry file
        """
        start_time = time.perf_counter()

        try:
            registry_path = Path.home() / ".config" / "i3" / "application-registry.json"

            if not registry_path.exists():
                raise RuntimeError(json.dumps({
                    "code": -32001,
                    "message": "Application registry not found",
                    "data": {"reason": "registry_file_not_found", "path": str(registry_path)}
                }))

            with open(registry_path, "r") as f:
                registry = json.load(f)

            applications = registry.get("applications", [])
            version = registry.get("version", "unknown")

            # Filter by name if requested
            name_filter = params.get("name")
            if name_filter:
                applications = [app for app in applications if app.get("name") == name_filter]

            # Filter by scope if requested
            scope_filter = params.get("scope")
            if scope_filter:
                applications = [app for app in applications if app.get("scope") == scope_filter]

            # Filter by workspace if requested
            workspace_filter = params.get("workspace")
            if workspace_filter:
                applications = [app for app in applications if app.get("preferred_workspace") == workspace_filter]

            return {
                "applications": applications,
                "version": version,
                "count": len(applications),
                "registry_path": str(registry_path),
            }

        finally:
            duration_ms = (time.perf_counter() - start_time) * 1000
            await self._log_ipc_event(
                event_type="query::daemon_apps",
                params=params,
                duration_ms=duration_ms,
            )

    async def _layout_save(self, params: Dict[str, Any]) -> Dict[str, Any]:
        """
        Capture and save current workspace layout.

        Feature 058: Python Backend Consolidation - User Story 2
        Implements layout_save JSON-RPC method from contracts/layout-api.json

        Args:
            params: Save parameters
                - project_name: Project name (required)
                - layout_name: Layout name (optional, defaults to project_name)

        Returns:
            {
                "project": str,
                "layout_name": str,
                "windows_captured": int,
                "file_path": str
            }

        Raises:
            ValueError: If project_name is missing
            LayoutError: If capture or save fails
        """
        start_time = time.perf_counter()

        try:
            project_name = params.get("project_name")
            layout_name = params.get("layout_name")

            if not project_name:
                raise ValueError("project_name parameter is required")

            # Create LayoutEngine instance
            from .services.layout_engine import LayoutEngine
            layout_engine = LayoutEngine(self.i3_connection)

            # Capture layout
            layout, warnings = await layout_engine.capture_layout(project_name, layout_name)

            # Log warnings
            for warning in warnings:
                logger.warning(f"Layout capture warning: {warning}")

            # Save to file
            filepath = layout_engine.save_layout(layout)

            result = {
                "project": layout.project_name,
                "layout_name": layout.layout_name,
                "windows_captured": len(layout.windows),
                "file_path": str(filepath)
            }

            logger.info(
                f"Layout saved: {layout.project_name}/{layout.layout_name} "
                f"({len(layout.windows)} windows) to {filepath}"
            )

            return result

        except ValueError as e:
            # Invalid params error code
            raise ValueError(str(e))
        except FileNotFoundError as e:
            # Project not found
            raise RuntimeError(f"Project not found: {params.get('project_name')}")
        except Exception as e:
            logger.error(f"Layout save failed: {e}", exc_info=True)
            raise RuntimeError(f"Layout save failed: {e}")
        finally:
            duration_ms = (time.perf_counter() - start_time) * 1000
            await self._log_ipc_event(
                event_type="layout::save",
                project_name=params.get("project_name"),
                params=params,
                duration_ms=duration_ms,
            )

    async def _layout_restore(self, params: Dict[str, Any]) -> Dict[str, Any]:
        """
        Restore workspace layout from snapshot.

        Feature 058: Python Backend Consolidation - User Story 2
        Implements layout_restore JSON-RPC method from contracts/layout-api.json

        Args:
            params: Restore parameters
                - project_name: Project name (required)
                - layout_name: Layout name (optional, defaults to project_name)

        Returns:
            {
                "restored": int,  # Number of windows successfully restored
                "missing": [  # Windows that couldn't be restored
                    {
                        "app_id": str,
                        "app_name": str,
                        "workspace": int
                    }
                ],
                "total": int  # Total windows in layout
            }

        Raises:
            ValueError: If project_name is missing
            LayoutError: If layout file not found or restoration fails
        """
        start_time = time.perf_counter()

        try:
            project_name = params.get("project_name")
            layout_name = params.get("layout_name")

            if not project_name:
                raise ValueError("project_name parameter is required")

            # Create LayoutEngine instance
            from .services.layout_engine import LayoutEngine
            layout_engine = LayoutEngine(self.i3_connection)

            # Restore layout
            restore_results = await layout_engine.restore_layout(project_name, layout_name)

            result = {
                "restored": restore_results["restored"],
                "missing": restore_results["missing"],
                "total": restore_results["total"]
            }

            logger.info(
                f"Layout restored: {project_name}/{layout_name or project_name} - "
                f"{result['restored']}/{result['total']} windows restored, "
                f"{len(result['missing'])} missing"
            )

            return result

        except FileNotFoundError as e:
            # Layout not found
            raise RuntimeError(
                f"Layout not found: {params.get('layout_name') or params.get('project_name')} "
                f"for project {params.get('project_name')}"
            )
        except ValueError as e:
            # Invalid params
            raise ValueError(str(e))
        except Exception as e:
            logger.error(f"Layout restore failed: {e}", exc_info=True)
            raise RuntimeError(f"Layout restore failed: {e}")
        finally:
            duration_ms = (time.perf_counter() - start_time) * 1000
            await self._log_ipc_event(
                event_type="layout::restore",
                project_name=params.get("project_name"),
                params=params,
                duration_ms=duration_ms,
            )

    async def _layout_list(self, params: Dict[str, Any]) -> Dict[str, Any]:
        """
        List saved layout snapshots.

        Feature 058: Python Backend Consolidation - User Story 2
        Implements layout_list JSON-RPC method from contracts/layout-api.json

        Args:
            params: List parameters
                - project_name: Project name (required)

        Returns:
            {
                "project": str,
                "layouts": [
                    {
                        "layout_name": str,
                        "timestamp": str (ISO 8601),
                        "windows_count": int,
                        "file_path": str
                    }
                ]
            }

        Raises:
            ValueError: If project_name is missing
        """
        start_time = time.perf_counter()

        try:
            project_name = params.get("project_name")

            if not project_name:
                raise ValueError("project_name parameter is required")

            # Create LayoutEngine instance
            from .services.layout_engine import LayoutEngine
            layout_engine = LayoutEngine(self.i3_connection)

            # List layouts
            layouts = layout_engine.list_layouts(project_name)

            result = {
                "project": project_name,
                "layouts": layouts
            }

            logger.info(f"Listed layouts: {len(layouts)} found for project {project_name}")

            return result

        except ValueError as e:
            raise ValueError(str(e))
        except Exception as e:
            logger.error(f"Layout list failed: {e}", exc_info=True)
            raise RuntimeError(f"Layout list failed: {e}")
        finally:
            duration_ms = (time.perf_counter() - start_time) * 1000
            await self._log_ipc_event(
                event_type="query::layout_list",
                project_name=params.get("project_name"),
                params=params,
                duration_ms=duration_ms,
            )

    async def _layout_delete(self, params: Dict[str, Any]) -> Dict[str, Any]:
        """
        Delete a saved layout snapshot.

        Feature 058: Python Backend Consolidation - User Story 2
        Implements layout_delete JSON-RPC method from contracts/layout-api.json

        Args:
            params: Delete parameters
                - project_name: Project name (required)
                - layout_name: Layout name (required)

        Returns:
            {
                "deleted": bool,
                "layout_name": str
            }

        Raises:
            ValueError: If required parameters are missing
            LayoutError: If layout not found
        """
        start_time = time.perf_counter()

        try:
            project_name = params.get("project_name")
            layout_name = params.get("layout_name")

            if not project_name or not layout_name:
                raise ValueError("project_name and layout_name parameters are required")

            # Create LayoutEngine instance
            from .services.layout_engine import LayoutEngine
            layout_engine = LayoutEngine(self.i3_connection)

            # Delete layout
            deleted = layout_engine.delete_layout(project_name, layout_name)

            if not deleted:
                raise RuntimeError(
                    f"Layout not found: {layout_name} for project {project_name}"
                )

            result = {
                "deleted": True,
                "layout_name": layout_name
            }

            logger.info(f"Deleted layout: {project_name}/{layout_name}")

            return result

        finally:
            duration_ms = (time.perf_counter() - start_time) * 1000
            await self._log_ipc_event(
                event_type="layout::delete",
                project_name=params.get("project"),
                params=params,
                duration_ms=duration_ms,
            )

    async def _layout_info(self, params: Dict[str, Any]) -> Dict[str, Any]:
        """
        Get detailed information about a saved layout

        Implements layout.info JSON-RPC method
        Feature 030: Task T048 (CLI info command)

        Args:
            params: Info parameters
                - name: Layout name (required)
                - project: Project name (default: "global")

        Returns:
            Dictionary with detailed layout information
        """
        start_time = time.perf_counter()

        try:
            name = params.get("name")
            project = params.get("project", "global")

            if not name:
                raise ValueError("'name' parameter is required")

            # Import layout module
            from .layout import load_layout

            # Load layout
            snapshot = load_layout(name=name, project=project)

            if not snapshot:
                raise ValueError(f"Layout not found: {name} (project: {project})")

            # Build detailed info
            workspaces = []
            for ws_layout in snapshot.workspace_layouts:
                ws_info = {
                    "workspace_num": ws_layout.workspace_num,
                    "workspace_name": ws_layout.workspace_name if ws_layout.workspace_name else "",
                    "output": ws_layout.output,
                    "window_count": len(ws_layout.windows),
                }
                workspaces.append(ws_info)

            monitors = []
            for monitor in snapshot.monitor_config.monitors:
                mon_info = {
                    "name": monitor.name,
                    "width": monitor.resolution.width if monitor.resolution else 0,
                    "height": monitor.resolution.height if monitor.resolution else 0,
                    "primary": monitor.primary,
                }
                monitors.append(mon_info)

            result = {
                "name": snapshot.name,
                "project": snapshot.project,
                "created_at": snapshot.created_at.isoformat(),
                "total_windows": snapshot.metadata.get("total_windows", 0),
                "total_workspaces": snapshot.metadata.get("total_workspaces", 0),
                "total_monitors": snapshot.metadata.get("total_monitors", 0),
                "workspaces": workspaces,
                "monitors": monitors,
            }

            logger.info(f"Retrieved layout info: {project}/{name}")

            return result

        finally:
            duration_ms = (time.perf_counter() - start_time) * 1000
            await self._log_ipc_event(
                event_type="query::layout_info",
                project_name=params.get("project"),
                params=params,
                duration_ms=duration_ms,
            )

    # ======================================================================
    # Feature 033: Declarative Workspace-to-Monitor Mapping Methods
    # ======================================================================

    async def _get_monitor_config(self) -> Dict[str, Any]:
        """Get current workspace-to-monitor configuration.

        Feature 033: T021

        Returns:
            Configuration dict from workspace-monitor-mapping.json
        """
        start_time = time.perf_counter()
        error_msg = None

        try:
            from .monitor_config_manager import MonitorConfigManager

            config_manager = MonitorConfigManager()
            config = config_manager.load_config()

            # Convert Pydantic model to dict for JSON serialization
            return config.model_dump()

        except Exception as e:
            error_msg = str(e)
            logger.error(f"Error getting monitor config: {e}")
            raise
        finally:
            duration_ms = (time.perf_counter() - start_time) * 1000
            await self._log_ipc_event(
                event_type="query::monitor_config",
                duration_ms=duration_ms,
                error=error_msg,
            )

    async def _validate_monitor_config(self, params: Dict[str, Any]) -> Dict[str, Any]:
        """Validate workspace-to-monitor configuration file.

        Feature 033: T022

        Args:
            params: Optional params dict with:
                - config_path: str (optional) - Path to config file

        Returns:
            ValidationResult dict with valid, issues, and config fields
        """
        start_time = time.perf_counter()
        error_msg = None

        try:
            from pathlib import Path
            from .monitor_config_manager import MonitorConfigManager

            # Get config path from params or use default
            config_path_str = params.get("config_path")
            if config_path_str:
                config_path = Path(config_path_str)
            else:
                config_path = MonitorConfigManager.DEFAULT_CONFIG_PATH

            # Validate configuration
            validation_result = MonitorConfigManager.validate_config_file(config_path)

            # Convert Pydantic models to dicts
            result_dict = {
                "valid": validation_result.valid,
                "issues": [issue.model_dump() for issue in validation_result.issues],
                "config": validation_result.config.model_dump() if validation_result.config else None,
            }

            return result_dict

        except Exception as e:
            error_msg = str(e)
            logger.error(f"Error validating monitor config: {e}")
            raise
        finally:
            duration_ms = (time.perf_counter() - start_time) * 1000
            await self._log_ipc_event(
                event_type="config::validate_monitor",
                params=params,
                duration_ms=duration_ms,
                error=error_msg,
            )

    async def _reload_monitor_config(self) -> Dict[str, Any]:
        """Reload workspace-to-monitor configuration from disk.

        Feature 033: T023

        Returns:
            Dict with success status and change summary
        """
        start_time = time.perf_counter()
        error_msg = None

        try:
            from .monitor_config_manager import MonitorConfigManager

            config_manager = MonitorConfigManager()

            # Force reload from disk
            new_config = config_manager.load_config(force_reload=True)

            # Get summary of changes (simplified - just report success)
            changes = [
                f"Configuration reloaded from {config_manager.config_path}",
                f"Distribution rules updated for {len(new_config.distribution.model_dump())} monitor configurations",
                f"Workspace preferences: {len(new_config.workspace_preferences)} entries",
            ]

            logger.info(f"Monitor configuration reloaded: {config_manager.config_path}")

            return {
                "success": True,
                "changes": changes,
                "error": None,
            }

        except Exception as e:
            error_msg = str(e)
            logger.error(f"Error reloading monitor config: {e}")
            return {
                "success": False,
                "changes": [],
                "error": str(e),
            }
        finally:
            duration_ms = (time.perf_counter() - start_time) * 1000
            await self._log_ipc_event(
                event_type="config::reload_monitor",
                config_type="workspace_monitor_mapping",
                duration_ms=duration_ms,
                error=error_msg,
            )

    async def _reassign_workspaces(self, params: Dict[str, Any]) -> Dict[str, Any]:
        """Reassign all workspaces to monitors based on configuration.

        Feature 033: T020

        Args:
            params: Optional params dict with:
                - dry_run: bool (default False) - Preview without applying

        Returns:
            Dict with success status, assignments_made count, and errors list
        """
        start_time = time.perf_counter()
        error_msg = None

        try:
            from .monitor_config_manager import MonitorConfigManager
            from .workspace_manager import get_monitor_configs, assign_workspaces_to_monitors

            dry_run = params.get("dry_run", False)

            # Get i3 connection
            if not self.i3_connection or not self.i3_connection.conn:
                raise RuntimeError("i3 connection not available")

            i3 = self.i3_connection.conn  # Get the underlying i3ipc connection

            # Get monitor configurations with roles
            config_manager = MonitorConfigManager()
            monitors = await get_monitor_configs(i3, config_manager)

            if not monitors:
                return {
                    "success": False,
                    "assignments_made": 0,
                    "errors": ["No active monitors detected"],
                }

            # Count workspaces to be assigned
            distribution = config_manager.get_workspace_distribution(len(monitors))
            total_workspaces = sum(len(ws_list) for ws_list in distribution.values())

            # Apply workspace assignments (unless dry-run)
            if not dry_run:
                await assign_workspaces_to_monitors(i3, monitors, config_manager=config_manager)
                logger.info(f"Reassigned {total_workspaces} workspaces to {len(monitors)} monitors")
            else:
                logger.info(f"Dry-run: Would reassign {total_workspaces} workspaces to {len(monitors)} monitors")

            return {
                "success": True,
                "assignments_made": total_workspaces if not dry_run else 0,
                "errors": [],
            }

        except Exception as e:
            error_msg = str(e)
            logger.error(f"Error reassigning workspaces: {e}")
            return {
                "success": False,
                "assignments_made": 0,
                "errors": [str(e)],
            }
        finally:
            duration_ms = (time.perf_counter() - start_time) * 1000
            await self._log_ipc_event(
                event_type="workspace::reassign",
                params=params,
                duration_ms=duration_ms,
                error=error_msg,
            )

    async def _get_monitors(self) -> list[Dict[str, Any]]:
        """Get current monitor/output configurations with roles.

        Feature 033: T032 (User Story 2)

        Returns:
            List of MonitorConfig dicts with name, active, primary, role, rect, current_workspace
        """
        start_time = time.perf_counter()
        error_msg = None

        try:
            from .monitor_config_manager import MonitorConfigManager
            from .workspace_manager import get_monitor_configs
            from .models import MonitorConfig as PydanticMonitorConfig, OutputRect, MonitorRole

            # Get i3 connection
            if not self.i3_connection or not self.i3_connection.conn:
                raise RuntimeError("i3 connection not available")

            i3 = self.i3_connection.conn

            # Get monitor configurations with assigned roles
            config_manager = MonitorConfigManager()
            monitors_dataclass = await get_monitor_configs(i3, config_manager)

            # Convert dataclass instances to Pydantic models for JSON-RPC
            monitors_pydantic = []
            for monitor in monitors_dataclass:
                pydantic_monitor = PydanticMonitorConfig(
                    name=monitor.name,
                    active=monitor.active,
                    primary=monitor.primary,
                    role=MonitorRole(monitor.role) if monitor.role else None,
                    rect=OutputRect(**monitor.rect),
                    current_workspace=None,  # TODO: Query from i3
                )
                monitors_pydantic.append(pydantic_monitor)

            # Convert Pydantic models to dicts for JSON serialization
            return [monitor.model_dump() for monitor in monitors_pydantic]

        except Exception as e:
            error_msg = str(e)
            logger.error(f"Error getting monitors: {e}")
            raise
        finally:
            duration_ms = (time.perf_counter() - start_time) * 1000
            await self._log_ipc_event(
                event_type="query::monitors",
                duration_ms=duration_ms,
                error=error_msg,
            )

    async def _get_workspaces(self) -> list[Dict[str, Any]]:
        """Get current workspace assignments with target roles.

        Feature 033: T033 (User Story 2)

        Returns:
            List of WorkspaceAssignment dicts with workspace_num, output_name, target_role, target_output, source, visible
        """
        start_time = time.perf_counter()
        error_msg = None

        try:
            from .monitor_config_manager import MonitorConfigManager
            from .workspace_manager import get_monitor_configs
            from .models import WorkspaceAssignment, MonitorRole

            # Get i3 connection
            if not self.i3_connection or not self.i3_connection.conn:
                raise RuntimeError("i3 connection not available")

            i3 = self.i3_connection.conn

            # Get monitor configurations with assigned roles
            config_manager = MonitorConfigManager()
            monitors = await get_monitor_configs(i3, config_manager)

            # Build role_map: role -> output_name
            role_map = {monitor.role: monitor.name for monitor in monitors if monitor.role}

            # Get workspace distribution for current monitor count
            distribution = config_manager.get_workspace_distribution(len(monitors))

            # Query i3 for actual workspace assignments
            i3_workspaces = await i3.get_workspaces()

            # Build workspace assignments
            assignments = []
            for ws in i3_workspaces:
                # Determine target role for this workspace
                target_role = None
                target_output = None
                source = "runtime"

                # Check workspace preferences first
                config = config_manager.load_config()
                if ws.num in config.workspace_preferences:
                    target_role = config.workspace_preferences[ws.num]
                    target_output = role_map.get(target_role)
                    source = "explicit"
                else:
                    # Check distribution rules
                    for role, ws_nums in distribution.items():
                        if ws.num in ws_nums:
                            target_role = role
                            target_output = role_map.get(role)
                            source = "default"
                            break

                assignment = WorkspaceAssignment(
                    workspace_num=ws.num,
                    output_name=ws.output,
                    target_role=target_role,
                    target_output=target_output,
                    source=source,
                    visible=ws.visible,
                    window_count=0,  # TODO: Query window count from i3 tree
                )
                assignments.append(assignment)

            # Convert to dicts
            return [assignment.model_dump() for assignment in assignments]

        except Exception as e:
            error_msg = str(e)
            logger.error(f"Error getting workspaces: {e}")
            raise
        finally:
            duration_ms = (time.perf_counter() - start_time) * 1000
            await self._log_ipc_event(
                event_type="query::workspaces",
                duration_ms=duration_ms,
                error=error_msg,
            )

    async def _get_system_state(self) -> Dict[str, Any]:
        """Get complete monitor system state.

        Feature 033: T034 (User Story 2)

        Combines monitors and workspaces into unified system state.

        Returns:
            MonitorSystemState dict with monitors, workspaces, active_monitor_count, primary_output, last_updated
        """
        start_time = time.perf_counter()
        error_msg = None

        try:
            from .models import MonitorSystemState

            # Get monitors and workspaces
            monitors = await self._get_monitors()
            workspaces = await self._get_workspaces()

            # Calculate derived fields
            active_monitor_count = len([m for m in monitors if m["active"]])
            primary_output = next((m["name"] for m in monitors if m["primary"]), None)

            # Build system state
            state = MonitorSystemState(
                monitors=[m for m in monitors],  # Already dicts
                workspaces=[ws for ws in workspaces],  # Already dicts
                active_monitor_count=active_monitor_count,
                primary_output=primary_output,
                last_updated=time.time(),
            )

            return state.model_dump()

        except Exception as e:
            error_msg = str(e)
            logger.error(f"Error getting system state: {e}")
            raise
        finally:
            duration_ms = (time.perf_counter() - start_time) * 1000
            await self._log_ipc_event(
                event_type="query::system_state",
                duration_ms=duration_ms,
                error=error_msg,
            )

    # Feature 037: Window filtering methods

    async def _hide_windows(self, params: Dict[str, Any]) -> Dict[str, Any]:
        """Hide windows for a project (move to scratchpad).

        Args:
            params: {
                "project_name": str  # Project whose windows to hide
            }

        Returns:
            {
                "windows_hidden": int,
                "errors": List[str],
                "duration_ms": float
            }
        """
        start_time = time.perf_counter()
        error_msg = None

        try:
            project_name = params.get("project_name")
            if not project_name:
                raise ValueError("project_name parameter is required")

            if not self.i3_connection or not self.i3_connection.conn:
                raise RuntimeError("i3 connection not available")

            if not self.workspace_tracker:
                raise RuntimeError("workspace tracker not available")

            # Get i3 tree and find all visible windows for project
            tree = await self.i3_connection.conn.get_tree()
            window_ids_to_hide = []

            async def collect_project_windows(con):
                # Feature 046: Check for windows using container ID (works for both X11 and Wayland)
                # For Wayland: con.window is None, but con.id exists
                # For X11: both con.window and con.id exist
                if hasattr(con, 'id') and (con.window is not None or (hasattr(con, 'app_id') and con.app_id)):
                    # Feature 058: Use window marks instead of /proc for project detection
                    # Marks are mutable and updated by intent-first architecture, while
                    # /proc environment is immutable and frozen at process launch.
                    # This fixes filtering for shared-PID apps (VS Code, Chrome, Electron).
                    window_project = None
                    is_scoped = False

                    # DEBUG: Log all windows with marks
                    if con.marks:
                        logger.debug(
                            f"Scanning window {con.id} for hiding: "
                            f"marks={con.marks}, "
                            f"app_id={getattr(con, 'app_id', None)}, "
                            f"name={getattr(con, 'name', '')[:30]}"
                        )

                    for mark in con.marks:
                        if mark.startswith("project:"):
                            mark_parts = mark.split(":")
                            if len(mark_parts) >= 2:
                                window_project = mark_parts[1]
                                is_scoped = True  # If it has a project mark, it's scoped
                                logger.debug(
                                    f"Window {con.id} has project mark: {mark} "
                                    f"(extracted project: {window_project})"
                                )
                                break

                    # Only hide if matches project and is scoped
                    if window_project == project_name and is_scoped:
                        logger.info(
                            f"Will hide window {con.id} (project '{window_project}' matches '{project_name}')"
                        )
                        window_ids_to_hide.append(con.id)

                for child in con.nodes:
                    await collect_project_windows(child)
                for child in con.floating_nodes:
                    await collect_project_windows(child)

            await collect_project_windows(tree)

            # Hide windows in batch
            hidden_count, errors = await window_filtering.hide_windows_batch(
                self.i3_connection.conn,
                window_ids_to_hide,
                self.workspace_tracker,
            )

            logger.info(
                f"Hidden {hidden_count} windows for project '{project_name}' "
                f"({len(errors)} errors)"
            )

            duration_ms = (time.perf_counter() - start_time) * 1000

            return {
                "windows_hidden": hidden_count,
                "errors": errors,
                "duration_ms": duration_ms,
            }

        except Exception as e:
            error_msg = str(e)
            logger.error(f"Error hiding windows: {e}")
            raise
        finally:
            duration_ms = (time.perf_counter() - start_time) * 1000
            await self._log_ipc_event(
                event_type="project::hide_windows",
                duration_ms=duration_ms,
                error=error_msg,
            )

    async def _restore_windows(self, params: Dict[str, Any]) -> Dict[str, Any]:
        """Restore windows for a project (from scratchpad).

        Args:
            params: {
                "project_name": str,  # Project whose windows to restore
                "fallback_workspace": int = 1  # Workspace for invalid positions
            }

        Returns:
            {
                "windows_restored": int,
                "errors": List[str],
                "fallback_warnings": List[str],
                "duration_ms": float
            }
        """
        start_time = time.perf_counter()
        error_msg = None

        try:
            project_name = params.get("project_name")
            fallback_workspace = params.get("fallback_workspace", 1)

            if not project_name:
                raise ValueError("project_name parameter is required")

            if not self.i3_connection or not self.i3_connection.conn:
                raise RuntimeError("i3 connection not available")

            if not self.workspace_tracker:
                raise RuntimeError("workspace tracker not available")

            # Get all scratchpad windows
            scratchpad_windows = await window_filtering.get_scratchpad_windows(
                self.i3_connection.conn
            )

            # Find windows matching project
            # Use window marks instead of /proc for project detection (Feature 046)
            # Marks format: "project:PROJECT_NAME:WINDOW_ID"
            window_ids_to_restore = []
            for window in scratchpad_windows:
                window_project = None
                for mark in window.marks:
                    if mark.startswith("project:"):
                        mark_parts = mark.split(":")
                        if len(mark_parts) >= 2:
                            window_project = mark_parts[1]
                            break

                if window_project == project_name:
                    window_ids_to_restore.append(window.id)

            # Restore windows in batch
            restored_count, errors, fallback_warnings = await window_filtering.restore_windows_batch(
                self.i3_connection.conn,
                window_ids_to_restore,
                self.workspace_tracker,
                fallback_workspace,
            )

            logger.info(
                f"Restored {restored_count} windows for project '{project_name}' "
                f"({len(errors)} errors, {len(fallback_warnings)} fallbacks)"
            )

            duration_ms = (time.perf_counter() - start_time) * 1000

            return {
                "windows_restored": restored_count,
                "errors": errors,
                "fallback_warnings": fallback_warnings,
                "duration_ms": duration_ms,
            }

        except Exception as e:
            error_msg = str(e)
            logger.error(f"Error restoring windows: {e}")
            raise
        finally:
            duration_ms = (time.perf_counter() - start_time) * 1000
            await self._log_ipc_event(
                event_type="project::restore_windows",
                duration_ms=duration_ms,
                error=error_msg,
            )

    async def _switch_with_filtering(self, params: Dict[str, Any]) -> Dict[str, Any]:
        """Switch projects with automatic window filtering.

        Args:
            params: {
                "old_project": str,  # Previous project (windows to hide)
                "new_project": str,  # New project (windows to restore)
                "fallback_workspace": int = 1
            }

        Returns:
            {
                "windows_hidden": int,
                "windows_restored": int,
                "errors": List[str],
                "fallback_warnings": List[str],
                "duration_ms": float
            }
        """
        start_time = time.perf_counter()
        error_msg = None

        try:
            old_project = params.get("old_project", "")
            new_project = params.get("new_project")
            fallback_workspace = params.get("fallback_workspace", 1)

            if not new_project:
                raise ValueError("new_project parameter is required")

            if not self.i3_connection or not self.i3_connection.conn:
                raise RuntimeError("i3 connection not available")

            if not self.workspace_tracker:
                raise RuntimeError("workspace tracker not available")

            all_errors = []
            fallback_warnings = []

            # Phase 1: Hide windows from old project (if any)
            windows_hidden = 0
            if old_project:
                hide_result = await self._hide_windows({"project_name": old_project})
                windows_hidden = hide_result["windows_hidden"]
                all_errors.extend(hide_result.get("errors", []))

            # Phase 2: Restore windows for new project
            restore_result = await self._restore_windows({
                "project_name": new_project,
                "fallback_workspace": fallback_workspace,
            })
            windows_restored = restore_result["windows_restored"]
            all_errors.extend(restore_result.get("errors", []))
            fallback_warnings = restore_result.get("fallback_warnings", [])

            logger.info(
                f"Project switch filtering: {old_project or '(none)'} → {new_project} "
                f"(hidden {windows_hidden}, restored {windows_restored})"
            )

            duration_ms = (time.perf_counter() - start_time) * 1000

            return {
                "windows_hidden": windows_hidden,
                "windows_restored": windows_restored,
                "errors": all_errors,
                "fallback_warnings": fallback_warnings,
                "duration_ms": duration_ms,
            }

        except Exception as e:
            error_msg = str(e)
            logger.error(f"Error in switch with filtering: {e}")
            raise
        finally:
            duration_ms = (time.perf_counter() - start_time) * 1000
            await self._log_ipc_event(
                event_type="project::switch_with_filtering",
                duration_ms=duration_ms,
                error=error_msg,
            )

    async def _get_hidden_windows(self, params: Dict[str, Any]) -> Dict[str, Any]:
        """Get all hidden windows (in scratchpad) grouped by project.

        Feature 037 US5 T036: Provides visibility into hidden windows for debugging
        and manual management. Queries scratchpad windows, reads I3PM_* variables,
        and groups by project name.

        Args:
            params: {
                "project_name": str (optional) # Filter by specific project
                "workspace": int (optional)    # Filter by tracked workspace
                "app_name": str (optional)     # Filter by app name
            }

        Returns:
            {
                "projects": {
                    "<project_name>": [
                        {
                            "window_id": int,
                            "app_name": str,
                            "window_class": str,
                            "window_title": str,
                            "tracked_workspace": int,
                            "floating": bool,
                            "last_seen": float
                        },
                        ...
                    ]
                },
                "total_hidden": int,
                "duration_ms": float
            }
        """
        start_time = time.perf_counter()
        error_msg = None

        try:
            if not self.i3_connection or not self.i3_connection.conn:
                raise RuntimeError("i3 connection not available")

            if not self.workspace_tracker:
                raise RuntimeError("workspace tracker not available")

            # Get filters
            filter_project = params.get("project_name")
            filter_workspace = params.get("workspace")
            filter_app = params.get("app_name")

            # Get all scratchpad windows
            scratchpad_windows = await window_filtering.get_scratchpad_windows(
                self.i3_connection.conn
            )

            # Group windows by project
            projects_map = {}
            total_hidden = 0

            for window in scratchpad_windows:
                # Read I3PM_* environment variables
                i3pm_env = await window_filtering.get_window_i3pm_env(window.id, window.pid, window.window)
                project_name = i3pm_env.get("I3PM_PROJECT_NAME", "(unknown)")
                app_name = i3pm_env.get("I3PM_APP_NAME", "unknown")

                # Apply filters
                if filter_project and project_name != filter_project:
                    continue
                if filter_app and app_name != filter_app:
                    continue

                # Get tracking info
                tracking_info = self.workspace_tracker.windows.get(window.id, {})
                tracked_workspace = tracking_info.get("workspace_number", 0)

                if filter_workspace and tracked_workspace != filter_workspace:
                    continue

                # Build window info
                window_info = {
                    "window_id": window.id,
                    "app_name": app_name,
                    "window_class": window.window_class or "unknown",
                    "window_title": window.name or "(no title)",
                    "tracked_workspace": tracked_workspace,
                    "floating": tracking_info.get("floating", False),
                    "last_seen": tracking_info.get("last_seen", 0.0),
                }

                # Add to project group
                if project_name not in projects_map:
                    projects_map[project_name] = []
                projects_map[project_name].append(window_info)
                total_hidden += 1

            logger.debug(
                f"Found {total_hidden} hidden windows across {len(projects_map)} projects"
            )

            duration_ms = (time.perf_counter() - start_time) * 1000

            return {
                "projects": projects_map,
                "total_hidden": total_hidden,
                "duration_ms": duration_ms,
            }

        except Exception as e:
            error_msg = str(e)
            logger.error(f"Error getting hidden windows: {e}")
            raise
        finally:
            duration_ms = (time.perf_counter() - start_time) * 1000
            await self._log_ipc_event(
                event_type="windows::get_hidden",
                duration_ms=duration_ms,
                error=error_msg,
            )

    async def _get_window_state(self, params: Dict[str, Any]) -> Dict[str, Any]:
        """Get comprehensive state for a specific window.

        Feature 037 US5 T037: Provides detailed window inspection for debugging.
        Feature 041 T022: Includes launch correlation metadata if available.
        Shows all I3PM_* variables, tracking state, and i3 window properties.

        Args:
            params: {
                "window_id": int  # Window to inspect
            }

        Returns:
            {
                "window_id": int,
                "visible": bool,  # true if not in scratchpad
                "window_class": str,
                "window_title": str,
                "pid": int,
                "i3pm_env": {
                    "I3PM_PROJECT_NAME": str,
                    "I3PM_APP_NAME": str,
                    "I3PM_SCOPE": str,
                    ... # all I3PM_* variables
                },
                "tracking": {
                    "workspace_number": int,
                    "floating": bool,
                    "geometry": dict,  # Feature 038: x, y, width, height for floating windows
                    "original_scratchpad": bool,  # Feature 038: True if window was in scratchpad before filtering
                    "last_seen": float,
                    "project_name": str,
                    "app_name": str
                },
                "i3_state": {
                    "workspace": int,
                    "output": str,
                    "floating": str,
                    "focused": bool
                },
                "correlation": {  # Feature 041 T022, T040: Optional, only present if matched via launch
                    "matched_via_launch": bool,
                    "launch_id": str,
                    "confidence": float,  # 0.0 - 1.0
                    "confidence_level": str,  # EXACT, HIGH, MEDIUM, LOW
                    "signals_used": {
                        "class_match": bool,
                        "time_delta": float,  # seconds
                        "time_score": float,  # 0.0 - 0.3 time proximity bonus
                        "workspace_match": bool,  # T040: Workspace location match
                        "launch_workspace": int,  # T040: Expected workspace number
                        "window_workspace": int,  # T040: Actual workspace number
                        "workspace_bonus": float  # T040: 0.2 if match, 0.0 otherwise
                    }
                }
            }
        """
        start_time = time.perf_counter()
        error_msg = None

        try:
            window_id = params.get("window_id")
            if window_id is None:
                raise ValueError("window_id parameter is required")

            if not self.i3_connection or not self.i3_connection.conn:
                raise RuntimeError("i3 connection not available")

            # Find window in i3 tree
            tree = await self.i3_connection.conn.get_tree()

            def find_window(con):
                if con.id == window_id:
                    return con
                for child in con.nodes:
                    result = find_window(child)
                    if result:
                        return result
                for child in con.floating_nodes:
                    result = find_window(child)
                    if result:
                        return result
                return None

            window = find_window(tree)
            if not window:
                raise ValueError(f"Window {window_id} not found")

            # Check if in scratchpad
            scratchpad_windows = await window_filtering.get_scratchpad_windows(
                self.i3_connection.conn
            )
            is_visible = window_id not in [w.id for w in scratchpad_windows]

            # Read I3PM_* environment variables
            i3pm_env = await window_filtering.get_window_i3pm_env(window_id, window.pid, window.window)

            # Get tracking info
            tracking_info = self.workspace_tracker.windows.get(window_id, {}) if self.workspace_tracker else {}

            # Feature 041 T022: Get correlation metadata from WindowInfo if available
            window_info = await self.state_manager.get_window(window_id)
            correlation_info = None
            if window_info and window_info.correlation_matched:
                correlation_info = {
                    "matched_via_launch": window_info.correlation_matched,
                    "launch_id": window_info.correlation_launch_id,
                    "confidence": window_info.correlation_confidence,
                    "confidence_level": window_info.correlation_confidence_level,
                    "signals_used": window_info.correlation_signals,
                }

            # Get i3 state
            workspace = window.workspace()
            i3_state = {
                "workspace": workspace.num if workspace else None,
                "output": workspace.ipc_data.get("output") if workspace else None,
                "floating": window.floating,
                "focused": window.focused,
            }

            logger.debug(f"Inspected window {window_id}: visible={is_visible}")

            duration_ms = (time.perf_counter() - start_time) * 1000

            # Feature 041 T022: Include correlation field in response
            result = {
                "window_id": window_id,
                "visible": is_visible,
                "window_class": window.window_class or "unknown",
                "window_title": window.name or "(no title)",
                "pid": window.pid,
                "i3pm_env": i3pm_env,
                "tracking": tracking_info,
                "i3_state": i3_state,
                "duration_ms": duration_ms,
            }

            # Add correlation field only if window was matched via launch
            if correlation_info:
                result["correlation"] = correlation_info

            return result

        except Exception as e:
            error_msg = str(e)
            logger.error(f"Error getting window state: {e}")
            raise
        finally:
            duration_ms = (time.perf_counter() - start_time) * 1000
            await self._log_ipc_event(
                event_type="windows::get_state",
                duration_ms=duration_ms,
                error=error_msg,
            )

    # ========================================================================
    # Feature 039: Diagnostic API Methods (T087-T092)
    # ========================================================================

    async def _health_check(self) -> Dict[str, Any]:
        """
        Health check method for diagnostic CLI.
        
        Feature 039 - T087
        
        Returns comprehensive daemon health status including:
        - Daemon version and uptime
        - i3 IPC connection status
        - JSON-RPC server status
        - Event subscription details
        - Window tracking stats
        - Overall health assessment
        
        Returns:
            DiagnosticReport with health information
        """
        start_time = time.perf_counter()
        
        # Get daemon start time (uptime)
        daemon_start = getattr(self.state_manager, 'daemon_start_time', time.time())
        uptime_seconds = time.time() - daemon_start
        
        # Check i3 IPC connection
        i3_connected = False
        if self.i3_connection:
            i3_connected = self.i3_connection.is_connected
        
        # Check event subscriptions (from existing _daemon_status method)
        event_subscriptions = []
        if self.event_buffer:
            # Get subscription stats from event buffer
            buffer_stats = getattr(self.event_buffer, 'get_stats', lambda: {})()
            for sub_type in ['window', 'workspace', 'output', 'tick']:
                events = [e for e in self.event_buffer.get_recent(limit=500) if e.event_type.startswith(sub_type)]
                last_event = events[0] if events else None

                event_subscriptions.append({
                    "subscription_type": sub_type,
                    "is_active": i3_connected,
                    "event_count": len(events),
                    "last_event_time": last_event.timestamp.isoformat() if last_event else None,
                    "last_event_type": last_event.event_type if last_event else None
                })
        
        # Get total events processed
        total_events = len(self.event_buffer.get_recent(limit=9999)) if self.event_buffer else 0
        
        # Get total windows tracked
        total_windows = len(self.state_manager.state.window_map)
        
        # Assess overall health
        health_issues = []
        if not i3_connected:
            health_issues.append("i3 IPC connection lost")
        if not event_subscriptions:
            health_issues.append("No event subscriptions active")
        if total_events == 0 and uptime_seconds > 60:
            health_issues.append("No events processed (daemon may not be receiving events)")
        
        overall_status = "healthy"
        if len(health_issues) > 0:
            if "i3 IPC connection lost" in health_issues or "No event subscriptions" in health_issues:
                overall_status = "critical"
            else:
                overall_status = "warning"
        
        duration_ms = (time.perf_counter() - start_time) * 1000
        
        result = {
            "daemon_version": "1.4.0",  # TODO: Get from module __version__
            "uptime_seconds": round(uptime_seconds, 1),
            "i3_ipc_connected": i3_connected,
            "json_rpc_server_running": True,  # If we're responding, server is running
            "event_subscriptions": event_subscriptions,
            "total_events_processed": total_events,
            "total_windows": total_windows,
            "overall_status": overall_status,
            "health_issues": health_issues
        }
        
        await self._log_ipc_event(
            event_type="health_check",
            duration_ms=duration_ms
        )
        
        return result

    async def _get_window_identity_diagnostic(self, params: Dict[str, Any]) -> Dict[str, Any]:
        """
        Get comprehensive window identity for diagnostic purposes.
        
        Feature 039 - T088
        
        Args:
            params: {"window_id": int}
        
        Returns:
            WindowIdentity with all window properties
        
        Raises:
            Error -32001: Window not found
            Error -32002: Window not tracked by daemon
        """
        start_time = time.perf_counter()
        window_id = params.get("window_id")
        
        if not window_id:
            raise ValueError("window_id parameter required")
        
        # Get window from i3
        if not self.i3_connection or not self.i3_connection.is_connected:
            raise RuntimeError("i3 IPC connection not available")
        
        try:
            tree = await self.i3_connection.conn.get_tree()
            window = tree.find_by_id(window_id)
            
            if not window:
                raise ValueError(f"Window {window_id} not found")
            
            # Get window properties
            window_class = window.window_class or "unknown"
            window_instance = window.window_instance or ""
            window_title = window.name or "(no title)"
            window_pid = window.pid if hasattr(window, 'pid') else None
            
            # Get workspace info
            workspace = window.workspace()
            workspace_number = workspace.num if workspace else None
            workspace_name = workspace.name if workspace else None
            output_name = workspace.ipc_data.get('output') if workspace else None
            
            # Get window state
            is_floating = window.floating != 'auto_off' if hasattr(window, 'floating') else False
            is_focused = window.focused
            
            # Check if window is hidden (in scratchpad)
            is_hidden = False
            parent = window.parent
            while parent:
                if parent.scratchpad_state and parent.scratchpad_state != 'none':
                    is_hidden = True
                    break
                parent = parent.parent
            
            # Get I3PM environment from /proc
            i3pm_env = None
            if window_pid:
                from .services.window_filter import read_process_environ
                env = read_process_environ(window_pid)
                if env:
                    i3pm_env = {
                        "app_id": env.get("I3PM_APP_ID"),
                        "app_name": env.get("I3PM_APP_NAME"),
                        "project_name": env.get("I3PM_PROJECT_NAME"),
                        "scope": env.get("I3PM_SCOPE")
                    }
            
            # Get i3 marks
            i3pm_marks = [m for m in (window.marks or []) if m.startswith("project:") or m.startswith("app:")]
            
            # Get normalized class
            from .services.window_identifier import normalize_class, get_window_identity
            window_class_normalized = normalize_class(window_class)
            
            # Check if tracked by daemon
            tracked_window = self.state_manager.state.window_map.get(window_id)
            matched_app = None
            match_type = "none"
            
            if tracked_window:
                matched_app = getattr(tracked_window, 'app_name', None)
                match_type = getattr(tracked_window, 'match_type', 'tracked')
            
            duration_ms = (time.perf_counter() - start_time) * 1000
            
            result = {
                "window_id": window_id,
                "window_class": window_class,
                "window_class_normalized": window_class_normalized,
                "window_instance": window_instance,
                "window_title": window_title,
                "window_pid": window_pid,
                "workspace_number": workspace_number,
                "workspace_name": workspace_name,
                "output_name": output_name,
                "is_floating": is_floating,
                "is_focused": is_focused,
                "is_hidden": is_hidden,
                "i3pm_env": i3pm_env,
                "i3pm_marks": i3pm_marks,
                "matched_app": matched_app,
                "match_type": match_type
            }
            
            await self._log_ipc_event(
                event_type="get_window_identity",
                duration_ms=duration_ms,
                params={"window_id": window_id}
            )
            
            return result
            
        except ValueError as e:
            if "not found" in str(e):
                # Return JSON-RPC error -32001
                raise RuntimeError(json.dumps({
                    "code": -32001,
                    "message": "Window not found",
                    "data": {"window_id": window_id}
                }))
            raise
        except Exception as e:
            logger.error(f"Error getting window identity: {e}")
            raise

    async def _get_window_environment(self, params: Dict[str, Any]) -> Dict[str, Any]:
        """
        Get I3PM environment variables for a window by PID.

        Feature 058 - Phase 3: Eliminate duplicate environment reading

        Args:
            params: {"pid": int} - Process ID of the window

        Returns:
            Dictionary with I3PM environment variables or None if not available:
            {
                "app_id": str | None,
                "app_name": str | None,
                "project_name": str | None,
                "project_dir": str | None,
                "scope": str | None,
                "target_workspace": int | None,
                "expected_class": str | None
            }

        Raises:
            ValueError: If PID parameter is missing or invalid
        """
        start_time = time.perf_counter()
        pid = params.get("pid")

        if not pid:
            raise ValueError("pid parameter required")

        if not isinstance(pid, int) or pid <= 0:
            raise ValueError(f"Invalid PID: {pid}")

        # Read process environment using existing window_filter module
        from .services.window_filter import read_process_environ
        env = read_process_environ(pid)

        result = {
            "app_id": env.get("I3PM_APP_ID") if env else None,
            "app_name": env.get("I3PM_APP_NAME") if env else None,
            "project_name": env.get("I3PM_PROJECT_NAME") if env else None,
            "project_dir": env.get("I3PM_PROJECT_DIR") if env else None,
            "scope": env.get("I3PM_SCOPE") if env else None,
            "target_workspace": None,
            "expected_class": env.get("I3PM_EXPECTED_CLASS") if env else None
        }

        # Parse target workspace if present
        if env and "I3PM_TARGET_WORKSPACE" in env:
            try:
                result["target_workspace"] = int(env["I3PM_TARGET_WORKSPACE"])
            except (ValueError, TypeError):
                pass  # Invalid workspace value, leave as None

        duration_ms = (time.perf_counter() - start_time) * 1000
        await self._log_ipc_event(
            event_type="get_window_environment",
            duration_ms=duration_ms,
            params={"pid": pid}
        )

        return result

    async def _get_workspace_rule_diagnostic(self, params: Dict[str, Any]) -> Optional[Dict[str, Any]]:
        """
        Get workspace assignment rule for an application.
        
        Feature 039 - T089
        
        Args:
            params: {"app_name": str}
        
        Returns:
            WorkspaceRule or None
        
        Raises:
            Error -32003: Application not found in registry
        """
        start_time = time.perf_counter()
        app_name = params.get("app_name")
        
        if not app_name:
            raise ValueError("app_name parameter required")
        
        # Get application registry
        registry_path = Path.home() / ".config" / "i3" / "application-registry.json"
        
        if not registry_path.exists():
            raise RuntimeError(json.dumps({
                "code": -32003,
                "message": "Application not found in registry",
                "data": {"app_name": app_name, "reason": "registry_file_not_found"}
            }))
        
        try:
            with open(registry_path) as f:
                registry = json.load(f)
            
            app_def = registry.get(app_name)
            
            if not app_def:
                raise RuntimeError(json.dumps({
                    "code": -32003,
                    "message": "Application not found in registry",
                    "data": {"app_name": app_name}
                }))
            
            # Build workspace rule response
            result = {
                "app_identifier": app_def.get("expected_class", app_name),
                "matching_strategy": "normalized",  # Default strategy
                "aliases": app_def.get("aliases", []),
                "target_workspace": app_def.get("preferred_workspace"),
                "fallback_behavior": app_def.get("fallback_behavior", "current"),
                "app_name": app_name,
                "description": app_def.get("display_name", app_name)
            }
            
            duration_ms = (time.perf_counter() - start_time) * 1000
            
            await self._log_ipc_event(
                event_type="get_workspace_rule",
                duration_ms=duration_ms,
                params={"app_name": app_name}
            )
            
            return result
            
        except RuntimeError as e:
            # Re-raise JSON-RPC errors
            if str(e).startswith("{"):
                raise
            raise
        except Exception as e:
            logger.error(f"Error getting workspace rule: {e}")
            raise

    async def _validate_state_diagnostic(self) -> Dict[str, Any]:
        """
        Validate daemon state consistency against i3 IPC.
        
        Feature 039 - T090
        
        Compares daemon's tracked windows with actual i3 window tree
        to detect state drift.
        
        Returns:
            StateValidation with consistency report
        
        Raises:
            Error -32010: i3 IPC connection failed
        """
        start_time = time.perf_counter()
        
        if not self.i3_connection or not self.i3_connection.is_connected:
            raise RuntimeError(json.dumps({
                "code": -32010,
                "message": "i3 IPC connection failed",
                "data": {"reason": "not_connected"}
            }))

        try:
            # Get i3 window tree
            tree = await self.i3_connection.conn.get_tree()
            i3_windows = tree.leaves()
            
            # Get daemon tracked windows
            daemon_windows = self.state_manager.state.window_map
            
            # Compare states
            total_windows_checked = len(i3_windows)
            windows_consistent = 0
            windows_inconsistent = 0
            mismatches = []
            
            for i3_window in i3_windows:
                window_id = i3_window.id
                daemon_window = daemon_windows.get(window_id)
                
                # Check workspace consistency
                i3_workspace = i3_window.workspace()
                i3_workspace_num = i3_workspace.num if i3_workspace else None
                
                if daemon_window:
                    daemon_workspace_num = getattr(daemon_window, 'workspace_number', None)
                    
                    if daemon_workspace_num and daemon_workspace_num != i3_workspace_num:
                        mismatches.append({
                            "window_id": window_id,
                            "property_name": "workspace",
                            "daemon_value": str(daemon_workspace_num),
                            "i3_value": str(i3_workspace_num),
                            "severity": "warning"
                        })
                        windows_inconsistent += 1
                    else:
                        windows_consistent += 1
                else:
                    # Window exists in i3 but not tracked by daemon
                    # This is normal for pre-existing windows, so just count as consistent
                    windows_consistent += 1
            
            is_consistent = windows_inconsistent == 0
            consistency_percentage = round((windows_consistent / total_windows_checked * 100), 1) if total_windows_checked > 0 else 100.0
            
            duration_ms = (time.perf_counter() - start_time) * 1000
            
            result = {
                "validated_at": datetime.now().isoformat(),
                "total_windows_checked": total_windows_checked,
                "windows_consistent": windows_consistent,
                "windows_inconsistent": windows_inconsistent,
                "mismatches": mismatches,
                "is_consistent": is_consistent,
                "consistency_percentage": consistency_percentage
            }
            
            await self._log_ipc_event(
                event_type="validate_state",
                duration_ms=duration_ms
            )
            
            return result
            
        except Exception as e:
            logger.error(f"Error validating state: {e}")
            raise

    async def _get_recent_events_diagnostic(self, params: Dict[str, Any]) -> list:
        """
        Get recent events from circular buffer.
        
        Feature 039 - T091
        
        Args:
            params: {
                "limit": int (optional, default=50, max=500),
                "event_type": str (optional, filter by type)
            }
        
        Returns:
            List of WindowEvent objects
        
        Raises:
            Error -32004: Invalid limit
        """
        start_time = time.perf_counter()
        
        limit = params.get("limit", 50)
        event_type = params.get("event_type")
        
        # Validate limit
        if limit < 1 or limit > 500:
            raise RuntimeError(json.dumps({
                "code": -32004,
                "message": "Invalid limit (must be 1-500)",
                "data": {"limit": limit}
            }))
        
        if not self.event_buffer:
            return []
        
        # Get events from buffer
        events = self.event_buffer.get_recent(limit=limit, event_type=event_type)

        # Format events for diagnostic output
        formatted_events = []
        for event in events:
            formatted_event = {
                "event_id": event.event_id,
                "event_type": event.event_type,
                "timestamp": event.timestamp.isoformat() if event.timestamp else '',
                "source": event.source,
                "window_id": event.window_id,
                "window_class": event.window_class,
                "window_title": event.window_title,
                "workspace_name": event.workspace_name,
                "project_name": event.project_name,
                "processing_duration_ms": event.processing_duration_ms,
                "error": event.error
            }
            formatted_events.append(formatted_event)
        
        duration_ms = (time.perf_counter() - start_time) * 1000
        
        await self._log_ipc_event(
            event_type="get_recent_events",
            duration_ms=duration_ms,
            params={"limit": limit, "event_type": event_type}
        )
        
        return formatted_events

    async def _get_diagnostic_report_full(self, params: Dict[str, Any]) -> Dict[str, Any]:
        """
        Get complete diagnostic report with all state information.
        
        Feature 039 - T092
        
        Args:
            params: {
                "include_windows": bool (optional, default=False),
                "include_events": bool (optional, default=False),
                "include_validation": bool (optional, default=False)
            }
        
        Returns:
            DiagnosticReport with comprehensive state information
        """
        start_time = time.perf_counter()
        
        include_windows = params.get("include_windows", False)
        include_events = params.get("include_events", False)
        include_validation = params.get("include_validation", False)
        
        # Get base health check
        health_data = await self._health_check()
        
        # Start building report
        report = {
            "generated_at": datetime.now().isoformat(),
            **health_data  # Include all health check data
        }
        
        # Add i3 IPC state
        if self.i3_connection and self.i3_connection.is_connected():
            try:
                tree = await self.i3_connection.get_tree()
                workspaces = await self.i3_connection.get_workspaces()
                outputs = await self.i3_connection.get_outputs()
                
                report["i3_ipc_state"] = {
                    "total_windows": len(tree.leaves()),
                    "total_workspaces": len(workspaces),
                    "total_outputs": len([o for o in outputs if o.active])
                }
            except Exception as e:
                logger.error(f"Error getting i3 state: {e}")
                report["i3_ipc_state"] = {"error": str(e)}
        
        # Include windows if requested
        if include_windows:
            windows = []
            for window_id, window_data in self.state_manager.state.windows.items():
                windows.append({
                    "window_id": window_id,
                    "window_class": getattr(window_data, 'window_class', 'unknown'),
                    "workspace": getattr(window_data, 'workspace_number', None)
                })
            report["tracked_windows"] = windows
        
        # Include events if requested
        if include_events:
            events = await self._get_recent_events_diagnostic({"limit": 100})
            report["recent_events"] = events
        
        # Include validation if requested
        if include_validation:
            validation = await self._validate_state_diagnostic()
            report["state_validation"] = validation
        
        duration_ms = (time.perf_counter() - start_time) * 1000

        await self._log_ipc_event(
            event_type="get_diagnostic_report",
            duration_ms=duration_ms,
            params=params
        )

        return report

    async def _notify_launch(self, params: Dict[str, Any]) -> Dict[str, Any]:
        """
        Register a pending application launch for window correlation.

        Feature 041 - T010

        Args:
            params: {
                "app_name": str - Application name from registry,
                "project_name": str - Project name for this launch,
                "project_directory": str - Absolute path to project directory,
                "launcher_pid": int - Process ID of launcher wrapper,
                "workspace_number": int - Target workspace number (1-70),
                "timestamp": float - Unix timestamp when launch notification sent
            }

        Returns:
            {
                "status": "success",
                "launch_id": str - Unique launch identifier,
                "expected_class": str - Window class expected from registry,
                "pending_count": int - Number of pending launches
            }

        Raises:
            RuntimeError: If app not found in registry, invalid workspace, or future timestamp
        """
        start_time = time.perf_counter()

        # Extract parameters
        app_name = params.get("app_name")
        project_name = params.get("project_name")
        project_directory = params.get("project_directory")
        launcher_pid = params.get("launcher_pid")
        workspace_number = params.get("workspace_number")
        timestamp = params.get("timestamp")

        # Feature 041 T023: Log received launch notification
        logger.info(f"Received notify_launch: {app_name} → {project_name}")

        # Validate required parameters
        if not app_name:
            raise RuntimeError(json.dumps({
                "code": -32602,
                "message": "Missing required parameter: app_name",
                "data": {"param": "app_name"}
            }))

        if not project_name:
            raise RuntimeError(json.dumps({
                "code": -32602,
                "message": "Missing required parameter: project_name",
                "data": {"param": "project_name"}
            }))

        if not project_directory:
            raise RuntimeError(json.dumps({
                "code": -32602,
                "message": "Missing required parameter: project_directory",
                "data": {"param": "project_directory"}
            }))

        if launcher_pid is None:
            raise RuntimeError(json.dumps({
                "code": -32602,
                "message": "Missing required parameter: launcher_pid",
                "data": {"param": "launcher_pid"}
            }))

        if workspace_number is None:
            raise RuntimeError(json.dumps({
                "code": -32602,
                "message": "Missing required parameter: workspace_number",
                "data": {"param": "workspace_number"}
            }))

        if timestamp is None:
            raise RuntimeError(json.dumps({
                "code": -32602,
                "message": "Missing required parameter: timestamp",
                "data": {"param": "timestamp"}
            }))

        # Get application registry to resolve expected_class
        registry_path = Path.home() / ".config" / "i3" / "application-registry.json"
        if not registry_path.exists():
            raise RuntimeError(json.dumps({
                "code": -32001,
                "message": "Application registry not found",
                "data": {"app_name": app_name, "reason": "registry_file_not_found"}
            }))

        with open(registry_path, "r") as f:
            registry = json.load(f)

        # Find app in registry
        app_def = None
        for app in registry.get("applications", []):
            if app.get("name") == app_name:
                app_def = app
                break

        if not app_def:
            raise RuntimeError(json.dumps({
                "code": -32002,
                "message": f"Application '{app_name}' not found in registry",
                "data": {"app_name": app_name, "reason": "app_not_found"}
            }))

        expected_class = app_def.get("expected_class")
        if not expected_class:
            raise RuntimeError(json.dumps({
                "code": -32003,
                "message": f"Application '{app_name}' has no expected_class in registry",
                "data": {"app_name": app_name, "reason": "missing_expected_class"}
            }))

        # Create PendingLaunch using Pydantic model
        from .models import PendingLaunch
        try:
            pending_launch = PendingLaunch(
                app_name=app_name,
                project_name=project_name,
                project_directory=Path(project_directory),
                launcher_pid=launcher_pid,
                workspace_number=workspace_number,
                timestamp=timestamp,
                expected_class=expected_class,
                matched=False
            )
        except Exception as e:
            raise RuntimeError(json.dumps({
                "code": -32004,
                "message": f"Validation error: {str(e)}",
                "data": {"validation_error": str(e)}
            }))

        # Add to launch registry
        if not hasattr(self.state_manager, 'launch_registry'):
            raise RuntimeError(json.dumps({
                "code": -32005,
                "message": "Launch registry not initialized in daemon state",
                "data": {"reason": "registry_not_initialized"}
            }))

        launch_id = await self.state_manager.launch_registry.add(pending_launch)

        # Get current pending count for response
        stats = self.state_manager.launch_registry.get_stats()

        duration_ms = (time.perf_counter() - start_time) * 1000

        await self._log_ipc_event(
            event_type="notify_launch",
            duration_ms=duration_ms,
            params={"app_name": app_name, "project_name": project_name}
        )

        logger.info(
            f"Registered launch: {launch_id} for project {project_name} "
            f"(expected_class={expected_class}, workspace={workspace_number})"
        )

        return {
            "status": "success",
            "launch_id": launch_id,
            "expected_class": expected_class,
            "pending_count": stats.total_pending
        }

    async def _get_launch_stats(self) -> Dict[str, Any]:
        """
        Get launch registry statistics for diagnostics.

        Feature 041 - T011

        Returns:
            LaunchRegistryStats with current state and historical counters
        """
        start_time = time.perf_counter()

        if not hasattr(self.state_manager, 'launch_registry'):
            raise RuntimeError(json.dumps({
                "code": -32005,
                "message": "Launch registry not initialized in daemon state",
                "data": {"reason": "registry_not_initialized"}
            }))

        stats = self.state_manager.launch_registry.get_stats()

        duration_ms = (time.perf_counter() - start_time) * 1000

        await self._log_ipc_event(
            event_type="get_launch_stats",
            duration_ms=duration_ms
        )

        # Convert Pydantic model to dict
        return {
            "total_pending": stats.total_pending,
            "unmatched_pending": stats.unmatched_pending,
            "total_notifications": stats.total_notifications,
            "total_matched": stats.total_matched,
            "total_expired": stats.total_expired,
            "total_failed_correlation": stats.total_failed_correlation,
            "match_rate": stats.match_rate,
            "expiration_rate": stats.expiration_rate
        }

    async def _get_pending_launches(self, params: Dict[str, Any]) -> Dict[str, Any]:
        """
        Get list of pending launches for debugging.

        Feature 041 - T012

        Args:
            params: {
                "include_matched": bool (optional, default=False)
            }

        Returns:
            {
                "launches": [
                    {
                        "launch_id": str,
                        "app_name": str,
                        "project_name": str,
                        "expected_class": str,
                        "workspace_number": int,
                        "matched": bool,
                        "age": float,
                        "timestamp": float
                    }
                ]
            }
        """
        start_time = time.perf_counter()

        include_matched = params.get("include_matched", False)

        if not hasattr(self.state_manager, 'launch_registry'):
            raise RuntimeError(json.dumps({
                "code": -32005,
                "message": "Launch registry not initialized in daemon state",
                "data": {"reason": "registry_not_initialized"}
            }))

        launches = await self.state_manager.launch_registry.get_pending_launches(
            include_matched=include_matched
        )

        duration_ms = (time.perf_counter() - start_time) * 1000

        await self._log_ipc_event(
            event_type="get_pending_launches",
            duration_ms=duration_ms,
            params={"include_matched": include_matched}
        )

        return {"launches": launches}

    # =============================================================================
    # Feature 042: Workspace Mode Navigation IPC Methods
    # =============================================================================

    async def _workspace_mode_digit(self, params: Dict[str, Any]) -> Dict[str, Any]:
        """Handle workspace_mode.digit IPC method.

        Args:
            params: {"digit": "2"}

        Returns:
            {"accumulated_digits": "23"}
        """
        start_time = time.perf_counter()

        if not hasattr(self.state_manager, 'workspace_mode_manager'):
            raise RuntimeError("Workspace mode manager not initialized")

        digit = params.get("digit")
        if not digit or digit not in "0123456789":
            raise ValueError(f"Invalid digit: {digit}. Must be 0-9")

        manager = self.state_manager.workspace_mode_manager
        accumulated = await manager.add_digit(digit)

        # Broadcast event for status bar update
        event = manager.create_event("digit")
        await self.broadcast_event({"type": "workspace_mode", **event.model_dump()})

        duration_ms = (time.perf_counter() - start_time) * 1000

        await self._log_ipc_event(
            event_type="workspace_mode::digit",
            duration_ms=duration_ms,
            params={"digit": digit, "accumulated": accumulated}
        )

        return {"accumulated_digits": accumulated}

    async def _workspace_mode_execute(self, params: Dict[str, Any]) -> Dict[str, Any]:
        """Handle workspace_mode.execute IPC method.

        Returns:
            {"workspace": 23, "output": "HEADLESS-2", "success": true}
        """
        start_time = time.perf_counter()

        if not hasattr(self.state_manager, 'workspace_mode_manager'):
            raise RuntimeError("Workspace mode manager not initialized")

        manager = self.state_manager.workspace_mode_manager
        result = await manager.execute()

        # Broadcast event (mode now inactive)
        event = manager.create_event("execute")
        await self.broadcast_event({"type": "workspace_mode", **event.model_dump()})

        duration_ms = (time.perf_counter() - start_time) * 1000

        if result:
            await self._log_ipc_event(
                event_type="workspace_mode::execute",
                duration_ms=duration_ms,
                params={"workspace": result["workspace"], "output": result["output"]}
            )
            return result
        else:
            # Empty execution (no-op)
            await self._log_ipc_event(
                event_type="workspace_mode::execute_noop",
                duration_ms=duration_ms
            )
            return {"success": False, "reason": "no_digits"}

    async def _workspace_mode_cancel(self, params: Dict[str, Any]) -> Dict[str, Any]:
        """Handle workspace_mode.cancel IPC method.

        Returns:
            {"cancelled": true}
        """
        start_time = time.perf_counter()

        if not hasattr(self.state_manager, 'workspace_mode_manager'):
            raise RuntimeError("Workspace mode manager not initialized")

        manager = self.state_manager.workspace_mode_manager
        await manager.cancel()

        # Broadcast event (mode now inactive)
        event = manager.create_event("cancel")
        await self.broadcast_event({"type": "workspace_mode", **event.model_dump()})

        duration_ms = (time.perf_counter() - start_time) * 1000

        await self._log_ipc_event(
            event_type="workspace_mode::cancel",
            duration_ms=duration_ms
        )

        return {"cancelled": True}

    async def _workspace_mode_state(self, params: Dict[str, Any]) -> Dict[str, Any]:
        """Handle workspace_mode.state IPC method.

        Returns:
            WorkspaceModeState as dict
        """
        start_time = time.perf_counter()

        if not hasattr(self.state_manager, 'workspace_mode_manager'):
            raise RuntimeError("Workspace mode manager not initialized")

        manager = self.state_manager.workspace_mode_manager
        state = manager.state

        duration_ms = (time.perf_counter() - start_time) * 1000

        await self._log_ipc_event(
            event_type="workspace_mode::query_state",
            duration_ms=duration_ms
        )

        return state.to_dict()

    async def _workspace_mode_history(self, params: Dict[str, Any]) -> Dict[str, Any]:
        """Handle workspace_mode.history IPC method.

        Args:
            params: {"limit": 10} (optional)

        Returns:
            {"history": [...], "total": N}
        """
        start_time = time.perf_counter()

        if not hasattr(self.state_manager, 'workspace_mode_manager'):
            raise RuntimeError("Workspace mode manager not initialized")

        manager = self.state_manager.workspace_mode_manager
        limit = params.get("limit")

        history = manager.get_history(limit=limit)
        total_count = len(manager._history)

        duration_ms = (time.perf_counter() - start_time) * 1000

        await self._log_ipc_event(
            event_type="workspace_mode::query_history",
            duration_ms=duration_ms,
            params={"limit": limit},
            result_count=len(history)
        )

        return {
            "history": [switch.to_dict() for switch in history],
            "total": total_count
        }

    # ======================
    # Feature 058: Project Management JSON-RPC Handlers (T030-T033)
    # ======================

    async def _project_create(self, params: Dict[str, Any]) -> Dict[str, Any]:
        """Create a new project.

        Args:
            params: {
                "name": str,          # Unique project identifier
                "directory": str,     # Absolute path to project directory
                "display_name": str,  # Human-readable project name
                "icon": str = "📁"    # Project icon (optional)
            }

        Returns:
            Project data (name, directory, display_name, icon, created_at, updated_at)

        Raises:
            VALIDATION_ERROR (1003): Invalid parameters or directory
            FILE_IO_ERROR (1004): Project already exists
        """
        start_time = time.perf_counter()

        try:
            # Import ProjectService
            from .services.project_service import ProjectService
            config_dir = Path.home() / ".config" / "i3"
            service = ProjectService(config_dir, self.state_manager)

            # Extract parameters
            name = params.get("name")
            directory = params.get("directory")
            display_name = params.get("display_name")
            icon = params.get("icon", "📁")

            # Validate required parameters
            if not name or not directory or not display_name:
                raise ValueError("Missing required parameters: name, directory, display_name")

            # Create project
            project = service.create(
                name=name,
                directory=directory,
                display_name=display_name,
                icon=icon
            )

            duration_ms = (time.perf_counter() - start_time) * 1000

            await self._log_ipc_event(
                event_type="project::create",
                duration_ms=duration_ms,
                params={"name": name, "directory": directory}
            )

            # Return project data
            return {
                "name": project.name,
                "directory": project.directory,
                "display_name": project.display_name,
                "icon": project.icon,
                "created_at": project.created_at.isoformat(),
                "updated_at": project.updated_at.isoformat()
            }

        except FileExistsError as e:
            duration_ms = (time.perf_counter() - start_time) * 1000
            await self._log_ipc_event(
                event_type="project::create",
                duration_ms=duration_ms,
                params={"name": params.get("name")},
                error=str(e)
            )
            raise RuntimeError(f"{FILE_IO_ERROR}:{str(e)}")

        except ValueError as e:
            duration_ms = (time.perf_counter() - start_time) * 1000
            await self._log_ipc_event(
                event_type="project::create",
                duration_ms=duration_ms,
                params=params,
                error=str(e)
            )
            raise RuntimeError(f"{VALIDATION_ERROR}:{str(e)}")

        except Exception as e:
            duration_ms = (time.perf_counter() - start_time) * 1000
            await self._log_ipc_event(
                event_type="project::create",
                duration_ms=duration_ms,
                params=params,
                error=str(e)
            )
            raise

    async def _project_list(self, params: Dict[str, Any]) -> Dict[str, Any]:
        """List all projects.

        Args:
            params: {} (no parameters required)

        Returns:
            {"projects": [Project data...]}
        """
        start_time = time.perf_counter()

        try:
            # Import ProjectService
            from .services.project_service import ProjectService
            config_dir = Path.home() / ".config" / "i3"
            service = ProjectService(config_dir, self.state_manager)

            # List projects
            projects = service.list()

            duration_ms = (time.perf_counter() - start_time) * 1000

            await self._log_ipc_event(
                event_type="project::list",
                duration_ms=duration_ms,
                result_count=len(projects)
            )

            return {
                "projects": [
                    {
                        "name": p.name,
                        "directory": p.directory,
                        "display_name": p.display_name,
                        "icon": p.icon,
                        "created_at": p.created_at.isoformat(),
                        "updated_at": p.updated_at.isoformat()
                    }
                    for p in projects
                ]
            }

        except Exception as e:
            duration_ms = (time.perf_counter() - start_time) * 1000
            await self._log_ipc_event(
                event_type="project::list",
                duration_ms=duration_ms,
                error=str(e)
            )
            raise

    async def _project_get(self, params: Dict[str, Any]) -> Dict[str, Any]:
        """Get project details.

        Args:
            params: {"name": str}

        Returns:
            Project data

        Raises:
            PROJECT_NOT_FOUND (1001): Project doesn't exist
        """
        start_time = time.perf_counter()

        try:
            # Import ProjectService
            from .services.project_service import ProjectService
            config_dir = Path.home() / ".config" / "i3"
            service = ProjectService(config_dir, self.state_manager)

            # Get project name
            name = params.get("name")
            if not name:
                raise ValueError("Missing required parameter: name")

            # Get project
            project = service.get(name)

            duration_ms = (time.perf_counter() - start_time) * 1000

            await self._log_ipc_event(
                event_type="project::get",
                duration_ms=duration_ms,
                params={"name": name}
            )

            return {
                "name": project.name,
                "directory": project.directory,
                "display_name": project.display_name,
                "icon": project.icon,
                "created_at": project.created_at.isoformat(),
                "updated_at": project.updated_at.isoformat()
            }

        except FileNotFoundError as e:
            duration_ms = (time.perf_counter() - start_time) * 1000
            await self._log_ipc_event(
                event_type="project::get",
                duration_ms=duration_ms,
                params={"name": params.get("name")},
                error=str(e)
            )
            raise RuntimeError(f"{PROJECT_NOT_FOUND}:{str(e)}")

        except Exception as e:
            duration_ms = (time.perf_counter() - start_time) * 1000
            await self._log_ipc_event(
                event_type="project::get",
                duration_ms=duration_ms,
                params=params,
                error=str(e)
            )
            raise

    async def _project_update(self, params: Dict[str, Any]) -> Dict[str, Any]:
        """Update project metadata.

        Args:
            params: {
                "name": str,              # Project to update
                "directory": str = None,  # New directory (optional)
                "display_name": str = None,  # New display name (optional)
                "icon": str = None        # New icon (optional)
            }

        Returns:
            Updated project data

        Raises:
            PROJECT_NOT_FOUND (1001): Project doesn't exist
            VALIDATION_ERROR (1003): Invalid parameters
        """
        start_time = time.perf_counter()

        try:
            # Import ProjectService
            from .services.project_service import ProjectService
            config_dir = Path.home() / ".config" / "i3"
            service = ProjectService(config_dir, self.state_manager)

            # Get parameters
            name = params.get("name")
            if not name:
                raise ValueError("Missing required parameter: name")

            directory = params.get("directory")
            display_name = params.get("display_name")
            icon = params.get("icon")

            # Update project
            project = service.update(
                name=name,
                directory=directory,
                display_name=display_name,
                icon=icon
            )

            duration_ms = (time.perf_counter() - start_time) * 1000

            await self._log_ipc_event(
                event_type="project::update",
                duration_ms=duration_ms,
                params={"name": name}
            )

            return {
                "name": project.name,
                "directory": project.directory,
                "display_name": project.display_name,
                "icon": project.icon,
                "created_at": project.created_at.isoformat(),
                "updated_at": project.updated_at.isoformat()
            }

        except FileNotFoundError as e:
            duration_ms = (time.perf_counter() - start_time) * 1000
            await self._log_ipc_event(
                event_type="project::update",
                duration_ms=duration_ms,
                params={"name": params.get("name")},
                error=str(e)
            )
            raise RuntimeError(f"{PROJECT_NOT_FOUND}:{str(e)}")

        except ValueError as e:
            duration_ms = (time.perf_counter() - start_time) * 1000
            await self._log_ipc_event(
                event_type="project::update",
                duration_ms=duration_ms,
                params=params,
                error=str(e)
            )
            raise RuntimeError(f"{VALIDATION_ERROR}:{str(e)}")

        except Exception as e:
            duration_ms = (time.perf_counter() - start_time) * 1000
            await self._log_ipc_event(
                event_type="project::update",
                duration_ms=duration_ms,
                params=params,
                error=str(e)
            )
            raise

    async def _project_delete(self, params: Dict[str, Any]) -> Dict[str, Any]:
        """Delete a project.

        Args:
            params: {"name": str}

        Returns:
            {"deleted": bool, "name": str}

        Raises:
            PROJECT_NOT_FOUND (1001): Project doesn't exist
        """
        start_time = time.perf_counter()

        try:
            # Import ProjectService
            from .services.project_service import ProjectService
            config_dir = Path.home() / ".config" / "i3"
            service = ProjectService(config_dir, self.state_manager)

            # Get project name
            name = params.get("name")
            if not name:
                raise ValueError("Missing required parameter: name")

            # Delete project
            deleted = service.delete(name)

            duration_ms = (time.perf_counter() - start_time) * 1000

            await self._log_ipc_event(
                event_type="project::delete",
                duration_ms=duration_ms,
                params={"name": name}
            )

            return {
                "deleted": deleted,
                "name": name
            }

        except FileNotFoundError as e:
            duration_ms = (time.perf_counter() - start_time) * 1000
            await self._log_ipc_event(
                event_type="project::delete",
                duration_ms=duration_ms,
                params={"name": params.get("name")},
                error=str(e)
            )
            raise RuntimeError(f"{PROJECT_NOT_FOUND}:{str(e)}")

        except Exception as e:
            duration_ms = (time.perf_counter() - start_time) * 1000
            await self._log_ipc_event(
                event_type="project::delete",
                duration_ms=duration_ms,
                params=params,
                error=str(e)
            )
            raise

    async def _project_get_active(self, params: Dict[str, Any]) -> Dict[str, Any]:
        """Get currently active project.

        Args:
            params: {} (no parameters required)

        Returns:
            {"name": str | null}  # null if in global mode
        """
        start_time = time.perf_counter()

        try:
            # Import ProjectService
            from .services.project_service import ProjectService
            config_dir = Path.home() / ".config" / "i3"
            service = ProjectService(config_dir, self.state_manager)

            # Get active project
            active_name = service.get_active()

            duration_ms = (time.perf_counter() - start_time) * 1000

            await self._log_ipc_event(
                event_type="project::get_active",
                duration_ms=duration_ms,
                params={"active": active_name}
            )

            return {"name": active_name}

        except Exception as e:
            duration_ms = (time.perf_counter() - start_time) * 1000
            await self._log_ipc_event(
                event_type="project::get_active",
                duration_ms=duration_ms,
                error=str(e)
            )
            raise

    async def _project_set_active(self, params: Dict[str, Any]) -> Dict[str, Any]:
        """Set active project (triggers window filtering).

        Args:
            params: {"name": str | null}  # null to clear (global mode)

        Returns:
            {
                "previous": str | null,
                "current": str | null,
                "filtering_applied": bool
            }

        Raises:
            PROJECT_NOT_FOUND (1001): Project doesn't exist
        """
        start_time = time.perf_counter()

        try:
            # Import ProjectService
            from .services.project_service import ProjectService
            config_dir = Path.home() / ".config" / "i3"
            service = ProjectService(config_dir, self.state_manager)

            # Get project name (can be None for global mode)
            name = params.get("name")

            # Set active project
            result = await service.set_active(name)

            # Trigger window filtering (Feature 037 integration)
            filtering_applied = False
            if self.workspace_tracker:
                try:
                    # Switch projects with filtering
                    old_project = result["previous"] or ""
                    new_project = result["current"]

                    if old_project or new_project:
                        filter_result = await self._switch_with_filtering({
                            "old_project": old_project,
                            "new_project": new_project or "",
                            "fallback_workspace": 1
                        })
                        filtering_applied = True
                        logger.info(
                            f"Window filtering applied: "
                            f"{filter_result.get('windows_hidden', 0)} hidden, "
                            f"{filter_result.get('windows_restored', 0)} restored"
                        )
                except Exception as e:
                    logger.warning(f"Window filtering failed (non-fatal): {e}")

            duration_ms = (time.perf_counter() - start_time) * 1000

            await self._log_ipc_event(
                event_type="project::set_active",
                duration_ms=duration_ms,
                params={"name": name, "previous": result["previous"]}
            )

            return {
                "previous": result["previous"],
                "current": result["current"],
                "filtering_applied": filtering_applied
            }

        except FileNotFoundError as e:
            duration_ms = (time.perf_counter() - start_time) * 1000
            await self._log_ipc_event(
                event_type="project::set_active",
                duration_ms=duration_ms,
                params={"name": params.get("name")},
                error=str(e)
            )
            raise RuntimeError(f"{PROJECT_NOT_FOUND}:{str(e)}")

        except Exception as e:
            duration_ms = (time.perf_counter() - start_time) * 1000
            await self._log_ipc_event(
                event_type="project::set_active",
                duration_ms=duration_ms,
                params=params,
                error=str(e)
            )
            raise
