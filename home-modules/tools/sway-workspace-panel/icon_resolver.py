#!/usr/bin/env python3
"""Shared icon resolution for workspace bar and preview renderer.

Provides centralized icon lookup from:
1. Application registry (application-registry.json)
2. PWA registry (pwa-registry.json)
3. Desktop entries (.desktop files)

Uses XDG icon theme lookup and caching for performance.
"""
from __future__ import annotations

import json
from pathlib import Path
from typing import Dict, Optional

from xdg.DesktopEntry import DesktopEntry
from xdg.IconTheme import getIconPath

# Icon search directories for manual fallback
ICON_SEARCH_DIRS = [
    Path.home() / ".local/share/icons",
    Path.home() / ".icons",
    Path("/usr/share/icons"),
    Path("/usr/share/pixmaps"),
]

# Desktop file directories
DESKTOP_DIRS = [
    Path.home() / ".local/share/i3pm-applications/applications",  # Our app registry desktop files (primary)
    Path.home() / ".local/share/applications",  # PWA desktop files
    Path("/usr/share/applications"),  # System desktop files
]

ICON_EXTENSIONS = (".svg", ".png", ".xpm")
APP_REGISTRY_PATH = Path.home() / ".config/i3/application-registry.json"
PWA_REGISTRY_PATH = Path.home() / ".config/i3/pwa-registry.json"


class DesktopIconIndex:
    """Index .desktop entries and app registry so we can map windows to themed icons."""

    def __init__(self) -> None:
        self._by_desktop_id: Dict[str, Dict[str, str]] = {}
        self._by_startup_wm: Dict[str, Dict[str, str]] = {}
        self._by_app_id: Dict[str, Dict[str, str]] = {}
        self._icon_cache: Dict[str, str] = {}
        self._load_app_registry()
        self._load_pwa_registry()
        self._load_desktop_entries()

    def _load_app_registry(self) -> None:
        """Load icons from application-registry.json (primary source)."""
        if not APP_REGISTRY_PATH.exists():
            return
        try:
            with open(APP_REGISTRY_PATH) as f:
                data = json.load(f)
                for app in data.get("applications", []):
                    icon_path = self._resolve_icon(app.get("icon", ""))
                    payload = {
                        "icon": icon_path or "",
                        "name": app.get("display_name", app.get("name", "")),
                    }
                    # Index by name only (NOT expected_class - multiple apps share same class)
                    app_name = app.get("name", "").lower()
                    if app_name:
                        self._by_app_id[app_name] = payload
        except Exception:
            pass

    def _load_pwa_registry(self) -> None:
        """Load icons from pwa-registry.json (for PWAs)."""
        if not PWA_REGISTRY_PATH.exists():
            return
        try:
            with open(PWA_REGISTRY_PATH) as f:
                data = json.load(f)
                for pwa in data.get("pwas", []):
                    icon_path = self._resolve_icon(pwa.get("icon", ""))
                    payload = {
                        "icon": icon_path or "",
                        "name": pwa.get("name", ""),
                    }
                    # Index by ULID-based app_id (e.g., "FFPWA-01JCYF8Z2M")
                    pwa_id = f"ffpwa-{pwa.get('ulid', '')}".lower()
                    if pwa_id:
                        self._by_app_id[pwa_id] = payload
        except Exception:
            pass

    def _load_desktop_entries(self) -> None:
        """Load icons from .desktop files (fallback)."""
        for directory in DESKTOP_DIRS:
            if not directory.exists():
                continue
            for entry_path in directory.glob("*.desktop"):
                try:
                    entry = DesktopEntry(entry_path)
                except Exception:
                    continue
                icon_path = self._resolve_icon(entry.getIcon())
                display_name = entry.getName() or entry_path.stem
                payload = {
                    "icon": icon_path or "",
                    "name": display_name,
                }
                desktop_id = entry_path.stem.lower()
                self._by_desktop_id[desktop_id] = payload
                startup = entry.getStartupWMClass()
                if startup:
                    self._by_startup_wm[startup.lower()] = payload

    def _resolve_icon(self, icon_name: Optional[str]) -> Optional[str]:
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

    def lookup(self, *, app_id: Optional[str], window_class: Optional[str] = None, window_instance: Optional[str] = None) -> Dict[str, str]:
        """Look up icon and display name for a window.

        Args:
            app_id: Wayland app_id or I3PM_APP_NAME
            window_class: X11 window class (optional, for backwards compatibility)
            window_instance: X11 window instance (optional, for backwards compatibility)

        Returns:
            Dict with 'icon' and 'name' keys, or empty dict if not found
        """
        keys = [value.lower() for value in [app_id, window_class, window_instance] if value]
        # First priority: app registry (same icons as walker/launcher)
        for key in keys:
            if key in self._by_app_id:
                return self._by_app_id[key]
        # Second priority: desktop file by ID
        for key in keys:
            if key in self._by_desktop_id:
                return self._by_desktop_id[key]
        # Third priority: desktop file by StartupWMClass
        for key in keys:
            if key in self._by_startup_wm:
                return self._by_startup_wm[key]
        return {}
