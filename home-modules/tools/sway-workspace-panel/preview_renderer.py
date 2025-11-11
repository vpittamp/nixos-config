#!/usr/bin/env python3
"""Workspace preview renderer for Feature 057: User Story 2.

Queries Sway IPC for workspace contents and app icons from application registry.
"""
from __future__ import annotations

from typing import Optional

import i3ipc
from icon_resolver import DesktopIconIndex
from models import WorkspaceApp, WorkspacePreview


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
        """Render workspace preview data.

        Args:
            workspace_num: Target workspace number (1-70)
            monitor_output: Monitor output name (e.g., HEADLESS-1, eDP-1)
            mode: Workspace mode ("goto" or "move")
            sway: Sway IPC connection (creates new if None)

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
