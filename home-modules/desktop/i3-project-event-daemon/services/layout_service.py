"""Layout capture, restore, and persistence RPC service."""

from __future__ import annotations

import logging
import time
from pathlib import Path
from typing import Any, Awaitable, Callable, Dict, Optional


logger = logging.getLogger(__name__)

I3ConnectionProvider = Callable[[], Optional[Any]]
LogIpcEvent = Callable[..., Awaitable[None]]


async def _noop_log_ipc_event(**_kwargs: Any) -> None:
    return None


class LayoutService:
    """Own layout RPC behavior independently from JSON-RPC dispatch."""

    def __init__(
        self,
        *,
        i3_connection_provider: I3ConnectionProvider,
        log_ipc_event: LogIpcEvent = _noop_log_ipc_event,
        capture_layout_fn: Optional[Callable[..., Awaitable[Any]]] = None,
        save_layout_fn: Optional[Callable[[Any], Path]] = None,
        restore_workflow_fn: Optional[Callable[..., Awaitable[Any]]] = None,
        load_layout_fn: Optional[Callable[..., Any]] = None,
        list_layouts_fn: Optional[Callable[..., list[dict[str, Any]]]] = None,
        delete_layout_fn: Optional[Callable[..., bool]] = None,
    ) -> None:
        self.i3_connection_provider = i3_connection_provider
        self.log_ipc_event = log_ipc_event
        self.capture_layout_fn = capture_layout_fn
        self.save_layout_fn = save_layout_fn
        self.restore_workflow_fn = restore_workflow_fn
        self.load_layout_fn = load_layout_fn
        self.list_layouts_fn = list_layouts_fn
        self.delete_layout_fn = delete_layout_fn

    async def save(self, params: Dict[str, Any]) -> Dict[str, Any]:
        """Capture and save the current workspace layout."""
        start_time = time.perf_counter()

        try:
            project = params.get("project")
            name = params.get("name")

            if not project:
                raise ValueError("project parameter is required")
            if not name:
                raise ValueError("name parameter is required")

            capture_layout = self.capture_layout_fn
            save_layout = self.save_layout_fn
            if capture_layout is None or save_layout is None:
                from ..layout.capture import capture_layout as default_capture_layout
                from ..layout.persistence import save_layout as default_save_layout

                capture_layout = capture_layout or default_capture_layout
                save_layout = save_layout or default_save_layout

            snapshot = await capture_layout(
                i3_connection=self.i3_connection_provider(),
                name=name,
                project=project,
            )
            layout_path = save_layout(snapshot)

            result = {
                "success": True,
                "layout_path": str(layout_path),
                "workspace_count": len(snapshot.workspace_layouts),
                "window_count": snapshot.metadata.get("total_windows", 0),
                "focused_workspace": snapshot.focused_workspace or 1,
            }

            logger.info(
                "Layout captured: %s/%s - %s workspaces, %s windows -> %s",
                project,
                name,
                result["workspace_count"],
                result["window_count"],
                layout_path,
            )

            return result

        except ValueError as exc:
            raise ValueError(str(exc))
        except Exception as exc:
            logger.error("Layout capture failed: %s", exc, exc_info=True)
            raise RuntimeError(f"Layout capture failed: {exc}")
        finally:
            duration_ms = (time.perf_counter() - start_time) * 1000
            await self.log_ipc_event(
                event_type="layout::capture",
                project_name=params.get("project"),
                params=params,
                duration_ms=duration_ms,
            )

    async def restore(self, params: Dict[str, Any]) -> Dict[str, Any]:
        """Restore a saved workspace layout."""
        start_time = time.perf_counter()

        try:
            project = params.get("project")
            name = params.get("name")

            if not project:
                raise ValueError("project parameter is required")
            if not name:
                raise ValueError("name parameter is required")

            restore_workflow = self.restore_workflow_fn
            load_layout = self.load_layout_fn
            if restore_workflow is None or load_layout is None:
                from ..layout.persistence import load_layout as default_load_layout
                from ..layout.restore import restore_workflow as default_restore_workflow

                restore_workflow = restore_workflow or default_restore_workflow
                load_layout = load_layout or default_load_layout

            layout = load_layout(name, project)
            if not layout:
                raise FileNotFoundError(f"Layout '{name}' not found for project '{project}'")

            restore_result = await restore_workflow(
                layout=layout,
                project=project,
                i3_connection=self.i3_connection_provider(),
            )

            result = {
                "success": restore_result.status == "success",
                "status": restore_result.status,
                "apps_already_running": restore_result.apps_already_running,
                "apps_launched": restore_result.apps_launched,
                "apps_failed": restore_result.apps_failed,
                "elapsed_seconds": restore_result.elapsed_seconds,
                "total_apps": restore_result.total_apps,
                "success_rate": restore_result.success_rate,
                "windows_launched": len(restore_result.apps_launched),
                "windows_matched": 0,
                "windows_timeout": 0,
                "windows_failed": len(restore_result.apps_failed),
            }

            logger.info(
                "Layout restored: %s/%s - status=%s, %s already running, "
                "%s launched, %s failed (%.1fs, %.1f%% success)",
                project,
                name,
                result["status"],
                len(result["apps_already_running"]),
                len(result["apps_launched"]),
                len(result["apps_failed"]),
                result["elapsed_seconds"],
                result["success_rate"],
            )

            return result

        except FileNotFoundError:
            raise RuntimeError(
                f"Layout not found: {params.get('name')} for project {params.get('project')}"
            )
        except ValueError as exc:
            raise ValueError(str(exc))
        except Exception as exc:
            logger.error("Layout restore failed: %s", exc, exc_info=True)
            raise RuntimeError(f"Layout restore failed: {exc}")
        finally:
            duration_ms = (time.perf_counter() - start_time) * 1000
            await self.log_ipc_event(
                event_type="layout::restore",
                project_name=params.get("project"),
                params=params,
                duration_ms=duration_ms,
            )

    async def list(self, params: Dict[str, Any]) -> Dict[str, Any]:
        """List saved layout snapshots."""
        start_time = time.perf_counter()

        try:
            project_name = params.get("project_name")
            include_auto_saves = params.get("include_auto_saves", True)

            if not project_name:
                raise ValueError("project_name parameter is required")

            list_layouts = self.list_layouts_fn
            if list_layouts is None:
                from ..layout.persistence import list_layouts as default_list_layouts

                list_layouts = default_list_layouts

            all_layouts = list_layouts(project_name)
            layouts = [
                {
                    "layout_name": layout.get("name", ""),
                    "timestamp": layout.get("created_at"),
                    "windows_count": layout.get("total_windows", 0),
                    "file_path": layout.get("file_path", ""),
                }
                for layout in all_layouts
            ]

            if not include_auto_saves:
                layouts = [
                    layout
                    for layout in layouts
                    if not layout.get("layout_name", "").startswith("auto-")
                ]

            for layout in layouts:
                layout["is_auto_save"] = layout.get("layout_name", "").startswith("auto-")

            result = {
                "project": project_name,
                "layouts": layouts,
                "total_count": len(layouts),
            }

            logger.info(
                "Listed layouts: %s found for %s (include_auto_saves=%s)",
                len(layouts),
                project_name,
                include_auto_saves,
            )

            return result

        except ValueError as exc:
            raise ValueError(str(exc))
        except Exception as exc:
            logger.error("Layout list failed: %s", exc, exc_info=True)
            raise RuntimeError(f"Layout list failed: {exc}")
        finally:
            duration_ms = (time.perf_counter() - start_time) * 1000
            await self.log_ipc_event(
                event_type="query::layout_list",
                project_name=params.get("project_name"),
                params=params,
                duration_ms=duration_ms,
            )

    async def delete(self, params: Dict[str, Any]) -> Dict[str, Any]:
        """Delete a saved layout snapshot."""
        start_time = time.perf_counter()

        try:
            project_name = params.get("project_name")
            layout_name = params.get("layout_name")

            if not project_name or not layout_name:
                raise ValueError("project_name and layout_name parameters are required")

            delete_layout = self.delete_layout_fn
            if delete_layout is None:
                from ..layout.persistence import delete_layout as default_delete_layout

                delete_layout = default_delete_layout

            deleted = delete_layout(layout_name, project_name)
            if not deleted:
                raise RuntimeError(f"Layout not found: {layout_name} for project {project_name}")

            result = {
                "deleted": True,
                "layout_name": layout_name,
            }

            logger.info("Deleted layout: %s/%s", project_name, layout_name)

            return result

        finally:
            duration_ms = (time.perf_counter() - start_time) * 1000
            await self.log_ipc_event(
                event_type="layout::delete",
                project_name=params.get("project_name"),
                params=params,
                duration_ms=duration_ms,
            )

    async def info(self, params: Dict[str, Any]) -> Dict[str, Any]:
        """Return detailed information about a saved layout."""
        start_time = time.perf_counter()

        try:
            name = params.get("name")
            project = params.get("project", "global")

            if not name:
                raise ValueError("'name' parameter is required")

            load_layout = self.load_layout_fn
            if load_layout is None:
                from ..layout import load_layout as default_load_layout

                load_layout = default_load_layout

            snapshot = load_layout(name=name, project=project)
            if not snapshot:
                raise ValueError(f"Layout not found: {name} (project: {project})")

            workspaces = [
                {
                    "workspace_num": ws_layout.workspace_num,
                    "workspace_name": ws_layout.workspace_name if ws_layout.workspace_name else "",
                    "output": ws_layout.output,
                    "window_count": len(ws_layout.windows),
                }
                for ws_layout in snapshot.workspace_layouts
            ]

            monitors = [
                {
                    "name": monitor.name,
                    "width": monitor.resolution.width if monitor.resolution else 0,
                    "height": monitor.resolution.height if monitor.resolution else 0,
                    "primary": monitor.primary,
                }
                for monitor in snapshot.monitor_config.monitors
            ]

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

            logger.info("Retrieved layout info: %s/%s", project, name)

            return result

        finally:
            duration_ms = (time.perf_counter() - start_time) * 1000
            await self.log_ipc_event(
                event_type="query::layout_info",
                project_name=params.get("project"),
                params=params,
                duration_ms=duration_ms,
            )
