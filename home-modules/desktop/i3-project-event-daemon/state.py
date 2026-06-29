"""State manager for i3 project event daemon.

Manages in-memory daemon state with async-safe operations.
"""

import asyncio
import logging
from typing import Dict, List, Optional
from i3ipc import aio

from .models import DaemonState, WindowInfo, WorkspaceInfo
from .services.launch_registry import LaunchRegistry  # Feature 041: IPC Launch Context - T013
from .services.focus_tracker import FocusTracker  # Feature 074: Session Management - T021
from .services.window_filter import parse_window_environment, read_process_environ
from .worktree_utils import (
    canonicalize_context_key,
    extract_project_from_mark,
    target_host_from_connection_key,
)  # Feature 101
from pathlib import Path

logger = logging.getLogger(__name__)


def _normalize_window_runtime(window_info: WindowInfo) -> None:
    """Keep tracked window binding state and durable workspace/output in sync."""
    window_info.connection_key = str(getattr(window_info, "connection_key", "") or "").strip()
    window_info.context_key = canonicalize_context_key(
        getattr(window_info, "context_key", ""),
        project_name=getattr(window_info, "project", ""),
        connection_key=window_info.connection_key,
    )
    if window_info.context_key and not window_info.project:
        window_info.project = window_info.context_key.split("::host::", 1)[0].strip()
    normalized_marks: list[str] = []
    for mark in list(getattr(window_info, "marks", []) or []):
        raw_mark = str(mark or "").strip()
        if raw_mark.startswith("ctx:"):
            canonical_context_mark = canonicalize_context_key(
                raw_mark.split("ctx:", 1)[1],
                project_name=getattr(window_info, "project", ""),
                connection_key=window_info.connection_key,
            )
            if canonical_context_mark:
                raw_mark = f"ctx:{canonical_context_mark}"
        if raw_mark and raw_mark not in normalized_marks:
            normalized_marks.append(raw_mark)
    window_info.marks = normalized_marks

    state = str(getattr(window_info, "binding_state", "") or "").strip()
    if state not in {"bound_workspace", "scratchpad_hidden", "transient_unbound"}:
        state = "bound_workspace" if getattr(window_info, "workspace", "") else "transient_unbound"
        window_info.binding_state = state

    workspace = str(getattr(window_info, "workspace", "") or "").strip()
    output = str(getattr(window_info, "output", "") or "").strip()

    if state == "bound_workspace":
        if workspace:
            window_info.last_workspace = workspace
        if output:
            window_info.last_output = output
        window_info.last_visible = True
    elif state == "scratchpad_hidden":
        if workspace and workspace.lower() != "scratchpad":
            window_info.last_workspace = workspace
        if output:
            window_info.last_output = output
        if not workspace:
            window_info.workspace = "scratchpad"
        window_info.last_visible = False
    else:
        if workspace:
            window_info.last_workspace = workspace
        elif getattr(window_info, "last_workspace", ""):
            window_info.workspace = window_info.last_workspace
        if output:
            window_info.last_output = output
        elif getattr(window_info, "last_output", ""):
            window_info.output = window_info.last_output
        window_info.last_visible = True


