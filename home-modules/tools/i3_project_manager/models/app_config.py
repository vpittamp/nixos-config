"""
Application Configuration Data Models

Feature 094: Enhanced Projects & Applications CRUD Interface
Storage: home-modules/desktop/app-registry-data.nix (Nix expression)
"""

from typing import Optional, Literal, List
from pydantic import BaseModel, Field, field_validator, model_validator
import re


class ApplicationConfig(BaseModel):
    """
    Base application configuration model

    Storage: home-modules/desktop/app-registry-data.nix (Nix expression)
    """
    name: str = Field(..., min_length=1, max_length=64, description="Unique application identifier")
    display_name: str = Field(..., min_length=1, description="Human-readable application name")
    command: str = Field(..., min_length=1, description="Executable command")
    parameters: List[str] = Field(default_factory=list, description="Command-line arguments")
    scope: Literal["scoped", "global"] = Field(default="scoped", description="Window visibility scope")
    expected_class: str = Field(..., min_length=1, description="Expected window class for validation")
    preferred_workspace: int = Field(..., ge=1, le=70, description="Workspace number assignment")
    preferred_monitor_role: Optional[Literal["primary", "secondary", "tertiary"]] = Field(
        default=None, description="Monitor role preference"
    )
    icon: str = Field(default="", description="Icon name, emoji, or file path")
    nix_package: str = Field(default="null", description="Nix package identifier")
    multi_instance: bool = Field(default=False, description="Allow multiple windows")
    floating: bool = Field(default=False, description="Launch as floating window")
    floating_size: Optional[Literal["scratchpad", "small", "medium", "large"]] = Field(
        default=None, description="Floating window size preset"
    )
    fallback_behavior: Literal["skip", "create"] = Field(default="skip", description="Behavior when window not found")
    description: str = Field(default="", description="Application description")
    terminal: bool = Field(default=False, description="Terminal-based application flag")

    @field_validator("name")
    @classmethod
    def validate_name_format(cls, v: str) -> str:
        """Per spec.md FR-A-006: lowercase, hyphens or dots, no spaces"""
        if not re.match(r'^[a-z0-9.-]+$', v):
            raise ValueError("Application name must be lowercase alphanumeric with hyphens or dots only")
        return v

    @field_validator("command")
    @classmethod
    def validate_command_no_metacharacters(cls, v: str) -> str:
        """Per spec.md FR-A-009: Validate command field does not contain shell metacharacters"""
        dangerous_chars = [';', '|', '&', '`', '$']
        for char in dangerous_chars:
            if char in v:
                raise ValueError(f"Command contains dangerous metacharacter '{char}'")
        return v

    @field_validator("preferred_workspace")
    @classmethod
    def validate_workspace_range(cls, v: int) -> int:
        """Per spec.md FR-A-007: Enforce workspace range 1-50 for regular apps"""
        # Skip validation for PWAConfig (will be validated by PWAConfig.validate_pwa_workspace_range)
        if cls.__name__ == "PWAConfig":
            return v
        if not (1 <= v <= 50):
            raise ValueError(f"Regular applications must use workspaces 1-50, got: {v}")
        return v

    @model_validator(mode='after')
    def validate_floating_size(self):
        """Per spec.md Edge Case: Floating size only valid when floating enabled"""
        if self.floating_size and not self.floating:
            raise ValueError("floating_size can only be set when floating=True")
        return self

    model_config = {
        "json_schema_extra": {
            "examples": [
                {
                    "name": "firefox",
                    "display_name": "Firefox",
                    "command": "firefox",
                    "parameters": [],
                    "scope": "global",
                    "expected_class": "firefox",
                    "preferred_workspace": 3,
                    "preferred_monitor_role": "primary",
                    "icon": "firefox",
                    "nix_package": "pkgs.firefox",
                    "multi_instance": False,
                    "floating": False,
                    "floating_size": None,
                    "fallback_behavior": "skip",
                    "description": "Web browser",
                    "terminal": False
                }
            ]
        }
    }


