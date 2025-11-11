#!/usr/bin/env python3
"""Workspace preview renderer for Feature 057: User Story 2.

Queries Sway IPC for workspace contents and app icons from application registry.
"""
from __future__ import annotations

import json
from pathlib import Path
from typing import Dict, List, Optional

import i3ipc
from models import WorkspaceApp, WorkspacePreview
from xdg.IconTheme import getIconPath

# Icon search directories for manual fallback
ICON_SEARCH_DIRS = [
    Path.home() / ".local/share/icons",
    Path.home() / ".icons",
    Path("/usr/share/icons"),
    Path("/usr/share/pixmaps"),
]
ICON_EXTENSIONS = (".svg", ".png", ".xpm")


class PreviewRenderer:
    """Renders workspace preview data for Eww overlay."""

    def __init__(self, app_registry_path: Optional[Path] = None, pwa_registry_path: Optional[Path] = None):
        """Initialize preview renderer.

        Args:
            app_registry_path: Path to application-registry.json (default: ~/.config/i3/application-registry.json)
            pwa_registry_path: Path to pwa-registry.json (default: ~/.config/i3/pwa-registry.json)
        """
        self.app_registry_path = app_registry_path or Path.home() / ".config/i3/application-registry.json"
        self.pwa_registry_path = pwa_registry_path or Path.home() / ".config/i3/pwa-registry.json"
        self._app_icon_map: Dict[str, str] = {}
        self._app_name_map: Dict[str, str] = {}
        self._icon_cache: Dict[str, str] = {}  # Cache resolved icon paths
        self._load_registries()

    def _load_registries(self) -> None:
        """Load app and PWA registries for icon resolution."""
        # Load application registry
        if self.app_registry_path.exists():
            try:
                with open(self.app_registry_path) as f:
                    data = json.load(f)
                    for app in data.get("applications", []):
                        name = app.get("name", "").lower()
                        display_name = app.get("display_name", app.get("name", ""))
                        icon = app.get("icon", "")
                        if name:
                            self._app_icon_map[name] = icon
                            self._app_name_map[name] = display_name
                        # Also index by expected_class for window matching
                        expected_class = app.get("expected_class", "").lower()
                        if expected_class:
                            self._app_icon_map[expected_class] = icon
                            self._app_name_map[expected_class] = display_name
            except Exception as e:
                print(f"Warning: Failed to load application registry: {e}")

        # Load PWA registry
        if self.pwa_registry_path.exists():
            try:
                with open(self.pwa_registry_path) as f:
                    data = json.load(f)
                    for pwa in data.get("pwas", []):
                        ulid = pwa.get("ulid", "")
                        name = pwa.get("name", "")
                        icon = pwa.get("icon", "")
                        # PWAs use app_id pattern: "FFPWA-{ULID}"
                        pwa_id = f"ffpwa-{ulid}".lower()
                        if pwa_id:
                            self._app_icon_map[pwa_id] = icon
                            self._app_name_map[pwa_id] = name
            except Exception as e:
                print(f"Warning: Failed to load PWA registry: {e}")

    def _resolve_icon_name_to_path(self, icon_name: Optional[str]) -> Optional[str]:
        """Resolve icon name to full file path.

        Args:
            icon_name: Icon name or path (e.g., "com.mitchellh.ghostty" or "/path/to/icon.svg")

        Returns:
            Full path to icon file or None if not found
        """
        if not icon_name:
            return None

        # Check cache first
        cache_key = icon_name.lower()
        if cache_key in self._icon_cache:
            cached = self._icon_cache[cache_key]
            return cached or None

        # If it's already an absolute path, verify it exists
        candidate = Path(icon_name)
        if candidate.is_absolute() and candidate.exists():
            resolved = str(candidate)
            self._icon_cache[cache_key] = resolved
            return resolved

        # Try XDG icon theme lookup (resolves names like "com.mitchellh.ghostty")
        themed = getIconPath(icon_name, 48)
        if themed:
            resolved = str(Path(themed))
            self._icon_cache[cache_key] = resolved
            return resolved

        # Manual search through icon directories as fallback
        for directory in ICON_SEARCH_DIRS:
            if not directory.exists():
                continue
            for ext in ICON_EXTENSIONS:
                probe = directory / f"{icon_name}{ext}"
                if probe.exists():
                    resolved = str(probe)
                    self._icon_cache[cache_key] = resolved
                    return resolved

        # Not found - cache empty string to avoid repeated lookups
        self._icon_cache[cache_key] = ""
        return None

    def _resolve_icon(self, app_id: Optional[str], pid: Optional[int]) -> str:
        """Resolve icon path from I3PM_APP_NAME or app_id.

        Args:
            app_id: Wayland app_id (fallback)
            pid: Process ID (to read I3PM_APP_NAME)

        Returns:
            Icon path or empty string if not found
        """
        # First, try to get I3PM_APP_NAME from environment (most accurate)
        i3pm_app_name = self._get_i3pm_app_name(pid)
        if i3pm_app_name:
            # Look up icon by I3PM app name
            key = i3pm_app_name.lower()
            if key in self._app_icon_map:
                icon_name = self._app_icon_map[key]
                # Resolve icon name to full path
                resolved = self._resolve_icon_name_to_path(icon_name)
                return resolved or ""

        # Fallback: try app_id lookup
        if app_id:
            key = app_id.lower()
            if key in self._app_icon_map:
                icon_name = self._app_icon_map[key]
                # Resolve icon name to full path
                resolved = self._resolve_icon_name_to_path(icon_name)
                return resolved or ""

        # No match - return empty string (Eww will use default)
        return ""

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

    def _resolve_name(self, app_id: Optional[str], pid: Optional[int]) -> str:
        """Resolve display name from I3PM_APP_NAME or app_id.

        Args:
            app_id: Wayland app_id (fallback)
            pid: Process ID (to read I3PM_APP_NAME)

        Returns:
            Display name for the application
        """
        # First, try to get I3PM_APP_NAME from environment (most accurate)
        i3pm_app_name = self._get_i3pm_app_name(pid)
        if i3pm_app_name:
            # Look up display name by I3PM app name
            key = i3pm_app_name.lower()
            if key in self._app_name_map:
                return self._app_name_map[key]
            # Return the I3PM_APP_NAME as-is if not in registry
            return i3pm_app_name

        # Fallback: try app_id lookup
        if app_id:
            key = app_id.lower()
            if key in self._app_name_map:
                return self._app_name_map[key]
            # Use app_id as-is if no registry match
            return app_id

        # Last resort
        return "Unknown"

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
            icon_path = self._resolve_icon(app_id, pid)
            name = self._resolve_name(app_id, pid)

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
