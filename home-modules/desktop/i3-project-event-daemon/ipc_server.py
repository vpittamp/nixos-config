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

logger = logging.getLogger(__name__)


class IPCServer:
    """JSON-RPC IPC server for CLI tool queries."""

    def __init__(
        self,
        state_manager: StateManager,
        event_buffer: Optional[Any] = None,
        i3_connection: Optional[Any] = None,
        window_rules_getter: Optional[callable] = None
    ) -> None:
        """Initialize IPC server.

        Args:
            state_manager: StateManager instance for queries
            event_buffer: EventBuffer instance for event history (Feature 017)
            i3_connection: ResilientI3Connection instance for i3 IPC queries (Feature 018)
            window_rules_getter: Callable that returns current window rules list (Feature 021)
        """
        self.state_manager = state_manager
        self.event_buffer = event_buffer
        self.i3_connection = i3_connection
        self.window_rules_getter = window_rules_getter
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
        window_rules_getter: Optional[callable] = None
    ) -> "IPCServer":
        """Create IPC server using systemd socket activation.

        Args:
            state_manager: StateManager instance
            event_buffer: EventBuffer instance for event history (Feature 017)
            i3_connection: ResilientI3Connection instance for i3 IPC queries (Feature 018)
            window_rules_getter: Callable that returns current window rules list (Feature 021)

        Returns:
            IPCServer instance with inherited socket
        """
        server = cls(state_manager, event_buffer, i3_connection, window_rules_getter)

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
                # Adapt get_active_project response format for CLI
                active = await self._get_active_project()
                result = {"project": active.get("project_name")}
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

        except Exception as e:
            logger.error(f"Error handling request {method}: {e}")
            return {
                "jsonrpc": "2.0",
                "error": {"code": -32603, "message": str(e)},
                "id": request_id,
            }

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
        """Get active project info."""
        project_name = await self.state_manager.get_active_project()
        return {
            "project_name": project_name,
            "is_global": project_name is None,
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

            # Update window visibility based on new project
            if self.i3_connection and self.i3_connection.conn:
                # Hide scoped windows from other projects
                for window in all_windows:
                    if window.window_class not in self.state_manager.state.scoped_classes:
                        continue  # Skip global windows

                    if window.project == project_name:
                        # Show windows from new project
                        await self.i3_connection.conn.command(f'[con_id={window.window_id}] move scratchpad; move workspace current')
                    elif window.project is not None and window.project != project_name:
                        # Hide windows from other projects
                        await self.i3_connection.conn.command(f'[con_id={window.window_id}] move scratchpad')

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
            # Check if this is an actual window (has window ID)
            if node.window and node.window > 0:
                # Get project from marks
                project = None
                for mark in node.marks:
                    if mark.startswith("project:"):
                        project = mark.split(":", 1)[1]
                        break

                # Determine classification from daemon state
                classification = "global"
                hidden = False
                if node.window_class:
                    if project and node.window_class in self.state_manager.state.scoped_classes:
                        classification = "scoped"
                    # Check if window is hidden (not on visible workspace or project mismatch)
                    active_project = self.state_manager.state.active_project
                    if classification == "scoped" and active_project and project != active_project:
                        hidden = True

                # Format workspace as string (CLI expects "1" or "1:name")
                workspace_name = container.name if container.type == "workspace" else ""
                workspace_str = workspace_name if workspace_name else str(workspace_num)

                window_data = {
                    "id": node.window,
                    "class": node.window_class or "",
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

    async def _layout_save(self, params: Dict[str, Any]) -> Dict[str, Any]:
        """
        Capture and save current workspace layout

        Implements layout.save JSON-RPC method from daemon-ipc.json
        Feature 030: Tasks T030-T035 (Layout capture and persistence)

        Args:
            params: Save parameters
                - project: Project name
                - name: Layout name
                - workspaces: Optional list of workspace numbers to capture
                - discover_commands: Discover launch commands (default: true)
        """
        start_time = time.perf_counter()

        try:
            project = params.get("project")
            layout_name = params.get("name")

            if not project or not layout_name:
                raise ValueError("Both 'project' and 'name' are required")

            # Import layout module
            from .layout import capture_layout, save_layout

            # Capture current layout (T030-T033)
            snapshot = await capture_layout(
                self.i3_connection,
                name=layout_name,
                project=project,
            )

            # Save to disk (T034-T035)
            filepath = save_layout(snapshot)

            result = {
                "success": True,
                "name": layout_name,
                "project": project,
                "file_path": str(filepath),
                "total_windows": snapshot.metadata.get("total_windows", 0),
                "total_workspaces": snapshot.metadata.get("total_workspaces", 0),
                "total_monitors": snapshot.metadata.get("total_monitors", 0),
            }

            logger.info(f"Layout saved: {project}/{layout_name} ({result['total_windows']} windows)")

            return result

        finally:
            duration_ms = (time.perf_counter() - start_time) * 1000
            await self._log_ipc_event(
                event_type="layout::save",
                project_name=params.get("project"),
                params=params,
                duration_ms=duration_ms,
            )

    async def _layout_restore(self, params: Dict[str, Any]) -> Dict[str, Any]:
        """
        Restore workspace layout from snapshot

        Implements layout.restore JSON-RPC method from daemon-ipc.json
        Feature 030: Tasks T036-T040 (Layout restoration)

        Args:
            params: Restore parameters
                - project: Project name
                - name: Layout name
                - workspaces: Optional list of workspace numbers to restore
                - adapt_monitors: Adapt to current monitor config (default: true)
                - dry_run: Validate without restoring (default: false)
        """
        start_time = time.perf_counter()

        try:
            project = params.get("project", "global")
            layout_name = params.get("name")
            adapt_monitors = params.get("adapt_monitors", True)
            dry_run = params.get("dry_run", False)

            if not layout_name:
                raise ValueError("'name' parameter is required")

            # Import layout module
            from .layout import restore_layout

            if dry_run:
                # Just validate layout exists
                from .layout import load_layout
                snapshot = load_layout(layout_name, project)
                if not snapshot:
                    raise ValueError(f"Layout not found: {layout_name} (project: {project})")

                result = {
                    "success": True,
                    "dry_run": True,
                    "name": layout_name,
                    "project": project,
                    "total_windows": snapshot.metadata.get("total_windows", 0),
                    "total_workspaces": snapshot.metadata.get("total_workspaces", 0),
                }

            else:
                # Restore layout (T036-T040)
                restore_results = await restore_layout(
                    self.i3_connection,
                    name=layout_name,
                    project=project,
                    adapt_monitors=adapt_monitors,
                )

                result = {
                    "success": restore_results["success"],
                    "name": layout_name,
                    "project": project,
                    "windows_launched": restore_results["windows_launched"],
                    "windows_swallowed": restore_results["windows_swallowed"],
                    "windows_failed": restore_results["windows_failed"],
                    "duration_seconds": restore_results.get("duration_seconds", 0),
                    "errors": restore_results.get("errors", []),
                }

                logger.info(
                    f"Layout restored: {project}/{layout_name} "
                    f"({result['windows_swallowed']}/{result['windows_launched']} windows)"
                )

            return result

        finally:
            duration_ms = (time.perf_counter() - start_time) * 1000
            await self._log_ipc_event(
                event_type="layout::restore",
                project_name=params.get("project"),
                params=params,
                duration_ms=duration_ms,
            )

    async def _layout_list(self, params: Dict[str, Any]) -> Dict[str, Any]:
        """
        List saved layout snapshots

        Implements layout.list JSON-RPC method
        Feature 030: Task T043 (CLI list command)

        Args:
            params: List parameters
                - project: Filter by project name (optional)

        Returns:
            Dictionary with layouts array
        """
        start_time = time.perf_counter()

        try:
            project = params.get("project")

            # Import layout module
            from .layout import list_layouts

            # Get layouts
            layouts = list_layouts(project=project)

            result = {
                "layouts": layouts,
            }

            logger.info(f"Listed layouts: {len(layouts)} found (project: {project or 'all'})")

            return result

        finally:
            duration_ms = (time.perf_counter() - start_time) * 1000
            await self._log_ipc_event(
                event_type="query::layout_list",
                project_name=params.get("project"),
                params=params,
                duration_ms=duration_ms,
            )

    async def _layout_delete(self, params: Dict[str, Any]) -> Dict[str, Any]:
        """
        Delete a saved layout snapshot

        Implements layout.delete JSON-RPC method
        Feature 030: Task T044 (CLI delete command)

        Args:
            params: Delete parameters
                - name: Layout name (required)
                - project: Project name (default: "global")

        Returns:
            Dictionary with success status
        """
        start_time = time.perf_counter()

        try:
            name = params.get("name")
            project = params.get("project", "global")

            if not name:
                raise ValueError("'name' parameter is required")

            # Import layout module
            from .layout import delete_layout

            # Delete layout
            success = delete_layout(name=name, project=project)

            if not success:
                raise ValueError(f"Layout not found: {name} (project: {project})")

            result = {
                "success": True,
                "name": name,
                "project": project,
            }

            logger.info(f"Deleted layout: {project}/{name}")

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
            i3 = self.state_manager.i3
            if not i3:
                raise RuntimeError("i3 connection not available")

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
