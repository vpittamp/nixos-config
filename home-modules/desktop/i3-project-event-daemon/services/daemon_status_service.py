"""Daemon status and health payload shaping."""

from __future__ import annotations

import json
import logging
import os
import time
from dataclasses import asdict, is_dataclass
from datetime import datetime
from pathlib import Path
from typing import Any, Awaitable, Callable, Dict, Optional


logger = logging.getLogger(__name__)

SocketPathProvider = Callable[[], str]
IpcStatsProvider = Callable[[], Dict[str, Any]]
StartupRecoveryProvider = Callable[[], Optional[Any]]
ReconnectionManagerProvider = Callable[[], Optional[Any]]
EventBufferProvider = Callable[[], Optional[Any]]
LogIpcEvent = Callable[..., Awaitable[None]]


async def _noop_log_ipc_event(**_kwargs: Any) -> None:
    return None


def _json_safe(value: Any) -> Any:
    if isinstance(value, datetime):
        return value.isoformat()
    if isinstance(value, dict):
        return {key: _json_safe(item) for key, item in value.items()}
    if isinstance(value, list):
        return [_json_safe(item) for item in value]
    if isinstance(value, tuple):
        return [_json_safe(item) for item in value]
    return value


def _event_data(event: Any) -> Dict[str, Any]:
    to_dict = getattr(event, "to_dict", None)
    if callable(to_dict):
        return _json_safe(to_dict())
    if is_dataclass(event):
        return _json_safe(
            {key: value for key, value in asdict(event).items() if value is not None}
        )
    return _json_safe(
        {
            key: value
            for key, value in vars(event).items()
            if not key.startswith("_") and value is not None
        }
    )


