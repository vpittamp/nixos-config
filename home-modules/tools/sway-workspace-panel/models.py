"""Pydantic models for sway-workspace-panel.

Feature 058: Workspace Mode Visual Feedback - Workspace mode IPC events
Feature 057: Unified Bar System - Theme configuration models
"""

from typing import Optional, Literal
from pydantic import BaseModel, Field


class PendingWorkspaceState(BaseModel):
    """Pending workspace state received from workspace mode events.

    This is a simplified version for the workspace panel to parse IPC events.
    The canonical model is in i3pm daemon's models/workspace_mode_feedback.py.
    """

    workspace_number: int = Field(..., description="Target workspace number (1-70)")
    accumulated_digits: str = Field(..., description="Raw digit string")
    mode_type: Literal["goto", "move"] = Field(..., description="Navigation mode")
    target_output: Optional[str] = Field(default=None, description="Monitor output name")


class WorkspaceModeEvent(BaseModel):
    """Workspace mode event received via IPC from i3pm daemon.

    Feature 058: User Story 1 (Workspace Button Pending Highlight)
    """

    event_type: Literal["enter", "digit", "cancel", "execute"] = Field(..., description="Type of workspace mode event")
    pending_workspace: Optional[PendingWorkspaceState] = Field(default=None, description="Current pending workspace (None when mode inactive)")
    timestamp: float = Field(..., gt=0, description="Unix timestamp when event was emitted")

    class Config:
        """Pydantic config."""
        json_schema_extra = {
            "examples": [
                {
                    "event_type": "digit",
                    "pending_workspace": {
                        "workspace_number": 23,
                        "accumulated_digits": "23",
                        "mode_type": "goto",
                        "target_output": "HEADLESS-2"
                    },
                    "timestamp": 1699727480.8765
                },
                {
                    "event_type": "cancel",
                    "pending_workspace": None,
                    "timestamp": 1699727481.5432
                }
            ]
        }


# ============================================================================
# Feature 057: Unified Bar Theme Configuration Models
# ============================================================================


class ThemeColors(BaseModel):
    """Catppuccin Mocha color palette."""

    base: str = Field(..., pattern=r"^#[0-9a-fA-F]{6}$", description="Background base")
    mantle: str = Field(..., pattern=r"^#[0-9a-fA-F]{6}$", description="Darker background")
    surface0: str = Field(..., pattern=r"^#[0-9a-fA-F]{6}$", description="Surface layer 1")
    surface1: str = Field(..., pattern=r"^#[0-9a-fA-F]{6}$", description="Surface layer 2")
    overlay0: str = Field(..., pattern=r"^#[0-9a-fA-F]{6}$", description="Overlay/border")
    text: str = Field(..., pattern=r"^#[0-9a-fA-F]{6}$", description="Primary text")
    subtext0: str = Field(..., pattern=r"^#[0-9a-fA-F]{6}$", description="Dimmed text")
    blue: str = Field(..., pattern=r"^#[0-9a-fA-F]{6}$", description="Focused accent")
    mauve: str = Field(..., pattern=r"^#[0-9a-fA-F]{6}$", description="Border accent")
    yellow: str = Field(..., pattern=r"^#[0-9a-fA-F]{6}$", description="Pending state")
    red: str = Field(..., pattern=r"^#[0-9a-fA-F]{6}$", description="Urgent/critical")
    green: str = Field(..., pattern=r"^#[0-9a-fA-F]{6}$", description="Success")
    teal: str = Field(..., pattern=r"^#[0-9a-fA-F]{6}$", description="Info")


class ThemeFonts(BaseModel):
    """Font configuration for bars."""

    bar: str = Field(default="FiraCode Nerd Font", description="Top bar font family")
    bar_size: float = Field(default=8.0, ge=6, le=24, description="Top bar font size (pt)")
    workspace: str = Field(default="FiraCode Nerd Font", description="Workspace bar font family")
    workspace_size: float = Field(default=11.0, ge=6, le=24, description="Workspace bar font size (pt)")
    notification: str = Field(default="Ubuntu Nerd Font", description="SwayNC font family")
    notification_size: float = Field(default=10.0, ge=6, le=24, description="SwayNC font size (pt)")


