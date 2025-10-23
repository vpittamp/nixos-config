"""
Data models for window rules discovery and validation.

All models use Pydantic v2 for validation and type safety.
"""

from pydantic import BaseModel, Field, field_validator
from typing import Optional
from enum import Enum
from datetime import datetime
from pathlib import Path
import re


class PatternType(str, Enum):
    """Type of pattern matching to apply."""
    CLASS = "class"              # Exact WM_CLASS match
    TITLE = "title"              # Title substring match
    TITLE_REGEX = "title_regex"  # Title regex match
    PWA = "pwa"                  # PWA ID match (FFPWA-*)


class Scope(str, Enum):
    """Application scope classification."""
    SCOPED = "scoped"   # Project-specific, hidden when project inactive
    GLOBAL = "global"   # Always visible across all projects


class Window(BaseModel):
    """Represents an i3 window with properties from i3 IPC."""

    id: int = Field(..., description="i3 container ID")
    window_id: Optional[int] = Field(None, description="X11 window ID")
    window_class: str = Field(..., description="WM_CLASS class property")
    window_instance: str = Field(..., description="WM_CLASS instance property")
    title: str = Field(..., description="WM_NAME window title")
    workspace_num: int = Field(..., description="Workspace number (1-9)")
    workspace_name: str = Field(..., description="Workspace name from i3")
    output: str = Field(..., description="Output/monitor name (e.g., HDMI-0)")
    window_type: Optional[str] = Field(None, description="Window type (_NET_WM_WINDOW_TYPE)")
    floating: bool = Field(False, description="Whether window is floating")
    marks: list[str] = Field(default_factory=list, description="i3 marks applied to window")
    focused: bool = Field(False, description="Whether window has focus")

    # Derived properties
    is_terminal: bool = Field(False, description="Whether window is a known terminal emulator")
    is_pwa: bool = Field(False, description="Whether window is a Firefox PWA (FFPWA-*)")

    @classmethod
    def from_i3_container(cls, container) -> "Window":
        """Create Window from i3ipc Container object."""
        window_class = container.window_class or "Unknown"
        window_instance = container.window_instance or "Unknown"
        title = container.name or ""

        # Detect terminal emulators
        terminal_classes = ["ghostty", "Ghostty", "Alacritty", "kitty", "URxvt", "XTerm", "st"]
        is_terminal = any(term in window_class for term in terminal_classes)

        # Detect PWAs
        is_pwa = window_class.startswith("FFPWA-")

        # Get workspace info
        workspace = container.workspace()
        workspace_num = workspace.num if workspace else 0
        workspace_name = workspace.name if workspace else ""
        output = workspace.ipc_data.get("output", "") if workspace else ""

        # Get window_type from ipc_data if available
        window_type = None
        if hasattr(container, 'ipc_data') and container.ipc_data:
            window_type = container.ipc_data.get('window_type')

        return cls(
            id=container.id,
            window_id=container.window,
            window_class=window_class,
            window_instance=window_instance,
            title=title,
            workspace_num=workspace_num,
            workspace_name=workspace_name,
            output=output,
            window_type=window_type,
            floating=container.floating in ("user_on", "auto_on"),
            marks=container.marks if container.marks else [],
            focused=container.focused,
            is_terminal=is_terminal,
            is_pwa=is_pwa,
        )


class Pattern(BaseModel):
    """Window matching pattern."""

    type: PatternType = Field(..., description="Type of pattern matching")
    value: str = Field(..., description="Pattern value (class name, title substring, or regex)")
    description: Optional[str] = Field(None, description="Human-readable description of what this pattern matches")

    # Metadata
    priority: int = Field(10, description="Pattern priority (lower = higher priority, 0-100)")
    case_sensitive: bool = Field(True, description="Whether matching is case-sensitive")

    @field_validator("value")
    @classmethod
    def validate_value(cls, v: str) -> str:
        """Ensure value is not empty."""
        if not v or not v.strip():
            raise ValueError("Pattern value cannot be empty")
        return v.strip()

    def matches(self, window: Window) -> bool:
        """Check if this pattern matches the given window."""
        if self.type == PatternType.CLASS:
            target = window.window_class
            pattern = self.value
            if not self.case_sensitive:
                target = target.lower()
                pattern = pattern.lower()
            return target == pattern

        elif self.type == PatternType.TITLE:
            target = window.title
            pattern = self.value
            if not self.case_sensitive:
                target = target.lower()
                pattern = pattern.lower()
            return pattern in target

        elif self.type == PatternType.TITLE_REGEX:
            flags = 0 if self.case_sensitive else re.IGNORECASE
            return bool(re.search(self.value, window.title, flags))

        elif self.type == PatternType.PWA:
            return window.window_class == self.value and window.is_pwa

        return False


class WindowRule(BaseModel):
    """Associates a pattern with workspace assignment."""

    pattern: Pattern = Field(..., description="Pattern to match windows")
    workspace: int = Field(..., description="Target workspace number (1-9)")
    scope: Scope = Field(..., description="Application scope (scoped/global)")
    enabled: bool = Field(True, description="Whether this rule is active")

    # Metadata
    application_name: str = Field(..., description="Friendly application name (e.g., 'VSCode', 'Firefox')")
    notes: Optional[str] = Field(None, description="Additional notes about this rule")

    @field_validator("workspace")
    @classmethod
    def validate_workspace(cls, v: int) -> int:
        """Ensure workspace is valid (1-9)."""
        if not 1 <= v <= 9:
            raise ValueError("Workspace must be between 1 and 9")
        return v


