"""Daemon status and health payload shaping."""

from __future__ import annotations

import os
import time
from datetime import datetime
from typing import Any, Callable, Dict, Optional


SocketPathProvider = Callable[[], str]
IpcStatsProvider = Callable[[], Dict[str, Any]]
StartupRecoveryProvider = Callable[[], Optional[Any]]
ReconnectionManagerProvider = Callable[[], Optional[Any]]


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
        startup_recovery_provider: StartupRecoveryProvider = lambda: None,
        reconnection_manager_provider: ReconnectionManagerProvider = lambda: None,
        status_version: str = "1.0.0",
        health_version: str = "1.4.0",
    ) -> None:
        self.state_manager = state_manager
        self.event_buffer = event_buffer
        self.i3_connection_provider = i3_connection_provider
        self.socket_path_provider = socket_path_provider
        self.ipc_stats_provider = ipc_stats_provider
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
            "i3_connected": health.i3_connected,
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
                "is_connected": health.i3_connected,
                "reconnection_count": 0,
            }

        return result

    def health_check(self) -> Dict[str, Any]:
        """Return diagnostic daemon health for the legacy health_check RPC."""
        daemon_start = getattr(self.state_manager, "daemon_start_time", time.time())
        uptime_seconds = time.time() - daemon_start

        i3_connection = self.i3_connection_provider()
        i3_connected = bool(i3_connection and i3_connection.is_connected)

        event_subscriptions = []
        if self.event_buffer:
            for sub_type in ["window", "workspace", "output", "tick"]:
                events = [
                    event
                    for event in self.event_buffer.get_recent(limit=500)
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

        total_events = len(self.event_buffer.get_recent(limit=9999)) if self.event_buffer else 0
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
