#!/usr/bin/env python3
"""Workspace preview renderer for Feature 057: User Story 2.

Queries Sway IPC for workspace contents and app icons from application registry.

Feature 072: Extended with render_all_windows() for all-windows preview (User Story 1).
"""
from __future__ import annotations

import sys
from typing import Optional, List, Dict, Any

import i3ipc
from icon_resolver import DesktopIconIndex
from models import WorkspaceApp, WorkspacePreview, WindowPreviewEntry, WorkspaceGroup, AllWindowsPreview
from daemon_client import DaemonClient, DaemonIPCError


class PreviewRenderer:
    """Renders workspace preview data for Eww overlay."""

    def __init__(self, app_registry_path: Optional[str] = None, pwa_registry_path: Optional[str] = None):
        """Initialize preview renderer.

        Args:
            app_registry_path: Unused (kept for backwards compatibility)
            pwa_registry_path: Unused (kept for backwards compatibility)
        """
        # Feature 057: Use shared icon resolver
        self._icon_index = DesktopIconIndex()

    def _get_i3pm_app_name(self, pid: Optional[int]) -> Optional[str]:
        """Read I3PM_APP_NAME from process environment.

        Args:
            pid: Process ID

        Returns:
            I3PM_APP_NAME value or None if not found
        """
        if pid is None or pid <= 0:
            return None
        try:
            with open(f"/proc/{pid}/environ", "rb") as f:
                environ_bytes = f.read()
                environ_vars = environ_bytes.split(b'\0')
                for var in environ_vars:
                    if var.startswith(b'I3PM_APP_NAME='):
                        app_name = var.split(b'=', 1)[1].decode('utf-8', errors='ignore')
                        return app_name.strip() if app_name else None
        except (FileNotFoundError, PermissionError, OSError):
            pass
        return None

    def _resolve_icon_and_name(self, app_id: Optional[str], pid: Optional[int]) -> tuple[str, str]:
        """Resolve icon path and display name from I3PM_APP_NAME or app_id.

        Args:
            app_id: Wayland app_id (fallback)
            pid: Process ID (to read I3PM_APP_NAME)

        Returns:
            Tuple of (icon_path, display_name)
        """
        # First, try to get I3PM_APP_NAME from environment (most accurate)
        i3pm_app_name = self._get_i3pm_app_name(pid)
        lookup_key = i3pm_app_name or app_id

        if lookup_key:
            # Use shared icon index for lookup
            result = self._icon_index.lookup(app_id=lookup_key)
            if result:
                return (result.get("icon", ""), result.get("name", lookup_key))

        # Fallback: return app_id/I3PM_APP_NAME as-is
        return ("", lookup_key or "Unknown")

    def render_workspace_preview(
        self,
        workspace_num: int,
        monitor_output: str,
        mode: str = "goto",
        sway: Optional[i3ipc.Connection] = None,
    ) -> WorkspacePreview:
        """Render workspace preview data using daemon IPC.

        Feature 072: T033 - Updated to use daemon IPC query instead of direct Sway IPC
        for consistency with US1 architecture and improved performance.

        Args:
            workspace_num: Target workspace number (1-70)
            monitor_output: Monitor output name (e.g., HEADLESS-1, eDP-1)
            mode: Workspace mode ("goto" or "move")
            sway: Sway IPC connection (DEPRECATED - kept for backwards compatibility but not used)

        Returns:
            WorkspacePreview object with workspace contents
        """
        # Validate workspace number
        if workspace_num < 1 or workspace_num > 70:
            return WorkspacePreview(
                workspace_num=1,  # Pydantic requires valid value
                monitor_output=monitor_output,
                apps=[],
                window_count=0,
                visible=False,
                focused=False,
                urgent=False,
                empty=True,
                mode=mode,
            )

        try:
            # Feature 072: T033 - Use daemon IPC for workspace query (same as US1)
            # Performance: ~2-5ms vs ~15-30ms for direct Sway IPC GET_TREE
            daemon_client = DaemonClient()
            daemon_outputs = daemon_client.get_windows()

            # Filter daemon Output[] to find target workspace
            target_workspace_group = None
            for output in daemon_outputs:
                output_workspaces = output.get("workspaces", [])
                for ws in output_workspaces:
                    if ws.get("num") == workspace_num:
                        # Found target workspace - extract window info
                        windows = ws.get("windows", [])
                        window_entries: List[WindowPreviewEntry] = []

                        for win in windows:
                            app_id = win.get("app_id")
                            pid = win.get("pid")
                            title = win.get("name", "")
                            focused = win.get("focused", False)

                            # Resolve icon and display name (same logic as render_all_windows)
                            icon_path, display_name = self._resolve_icon_and_name(app_id, pid)

                            # Create WindowPreviewEntry
                            entry = WindowPreviewEntry(
                                name=display_name or title or "Unknown",
                                icon_path=icon_path,
                                app_id=app_id,
                                window_class=None,  # Not available from daemon
                                focused=focused,
                                workspace_num=workspace_num,
                            )
                            window_entries.append(entry)

                        # Convert WindowPreviewEntry list to WorkspaceApp list
                        apps: List[WorkspaceApp] = []
                        for entry in window_entries:
                            app = WorkspaceApp(
                                name=entry.name,
                                title=title,  # Use window title
                                app_id=entry.app_id,
                                window_class=None,
                                icon=entry.icon_path,
                                focused=entry.focused,
                                floating=False,  # Not available from daemon Output[]
                            )
                            apps.append(app)

                        # Build WorkspacePreview from filtered workspace
                        return WorkspacePreview(
                            workspace_num=workspace_num,
                            workspace_name=ws.get("name") if ws.get("name") != str(workspace_num) else None,
                            monitor_output=output.get("name", monitor_output),
                            apps=apps,
                            window_count=len(windows),
                            visible=ws.get("visible", False),
                            focused=ws.get("focused", False),
                            urgent=False,  # Not available from daemon Output[]
                            empty=len(windows) == 0,
                            mode=mode,
                        )

            # Workspace not found in daemon output - it's empty
            return WorkspacePreview(
                workspace_num=workspace_num,
                workspace_name=None,
                monitor_output=monitor_output,
                apps=[],
                window_count=0,
                visible=False,
                focused=False,
                urgent=False,
                empty=True,
                mode=mode,
            )

        except DaemonIPCError as e:
            # T033: Fallback to direct Sway IPC if daemon query fails
            # This maintains backwards compatibility but logs warning
            print(f"Warning: Daemon IPC query failed, falling back to direct Sway IPC: {e}", file=sys.stderr)
            # Fall through to legacy implementation below
            pass

        # Legacy implementation - direct Sway IPC (fallback only)
        # Connect to Sway IPC
        if sway is None:
            sway = i3ipc.Connection()

        # Query workspace state
        workspaces = sway.get_workspaces()
        target_ws = next((ws for ws in workspaces if ws.num == workspace_num), None)

        if target_ws is None:
            # Workspace doesn't exist yet - it's empty
            return WorkspacePreview(
                workspace_num=workspace_num,
                workspace_name=None,
                monitor_output=monitor_output,
                apps=[],
                window_count=0,
                visible=False,
                focused=False,
                urgent=False,
                empty=True,
                mode=mode,
            )

        # Query workspace tree for windows
        tree = sway.get_tree()
        # Find workspace node by number - iterate through all nodes to find matching workspace
        ws_node = None
        for node in tree:
            if node.type == "workspace" and node.num == workspace_num:
                ws_node = node
                break

        if ws_node is None:
            # Shouldn't happen, but handle gracefully
            return WorkspacePreview(
                workspace_num=workspace_num,
                workspace_name=target_ws.name if target_ws.name != str(workspace_num) else None,
                monitor_output=target_ws.output,
                apps=[],
                window_count=0,
                visible=target_ws.visible,
                focused=target_ws.focused,
                urgent=target_ws.urgent,
                empty=True,
                mode=mode,
            )

        # Extract windows (leaves with app_id or window_class)
        windows = ws_node.leaves()
        apps: List[WorkspaceApp] = []

        for win in windows:
            # Get window properties
            app_id = win.app_id
            pid = win.pid
            title = win.name or ""
            focused = win.focused
            floating = win.floating != "auto_off"

            # Resolve icon and name using I3PM_APP_NAME from /proc/<pid>/environ
            icon_path, name = self._resolve_icon_and_name(app_id, pid)

            # Create WorkspaceApp
            app = WorkspaceApp(
                name=name,
                title=title,
                app_id=app_id,
                window_class=None,  # Not needed for Wayland
                icon=icon_path,
                focused=focused,
                floating=floating,
            )
            apps.append(app)

        # Build WorkspacePreview
        return WorkspacePreview(
            workspace_num=workspace_num,
            workspace_name=target_ws.name if target_ws.name != str(workspace_num) else None,
            monitor_output=target_ws.output,
            apps=apps,
            window_count=len(windows),
            visible=target_ws.visible,
            focused=target_ws.focused,
            urgent=target_ws.urgent,
            empty=len(windows) == 0,
            mode=mode,
        )

    def _convert_daemon_output_to_groups(self, daemon_outputs: List[Dict[str, Any]]) -> List[WorkspaceGroup]:
        """Convert daemon IPC Output[] structure to List[WorkspaceGroup].

        Feature 072: T011 - Helper for render_all_windows() to convert daemon response
        to WorkspaceGroup Pydantic models.

        Args:
            daemon_outputs: Output[] array from daemon get_windows IPC call
                [
                    {
                        "name": "HEADLESS-1",
                        "workspaces": [
                            {
                                "num": 1,
                                "name": "1",
                                "visible": true,
                                "focused": true,
                                "windows": [
                                    {
                                        "name": "Alacritty",
                                        "app_id": "Alacritty",
                                        "pid": 12345,
                                        "focused": true
                                    }
                                ]
                            }
                        ]
                    }
                ]

        Returns:
            List[WorkspaceGroup] sorted by workspace number, with resolved icons
        """
        groups: List[WorkspaceGroup] = []

        # Iterate through all outputs
        for output in daemon_outputs:
            output_name = output.get("name", "UNKNOWN")
            workspaces = output.get("workspaces", [])

            # Iterate through workspaces on this output
            for ws in workspaces:
                ws_num = ws.get("num")
                ws_name = ws.get("name")
                windows = ws.get("windows", [])

                # Skip invalid workspace numbers
                if ws_num is None or ws_num < 1 or ws_num > 70:
                    continue

                # Skip empty workspaces (no windows)
                if not windows:
                    continue

                # Convert windows to WindowPreviewEntry models
                window_entries: List[WindowPreviewEntry] = []
                for win in windows:
                    app_id = win.get("app_id")
                    pid = win.get("pid")
                    title = win.get("name", "")
                    focused = win.get("focused", False)

                    # Resolve icon and display name (same logic as render_workspace_preview)
                    icon_path, display_name = self._resolve_icon_and_name(app_id, pid)

                    # Create WindowPreviewEntry
                    entry = WindowPreviewEntry(
                        name=display_name or title or "Unknown",
                        icon_path=icon_path,
                        app_id=app_id,
                        window_class=None,  # Not available from daemon (Wayland only)
                        focused=focused,
                        workspace_num=ws_num,
                    )
                    window_entries.append(entry)

                # Create WorkspaceGroup
                group = WorkspaceGroup(
                    workspace_num=ws_num,
                    workspace_name=ws_name if ws_name != str(ws_num) else None,
                    window_count=len(window_entries),
                    windows=window_entries,
                    monitor_output=output_name,
                )
                groups.append(group)

        # Sort by workspace number (ascending)
        groups.sort(key=lambda g: g.workspace_num)

        return groups

    def render_all_windows(self) -> AllWindowsPreview:
        """Render all-windows preview showing ALL windows grouped by workspace.

        Feature 072: T015 - User Story 1 (P1 MVP) implementation.

        Queries daemon IPC for all workspace windows and converts to AllWindowsPreview model.
        Shows all windows across all workspaces when user enters workspace mode (CapsLock/Ctrl+0).

        Performance target: <150ms total (50ms daemon query + 50ms construction + 50ms Eww render)

        Returns:
            AllWindowsPreview model with workspace_groups, counts, and state flags

        Raises:
            DaemonIPCError: If daemon query fails (fallback to empty state)
        """
        try:
            # Query daemon for all workspace windows (T010)
            # Performance: ~2-5ms vs ~15-30ms for direct Sway IPC GET_TREE
            daemon_client = DaemonClient()
            daemon_outputs = daemon_client.get_windows()

            # Convert daemon Output[] to WorkspaceGroup[] (T011)
            workspace_groups = self._convert_daemon_output_to_groups(daemon_outputs)

            # Calculate totals
            total_window_count = sum(group.window_count for group in workspace_groups)
            total_workspace_count = len(workspace_groups)

            # Determine state flags
            empty = total_window_count == 0
            instructional = False  # Not instructional when we have data

            # Apply workspace group limit (T018): max 20 initial groups
            # (remaining groups accessible via filtering by typing digits)
            MAX_INITIAL_GROUPS = 20
            if len(workspace_groups) > MAX_INITIAL_GROUPS:
                workspace_groups = workspace_groups[:MAX_INITIAL_GROUPS]
                # Note: Eww widget will show "... and N more workspaces" footer

            # Build AllWindowsPreview model (T006)
            preview = AllWindowsPreview(
                visible=True,
                type="all_windows",
                workspace_groups=workspace_groups,
                total_window_count=total_window_count,
                total_workspace_count=total_workspace_count,
                instructional=instructional,
                empty=empty,
            )

            return preview

        except DaemonIPCError as e:
            # T019: Error handling - daemon IPC failure, fallback to empty state
            print(f"Warning: Daemon IPC query failed: {e}", file=sys.stderr)
            return AllWindowsPreview(
                visible=True,
                type="all_windows",
                workspace_groups=[],
                total_window_count=0,
                total_workspace_count=0,
                instructional=False,
                empty=True,
            )
        except Exception as e:
            # T019: Unexpected errors - fallback to empty state
            print(f"Warning: Unexpected error in render_all_windows(): {e}", file=sys.stderr)
            return AllWindowsPreview(
                visible=True,
                type="all_windows",
                workspace_groups=[],
                total_window_count=0,
                total_workspace_count=0,
                instructional=False,
                empty=True,
            )
