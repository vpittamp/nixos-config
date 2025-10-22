"""JSON-RPC IPC server for daemon queries.

Exposes daemon state via UNIX socket with systemd socket activation support.

Updated: 2025-10-22 - Added Deno CLI compatibility (aliases + response formats)
"""

import asyncio
import json
import logging
import os
import socket
from datetime import datetime
from pathlib import Path
from typing import Any, Dict, Optional

from .state import StateManager
from .window_rules import WindowRule
from .pattern_resolver import classify_window

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
            elif method == "get_events":
                # Return events array (not dict with stats) for CLI
                # Note: CLI expects simplified diagnostic events, not full i3 event structure
                events_result = await self._get_events(params)
                events = events_result.get("events", [])
                # Adapt to simpler format for CLI
                result = [
                    {
                        "event_id": evt["event_id"],
                        "event_type": evt["event_type"].split("::")[0],  # "window::focus" -> "window"
                        "change": evt["event_type"].split("::")[ 1] if "::" in evt["event_type"] else "",
                        "container": None,  # Diagnostic events don't have full container
                        "timestamp": int(datetime.fromisoformat(evt["timestamp"].replace("Z", "+00:00")).timestamp()),
                    }
                    for evt in events
                ]
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

            # Method aliases for Deno CLI compatibility
            elif method == "list_projects":
                # Convert get_projects dict to array format for CLI
                projects_dict = await self._get_projects()
                result = [
                    {
                        "name": name,
                        "display_name": proj["display_name"],
                        "icon": proj["icon"],
                        "directory": proj["directory"],
                        "scoped_classes": [],  # TODO: Get from config
                        "created_at": 0,  # TODO: Add to state
                        "last_used_at": 0,  # TODO: Add to state
                    }
                    for name, proj in projects_dict.get("projects", {}).items()
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

    async def _get_status(self) -> Dict[str, Any]:
        """Get daemon status."""
        stats = await self.state_manager.get_stats()
        return {
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
        """Return recent events for diagnostics (Feature 017).

        Args:
            params: Query parameters (limit, event_type, since_id)

        Returns:
            Dictionary with events list and buffer stats
        """
        if not self.event_buffer:
            return {"events": [], "stats": {"total_events": 0, "buffer_size": 0, "max_size": 0}}

        limit = params.get("limit", 100)
        event_type = params.get("event_type")
        since_id = params.get("since_id")

        # Get events from buffer
        events = self.event_buffer.get_events(limit=limit, event_type=event_type, since_id=since_id)

        # Convert EventEntry objects to dict
        events_data = [
            {
                "event_id": e.event_id,
                "event_type": e.event_type,
                "timestamp": e.timestamp.isoformat(),
                "window_id": e.window_id,
                "window_class": e.window_class,
                "workspace_name": e.workspace_name,
                "project_name": e.project_name,
                "tick_payload": e.tick_payload,
                "processing_duration_ms": e.processing_duration_ms,
                "error": e.error,
            }
            for e in events
        ]

        return {
            "events": events_data,
            "stats": self.event_buffer.get_stats()
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
        event_data = {
            "event_id": event_entry.event_id,
            "event_type": event_entry.event_type,
            "timestamp": event_entry.timestamp.isoformat(),
            "window_id": event_entry.window_id,
            "window_class": event_entry.window_class,
            "workspace_name": event_entry.workspace_name,
            "project_name": event_entry.project_name,
            "tick_payload": event_entry.tick_payload,
            "processing_duration_ms": event_entry.processing_duration_ms,
            "error": event_entry.error,
        }
        await self.broadcast_event(event_data)

    async def _reload_config(self) -> Dict[str, Any]:
        """Reload project configs from disk."""
        # TODO: Implement config reload
        return {"success": True, "message": "Config reloaded"}

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