class TerminalAppConfig(ApplicationConfig):
    """Terminal application configuration (extends ApplicationConfig)"""
    terminal: bool = Field(default=True, description="Must be True for terminal apps")
    command: Literal["ghostty", "alacritty", "kitty", "wezterm"] = Field(
        ..., description="Terminal emulator command"
    )

    @field_validator("scope")
    @classmethod
    def validate_terminal_scope(cls, v: str) -> str:
        """Per spec.md: Terminal apps are typically scoped"""
        # This is a suggestion, not a hard requirement
        return v

    model_config = {
        "json_schema_extra": {
            "examples": [
                {
                    "name": "terminal",
                    "display_name": "Terminal",
                    "command": "ghostty",
                    "parameters": ["-e", "sesh", "connect", "$PROJECT_DIR"],
                    "scope": "scoped",
                    "expected_class": "ghostty",
                    "preferred_workspace": 1,
                    "preferred_monitor_role": None,
                    "icon": "🖥️",
                    "nix_package": "pkgs.ghostty",
                    "multi_instance": True,
                    "floating": False,
                    "terminal": True
                }
            ]
        }
    }


class PWAConfig(ApplicationConfig):
    """
    Progressive Web App configuration (extends ApplicationConfig)

    Per spec.md: PWAs have special requirements - ULID, start_url, workspace 50+
    """
    name: str = Field(..., pattern=r'^[a-z0-9.-]+-pwa$', description="Must end with '-pwa'")
    ulid: str = Field(..., min_length=26, max_length=26, description="26-character ULID identifier")
    start_url: str = Field(..., min_length=1, description="PWA launch URL")
    scope_url: str = Field(..., min_length=1, description="URL scope for PWA")
    expected_class: str = Field(..., pattern=r'^FFPWA-[0-9A-HJKMNP-TV-Z]{26}$', description="Format: FFPWA-<ULID>")
    app_scope: Literal["scoped", "global"] = Field(default="scoped", description="PWA-specific scope")
    categories: str = Field(default="Network;", description="Desktop entry categories")
    keywords: str = Field(default="", description="Search keywords")

    @field_validator("ulid")
    @classmethod
    def validate_ulid_format(cls, v: str) -> str:
        """Per spec.md FR-A-008, FR-A-030: Validate ULID is 26 chars, Crockford Base32"""
        if not re.match(r'^[0-7][0-9A-HJKMNP-TV-Z]{25}$', v):
            raise ValueError(
                f"Invalid ULID format: {v}. Must be 26 characters from Crockford Base32 "
                "(0-9, A-H, J-K, M-N, P-T, V-Z, excluding I, L, O, U), first char 0-7"
            )
        return v

    @field_validator("start_url", "scope_url")
    @classmethod
    def validate_url_format(cls, v: str) -> str:
        """Per spec.md FR-A-015: Validate URL is valid HTTP/HTTPS"""
        if not re.match(r'^https?://.+', v):
            raise ValueError(f"URL must start with http:// or https://, got: {v}")
        return v

    @field_validator("preferred_workspace")
    @classmethod
    def validate_pwa_workspace_range(cls, v: int) -> int:
        """Per spec.md FR-A-007: PWAs must use workspace 50+"""
        if v < 50:
            raise ValueError(f"PWAs must use workspaces 50 or higher, got: {v}")
        return v

    model_config = {
        "json_schema_extra": {
            "examples": [
                {
                    "name": "youtube-pwa",
                    "display_name": "YouTube",
                    "command": "firefoxpwa",
                    "parameters": ["site", "launch", "01JCYF8Z2M0N3P4Q5R6S7T8V9W"],
                    "scope": "global",
                    "expected_class": "FFPWA-01JCYF8Z2M0N3P4Q5R6S7T8V9W",
                    "preferred_workspace": 50,
                    "preferred_monitor_role": "secondary",
                    "icon": "/etc/nixos/assets/icons/youtube.svg",
                    "nix_package": "null",
                    "multi_instance": False,
                    "floating": False,
                    "ulid": "01JCYF8Z2M0N3P4Q5R6S7T8V9W",
                    "start_url": "https://www.youtube.com",
                    "scope_url": "https://www.youtube.com/",
                    "app_scope": "scoped",
                    "categories": "Network;AudioVideo;",
                    "keywords": "youtube;video;",
                    "description": "YouTube video platform",
                    "terminal": False
                }
            ]
        }
    }