class WorkspaceBarConfig(BaseModel):
    """Bottom bar (Eww) configuration."""

    height: int = Field(default=32, ge=24, le=48, description="Bar height (px)")
    padding: int = Field(default=4, ge=0, le=16, description="Padding (px)")
    border_radius: int = Field(default=6, ge=0, le=16, description="Border radius (px)")
    button_spacing: int = Field(default=3, ge=0, le=10, description="Workspace button spacing (px)")
    icon_size: int = Field(default=16, ge=12, le=32, description="Workspace icon size (px)")


class TopBarConfig(BaseModel):
    """Top bar (Swaybar) configuration."""

    position: Literal["top", "bottom"] = Field(default="top", description="Bar position")
    separator: str = Field(default=" | ", description="Module separator")
    show_tray: bool = Field(default=True, description="System tray visibility")
    show_binding_mode: bool = Field(default=True, description="Binding mode indicator")


class NotificationCenterConfig(BaseModel):
    """SwayNC configuration."""

    position_x: Literal["left", "center", "right"] = Field(default="right", description="Horizontal position")
    position_y: Literal["top", "center", "bottom"] = Field(default="top", description="Vertical position")
    width: int = Field(default=500, ge=300, le=800, description="Notification width (px)")
    timeout: int = Field(default=10, ge=0, le=120, description="Normal timeout (s)")
    timeout_critical: int = Field(default=0, ge=0, le=120, description="Critical timeout (0 = never)")
    grouping: bool = Field(default=True, description="Notification grouping")


class ThemeConfig(BaseModel):
    """Unified bar theme configuration (appearance.json)."""

    version: Literal["1.0"] = Field(default="1.0", description="Schema version")
    theme: str = Field(default="catppuccin-mocha", description="Theme identifier")
    colors: ThemeColors = Field(..., description="Catppuccin Mocha color palette")
    fonts: Optional[ThemeFonts] = Field(default_factory=ThemeFonts, description="Font configuration")
    workspace_bar: Optional[WorkspaceBarConfig] = Field(default_factory=WorkspaceBarConfig, description="Bottom bar config")
    top_bar: Optional[TopBarConfig] = Field(default_factory=TopBarConfig, description="Top bar config")
    notification_center: Optional[NotificationCenterConfig] = Field(default_factory=NotificationCenterConfig, description="SwayNC config")

    class Config:
        """Pydantic config."""
        json_schema_extra = {
            "examples": [
                {
                    "version": "1.0",
                    "theme": "catppuccin-mocha",
                    "colors": {
                        "base": "#1e1e2e",
                        "mantle": "#181825",
                        "surface0": "#313244",
                        "surface1": "#45475a",
                        "overlay0": "#6c7086",
                        "text": "#cdd6f4",
                        "subtext0": "#a6adc8",
                        "blue": "#89b4fa",
                        "mauve": "#cba6f7",
                        "yellow": "#f9e2af",
                        "red": "#f38ba8",
                        "green": "#a6e3a1",
                        "teal": "#94e2d5"
                    }
                }
            ]
        }


# Feature 057: User Story 2 - Enhanced Workspace Mode Visual Feedback
# T035: WorkspacePreview and WorkspaceApp Pydantic models


class WorkspaceApp(BaseModel):
    """Application in workspace preview."""

    name: str = Field(..., description="Application name (from app_id or window class)")
    title: str = Field(default="", description="Window title")
    app_id: Optional[str] = Field(default=None, description="Wayland app_id (if available)")
    window_class: Optional[str] = Field(default=None, description="X11 window class (if available)")
    icon: Optional[str] = Field(default=None, description="Icon name/path from application registry")
    focused: bool = Field(default=False, description="Whether this window is focused in the workspace")
    floating: bool = Field(default=False, description="Whether window is floating")


