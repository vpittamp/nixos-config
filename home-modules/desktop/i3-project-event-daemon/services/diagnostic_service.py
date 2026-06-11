"""Diagnostic RPC payload shaping for daemon operator endpoints."""

from __future__ import annotations

import json
import logging
import time
from datetime import datetime
from pathlib import Path
from typing import Any, Awaitable, Callable, Dict, List, Optional

from .window_filter import read_process_environ
from .window_identifier import normalize_class


logger = logging.getLogger(__name__)

I3ConnectionProvider = Callable[[], Optional[Any]]
LogIpcEvent = Callable[..., Awaitable[None]]
WorkspacesProvider = Callable[[], Awaitable[List[Any]]]


class DiagnosticService:
    """Own diagnostic RPC behavior independently from JSON-RPC dispatch."""

    def __init__(
        self,
        *,
        state_manager: Any,
        event_buffer: Optional[Any],
        i3_connection_provider: I3ConnectionProvider,
        daemon_status_service: Any,
        get_workspaces: WorkspacesProvider,
        log_ipc_event: LogIpcEvent,
        registry_path: Path,
    ) -> None:
        self.state_manager = state_manager
        self.event_buffer = event_buffer
        self.i3_connection_provider = i3_connection_provider
        self.daemon_status_service = daemon_status_service
        self.get_workspaces = get_workspaces
        self.log_ipc_event = log_ipc_event
        self.registry_path = registry_path

    def _i3_connection(self) -> Optional[Any]:
        return self.i3_connection_provider()

    @staticmethod
    def _connection_is_connected(connection: Any) -> bool:
        if connection is None:
            return False
        is_connected = getattr(connection, "is_connected", False)
        if callable(is_connected):
            return bool(is_connected())
        return bool(is_connected)

    async def window_identity(self, params: Dict[str, Any]) -> Dict[str, Any]:
        """Get comprehensive window identity for diagnostic purposes."""
        start_time = time.perf_counter()
        window_id = params.get("window_id")

        if not window_id:
            raise ValueError("window_id parameter required")

        connection = self._i3_connection()
        if not self._connection_is_connected(connection):
            raise RuntimeError("i3 IPC connection not available")

        try:
            tree = await connection.get_tree()
            window = tree.find_by_id(window_id)

            if not window:
                raise ValueError(f"Window {window_id} not found")

            window_class = window.window_class or "unknown"
            window_instance = window.window_instance or ""
            window_title = window.name or "(no title)"
            window_pid = window.pid if hasattr(window, "pid") else None

            workspace = window.workspace()
            workspace_number = workspace.num if workspace else None
            workspace_name = workspace.name if workspace else None
            output_name = workspace.ipc_data.get("output") if workspace else None

            is_floating = window.floating != "auto_off" if hasattr(window, "floating") else False
            is_focused = window.focused

            is_hidden = False
            parent = window.parent
            while parent:
                if parent.scratchpad_state and parent.scratchpad_state != "none":
                    is_hidden = True
                    break
                parent = parent.parent

            i3pm_env = None
            if window_pid:
                env = read_process_environ(window_pid)
                if env:
                    i3pm_env = {
                        "app_id": env.get("I3PM_APP_ID"),
                        "app_name": env.get("I3PM_APP_NAME"),
                        "project_name": env.get("I3PM_PROJECT_NAME"),
                        "scope": env.get("I3PM_SCOPE"),
                    }

            i3pm_marks = [
                mark
                for mark in (window.marks or [])
                if mark.startswith("scoped:") or mark.startswith("global:") or mark.startswith("app:")
            ]

            window_class_normalized = normalize_class(window_class)

            tracked_window = self.state_manager.state.window_map.get(window_id)
            matched_app = None
            match_type = "none"

            if tracked_window:
                matched_app = getattr(tracked_window, "app_name", None)
                match_type = getattr(tracked_window, "match_type", "tracked")

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
                "match_type": match_type,
            }

            await self.log_ipc_event(
                event_type="get_window_identity",
                duration_ms=duration_ms,
                params={"window_id": window_id},
            )

            return result

        except ValueError as error:
            if "not found" in str(error):
                raise RuntimeError(json.dumps({
                    "code": -32001,
                    "message": "Window not found",
                    "data": {"window_id": window_id},
                }))
            raise
        except Exception as error:
            logger.error("Error getting window identity: %s", error)
            raise

    async def window_environment(self, params: Dict[str, Any]) -> Dict[str, Any]:
        """Get I3PM environment variables for a window by PID."""
        start_time = time.perf_counter()
        pid = params.get("pid")

        if not pid:
            raise ValueError("pid parameter required")

        if not isinstance(pid, int) or pid <= 0:
            raise ValueError(f"Invalid PID: {pid}")

        env = read_process_environ(pid)

        result = {
            "app_id": env.get("I3PM_APP_ID") if env else None,
            "app_name": env.get("I3PM_APP_NAME") if env else None,
            "project_name": env.get("I3PM_PROJECT_NAME") if env else None,
            "project_dir": env.get("I3PM_PROJECT_DIR") if env else None,
            "scope": env.get("I3PM_SCOPE") if env else None,
            "target_workspace": None,
            "expected_class": env.get("I3PM_EXPECTED_CLASS") if env else None,
        }

        if env and "I3PM_TARGET_WORKSPACE" in env:
            try:
                result["target_workspace"] = int(env["I3PM_TARGET_WORKSPACE"])
            except (ValueError, TypeError):
                pass

        duration_ms = (time.perf_counter() - start_time) * 1000
        await self.log_ipc_event(
            event_type="get_window_environment",
            duration_ms=duration_ms,
            params={"pid": pid},
        )

        return result

    async def workspace_rule(self, params: Dict[str, Any]) -> Dict[str, Any]:
        """Get workspace assignment rule for an application."""
        start_time = time.perf_counter()
        app_name = params.get("app_name")

        if not app_name:
            raise ValueError("app_name parameter required")

        if not self.registry_path.exists():
            raise RuntimeError(json.dumps({
                "code": -32003,
                "message": "Application not found in registry",
                "data": {"app_name": app_name, "reason": "registry_file_not_found"},
            }))

        try:
            with open(self.registry_path) as registry_file:
                registry = json.load(registry_file)

            app_def = registry.get(app_name)

            if not app_def:
                raise RuntimeError(json.dumps({
                    "code": -32003,
                    "message": "Application not found in registry",
                    "data": {"app_name": app_name},
                }))

            result = {
                "app_identifier": app_def.get("expected_class", app_name),
                "matching_strategy": "normalized",
                "aliases": app_def.get("aliases", []),
                "target_workspace": app_def.get("preferred_workspace"),
                "fallback_behavior": app_def.get("fallback_behavior", "current"),
                "app_name": app_name,
                "description": app_def.get("display_name", app_name),
            }

            duration_ms = (time.perf_counter() - start_time) * 1000

            await self.log_ipc_event(
                event_type="get_workspace_rule",
                duration_ms=duration_ms,
                params={"app_name": app_name},
            )

            return result

        except RuntimeError as error:
            if str(error).startswith("{"):
                raise
            raise
        except Exception as error:
            logger.error("Error getting workspace rule: %s", error)
            raise

    async def validate_state(self) -> Dict[str, Any]:
        """Validate daemon state consistency against i3 IPC."""
        start_time = time.perf_counter()

        connection = self._i3_connection()
        if not self._connection_is_connected(connection):
            raise RuntimeError(json.dumps({
                "code": -32010,
                "message": "i3 IPC connection failed",
                "data": {"reason": "not_connected"},
            }))

        try:
            tree = await connection.get_tree()
            i3_windows = tree.leaves()
            daemon_windows = self.state_manager.state.window_map

            total_windows_checked = len(i3_windows)
            windows_consistent = 0
            windows_inconsistent = 0
            mismatches = []

            for i3_window in i3_windows:
                window_id = i3_window.id
                daemon_window = daemon_windows.get(window_id)

                i3_workspace = i3_window.workspace()
                i3_workspace_num = i3_workspace.num if i3_workspace else None

                if daemon_window:
                    daemon_workspace_num = getattr(daemon_window, "workspace_number", None)

                    if daemon_workspace_num and daemon_workspace_num != i3_workspace_num:
                        mismatches.append({
                            "window_id": window_id,
                            "property_name": "workspace",
                            "daemon_value": str(daemon_workspace_num),
                            "i3_value": str(i3_workspace_num),
                            "severity": "warning",
                        })
                        windows_inconsistent += 1
                    else:
                        windows_consistent += 1
                else:
                    windows_consistent += 1

            is_consistent = windows_inconsistent == 0
            consistency_percentage = (
                round((windows_consistent / total_windows_checked * 100), 1)
                if total_windows_checked > 0
                else 100.0
            )

            duration_ms = (time.perf_counter() - start_time) * 1000

            result = {
                "validated_at": datetime.now().isoformat(),
                "total_windows_checked": total_windows_checked,
                "windows_consistent": windows_consistent,
                "windows_inconsistent": windows_inconsistent,
                "mismatches": mismatches,
                "is_consistent": is_consistent,
                "consistency_percentage": consistency_percentage,
            }

            await self.log_ipc_event(
                event_type="validate_state",
                duration_ms=duration_ms,
            )

            return result

        except Exception as error:
            logger.error("Error validating state: %s", error)
            raise

    async def recent_events(self, params: Dict[str, Any]) -> List[Dict[str, Any]]:
        """Get recent events from the circular event buffer."""
        start_time = time.perf_counter()

        limit = params.get("limit", 50)
        event_type = params.get("event_type")

        if limit < 1 or limit > 500:
            raise RuntimeError(json.dumps({
                "code": -32004,
                "message": "Invalid limit (must be 1-500)",
                "data": {"limit": limit},
            }))

        if not self.event_buffer:
            return []

        events = self.event_buffer.get_recent(limit=limit, event_type=event_type)

        formatted_events = []
        for event in events:
            formatted_events.append({
                "event_id": event.event_id,
                "event_type": event.event_type,
                "timestamp": event.timestamp.isoformat() if event.timestamp else "",
                "source": event.source,
                "window_id": event.window_id,
                "window_class": event.window_class,
                "window_title": event.window_title,
                "workspace_name": event.workspace_name,
                "project_name": event.project_name,
                "processing_duration_ms": event.processing_duration_ms,
                "error": event.error,
            })

        duration_ms = (time.perf_counter() - start_time) * 1000

        await self.log_ipc_event(
            event_type="get_recent_events",
            duration_ms=duration_ms,
            params={"limit": limit, "event_type": event_type},
        )

        return formatted_events

    async def report(self, params: Dict[str, Any]) -> Dict[str, Any]:
        """Get complete diagnostic report with all requested state sections."""
        start_time = time.perf_counter()

        include_windows = params.get("include_windows", False)
        include_events = params.get("include_events", False)
        include_validation = params.get("include_validation", False)

        health_data = self.daemon_status_service.health_check()

        report = {
            "generated_at": datetime.now().isoformat(),
            **health_data,
        }

        connection = self._i3_connection()
        if connection and self._connection_is_connected(connection):
            try:
                tree = await connection.get_tree()
                workspaces = await self.get_workspaces()
                outputs = await connection.get_outputs()

                report["i3_ipc_state"] = {
                    "total_windows": len(tree.leaves()),
                    "total_workspaces": len(workspaces),
                    "total_outputs": len([output for output in outputs if output.active]),
                }
            except Exception as error:
                logger.error("Error getting i3 state: %s", error)
                report["i3_ipc_state"] = {"error": str(error)}

        if include_windows:
            windows = []
            for window_id, window_data in self.state_manager.state.windows.items():
                windows.append({
                    "window_id": window_id,
                    "window_class": getattr(window_data, "window_class", "unknown"),
                    "workspace": getattr(window_data, "workspace_number", None),
                })
            report["tracked_windows"] = windows

        if include_events:
            report["recent_events"] = await self.recent_events({"limit": 100})

        if include_validation:
            report["state_validation"] = await self.validate_state()

        duration_ms = (time.perf_counter() - start_time) * 1000

        await self.log_ipc_event(
            event_type="get_diagnostic_report",
            duration_ms=duration_ms,
            params=params,
        )

        return report
