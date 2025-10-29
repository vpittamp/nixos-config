"""
Pydantic data models for Sway configuration management.

Defines all configuration entities with validation rules.
"""

import re
from datetime import datetime
from enum import Enum
from typing import List, Optional, Dict, Any

from pydantic import BaseModel, Field, field_validator, model_validator


# Enumerations

class ConfigSource(str, Enum):
    """Configuration source attribution."""
    NIX = "nix"
    RUNTIME = "runtime"
    PROJECT = "project"


class RuleScope(str, Enum):
    """Window rule application scope."""
    GLOBAL = "global"
    PROJECT = "project"


# Core Entities

class KeybindingConfig(BaseModel):
    """Keyboard shortcut mapping to Sway command."""

    key_combo: str = Field(..., description="Key combination (e.g., Mod+Return)")
    command: str = Field(..., description="Sway command to execute")
    description: Optional[str] = Field(None, description="Human-readable description")
    source: ConfigSource = Field(..., description="Configuration source")
    mode: str = Field("default", description="Sway mode for binding")

    @field_validator('key_combo')
    @classmethod
    def validate_key_combo(cls, v: str) -> str:
        """Validate key combination syntax.

        Accepts:
        - Modified keys: Mod+Return, Mod+Shift+x, Control+Alt+Delete
        - Standalone special keys: Print, F1-F12, XF86AudioRaiseVolume, etc.
        """
        # Pattern for modified keys (requires at least one modifier)
        modified_pattern = r'^(Mod|Shift|Control|Alt|Ctrl)(\+(Mod|Shift|Control|Alt|Ctrl))*\+[a-zA-Z0-9_\-]+$'

        # Pattern for standalone special keys (Print, F-keys, XF86 media keys)
        special_pattern = r'^(Print|F[0-9]+|XF86[a-zA-Z0-9]+)$'

        if not (re.match(modified_pattern, v) or re.match(special_pattern, v)):
            raise ValueError(f"Invalid key combo syntax: {v}")
        return v

    @field_validator('command')
    @classmethod
    def validate_command(cls, v: str) -> str:
        """Validate command is not empty."""
        if not v.strip():
            raise ValueError("Command cannot be empty")
        return v.strip()


class WindowCriteria(BaseModel):
    """Window matching criteria."""

    app_id: Optional[str] = Field(None, description="Application ID regex pattern")
    window_class: Optional[str] = Field(None, description="Window class regex pattern")
    title: Optional[str] = Field(None, description="Window title regex pattern")
    window_role: Optional[str] = Field(None, description="Window role pattern")

    @field_validator('app_id', 'window_class', 'title', 'window_role')
    @classmethod
    def validate_regex(cls, v: Optional[str]) -> Optional[str]:
        """Validate regex patterns."""
        if v is not None:
            try:
                re.compile(v)
            except re.error as e:
                raise ValueError(f"Invalid regex pattern: {e}")
        return v

    def has_criteria(self) -> bool:
        """Check if at least one criteria is specified."""
        return any([self.app_id, self.window_class, self.title, self.window_role])


class WindowRule(BaseModel):
    """Window behavior rule."""

    id: str = Field(..., description="Unique rule identifier")
    criteria: WindowCriteria = Field(..., description="Window matching criteria")
    actions: List[str] = Field(..., min_length=1, description="Sway commands to apply")
    scope: RuleScope = Field(..., description="Rule application scope")
    project_name: Optional[str] = Field(None, description="Project name (if scope=project)")
    priority: int = Field(100, ge=0, le=1000, description="Rule precedence (0-1000)")
    source: ConfigSource = Field(..., description="Configuration source")

    @model_validator(mode='after')
    def validate_criteria_and_scope(self):
        """Validate criteria has at least one field and scope requirements."""
        if not self.criteria.has_criteria():
            raise ValueError("At least one criteria field must be specified")

        if self.scope == RuleScope.PROJECT and not self.project_name:
            raise ValueError("project_name required when scope=project")

        return self


class WorkspaceAssignment(BaseModel):
    """Workspace-to-output mapping."""

    workspace_number: int = Field(..., ge=1, le=70, description="Workspace number (1-70)")
    primary_output: str = Field(..., description="Primary output name")
    fallback_outputs: List[str] = Field(default_factory=list, description="Fallback outputs")
    auto_reassign: bool = Field(True, description="Auto-reassign on output changes")
    source: ConfigSource = Field(..., description="Configuration source")

    @field_validator('primary_output')
    @classmethod
    def validate_primary_output(cls, v: str) -> str:
        """Validate primary output is not empty."""
        if not v.strip():
            raise ValueError("Primary output cannot be empty")
        return v.strip()

    @field_validator('fallback_outputs')
    @classmethod
    def validate_fallbacks(cls, v: List[str], info) -> List[str]:
        """Validate fallback outputs don't include primary."""
        data = info.data
        primary = data.get('primary_output')
        if primary and primary in v:
            raise ValueError("Fallback outputs must not include primary output")
        return v