class WorkspacePreview(BaseModel):
    """Workspace preview data for preview card overlay."""

    workspace_num: int = Field(..., ge=1, le=70, description="Workspace number (1-70)")
    workspace_name: Optional[str] = Field(default=None, description="Workspace name (if set)")
    monitor_output: str = Field(..., description="Monitor output name (e.g., HEADLESS-1, eDP-1)")
    apps: list[WorkspaceApp] = Field(default_factory=list, description="Applications in workspace")
    window_count: int = Field(default=0, ge=0, description="Total window count")
    visible: bool = Field(default=False, description="Whether workspace is currently visible")
    focused: bool = Field(default=False, description="Whether workspace is currently focused")
    urgent: bool = Field(default=False, description="Whether workspace has urgent windows")
    empty: bool = Field(default=True, description="Whether workspace has no windows")
    mode: Literal["goto", "move"] = Field(default="goto", description="Workspace mode operation (Feature 057 US3)")

    class Config:
        """Pydantic config."""
        json_schema_extra = {
            "examples": [
                {
                    "workspace_num": 23,
                    "workspace_name": "coding",
                    "monitor_output": "HEADLESS-2",
                    "apps": [
                        {
                            "name": "Code",
                            "title": "main.py - VS Code",
                            "app_id": "code",
                            "icon": "/etc/nixos/assets/icons/apps/code.svg",
                            "focused": True,
                            "floating": False
                        },
                        {
                            "name": "Firefox",
                            "title": "Claude AI",
                            "app_id": "firefox",
                            "icon": "/etc/nixos/assets/icons/apps/firefox.svg",
                            "focused": False,
                            "floating": False
                        }
                    ],
                    "window_count": 2,
                    "visible": False,
                    "focused": False,
                    "urgent": False,
                    "empty": False,
                    "mode": "goto"
                }
            ]
        }


# ============================================================================
# Feature 057: User Story 4 - App-Aware Notification Icons
# T021: NotificationIcon and AppIconMapping Pydantic models
# ============================================================================


class AppIconMapping(BaseModel):
    """Mapping from app identifier to icon path.

    Used for resolving notification icons from application registry.
    """

    app_id: str = Field(..., description="Application identifier (app_id, window_class, or I3PM_APP_NAME)")
    icon_path: str = Field(..., description="Absolute path to icon file")
    icon_name: Optional[str] = Field(default=None, description="Icon name for XDG theme lookup")
    display_name: str = Field(..., description="Human-readable application name")
    desktop_id: Optional[str] = Field(default=None, description="Desktop entry ID (e.g., 'firefox.desktop')")

    class Config:
        """Pydantic config."""
        json_schema_extra = {
            "examples": [
                {
                    "app_id": "com.mitchellh.ghostty",
                    "icon_path": "/etc/profiles/per-user/vpittamp/share/icons/hicolor/128x128/apps/com.mitchellh.ghostty.png",
                    "icon_name": "com.mitchellh.ghostty",
                    "display_name": "Ghostty",
                    "desktop_id": "com.mitchellh.ghostty.desktop"
                },
                {
                    "app_id": "code",
                    "icon_path": "/etc/nixos/assets/icons/apps/code.svg",
                    "icon_name": "vscode",
                    "display_name": "VS Code",
                    "desktop_id": "code.desktop"
                }
            ]
        }


class NotificationIcon(BaseModel):
    """Notification icon metadata resolved from application registry.

    Represents the icon to be used for a notification based on the app that sent it.
    """

    source_app: str = Field(..., description="Source application identifier (from notification hint or window tracking)")
    resolved_icon: str = Field(..., description="Resolved icon path (absolute path or XDG icon name)")
    fallback_icon: Optional[str] = Field(default="dialog-information", description="Fallback icon if resolution fails")
    resolution_method: Literal["registry", "desktop_entry", "xdg_theme", "fallback"] = Field(
        default="fallback",
        description="How the icon was resolved"
    )

    class Config:
        """Pydantic config."""
        json_schema_extra = {
            "examples": [
                {
                    "source_app": "code",
                    "resolved_icon": "/etc/nixos/assets/icons/apps/code.svg",
                    "fallback_icon": "dialog-information",
                    "resolution_method": "registry"
                },
                {
                    "source_app": "ffpwa-01JCYF8Z2M",
                    "resolved_icon": "/etc/nixos/assets/icons/claude.svg",
                    "fallback_icon": "dialog-information",
                    "resolution_method": "registry"
                },
                {
                    "source_app": "unknown-app",
                    "resolved_icon": "dialog-information",
                    "fallback_icon": "dialog-information",
                    "resolution_method": "fallback"
                }
            ]
        }