class ApplicationDefinition(BaseModel):
    """Defines an application with launch command and pattern expectations."""

    name: str = Field(..., description="Application name (e.g., 'vscode', 'firefox')")
    display_name: str = Field(..., description="Human-readable name (e.g., 'VS Code', 'Firefox')")

    # Launch configuration
    command: str = Field(..., description="Base launch command (e.g., 'code', 'firefox')")
    rofi_name: Optional[str] = Field(None, description="Name as it appears in rofi (if different from display_name)")
    parameters: Optional[str] = Field(None, description="Additional command parameters (e.g., '$PROJECT_DIR')")

    # Pattern expectations
    expected_pattern_type: PatternType = Field(..., description="Expected pattern type (class/title/pwa)")
    expected_class: Optional[str] = Field(None, description="Expected WM_CLASS (if known)")
    expected_title_contains: Optional[str] = Field(None, description="Expected title substring (if known)")

    # Classification
    scope: Scope = Field(..., description="Application scope (scoped/global)")
    preferred_workspace: Optional[int] = Field(None, description="Preferred workspace number (1-9)")

    # NixOS integration
    desktop_file_path: Optional[str] = Field(None, description="Path to .desktop file for customization")
    nix_package: Optional[str] = Field(None, description="NixOS package name (e.g., 'pkgs.vscode')")

    @field_validator("command")
    @classmethod
    def validate_command(cls, v: str) -> str:
        """Ensure command is not empty."""
        if not v or not v.strip():
            raise ValueError("Command cannot be empty")
        return v.strip()

    def get_full_command(self, **kwargs) -> str:
        """Get full launch command with parameter substitution."""
        cmd = self.command
        if self.parameters:
            # Substitute parameters (e.g., $PROJECT_DIR)
            params = self.parameters
            for key, value in kwargs.items():
                params = params.replace(f"${key.upper()}", str(value))
            cmd = f"{cmd} {params}"
        return cmd


class DiscoveryResult(BaseModel):
    """Result of discovering a window pattern for an application."""

    application_name: str = Field(..., description="Application name that was launched")
    launch_command: str = Field(..., description="Command used to launch application")
    launch_method: str = Field(..., description="Launch method (rofi/direct/manual)")

    # Captured window
    window: Optional[Window] = Field(None, description="Captured window (None if window didn't appear)")
    capture_time: datetime = Field(default_factory=datetime.now, description="When window was captured")
    wait_duration: float = Field(..., description="How long waited for window (seconds)")

    # Generated pattern
    generated_pattern: Optional[Pattern] = Field(None, description="Generated pattern (None if discovery failed)")
    confidence: float = Field(0.0, description="Confidence score 0.0-1.0")

    # Issues
    success: bool = Field(False, description="Whether discovery succeeded")
    warnings: list[str] = Field(default_factory=list, description="Warnings during discovery")
    errors: list[str] = Field(default_factory=list, description="Errors during discovery")

    @field_validator("confidence")
    @classmethod
    def validate_confidence(cls, v: float) -> float:
        """Ensure confidence is 0.0-1.0."""
        if not 0.0 <= v <= 1.0:
            raise ValueError("Confidence must be between 0.0 and 1.0")
        return v


class ValidationStatus(str, Enum):
    """Validation result status."""
    SUCCESS = "success"              # Pattern matched correctly
    FALSE_POSITIVE = "false_positive"  # Pattern matched wrong window
    FALSE_NEGATIVE = "false_negative"  # Pattern didn't match intended window
    WRONG_WORKSPACE = "wrong_workspace"  # Matched but on wrong workspace
    NO_WINDOW = "no_window"          # No window found to test against


class ValidationResult(BaseModel):
    """Result of validating a pattern against windows."""

    pattern: Pattern = Field(..., description="Pattern being validated")
    application_name: str = Field(..., description="Expected application name")

    # Validation outcome
    status: ValidationStatus = Field(..., description="Validation status")
    matched_window: Optional[Window] = Field(None, description="Window that matched (if any)")

    # Workspace verification
    expected_workspace: Optional[int] = Field(None, description="Expected workspace from rule")
    actual_workspace: Optional[int] = Field(None, description="Actual workspace where window appeared")
    workspace_correct: bool = Field(False, description="Whether workspace assignment is correct")

    # Discrepancies
    false_positive_windows: list[Window] = Field(default_factory=list, description="Other windows incorrectly matched")
    message: str = Field("", description="Human-readable validation message")


class ConfigurationBackup(BaseModel):
    """Backup of configuration files before modification."""

    timestamp: datetime = Field(default_factory=datetime.now, description="When backup was created")
    backup_dir: Path = Field(..., description="Directory containing backups")

    # Backup file paths
    window_rules_backup: Path = Field(..., description="Backup of window-rules.json")
    app_classes_backup: Path = Field(..., description="Backup of app-classes.json")

    # Metadata
    reason: str = Field(..., description="Reason for backup (e.g., 'migration', 'manual update')")
    rules_count: int = Field(0, description="Number of rules in backup")

    def restore(self) -> None:
        """Restore configuration from backup."""
        import shutil

        # Restore window-rules.json
        target = Path.home() / ".config/i3/window-rules.json"
        shutil.copy2(self.window_rules_backup, target)

        # Restore app-classes.json
        target = Path.home() / ".config/i3/app-classes.json"
        shutil.copy2(self.app_classes_backup, target)
