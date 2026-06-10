"""Assistant desktop snapshot, preview, and action orchestration."""

from __future__ import annotations

import logging
import subprocess
from difflib import SequenceMatcher
from typing import Any, Awaitable, Callable, Dict, List, Optional, Tuple

from .registry_loader import RegistryApp, RegistryLoader

logger = logging.getLogger(__name__)


class AssistantDesktopService:
    """Own assistant.desktop view shaping and deterministic action resolution."""

    def __init__(
        self,
        *,
        registry_loader: RegistryLoader,
        desktop_revision: Callable[[], int],
        runtime_snapshot: Callable[[Dict[str, Any]], Awaitable[Dict[str, Any]]],
        window_focus: Callable[[Dict[str, Any]], Awaitable[Dict[str, Any]]],
        window_action: Callable[[Dict[str, Any]], Awaitable[Dict[str, Any]]],
        workspace_focus: Callable[[Dict[str, Any]], Awaitable[Dict[str, Any]]],
        context_ensure: Callable[[Dict[str, Any]], Awaitable[Dict[str, Any]]],
        scratchpad_toggle: Callable[[Dict[str, Any]], Awaitable[Dict[str, Any]]],
        launch_open: Callable[[Dict[str, Any]], Awaitable[Dict[str, Any]]],
        display_cycle: Callable[[Dict[str, Any]], Awaitable[Dict[str, Any]]],
        run_command: Callable[..., subprocess.CompletedProcess[str]] = subprocess.run,
    ) -> None:
        self._registry_loader = registry_loader
        self._desktop_revision = desktop_revision
        self._runtime_snapshot = runtime_snapshot
        self._window_focus = window_focus
        self._window_action = window_action
        self._workspace_focus = workspace_focus
        self._context_ensure = context_ensure
        self._scratchpad_toggle = scratchpad_toggle
        self._launch_open = launch_open
        self._display_cycle = display_cycle
        self._run_command = run_command

    def window_search_text(self, window: Dict[str, Any]) -> str:
        parts = [
            window.get("title"),
            window.get("app_name"),
            window.get("app_key"),
            window.get("window_class"),
            window.get("project"),
            window.get("workspace"),
            window.get("output"),
            window.get("context_key"),
        ]
        return " ".join(str(part or "").strip().lower() for part in parts if str(part or "").strip())

    def _window_score(
        self,
        *,
        query: str,
        window: Dict[str, Any],
        active_context_key: str,
    ) -> float:
        normalized_query = str(query or "").strip().lower()
        if not normalized_query:
            return 0.0

        window_id = int(window.get("window_id") or 0)
        if normalized_query.isdigit() and window_id == int(normalized_query):
            return 1000.0

        score = 0.0
        title = str(window.get("title") or "").strip().lower()
        app_name = str(window.get("app_name") or "").strip().lower()
        window_class = str(window.get("window_class") or "").strip().lower()
        workspace = str(window.get("workspace") or "").strip().lower()
        project = str(window.get("project") or "").strip().lower()
        search_text = self.window_search_text(window)

        for field_value, field_weight in (
            (title, 180.0),
            (app_name, 220.0),
            (window_class, 200.0),
            (workspace, 120.0),
            (project, 120.0),
        ):
            if not field_value:
                continue
            if field_value == normalized_query:
                score = max(score, 700.0 + field_weight)
            elif normalized_query in field_value:
                score = max(score, 520.0 + field_weight)
            else:
                ratio = SequenceMatcher(None, normalized_query, field_value).ratio()
                score = max(score, ratio * field_weight)

        if search_text and normalized_query in search_text:
            score = max(score, 480.0)
        elif search_text:
            score = max(score, SequenceMatcher(None, normalized_query, search_text).ratio() * 140.0)

        if active_context_key and str(window.get("context_key") or "").strip() == active_context_key:
            score += 90.0
        if bool(window.get("focused", False)):
            score += 30.0
        if bool(window.get("visible", False)):
            score += 20.0
        if bool(window.get("hidden", False)):
            score -= 40.0
        return score

    def resolve_window_target(
        self,
        *,
        runtime_snapshot: Dict[str, Any],
        query: str = "",
        window_id: int = 0,
        current_context_only: bool = True,
    ) -> Dict[str, Any]:
        active_context = runtime_snapshot.get("active_context") if isinstance(runtime_snapshot, dict) else {}
        if not isinstance(active_context, dict):
            active_context = {}
        active_context_key = str(active_context.get("context_key") or "").strip()
        tracked_windows = [
            dict(item)
            for item in runtime_snapshot.get("tracked_windows", [])
            if isinstance(item, dict) and int(item.get("window_id") or 0) > 0
        ]
        if current_context_only and active_context_key:
            scoped = [
                item for item in tracked_windows
                if str(item.get("context_key") or "").strip() == active_context_key
            ]
            if scoped:
                tracked_windows = scoped

        if window_id > 0:
            for item in tracked_windows:
                if int(item.get("window_id") or 0) == int(window_id):
                    return {
                        "matched": True,
                        "ambiguous": False,
                        "window": item,
                        "candidates": [item],
                    }
            return {
                "matched": False,
                "ambiguous": False,
                "window": None,
                "candidates": [],
            }

        normalized_query = str(query or "").strip()
        if not normalized_query:
            return {
                "matched": False,
                "ambiguous": False,
                "window": None,
                "candidates": [],
            }

        ranked: List[Tuple[float, Dict[str, Any]]] = []
        for item in tracked_windows:
            score = self._window_score(
                query=normalized_query,
                window=item,
                active_context_key=active_context_key,
            )
            if score > 0:
                ranked.append((score, item))
        ranked.sort(key=lambda entry: entry[0], reverse=True)

        if not ranked:
            return {
                "matched": False,
                "ambiguous": False,
                "window": None,
                "candidates": [],
            }

        top_score, top_window = ranked[0]
        candidate_rows = [item for _score, item in ranked[:5]]
        ambiguous = False
        if len(ranked) > 1:
            next_score = ranked[1][0]
            ambiguous = top_score < 250.0 or abs(top_score - next_score) < 55.0
        return {
            "matched": True,
            "ambiguous": ambiguous,
            "window": top_window,
            "candidates": candidate_rows,
        }

    def _app_score(self, query: str, app: RegistryApp) -> float:
        normalized_query = str(query or "").strip().lower()
        if not normalized_query:
            return 0.0
        fields = [
            str(app.name or "").strip().lower(),
            str(app.display_name or "").strip().lower(),
            str(app.expected_class or "").strip().lower(),
            str(app.description or "").strip().lower(),
        ]
        score = 0.0
        for field in fields:
            if not field:
                continue
            if field == normalized_query:
                score = max(score, 700.0)
            elif normalized_query in field:
                score = max(score, 500.0)
            else:
                score = max(score, SequenceMatcher(None, normalized_query, field).ratio() * 140.0)
        return score

    @staticmethod
    def _serialize_registry_app(app: RegistryApp) -> Dict[str, Any]:
        return {
            "name": app.name,
            "display_name": app.display_name,
            "description": app.description,
            "scope": app.scope,
            "terminal": bool(app.terminal),
            "expected_class": app.expected_class,
            "preferred_workspace": app.preferred_workspace,
            "multi_instance": bool(app.multi_instance),
        }

    def resolve_app_target(self, query: str) -> Dict[str, Any]:
        normalized_query = str(query or "").strip()
        if not normalized_query:
            return {"matched": False, "ambiguous": False, "app": None, "candidates": []}

        self._registry_loader.ensure_current()
        apps = self._registry_loader.list_all()
        ranked: List[Tuple[float, RegistryApp]] = []
        for app in apps:
            score = self._app_score(normalized_query, app)
            if score > 0:
                ranked.append((score, app))
        ranked.sort(key=lambda entry: entry[0], reverse=True)

        if not ranked:
            return {"matched": False, "ambiguous": False, "app": None, "candidates": []}

        top_score, top_app = ranked[0]
        candidates = [self._serialize_registry_app(app) for _score, app in ranked[:5]]
        ambiguous = False
        if len(ranked) > 1:
            ambiguous = top_score < 200.0 or abs(top_score - ranked[1][0]) < 45.0
        return {
            "matched": True,
            "ambiguous": ambiguous,
            "app": self._serialize_registry_app(top_app),
            "candidates": candidates,
        }

    def processes(self, limit: int = 8) -> List[Dict[str, Any]]:
        process_limit = max(1, min(int(limit or 8), 20))
        try:
            result = self._run_command(
                ["ps", "-eo", "pid=,pcpu=,pmem=,comm=,args=", "--sort=-pcpu"],
                capture_output=True,
                text=True,
                timeout=2.0,
                check=True,
            )
        except Exception as error:
            logger.debug("assistant.desktop failed to collect processes: %s", error)
            return []

        rows: List[Dict[str, Any]] = []
        for line in result.stdout.splitlines():
            stripped = str(line or "").strip()
            if not stripped:
                continue
            parts = stripped.split(None, 4)
            if len(parts) < 5:
                continue
            try:
                rows.append(
                    {
                        "pid": int(parts[0]),
                        "cpu_percent": float(parts[1]),
                        "memory_percent": float(parts[2]),
                        "command": parts[3],
                        "argv": parts[4],
                    }
                )
            except Exception:
                continue
            if len(rows) >= process_limit:
                break
        return rows

    @staticmethod
    def workspace_summary(
        runtime_snapshot: Dict[str, Any],
        focused_window: Dict[str, Any],
    ) -> Dict[str, Any]:
        outputs = runtime_snapshot.get("outputs", []) if isinstance(runtime_snapshot, dict) else []
        workspace_count = 0
        current_workspace = str(focused_window.get("workspace") or "").strip()
        current_output = str(focused_window.get("output") or "").strip()
        for output in outputs:
            if not isinstance(output, dict):
                continue
            workspaces = output.get("workspaces", []) or []
            workspace_count += len(workspaces)
            if current_output and not current_workspace and str(output.get("name") or "").strip() == current_output:
                for workspace in workspaces:
                    if isinstance(workspace, dict) and bool(workspace.get("focused", False)):
                        current_workspace = str(workspace.get("name") or workspace.get("num") or "").strip()
                        break
            if not current_output and workspaces:
                for workspace in workspaces:
                    if isinstance(workspace, dict) and bool(workspace.get("focused", False)):
                        current_output = str(output.get("name") or "").strip()
                        current_workspace = str(workspace.get("name") or workspace.get("num") or "").strip()
                        break
        return {
            "current_workspace": current_workspace,
            "current_output": current_output,
            "workspace_count": workspace_count,
            "active_outputs": list(runtime_snapshot.get("active_outputs", []) or []),
        }

    def build_snapshot(
        self,
        runtime_snapshot: Dict[str, Any],
        *,
        include_processes: bool = False,
        process_limit: int = 8,
    ) -> Dict[str, Any]:
        active_context = runtime_snapshot.get("active_context") if isinstance(runtime_snapshot, dict) else {}
        if not isinstance(active_context, dict):
            active_context = {}
        active_context_key = str(active_context.get("context_key") or "").strip()
        tracked_windows = [
            dict(item)
            for item in runtime_snapshot.get("tracked_windows", [])
            if isinstance(item, dict)
        ]
        visible_windows = [
            item
            for item in tracked_windows
            if bool(item.get("visible", False))
            and (
                not active_context_key
                or str(item.get("context_key") or "").strip() == active_context_key
            )
        ]
        focused_window_id = int(runtime_snapshot.get("focused_window_id") or 0)
        focused_window = next(
            (
                item for item in tracked_windows
                if int(item.get("window_id") or 0) == focused_window_id
            ),
            {},
        )
        if not focused_window and visible_windows:
            focused_window = visible_windows[0]

        relevant_sessions = []
        for session in runtime_snapshot.get("sessions", []) or []:
            if not isinstance(session, dict):
                continue
            session_context = session.get("context") if isinstance(session.get("context"), dict) else {}
            session_context_key = str(
                session_context.get("context_key")
                or session.get("context_key")
                or ""
            ).strip()
            if active_context_key and session_context_key and session_context_key != active_context_key:
                continue
            relevant_sessions.append(
                {
                    "session_key": str(session.get("session_key") or ""),
                    "title": str(session.get("title") or ""),
                    "preview": str(session.get("preview") or ""),
                    "session_phase": str(session.get("session_phase") or ""),
                    "needs_attention": bool(session.get("needs_attention", False)),
                    "is_current": bool(session.get("is_current", False)),
                }
            )

        processes = self.processes(process_limit) if include_processes else []
        workspace_summary = self.workspace_summary(runtime_snapshot, focused_window)
        runtime_summary = {
            "daemon_health": "ok",
            "desktop_revision": int(self._desktop_revision()),
            "tracked_window_count": len(tracked_windows),
            "visible_window_count": len(visible_windows),
            "workspace_count": int(workspace_summary.get("workspace_count") or 0),
            "active_output_count": len(workspace_summary.get("active_outputs") or []),
            "ai_session_count": len(relevant_sessions),
            "launch_stats": runtime_snapshot.get("launch_stats", {}),
        }

        return {
            "success": True,
            "desktop_revision": int(self._desktop_revision()),
            "active_context": active_context,
            "focused_window": focused_window,
            "visible_windows": visible_windows,
            "visible_window_count": len(visible_windows),
            "workspace": workspace_summary,
            "scratchpad": runtime_snapshot.get("scratchpad", {}),
            "active_terminal": runtime_snapshot.get("active_terminal", {}),
            "sessions": relevant_sessions,
            "current_ai_session_key": str(runtime_snapshot.get("current_ai_session_key") or ""),
            "runtime": runtime_summary,
            "top_processes": processes,
        }

    async def snapshot(self, params: Optional[Dict[str, Any]] = None) -> Dict[str, Any]:
        payload = dict(params or {})
        runtime_snapshot = await self._runtime_snapshot(payload)
        return self.build_snapshot(
            runtime_snapshot,
            include_processes=bool(payload.get("include_processes", False)),
            process_limit=int(payload.get("process_limit") or 8),
        )

    async def resolve_action(
        self,
        params: Dict[str, Any],
        *,
        runtime_snapshot: Dict[str, Any],
    ) -> Dict[str, Any]:
        action_kind = str(params.get("action_kind") or params.get("action") or "").strip().lower()
        if not action_kind:
            raise ValueError("action_kind is required")

        desktop_snapshot = self.build_snapshot(
            runtime_snapshot,
            include_processes=bool(params.get("include_processes", False)),
            process_limit=int(params.get("process_limit") or 8),
        )
        active_context = desktop_snapshot.get("active_context") if isinstance(desktop_snapshot, dict) else {}
        if not isinstance(active_context, dict):
            active_context = {}
        context_key = str(active_context.get("context_key") or "").strip()
        connection_key = str(active_context.get("connection_key") or "").strip()
        target_label = ""
        target_id: Any = ""
        target_type = ""
        result_summary = ""
        resolution: Dict[str, Any] = {}
        risk_level = "low"
        requires_approval = False
        auto_runnable = True
        execution_status = "ready"
        success = True

        if action_kind == "get_desktop_context":
            result_summary = "Desktop context snapshot ready"
            resolution["snapshot"] = desktop_snapshot
        elif action_kind == "list_windows":
            query = str(params.get("query") or "").strip()
            windows = list(desktop_snapshot.get("visible_windows", []) or [])
            if query:
                query_lower = query.lower()
                windows = [
                    item for item in windows
                    if query_lower in self.window_search_text(item)
                ]
            target_type = "window_list"
            target_label = f"{len(windows)} windows"
            result_summary = f"Found {len(windows)} visible windows"
            resolution["windows"] = windows
        elif action_kind == "list_processes":
            processes = self.processes(int(params.get("limit") or params.get("process_limit") or 8))
            target_type = "process_list"
            target_label = f"{len(processes)} processes"
            result_summary = f"Found {len(processes)} running processes"
            resolution["processes"] = processes
        elif action_kind in {"focus_window", "close_window"}:
            resolved = self.resolve_window_target(
                runtime_snapshot=runtime_snapshot,
                query=str(params.get("query") or params.get("target") or "").strip(),
                window_id=int(params.get("window_id") or 0),
                current_context_only=bool(params.get("current_context_only", True)),
            )
            target_type = "window"
            resolution.update(resolved)
            matched_window = resolved.get("window") if isinstance(resolved.get("window"), dict) else None
            if not resolved.get("matched") or matched_window is None:
                success = False
                execution_status = "target_not_found"
                result_summary = "No matching window found"
            elif bool(resolved.get("ambiguous", False)):
                success = False
                execution_status = "needs_disambiguation"
                result_summary = "Window target is ambiguous"
            else:
                target_id = int(matched_window.get("window_id") or 0)
                target_label = str(matched_window.get("title") or matched_window.get("app_name") or f"window {target_id}")
                result_summary = (
                    f"Resolved window '{target_label}'"
                    if action_kind == "focus_window"
                    else f"Ready to close '{target_label}'"
                )
                if action_kind == "close_window":
                    risk_level = "high"
                    requires_approval = True
                    auto_runnable = False
        elif action_kind == "focus_workspace":
            workspace = str(params.get("workspace") or params.get("target") or "").strip()
            if not workspace:
                raise ValueError("workspace is required")
            target_type = "workspace"
            target_id = workspace
            target_label = workspace
            result_summary = f"Ready to focus workspace {workspace}"
        elif action_kind == "switch_context":
            qualified_name = str(params.get("qualified_name") or params.get("project_name") or "").strip()
            if not qualified_name:
                raise ValueError("qualified_name is required")
            target_type = "context"
            target_id = qualified_name
            target_label = qualified_name
            result_summary = f"Ready to switch to {qualified_name}"
            resolution["target_variant"] = str(params.get("target_variant") or "").strip().lower()
        elif action_kind == "toggle_scratchpad":
            target_type = "scratchpad"
            target_label = context_key or str(params.get("context_key") or "").strip() or "active context"
            result_summary = f"Ready to toggle scratchpad for {target_label}"
        elif action_kind == "launch_app":
            query = str(params.get("app_name") or params.get("query") or params.get("target") or "").strip()
            resolved = self.resolve_app_target(query)
            target_type = "application"
            resolution.update(resolved)
            matched_app = resolved.get("app") if isinstance(resolved.get("app"), dict) else None
            if not resolved.get("matched") or matched_app is None:
                success = False
                execution_status = "target_not_found"
                result_summary = "No matching application found"
            elif bool(resolved.get("ambiguous", False)):
                success = False
                execution_status = "needs_disambiguation"
                result_summary = "Application target is ambiguous"
            else:
                target_id = str(matched_app.get("name") or "")
                target_label = str(matched_app.get("display_name") or target_id)
                result_summary = f"Ready to launch {target_label}"
        elif action_kind == "cycle_display_layout":
            target_type = "display_layout"
            target_label = "next display layout"
            result_summary = "Ready to cycle display layout"
            risk_level = "medium"
        else:
            raise ValueError(f"Unsupported assistant desktop action: {action_kind}")

        return {
            "success": success,
            "action_kind": action_kind,
            "target_type": target_type,
            "target_id": target_id,
            "target_label": target_label,
            "risk_level": risk_level,
            "requires_approval": requires_approval,
            "auto_runnable": auto_runnable,
            "context_key": context_key,
            "connection_key": connection_key,
            "execution_status": execution_status,
            "result_summary": result_summary,
            "resolution": resolution,
            "snapshot": desktop_snapshot,
        }

    async def preview(self, params: Optional[Dict[str, Any]] = None) -> Dict[str, Any]:
        payload = dict(params or {})
        runtime_snapshot = await self._runtime_snapshot(payload)
        preview = await self.resolve_action(payload, runtime_snapshot=runtime_snapshot)
        preview["preview"] = True
        return preview

    async def execute(self, params: Optional[Dict[str, Any]] = None) -> Dict[str, Any]:
        payload = dict(params or {})
        runtime_snapshot = await self._runtime_snapshot(payload)
        resolved = await self.resolve_action(payload, runtime_snapshot=runtime_snapshot)
        if not bool(resolved.get("success", False)):
            return resolved

        action_kind = str(resolved.get("action_kind") or "").strip().lower()
        confirm = bool(payload.get("confirm", False))
        if bool(resolved.get("requires_approval", False)) and not confirm:
            resolved["execution_status"] = "approval_required"
            resolved["success"] = False
            resolved["result_summary"] = (
                f"{resolved.get('result_summary')}. Re-run with confirm=true to execute."
            )
            return resolved

        action_result: Dict[str, Any]
        if action_kind == "get_desktop_context":
            action_result = dict(resolved.get("snapshot") or {})
        elif action_kind == "list_windows":
            action_result = {"windows": resolved.get("resolution", {}).get("windows", [])}
        elif action_kind == "list_processes":
            action_result = {"processes": resolved.get("resolution", {}).get("processes", [])}
        elif action_kind == "focus_window":
            window = dict(resolved.get("resolution", {}).get("window") or {})
            action_result = await self._window_focus({
                "window_id": int(window.get("window_id") or 0),
                "project_name": str(window.get("project") or ""),
                "target_variant": str(window.get("execution_mode") or "").strip().lower(),
                "connection_key": str(window.get("connection_key") or ""),
            })
        elif action_kind == "close_window":
            window = dict(resolved.get("resolution", {}).get("window") or {})
            action_result = await self._window_action({
                "window_id": int(window.get("window_id") or 0),
                "action": "kill",
            })
        elif action_kind == "focus_workspace":
            action_result = await self._workspace_focus({
                "workspace": str(resolved.get("target_id") or ""),
            })
        elif action_kind == "switch_context":
            action_result = await self._context_ensure({
                "qualified_name": str(resolved.get("target_id") or ""),
                "target_variant": str(resolved.get("resolution", {}).get("target_variant") or ""),
            })
        elif action_kind == "toggle_scratchpad":
            action_result = await self._scratchpad_toggle({
                "context_key": str(payload.get("context_key") or ""),
                "project_name": str(payload.get("qualified_name") or payload.get("project_name") or ""),
            })
        elif action_kind == "launch_app":
            app = dict(resolved.get("resolution", {}).get("app") or {})
            action_result = await self._launch_open({
                "app_name": str(app.get("name") or ""),
                "qualified_name": str(payload.get("qualified_name") or payload.get("project_name") or ""),
                "target_variant": str(payload.get("target_variant") or "").strip().lower(),
            })
        elif action_kind == "cycle_display_layout":
            action_result = await self._display_cycle({})
        else:
            raise ValueError(f"Unsupported assistant desktop action: {action_kind}")

        after_snapshot = await self.snapshot({
            "include_processes": bool(payload.get("include_processes", False)),
            "process_limit": int(payload.get("process_limit") or 8),
        })
        resolved["success"] = bool(action_result.get("success", True))
        resolved["execution_status"] = "executed" if resolved["success"] else "failed"
        resolved["action_result"] = action_result
        resolved["snapshot_after"] = after_snapshot
        resolved["result_summary"] = str(
            action_result.get("message")
            or action_result.get("status")
            or resolved.get("result_summary")
            or "Action completed"
        )
        return resolved
