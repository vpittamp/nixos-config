"""Legacy monitor and workspace mapping RPC service."""

from __future__ import annotations

import logging
import time
from pathlib import Path
from typing import Any, Awaitable, Callable, Dict, Optional


logger = logging.getLogger(__name__)

I3ConnectionProvider = Callable[[], Optional[Any]]
MonitorProfileServiceProvider = Callable[[], Optional[Any]]
SwayWorkspacesProvider = Callable[[], Awaitable[list[Any]]]
LogIpcEvent = Callable[..., Awaitable[None]]


async def _noop_log_ipc_event(**_kwargs: Any) -> None:
    return None


class MonitorStateService:
    """Own legacy monitor/workspace mapping RPC behavior."""

    def __init__(
        self,
        *,
        i3_connection_provider: I3ConnectionProvider,
        monitor_profile_service_provider: MonitorProfileServiceProvider = lambda: None,
        sway_workspaces_provider: Optional[SwayWorkspacesProvider] = None,
        log_ipc_event: LogIpcEvent = _noop_log_ipc_event,
        monitor_config_manager_cls: Optional[type[Any]] = None,
        get_monitor_configs_fn: Optional[Callable[..., Awaitable[list[Any]]]] = None,
        load_output_states_fn: Optional[Callable[[], Any]] = None,
    ) -> None:
        self.i3_connection_provider = i3_connection_provider
        self.monitor_profile_service_provider = monitor_profile_service_provider
        self.sway_workspaces_provider = sway_workspaces_provider
        self.log_ipc_event = log_ipc_event
        self.monitor_config_manager_cls = monitor_config_manager_cls
        self.get_monitor_configs_fn = get_monitor_configs_fn
        self.load_output_states_fn = load_output_states_fn

    def _monitor_config_manager_cls(self) -> type[Any]:
        if self.monitor_config_manager_cls is not None:
            return self.monitor_config_manager_cls
        from ..monitor_config_manager import MonitorConfigManager

        return MonitorConfigManager

    async def _get_monitor_configs(self, i3: Any, config_manager: Any) -> list[Any]:
        if self.get_monitor_configs_fn is not None:
            return await self.get_monitor_configs_fn(i3, config_manager)
        from ..workspace_manager import get_monitor_configs

        return await get_monitor_configs(i3, config_manager)

    def _load_output_states(self) -> Any:
        if self.load_output_states_fn is not None:
            return self.load_output_states_fn()
        from ..output_state_manager import load_output_states

        return load_output_states()

    def _require_i3(self) -> Any:
        i3_connection = self.i3_connection_provider()
        if not i3_connection or not getattr(i3_connection, "conn", None):
            raise RuntimeError("i3 connection not available")
        return i3_connection

    async def get_monitor_config(self) -> Dict[str, Any]:
        start_time = time.perf_counter()
        error_msg = None

        try:
            config_manager = self._monitor_config_manager_cls()()
            config = config_manager.load_config()
            return config.model_dump()

        except Exception as exc:
            error_msg = str(exc)
            logger.error("Error getting monitor config: %s", exc)
            raise
        finally:
            duration_ms = (time.perf_counter() - start_time) * 1000
            await self.log_ipc_event(
                event_type="query::monitor_config",
                duration_ms=duration_ms,
                error=error_msg,
            )

    async def validate_monitor_config(self, params: Dict[str, Any]) -> Dict[str, Any]:
        start_time = time.perf_counter()
        error_msg = None

        try:
            manager_cls = self._monitor_config_manager_cls()
            config_path_str = params.get("config_path")
            config_path = Path(config_path_str) if config_path_str else manager_cls.DEFAULT_CONFIG_PATH
            validation_result = manager_cls.validate_config_file(config_path)

            return {
                "valid": validation_result.valid,
                "issues": [issue.model_dump() for issue in validation_result.issues],
                "config": (
                    validation_result.config.model_dump()
                    if validation_result.config
                    else None
                ),
            }

        except Exception as exc:
            error_msg = str(exc)
            logger.error("Error validating monitor config: %s", exc)
            raise
        finally:
            duration_ms = (time.perf_counter() - start_time) * 1000
            await self.log_ipc_event(
                event_type="config::validate_monitor",
                params=params,
                duration_ms=duration_ms,
                error=error_msg,
            )

    async def reload_monitor_config(self) -> Dict[str, Any]:
        start_time = time.perf_counter()
        error_msg = None

        try:
            config_manager = self._monitor_config_manager_cls()()
            new_config = config_manager.load_config(force_reload=True)
            changes = [
                f"Configuration reloaded from {config_manager.config_path}",
                "Distribution rules updated for "
                f"{len(new_config.distribution.model_dump())} monitor configurations",
                f"Workspace preferences: {len(new_config.workspace_preferences)} entries",
            ]

            logger.info("Monitor configuration reloaded: %s", config_manager.config_path)

            return {
                "success": True,
                "changes": changes,
                "error": None,
            }

        except Exception as exc:
            error_msg = str(exc)
            logger.error("Error reloading monitor config: %s", exc)
            return {
                "success": False,
                "changes": [],
                "error": str(exc),
            }
        finally:
            duration_ms = (time.perf_counter() - start_time) * 1000
            await self.log_ipc_event(
                event_type="config::reload_monitor",
                config_type="workspace_monitor_mapping",
                duration_ms=duration_ms,
                error=error_msg,
            )

    async def reassign_workspaces(self, params: Dict[str, Any]) -> Dict[str, Any]:
        start_time = time.perf_counter()
        error_msg = None

        try:
            dry_run = params.get("dry_run", False)
            i3_connection = self._require_i3()

            outputs = await i3_connection.get_outputs()
            states = self._load_output_states()
            enabled_outputs = [
                output.name
                for output in outputs
                if output.active and states.is_output_enabled(output.name)
            ]
            disabled_outputs = [
                output.name
                for output in outputs
                if output.active and not states.is_output_enabled(output.name)
            ]

            if not enabled_outputs:
                return {
                    "success": False,
                    "assignments_made": 0,
                    "errors": ["No enabled outputs detected"],
                }

            assignments_made = 0
            monitor_profile_service = self.monitor_profile_service_provider()
            if (
                not dry_run
                and disabled_outputs
                and monitor_profile_service
                and self.sway_workspaces_provider is not None
            ):
                before = await self.sway_workspaces_provider()
                before_by_name = {workspace.name: workspace.output for workspace in before}
                await monitor_profile_service.migrate_workspaces_from_disabled_outputs(
                    i3_connection.conn,
                    disabled_outputs,
                    fallback_output=enabled_outputs[0],
                )
                after = await self.sway_workspaces_provider()
                assignments_made = sum(
                    1
                    for workspace in after
                    if before_by_name.get(workspace.name) not in (None, workspace.output)
                )

            return {
                "success": True,
                "assignments_made": assignments_made,
                "errors": [],
            }

        except Exception as exc:
            error_msg = str(exc)
            logger.error("Error reassigning workspaces: %s", exc)
            return {
                "success": False,
                "assignments_made": 0,
                "errors": [str(exc)],
            }
        finally:
            duration_ms = (time.perf_counter() - start_time) * 1000
            await self.log_ipc_event(
                event_type="workspace::reassign",
                params=params,
                duration_ms=duration_ms,
                error=error_msg,
            )

    async def get_monitors(self) -> list[Dict[str, Any]]:
        start_time = time.perf_counter()
        error_msg = None

        try:
            i3_connection = self._require_i3()
            config_manager = self._monitor_config_manager_cls()()
            monitors_dataclass = await self._get_monitor_configs(i3_connection.conn, config_manager)

            from ..models import MonitorConfig as PydanticMonitorConfig
            from ..models import MonitorRole, OutputRect

            monitors_pydantic = []
            for monitor in monitors_dataclass:
                pydantic_monitor = PydanticMonitorConfig(
                    name=monitor.name,
                    active=monitor.active,
                    primary=monitor.primary,
                    role=MonitorRole(monitor.role) if monitor.role else None,
                    rect=OutputRect(**monitor.rect),
                    current_workspace=None,
                )
                monitors_pydantic.append(pydantic_monitor)

            return [monitor.model_dump() for monitor in monitors_pydantic]

        except Exception as exc:
            error_msg = str(exc)
            logger.error("Error getting monitors: %s", exc)
            raise
        finally:
            duration_ms = (time.perf_counter() - start_time) * 1000
            await self.log_ipc_event(
                event_type="query::monitors",
                duration_ms=duration_ms,
                error=error_msg,
            )

    async def get_workspaces(self) -> list[Dict[str, Any]]:
        start_time = time.perf_counter()
        error_msg = None

        try:
            i3_connection = self._require_i3()
            config_manager = self._monitor_config_manager_cls()()
            monitors = await self._get_monitor_configs(i3_connection.conn, config_manager)
            role_map = {monitor.role: monitor.name for monitor in monitors if monitor.role}
            distribution = config_manager.get_workspace_distribution(len(monitors))
            i3_workspaces = await i3_connection.conn.get_workspaces()

            from ..models import MonitorRole, WorkspaceAssignment

            assignments = []
            for workspace in i3_workspaces:
                target_role = None
                target_output = None
                source = "runtime"

                config = config_manager.load_config()
                if workspace.num in config.workspace_preferences:
                    target_role = config.workspace_preferences[workspace.num]
                    target_output = role_map.get(target_role)
                    source = "explicit"
                else:
                    for role, workspace_nums in distribution.items():
                        if workspace.num in workspace_nums:
                            target_role = role
                            target_output = role_map.get(role)
                            source = "default"
                            break

                assignment = WorkspaceAssignment(
                    workspace_num=workspace.num,
                    output_name=workspace.output,
                    target_role=target_role,
                    target_output=target_output,
                    source=source,
                    visible=workspace.visible,
                    window_count=0,
                )
                assignments.append(assignment)

            return [assignment.model_dump() for assignment in assignments]

        except Exception as exc:
            error_msg = str(exc)
            logger.error("Error getting workspaces: %s", exc)
            raise
        finally:
            duration_ms = (time.perf_counter() - start_time) * 1000
            await self.log_ipc_event(
                event_type="query::workspaces",
                duration_ms=duration_ms,
                error=error_msg,
            )

    async def get_system_state(self) -> Dict[str, Any]:
        start_time = time.perf_counter()
        error_msg = None

        try:
            from ..models import MonitorSystemState

            monitors = await self.get_monitors()
            workspaces = await self.get_workspaces()
            active_monitor_count = len([monitor for monitor in monitors if monitor["active"]])
            primary_output = next(
                (monitor["name"] for monitor in monitors if monitor["primary"]),
                None,
            )

            state = MonitorSystemState(
                monitors=[monitor for monitor in monitors],
                workspaces=[workspace for workspace in workspaces],
                active_monitor_count=active_monitor_count,
                primary_output=primary_output,
                last_updated=time.time(),
            )

            return state.model_dump()

        except Exception as exc:
            error_msg = str(exc)
            logger.error("Error getting system state: %s", exc)
            raise
        finally:
            duration_ms = (time.perf_counter() - start_time) * 1000
            await self.log_ipc_event(
                event_type="query::system_state",
                duration_ms=duration_ms,
                error=error_msg,
            )