class StateManager:
    """Manages runtime state for the daemon with async-safe operations."""

    def __init__(self) -> None:
        """Initialize state manager with empty state."""
        self.state = DaemonState()
        self._lock = asyncio.Lock()

        # Feature 041: IPC Launch Context - T013
        # Launch registry for correlating windows to launch notifications
        self.launch_registry = LaunchRegistry(timeout=5.0)
        logger.info("Initialized LaunchRegistry with 5-second timeout")

        # Feature 074: Session Management - T021
        # Focus tracker for workspace and window focus restoration
        config_dir = Path.home() / ".config" / "i3"
        config_dir.mkdir(parents=True, exist_ok=True)
        self.focus_tracker = FocusTracker(self, config_dir)
        logger.info("Initialized FocusTracker for session management")

        # Feature 074: Session Management - T099 (US5)
        # Auto-save manager for automatic layout capture
        # Note: Will be initialized when i3 connection is available
        self.auto_save_manager = None
        self.auto_restore_manager = None

    async def add_window(self, window_info: WindowInfo) -> None:
        """Add a window to the tracking map.

        Args:
            window_info: WindowInfo object to add
        """
        async with self._lock:
            _normalize_window_runtime(window_info)
            self.state.window_map[window_info.window_id] = window_info
            logger.debug(
                f"Added window {window_info.window_id} "
                f"(class={window_info.window_class}, project={window_info.project})"
            )

    async def remove_window(self, window_id: int) -> None:
        """Remove a window from the tracking map.

        Args:
            window_id: ID of window to remove
        """
        async with self._lock:
            if window_id in self.state.window_map:
                window_info = self.state.window_map.pop(window_id)
                logger.debug(
                    f"Removed window {window_id} "
                    f"(class={window_info.window_class}, project={window_info.project})"
                )
            else:
                logger.warning(f"Attempted to remove non-existent window {window_id}")

    async def update_window(self, window_id: int, **kwargs) -> None:
        """Update window properties.

        Args:
            window_id: ID of window to update
            **kwargs: Properties to update (project, workspace, marks, etc.)
        """
        async with self._lock:
            if window_id not in self.state.window_map:
                logger.warning(f"Attempted to update non-existent window {window_id}")
                return

            window_info = self.state.window_map[window_id]
            normalized_updates = dict(kwargs)
            if "title" in normalized_updates and "window_title" not in normalized_updates:
                normalized_updates["window_title"] = normalized_updates.pop("title")

            # Update allowed fields
            for key, value in normalized_updates.items():
                if hasattr(window_info, key):
                    setattr(window_info, key, value)
                    logger.debug(f"Updated window {window_id}: {key}={value}")
                else:
                    logger.warning(f"Unknown window property: {key}")
            _normalize_window_runtime(window_info)

    async def get_window(self, window_id: int) -> Optional[WindowInfo]:
        """Get window by ID.

        Args:
            window_id: ID of window to retrieve

        Returns:
            WindowInfo object or None if not found
        """
        async with self._lock:
            return self.state.window_map.get(window_id)

    async def get_windows_by_project(self, project: str) -> List[WindowInfo]:
        """Get all windows belonging to a specific project.

        Args:
            project: Project name to filter by

        Returns:
            List of WindowInfo objects for the project
        """
        async with self._lock:
            return [
                window_info
                for window_info in self.state.window_map.values()
                if window_info.project == project
            ]

    async def set_active_project(self, project: Optional[str]) -> None:
        """Update the active project.

        Args:
            project: Project name to activate, or None for global mode
        """
        async with self._lock:
            old_project = self.state.active_project
            self.state.active_project = project
            logger.info(f"Active project changed: {old_project} → {project}")

    async def get_active_project(self) -> Optional[str]:
        """Get the currently active project.

        Returns:
            Active project name or None if in global mode
        """
        async with self._lock:
            return self.state.active_project

    async def add_workspace(self, workspace_info: WorkspaceInfo) -> None:
        """Add or update a workspace in the tracking map.

        Args:
            workspace_info: WorkspaceInfo object to add
        """
        async with self._lock:
            self.state.workspace_map[workspace_info.name] = workspace_info
            logger.debug(f"Added workspace {workspace_info.name} on output {workspace_info.output}")

    async def remove_workspace(self, name: str) -> None:
        """Remove a workspace from the tracking map.

        Args:
            name: Workspace name to remove
        """
        async with self._lock:
            if name in self.state.workspace_map:
                self.state.workspace_map.pop(name)
                logger.debug(f"Removed workspace {name}")
            else:
                logger.warning(f"Attempted to remove non-existent workspace {name}")

    # Fields the live tree is authoritative for and that reconcile may refresh on
    # an existing entry. Everything else (project/scope/correlation_*/terminal_*/
    # execution/connection/context/created/last_focus) is daemon-managed and is
    # NEVER clobbered by reconcile — only set when a window is first ADDED.
    _RECONCILE_TREE_FIELDS = ("workspace", "output", "is_floating", "marks", "window_title")

    def _window_info_from_marked_container(self, container: aio.Con) -> Optional["WindowInfo"]:
        """Build a WindowInfo from a marked tree container, or None if unbuildable.

        No locking and no window_map mutation — pure construction (may read
        /proc/<pid>/environ). Shared by rebuild_from_marks and reconcile_from_tree
        so both produce identical entries. Caller must have already confirmed the
        container carries a scoped:/global: mark.
        """
        try:
            project_marks = [
                mark for mark in container.marks if mark.startswith("scoped:") or mark.startswith("global:")
            ]
            if not (project_marks and container.id):
                return None
            tracked_window_id = int(container.id)

            # Feature 045 parity: native Wayland windows only expose app_id/con_id.
            window_class = (
                getattr(container, "app_id", None)
                or getattr(container, "window_class", None)
                or "unknown"
            )

            window_env = None
            pid = getattr(container, "pid", None)
            if pid:
                try:
                    window_env = parse_window_environment(read_process_environ(int(pid)))
                except (PermissionError, FileNotFoundError, ProcessLookupError, ValueError):
                    window_env = None

            # Feature 101: Use centralized mark parser against the tracked con_id.
            project_name = extract_project_from_mark(
                project_marks[0], tracked_window_id
            )
            raw_context_key = next(
                (
                    str(mark).split("ctx:", 1)[1]
                    for mark in container.marks
                    if str(mark).startswith("ctx:")
                ),
                "",
            )
            context_key = canonicalize_context_key(
                raw_context_key,
                project_name=project_name,
            )
            parsed_connection_key = str(window_env.connection_key or "").strip() if window_env else ""
            parsed_execution_mode = ""
            if parsed_connection_key:
                parsed_execution_mode = (
                    "local"
                    if parsed_connection_key.startswith("local@")
                    else "ssh"
                )
            if not parsed_execution_mode and "i3pm_exec:ssh" in container.marks:
                parsed_execution_mode = "ssh"
            parsed_target_host = target_host_from_connection_key(parsed_connection_key)

            from datetime import datetime

            workspace = container.workspace()
            window_info = WindowInfo(
                window_id=tracked_window_id,
                con_id=container.id,
                window_class=window_class,
                window_title=container.name or "",
                window_instance=container.window_instance or "",
                app_identifier=(
                    window_env.app_name
                    if window_env and window_env.app_name
                    else window_class
                ),
                project=project_name,
                marks=list(container.marks),
                scope=(
                    window_env.scope
                    if window_env and window_env.scope in {"scoped", "global"}
                    else ("global" if project_name == "global" else ("scoped" if project_name else "global"))
                ),
                workspace=workspace.name if workspace else "",
                output=(
                    workspace.ipc_data.get("output", "")
                    if workspace and getattr(workspace, "ipc_data", None)
                    else ""
                ),
                is_floating=container.floating == "user_on",
                created=datetime.now(),
                terminal_anchor_id=(
                    window_env.terminal_anchor_id
                    if window_env and window_env.terminal_anchor_id
                    else None
                ),
                terminal_role=(
                    str(window_env.terminal_role or "")
                    if window_env and str(window_env.terminal_role or "").strip()
                    else ""
                ),
                tmux_session_name=(
                    str(window_env.tmux_session_name or "")
                    if window_env and str(window_env.tmux_session_name or "").strip()
                    else ""
                ),
                execution_mode=(
                    parsed_execution_mode
                    or (
                        "ssh"
                        if window_env and str(window_env.connection_key or "").strip() and not str(window_env.connection_key or "").startswith("local@")
                        else "local"
                    )
                ),
                connection_key=(
                    str(window_env.connection_key or "")
                    if window_env and str(window_env.connection_key or "").strip()
                    else parsed_connection_key
                ),
                context_key=(
                    str(window_env.context_key or "")
                    if window_env and str(window_env.context_key or "").strip()
                    else context_key
                ),
                remote_enabled=bool(
                    (window_env and str(window_env.connection_key or "").strip() and not str(window_env.connection_key or "").startswith("local@"))
                    or parsed_execution_mode == "ssh"
                    or bool(parsed_target_host and parsed_execution_mode == "ssh")
                ),
            )
            _normalize_window_runtime(window_info)
            return window_info
        except Exception as exc:
            logger.warning(
                "Failed to build WindowInfo from marked container %s: %s",
                getattr(container, "id", "?"), exc,
            )
            return None

    def _scan_marked_into_map(self, tree: aio.Con, *, allow_subtract: bool) -> Dict[str, int]:
        """Walk the tree and reconcile window_map against marked windows.

        Caller MUST hold self._lock. ADDs marked windows missing from the map,
        refreshes only _RECONCILE_TREE_FIELDS on existing entries (never clobbering
        daemon-managed metadata), and — only when allow_subtract — removes tracked
        entries no longer present anywhere in the tree. Returns counts.
        """
        seen: set = set()
        added = 0
        updated = 0
        removed = 0

        def scan(container: aio.Con) -> None:
            nonlocal added, updated
            project_marks = [
                mark for mark in container.marks if mark.startswith("scoped:") or mark.startswith("global:")
            ]
            if project_marks and container.id:
                cid = int(container.id)
                seen.add(cid)
                existing = self.state.window_map.get(cid)
                if existing is None:
                    info = self._window_info_from_marked_container(container)
                    if info is not None:
                        self.state.window_map[cid] = info
                        added += 1
                else:
                    workspace = container.workspace()
                    existing.workspace = workspace.name if workspace else existing.workspace
                    existing.output = (
                        workspace.ipc_data.get("output", "")
                        if workspace and getattr(workspace, "ipc_data", None)
                        else existing.output
                    )
                    existing.is_floating = container.floating == "user_on"
                    existing.marks = list(container.marks)
                    if container.name:
                        existing.window_title = container.name
                    updated += 1
            for child in container.nodes + container.floating_nodes:
                scan(child)

        scan(tree)

        if allow_subtract:
            for cid in [c for c in self.state.window_map.keys() if c not in seen]:
                self.state.window_map.pop(cid, None)
                removed += 1

        return {"added": added, "updated": updated, "removed": removed, "seen": len(seen)}

    async def rebuild_from_marks(self, tree: aio.Con) -> None:
        """Rebuild window_map from i3 tree by scanning for project marks.

        Used during daemon startup/reconnection to restore state from marks:
        clear then re-add every marked window.

        Args:
            tree: Root container from i3 GET_TREE (async)
        """
        async with self._lock:
            self.state.window_map.clear()
            stats = self._scan_marked_into_map(tree, allow_subtract=False)
        logger.info(f"Rebuilt state: found {stats['added']} windows with project marks")

    async def reconcile_from_tree(self, tree: aio.Con, *, allow_subtract: bool = False) -> Dict[str, int]:
        """Non-destructive reconcile of window_map against the live tree.

        ADDs marked windows missing from the map (self-heals a window dropped by a
        missed/misfired event or whose window::new was lost — without waiting for a
        daemon restart) and refreshes tree-authoritative fields on existing entries.
        It does NOT clear the map and NOT clobber daemon-managed metadata. Removal
        is gated behind allow_subtract (default off) and intended to be enabled only
        after a drift gauge proves it safe; even then the caller must pass the FULL
        raw tree (never the active-output-filtered view).
        """
        async with self._lock:
            stats = self._scan_marked_into_map(tree, allow_subtract=allow_subtract)
        if stats["added"] or stats["removed"]:
            logger.info(
                "reconcile_from_tree: +%d added, ~%d refreshed, -%d removed (%d marked in tree)",
                stats["added"], stats["updated"], stats["removed"], stats["seen"],
            )
        return stats

    async def increment_event_count(self) -> None:
        """Increment the total event counter."""
        async with self._lock:
            self.state.event_count += 1

    async def increment_error_count(self) -> None:
        """Increment the error counter."""
        async with self._lock:
            self.state.error_count += 1

    async def get_stats(self) -> Dict:
        """Get daemon statistics.

        Returns:
            Dictionary with event counts, window counts, etc.
        """
        async with self._lock:
            from datetime import datetime
            uptime = (datetime.now() - self.state.start_time).total_seconds()

            return {
                "event_count": self.state.event_count,
                "error_count": self.state.error_count,
                "window_count": len(self.state.window_map),
                "workspace_count": len(self.state.workspace_map),
                "active_project": self.state.active_project,
                "uptime_seconds": uptime,
            }

    async def get_window_map_snapshot(self) -> Dict[int, WindowInfo]:
        """Return a shallow copy of the tracked window map."""
        async with self._lock:
            return dict(self.state.window_map)

    async def update_app_classification(self, classification: "ApplicationClassification") -> None:
        """Update application classification (scoped/global classes).

        This method is called when reloading configuration via tick event (T030).

        Args:
            classification: New ApplicationClassification object with scoped/global sets
        """
        async with self._lock:
            old_scoped_count = len(self.state.scoped_classes)
            old_global_count = len(self.state.global_classes)

            self.state.scoped_classes = classification.scoped_classes
            self.state.global_classes = classification.global_classes

            logger.info(
                f"Updated app classification: "
                f"scoped {old_scoped_count}→{len(classification.scoped_classes)}, "
                f"global {old_global_count}→{len(classification.global_classes)}"
            )

    async def load_focus_state(self) -> None:
        """Load focus state from disk on daemon startup (Feature 074: T025, US1).

        Loads previously persisted workspace and window focus state to restore
        session management context across daemon restarts.
        """
        if hasattr(self, 'focus_tracker') and self.focus_tracker:
            try:
                await self.focus_tracker.load_focus_state()
                logger.info("Successfully loaded focus state from disk")
            except Exception as e:
                logger.warning(f"Failed to load focus state: {e}")
                # Non-fatal error - daemon can continue without persisted focus state
        else:
            logger.debug("FocusTracker not initialized, skipping focus state load")