class ProjectWindowRuleOverride(BaseModel):
    """Project-specific window rule override."""

    base_rule_id: Optional[str] = Field(None, description="Global rule ID to override")
    override_properties: Dict[str, Any] = Field(..., description="Properties to override")
    enabled: bool = Field(True, description="Override active status")

    @field_validator('override_properties')
    @classmethod
    def validate_override_properties(cls, v: Dict[str, Any]) -> Dict[str, Any]:
        """Validate override contains valid properties."""
        valid_fields = {'criteria', 'actions', 'priority'}
        if not any(k in valid_fields for k in v.keys()):
            raise ValueError(f"Override must contain at least one of: {valid_fields}")
        return v


class ProjectKeybindingOverride(BaseModel):
    """Project-specific keybinding override."""

    key_combo: str = Field(..., description="Key combination to override")
    command: Optional[str] = Field(None, description="New command (null to disable)")
    description: Optional[str] = Field(None, description="Override description")
    enabled: bool = Field(True, description="Override active status")

    @field_validator('key_combo')
    @classmethod
    def validate_key_combo(cls, v: str) -> str:
        """Validate key combination syntax."""
        # Pattern for modified keys (requires at least one modifier)
        modified_pattern = r'^(Mod|Shift|Control|Alt|Ctrl)(\+(Mod|Shift|Control|Alt|Ctrl))*\+[a-zA-Z0-9_\-]+$'

        # Pattern for standalone special keys (Print, F-keys, XF86 media keys)
        special_pattern = r'^(Print|F[0-9]+|XF86[a-zA-Z0-9]+)$'

        if not (re.match(modified_pattern, v) or re.match(special_pattern, v)):
            raise ValueError(f"Invalid key combo syntax: {v}")
        return v

    @field_validator('command')
    @classmethod
    def validate_command(cls, v: Optional[str]) -> Optional[str]:
        """Validate command is not empty if provided."""
        if v is not None and not v.strip():
            raise ValueError("Command cannot be empty string (use null to disable)")
        return v.strip() if v is not None else None


class Project(BaseModel):
    """Project configuration with override capabilities."""

    name: str = Field(..., description="Project unique identifier")
    display_name: str = Field(..., description="Human-readable project name")
    directory: str = Field(..., description="Project root directory path")
    icon: Optional[str] = Field(None, description="Project icon emoji")
    created_at: datetime = Field(default_factory=datetime.now, description="Creation timestamp")
    updated_at: datetime = Field(default_factory=datetime.now, description="Last update timestamp")

    # Feature 047 User Story 3: Project-specific overrides
    window_rule_overrides: List[ProjectWindowRuleOverride] = Field(
        default_factory=list,
        description="Project-specific window rule overrides"
    )
    keybinding_overrides: Dict[str, ProjectKeybindingOverride] = Field(
        default_factory=dict,
        description="Project-specific keybinding overrides (key_combo -> override)"
    )

    @field_validator('name')
    @classmethod
    def validate_name(cls, v: str) -> str:
        """Validate project name is alphanumeric with hyphens/underscores."""
        if not re.match(r'^[a-z0-9_-]+$', v):
            raise ValueError("Project name must be lowercase alphanumeric with hyphens/underscores")
        return v

    @field_validator('directory')
    @classmethod
    def validate_directory(cls, v: str) -> str:
        """Validate directory is absolute path."""
        if not v.startswith('/'):
            raise ValueError("Project directory must be an absolute path")
        return v


class ConfigurationVersion(BaseModel):
    """Configuration version snapshot for rollback."""

    commit_hash: str = Field(..., description="Git commit SHA")
    timestamp: datetime = Field(..., description="Commit timestamp")
    message: str = Field(..., description="Commit message")
    files_changed: List[str] = Field(..., min_length=1, description="Modified config files")
    author: Optional[str] = Field(None, description="Commit author")
    is_active: bool = Field(False, description="Currently active version")

    @field_validator('commit_hash')
    @classmethod
    def validate_commit_hash(cls, v: str) -> str:
        """Validate git SHA format."""
        if not re.match(r'^[0-9a-f]{40}$', v):
            raise ValueError("Invalid git SHA format")
        return v


class ConfigurationSourceAttribution(BaseModel):
    """Track which system owns each configuration setting."""

    setting_path: str = Field(..., description="Dot-notation setting path")
    source_system: ConfigSource = Field(..., description="Owning system")
    precedence_level: int = Field(..., ge=1, le=3, description="Precedence tier (1-3)")
    last_modified: datetime = Field(..., description="Last modification time")
    file_path: str = Field(..., description="Source file absolute path")


# Validation Result Models

class ValidationError(BaseModel):
    """Configuration validation error."""

    file_path: str
    line_number: Optional[int] = None
    error_type: str  # "syntax", "semantic", "conflict"
    message: str
    suggestion: Optional[str] = None


class ValidationResult(BaseModel):
    """Configuration validation result."""

    valid: bool
    errors: List[ValidationError] = Field(default_factory=list)
    warnings: List[ValidationError] = Field(default_factory=list)