class DaemonStatusService:
    """Own daemon status/health payloads independently from JSON-RPC dispatch."""

    def __init__(
        self,
        *,
        state_manager: Any,
        event_buffer: Optional[Any],
        i3_connection_provider: Callable[[], Optional[Any]],
        socket_path_provider: SocketPathProvider,
        ipc_stats_provider: IpcStatsProvider,
        event_buffer_provider: Optional[EventBufferProvider] = None,
        log_ipc_event: LogIpcEvent = _noop_log_ipc_event,
        registry_path: Optional[Path] = None,
        startup_recovery_provider: StartupRecoveryProvider = lambda: None,
        reconnection_manager_provider: ReconnectionManagerProvider = lambda: None,
        status_version: str = "1.0.0",
        health_version: str = "1.4.0",
    ) -> None:
        self.state_manager = state_manager
        self._event_buffer = event_buffer
        self.event_buffer_provider = event_buffer_provider or (lambda: self._event_buffer)
        self.i3_connection_provider = i3_connection_provider
        self.socket_path_provider = socket_path_provider
        self.ipc_stats_provider = ipc_stats_provider
        self.log_ipc_event = log_ipc_event
        self.registry_path = (
            registry_path
            or Path.home() / ".config" / "i3" / "application-registry.json"
        )
        self.startup_recovery_provider = startup_recovery_provider
        self.reconnection_manager_provider = reconnection_manager_provider
        self.status_version = status_version
        self.health_version = health_version

    async def cli_status(self) -> Dict[str, Any]:
        """Return the lightweight daemon status used by `i3pm daemon status`."""
        stats = await self.state_manager.get_stats()
        return {
            "status": "running",
            "connected": self.state_manager.state.is_connected,
            "uptime": stats.get("uptime_seconds", 0),
            "active_project": stats.get("active_project"),
            "window_count": stats.get("window_count", 0),
            "workspace_count": stats.get("workspace_count", 0),
            "event_count": stats.get("event_count", 0),
            "error_count": stats.get("error_count", 0),
            "version": self.status_version,
            "socket_path": self.socket_path_provider(),
            "ipc_stats": self.ipc_stats_provider(),
        }

    async def daemon_status(self) -> Dict[str, Any]:
        """Return the comprehensive daemon.status JSON-RPC payload."""
        from ..monitoring.health import get_health_metrics

        health = get_health_metrics()
        health.update_resource_usage()
        stats = await self.state_manager.get_stats()
        i3_connection = self.i3_connection_provider()
        i3_connected = (
            bool(i3_connection.is_connected)
            if i3_connection is not None
            else bool(health.i3_connected)
        )

        result = {
            "running": True,
            "uptime_seconds": health.uptime_seconds,
            "pid": os.getpid(),
            "memory_mb": health.memory_rss_mb,
            "event_count": health.total_events_processed,
            "error_count": health.total_errors,
            "last_event_time": datetime.fromtimestamp(health.last_event_time).isoformat()
            if health.last_event_time
            else None,
            "i3_connected": i3_connected,
            "active_project": stats.get("active_project"),
        }

        startup_recovery_result = self.startup_recovery_provider()
        if startup_recovery_result:
            result["recovery"] = {
                "startup_recovery_performed": True,
                "startup_recovery_success": startup_recovery_result.success,
                "actions_taken": startup_recovery_result.actions_taken,
                "recovery_timestamp": startup_recovery_result.timestamp.isoformat(),
            }
        else:
            result["recovery"] = {
                "startup_recovery_performed": False,
            }

        reconnection_manager = self.reconnection_manager_provider()
        if reconnection_manager:
            result["i3_reconnection"] = reconnection_manager.get_stats()
        else:
            result["i3_reconnection"] = {
                "is_connected": i3_connected,
                "reconnection_count": 0,
            }

        return result

    async def status_rpc(self) -> Dict[str, Any]:
        """Return daemon.status payload and record the IPC query event."""
        start_time = time.perf_counter()
        try:
            return await self.daemon_status()
        finally:
            duration_ms = (time.perf_counter() - start_time) * 1000
            await self.log_ipc_event(
                event_type="query::daemon_status",
                duration_ms=duration_ms,
            )

    async def events_rpc(self, params: Dict[str, Any]) -> Dict[str, Any]:
        """Return daemon.events payload with filtering."""
        start_time = time.perf_counter()
        result: Dict[str, Any] = {
            "events": [],
            "total_events": 0,
            "buffer_size": 0,
        }

        try:
            event_buffer = self.event_buffer_provider()
            if not event_buffer:
                return result

            source_filter = params.get("source", "all")
            event_type_filter = params.get("event_type")
            limit = min(params.get("limit", 20), 500)
            since_str = params.get("since")
            include_correlation = params.get("correlate", False)

            since_dt = None
            if since_str:
                try:
                    since_dt = datetime.fromisoformat(since_str.replace("Z", "+00:00"))
                except ValueError:
                    logger.warning("Invalid 'since' timestamp: %s", since_str)

            all_events = event_buffer.get_events(limit=limit)

            filtered_events = []
            for event in all_events:
                if source_filter != "all" and event.source != source_filter:
                    continue
                if event_type_filter and event.event_type != event_type_filter:
                    continue
                if since_dt and event.timestamp < since_dt:
                    continue
                filtered_events.append(event)

            events_data = []
            for event in filtered_events:
                event_dict = {
                    "event_id": str(event.event_id),
                    "source": event.source,
                    "event_type": event.event_type,
                    "timestamp": event.timestamp.isoformat(),
                    "data": _event_data(event),
                }

                correlation_id = getattr(event, "correlation_id", None)
                if include_correlation and correlation_id:
                    event_dict["correlation_id"] = str(correlation_id)
                    event_dict["confidence_score"] = getattr(event, "confidence_score", None)

                events_data.append(event_dict)

            result = {
                "events": events_data,
                "total_events": len(event_buffer.buffer),
                "buffer_size": event_buffer.max_size,
            }

            return result

        finally:
            duration_ms = (time.perf_counter() - start_time) * 1000
            await self.log_ipc_event(
                event_type="query::daemon_events",
                result_count=len(result.get("events", [])),
                params=params,
                duration_ms=duration_ms,
            )

    async def diagnose_rpc(self, params: Dict[str, Any]) -> Dict[str, Any]:
        """Generate comprehensive daemon diagnostic snapshot."""
        from ..monitoring.diagnostics import generate_diagnostic_snapshot

        start_time = time.perf_counter()

        try:
            include_events = params.get("include_events", True)
            include_i3_tree = params.get("include_i3_tree", True)
            include_config = params.get("include_config", True)

            snapshot = await generate_diagnostic_snapshot(
                include_i3_tree=include_i3_tree,
                include_events=include_events,
                event_limit=100,
                sanitize=True,
            )

            result = {
                "timestamp": snapshot.timestamp,
                "daemon_status": await self.status_rpc(),
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
            await self.log_ipc_event(
                event_type="query::daemon_diagnose",
                params=params,
                duration_ms=duration_ms,
            )

    async def apps_rpc(self, params: Dict[str, Any]) -> Dict[str, Any]:
        """Return applications currently loaded in the generated registry."""
        start_time = time.perf_counter()

        try:
            if not self.registry_path.exists():
                raise RuntimeError(json.dumps({
                    "code": -32001,
                    "message": "Application registry not found",
                    "data": {
                        "reason": "registry_file_not_found",
                        "path": str(self.registry_path),
                    },
                }))

            with self.registry_path.open("r", encoding="utf-8") as registry_file:
                registry = json.load(registry_file)

            applications = registry.get("applications", [])
            version = registry.get("version", "unknown")

            name_filter = params.get("name")
            if name_filter:
                applications = [app for app in applications if app.get("name") == name_filter]

            scope_filter = params.get("scope")
            if scope_filter:
                applications = [app for app in applications if app.get("scope") == scope_filter]

            workspace_filter = params.get("workspace")
            if workspace_filter:
                applications = [
                    app for app in applications
                    if app.get("preferred_workspace") == workspace_filter
                ]

            return {
                "applications": applications,
                "version": version,
                "count": len(applications),
                "registry_path": str(self.registry_path),
            }

        finally:
            duration_ms = (time.perf_counter() - start_time) * 1000
            await self.log_ipc_event(
                event_type="query::daemon_apps",
                params=params,
                duration_ms=duration_ms,
            )

    def health_check(self) -> Dict[str, Any]:
        """Return diagnostic daemon health for the legacy health_check RPC."""
        daemon_start = getattr(self.state_manager, "daemon_start_time", time.time())
        uptime_seconds = time.time() - daemon_start

        i3_connection = self.i3_connection_provider()
        i3_connected = bool(i3_connection and i3_connection.is_connected)
        event_buffer = self.event_buffer_provider()

        event_subscriptions = []
        if event_buffer:
            for sub_type in ["window", "workspace", "output", "tick"]:
                events = [
                    event
                    for event in event_buffer.get_recent(limit=500)
                    if event.event_type.startswith(sub_type)
                ]
                last_event = events[0] if events else None
                event_subscriptions.append(
                    {
                        "subscription_type": sub_type,
                        "is_active": i3_connected,
                        "event_count": len(events),
                        "last_event_time": last_event.timestamp.isoformat() if last_event else None,
                        "last_event_type": last_event.event_type if last_event else None,
                    }
                )

        total_events = len(event_buffer.get_recent(limit=9999)) if event_buffer else 0
        total_windows = len(self.state_manager.state.window_map)

        health_issues = []
        if not i3_connected:
            health_issues.append("i3 IPC connection lost")
        if not event_subscriptions:
            health_issues.append("No event subscriptions active")
        if total_events == 0 and uptime_seconds > 60:
            health_issues.append("No events processed (daemon may not be receiving events)")

        overall_status = "healthy"
        if health_issues:
            if "i3 IPC connection lost" in health_issues or "No event subscriptions active" in health_issues:
                overall_status = "critical"
            else:
                overall_status = "warning"

        return {
            "daemon_version": self.health_version,
            "uptime_seconds": round(uptime_seconds, 1),
            "i3_ipc_connected": i3_connected,
            "json_rpc_server_running": True,
            "event_subscriptions": event_subscriptions,
            "total_events_processed": total_events,
            "total_windows": total_windows,
            "overall_status": overall_status,
            "health_issues": health_issues,
        }

    async def socket_health(self) -> Dict[str, Any]:
        """Return Sway IPC socket health from the resilient connection manager."""
        i3_connection = self.i3_connection_provider()
        if not i3_connection:
            return {
                "status": "disconnected",
                "socket_path": None,
                "last_validated": None,
                "latency_ms": None,
                "reconnection_count": 0,
                "uptime_seconds": 0.0,
                "error": "No i3 connection manager available",
            }

        health_status = await i3_connection.get_health_status()
        return health_status.to_dict()
