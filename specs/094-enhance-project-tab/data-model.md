# Data Model: Enhanced Projects & Applications CRUD Interface

**Feature**: 094-enhance-project-tab
**Date**: 2025-11-24
**Status**: Complete

## Overview

This document defines the data models for Feature 094, including Python Pydantic models for backend validation and TypeScript Zod schemas for CLI integration. Models support three main entity types: Projects (local/remote/worktrees), Applications (regular/terminal/PWAs), and UI state (validation/conflicts).

---

## 1. Project Models

### 1.1 ProjectConfig (Python Pydantic)

**File**: `home-modules/tools/i3_project_manager/models/project_config.py`

```python
from pathlib import Path
from typing import Optional, Literal
from pydantic import BaseModel, Field, field_validator, model_validator
import re
import os

class RemoteConfig(BaseModel):
    """Remote SSH configuration for remote projects"""
    enabled: bool = False
    host: str = Field(..., min_length=1, description="SSH hostname or Tailscale FQDN")
    user: str = Field(..., min_length=1, description="SSH username")
    remote_dir: str = Field(..., min_length=1, description="Remote working directory (absolute path)")
    port: int = Field(default=22, ge=1, le=65535, description="SSH port")

    @field_validator("remote_dir")
    @classmethod
    def validate_absolute_path(cls, v: str) -> str:
        """Per spec.md FR-P-010: remote_dir must be absolute path"""
        if not v.startswith("/"):
            raise ValueError(f"Remote directory must be absolute path, got: {v}")
        return v


class ProjectConfig(BaseModel):
    """
    Project configuration model for i3pm projects

    Storage: ~/.config/i3/projects/<name>.json
    """
    name: str = Field(..., min_length=1, max_length=64, description="Unique project identifier")
    display_name: str = Field(..., min_length=1, description="Human-readable project name")
    icon: str = Field(default="📦", description="Emoji or file path for visual identification")
    working_dir: str = Field(..., min_length=1, description="Absolute path to project directory")
    scope: Literal["scoped", "global"] = Field(default="scoped", description="Window hiding behavior")
    remote: Optional[RemoteConfig] = Field(default=None, description="Remote SSH configuration")

    @field_validator("name")
    @classmethod
    def validate_name_format(cls, v: str) -> str:
        """Per spec.md FR-P-007: lowercase, hyphens only, no spaces"""
        if not re.match(r'^[a-z0-9-]+$', v):
            raise ValueError("Project name must be lowercase alphanumeric with hyphens only (no spaces)")
        return v

    @field_validator("name")
    @classmethod
    def validate_name_uniqueness(cls, v: str) -> str:
        """Per spec.md Edge Case: Duplicate project names"""
        project_file = Path.home() / f".config/i3/projects/{v}.json"
        if project_file.exists():
            raise ValueError(f"Project '{v}' already exists")
        return v

    @field_validator("working_dir")
    @classmethod
    def validate_working_dir_exists(cls, v: str) -> str:
        """Per spec.md FR-P-008: Validate directory exists and is accessible"""
        path = Path(v).expanduser().resolve()
        if not path.exists():
            raise ValueError(f"Working directory does not exist: {v}")
        if not path.is_dir():
            raise ValueError(f"Path is not a directory: {v}")
        if not os.access(path, os.R_OK | os.W_OK):
            raise ValueError(f"Working directory not accessible (check permissions): {v}")
        return str(path)

    @field_validator("icon")
    @classmethod
    def validate_icon_format(cls, v: str) -> str:
        """Per spec.md Edge Case: Icon picker integration - emoji or file path"""
        # Allow emoji (1-4 characters) or absolute file path
        if len(v) <= 4:
            return v  # Assume emoji

        # If longer, must be file path
        if not v.startswith("/"):
            raise ValueError(f"Icon must be emoji or absolute file path, got: {v}")

        path = Path(v)
        if path.exists() and not path.is_file():
            raise ValueError(f"Icon path exists but is not a file: {v}")

        return v

    model_config = {
        "json_schema_extra": {
            "examples": [
                {
                    "name": "nixos-094-feature",
                    "display_name": "NixOS Feature 094",
                    "icon": "📦",
                    "working_dir": "/home/vpittamp/nixos-094-enhance-project-tab",
                    "scope": "scoped",
                    "remote": None
                },
                {
                    "name": "hetzner-dev",
                    "display_name": "Hetzner Development",
                    "icon": "🌐",
                    "working_dir": "/home/vpittamp/projects/hetzner-dev",
                    "scope": "scoped",
                    "remote": {
                        "enabled": True,
                        "host": "hetzner-sway.tailnet",
                        "user": "vpittamp",
                        "remote_dir": "/home/vpittamp/dev/my-app",
                        "port": 22
                    }
                }
            ]
        }
    }


class WorktreeConfig(ProjectConfig):
    """
    Git worktree configuration (extends ProjectConfig)

    Storage: ~/.config/i3/projects/<name>.json (same as projects)
    Distinguished by presence of parent_project field
    """
    worktree_path: str = Field(..., min_length=1, description="Absolute path to worktree directory")
    branch_name: str = Field(..., min_length=1, description="Git branch name for this worktree")
    parent_project: str = Field(..., min_length=1, description="Name of main project this worktree belongs to")

    @field_validator("worktree_path")
    @classmethod
    def validate_worktree_path_not_exists(cls, v: str) -> str:
        """Per spec.md FR-P-018: Validate worktree path does not already exist"""
        path = Path(v).expanduser().resolve()
        if path.exists():
            raise ValueError(f"Worktree path already exists: {v}")
        return str(path)

    @field_validator("branch_name")
    @classmethod
    def validate_branch_name_format(cls, v: str) -> str:
        """Validate Git branch name format (no spaces, valid Git ref)"""
        if not re.match(r'^[a-zA-Z0-9/_-]+$', v):
            raise ValueError(f"Invalid Git branch name format: {v}")
        return v

    @model_validator(mode='after')
    def validate_parent_project_exists(self):
        """Per spec.md Edge Case: Worktree without parent"""
        parent_file = Path.home() / f".config/i3/projects/{self.parent_project}.json"
        if not parent_file.exists():
            raise ValueError(f"Parent project '{self.parent_project}' does not exist")
        return self

    model_config = {
        "json_schema_extra": {
            "examples": [
                {
                    "name": "nixos-095-worktree",
                    "display_name": "Feature 095 Worktree",
                    "icon": "🌿",
                    "working_dir": "/home/vpittamp/nixos-095-worktree",
                    "scope": "scoped",
                    "worktree_path": "/home/vpittamp/nixos-095-worktree",
                    "branch_name": "095-new-feature",
                    "parent_project": "nixos",
                    "remote": None
                }
            ]
        }
    }
```

### 1.2 ProjectConfig (TypeScript Zod)

**File**: `home-modules/tools/i3_project_manager/models/project_config.ts` (if CLI needs it)

```typescript
import { z } from "https://deno.land/x/zod@v3.22.4/mod.ts";

export const RemoteConfigSchema = z.object({
  enabled: z.boolean().default(false),
  host: z.string().min(1),
  user: z.string().min(1),
  remote_dir: z.string().min(1).refine(
    (val) => val.startsWith("/"),
    { message: "Remote directory must be absolute path" }
  ),
  port: z.number().int().min(1).max(65535).default(22),
});

export const ProjectConfigSchema = z.object({
  name: z.string()
    .min(1)
    .max(64)
    .regex(/^[a-z0-9-]+$/, "Project name must be lowercase alphanumeric with hyphens only"),
  display_name: z.string().min(1),
  icon: z.string().default("📦"),
  working_dir: z.string().min(1),
  scope: z.enum(["scoped", "global"]).default("scoped"),
  remote: RemoteConfigSchema.optional().nullable(),
});

export const WorktreeConfigSchema = ProjectConfigSchema.extend({
  worktree_path: z.string().min(1),
  branch_name: z.string()
    .min(1)
    .regex(/^[a-zA-Z0-9/_-]+$/, "Invalid Git branch name format"),
  parent_project: z.string().min(1),
});

export type ProjectConfig = z.infer<typeof ProjectConfigSchema>;
export type WorktreeConfig = z.infer<typeof WorktreeConfigSchema>;
export type RemoteConfig = z.infer<typeof RemoteConfigSchema>;
```

---

## 2. Application Models

### 2.1 ApplicationConfig (Python Pydantic)

**File**: `home-modules/tools/i3_project_manager/models/app_config.py`

```python
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
```

### 2.2 ApplicationConfig (TypeScript Zod)

**File**: `home-modules/tools/i3_project_manager/models/app_config.ts`

```typescript
import { z } from "https://deno.land/x/zod@v3.22.4/mod.ts";

export const ApplicationConfigSchema = z.object({
  name: z.string().min(1).max(64).regex(/^[a-z0-9.-]+$/),
  display_name: z.string().min(1),
  command: z.string().min(1),
  parameters: z.array(z.string()).default([]),
  scope: z.enum(["scoped", "global"]).default("scoped"),
  expected_class: z.string().min(1),
  preferred_workspace: z.number().int().min(1).max(70),
  preferred_monitor_role: z.enum(["primary", "secondary", "tertiary"]).optional().nullable(),
  icon: z.string().default(""),
  nix_package: z.string().default("null"),
  multi_instance: z.boolean().default(false),
  floating: z.boolean().default(false),
  floating_size: z.enum(["scratchpad", "small", "medium", "large"]).optional().nullable(),
  fallback_behavior: z.enum(["skip", "create"]).default("skip"),
  description: z.string().default(""),
  terminal: z.boolean().default(false),
});

export const PWAConfigSchema = ApplicationConfigSchema.extend({
  name: z.string().regex(/^[a-z0-9.-]+-pwa$/, "PWA name must end with '-pwa'"),
  ulid: z.string().length(26).regex(
    /^[0-7][0-9A-HJKMNP-TV-Z]{25}$/,
    "Invalid ULID format (Crockford Base32, first char 0-7)"
  ),
  start_url: z.string().url(),
  scope_url: z.string().url(),
  expected_class: z.string().regex(/^FFPWA-[0-9A-HJKMNP-TV-Z]{26}$/),
  app_scope: z.enum(["scoped", "global"]).default("scoped"),
  categories: z.string().default("Network;"),
  keywords: z.string().default(""),
  preferred_workspace: z.number().int().min(50),
});

export type ApplicationConfig = z.infer<typeof ApplicationConfigSchema>;
export type PWAConfig = z.infer<typeof PWAConfigSchema>;
```

---

## 3. UI State Models

### 3.1 FormValidationState

**File**: `home-modules/tools/i3_project_manager/models/validation_state.py`

```python
from typing import Dict
from pydantic import BaseModel, Field

class FormValidationState(BaseModel):
    """
    Real-time form validation state for Eww UI

    Streamed to Eww via deflisten, updated on every keystroke (300ms debounce)
    """
    valid: bool = Field(..., description="True if all fields pass validation")
    errors: Dict[str, str] = Field(default_factory=dict, description="Field name → error message")
    warnings: Dict[str, str] = Field(default_factory=dict, description="Field name → warning message")

    model_config = {
        "json_schema_extra": {
            "examples": [
                {
                    "valid": False,
                    "errors": {
                        "project_name": "Project 'nixos' already exists",
                        "directory": "Directory does not exist: /invalid/path"
                    },
                    "warnings": {}
                },
                {
                    "valid": True,
                    "errors": {},
                    "warnings": {
                        "icon": "Custom icon path not found, will use default"
                    }
                }
            ]
        }
    }
```

### 3.2 ConflictResolutionState

**File**: `home-modules/tools/i3_project_manager/models/conflict_state.py`

```python
from pydantic import BaseModel, Field

class ConflictResolutionState(BaseModel):
    """
    File modification conflict detection state

    Per spec.md clarification Q2: Detect conflicts via file modification timestamp
    """
    has_conflict: bool = Field(..., description="True if file modified externally")
    file_mtime: float = Field(..., description="File modification timestamp (seconds since epoch)")
    ui_mtime: float = Field(..., description="UI edit start timestamp (seconds since epoch)")
    diff_preview: str = Field(default="", description="Side-by-side diff preview for UI display")

    model_config = {
        "json_schema_extra": {
            "examples": [
                {
                    "has_conflict": True,
                    "file_mtime": 1732468800.0,
                    "ui_mtime": 1732468700.0,
                    "diff_preview": "< file: working_dir = /old/path\n> ui: working_dir = /new/path"
                },
                {
                    "has_conflict": False,
                    "file_mtime": 1732468700.0,
                    "ui_mtime": 1732468700.0,
                    "diff_preview": ""
                }
            ]
        }
    }
```

### 3.3 CLIExecutionResult

**File**: `home-modules/tools/i3_project_manager/models/cli_result.py`

```python
from typing import Optional, Literal
from pydantic import BaseModel, Field

class CLIExecutionResult(BaseModel):
    """
    CLI command execution result with error categorization

    Per spec.md clarification Q3: Parse stderr/exit codes for actionable messages
    """
    success: bool = Field(..., description="True if command succeeded (exit code 0)")
    exit_code: int = Field(..., description="Process exit code")
    stdout: str = Field(default="", description="Standard output")
    stderr: str = Field(default="", description="Standard error")
    error_category: Optional[Literal["validation", "permission", "git", "timeout", "unknown"]] = Field(
        default=None, description="Categorized error type for user-friendly messages"
    )
    user_message: str = Field(default="", description="User-friendly error message with recovery steps")
    command: str = Field(..., description="Command that was executed")

    model_config = {
        "json_schema_extra": {
            "examples": [
                {
                    "success": False,
                    "exit_code": 1,
                    "stdout": "",
                    "stderr": "fatal: 'feature-096' is not a commit and a branch 'feature-096' cannot be created from it",
                    "error_category": "git",
                    "user_message": "Branch 'feature-096' not found. Available branches: main, develop, feature-095",
                    "command": "i3pm worktree create nixos feature-096 ~/projects/nixos-feature-096"
                },
                {
                    "success": True,
                    "exit_code": 0,
                    "stdout": "Worktree created successfully",
                    "stderr": "",
                    "error_category": None,
                    "user_message": "",
                    "command": "i3pm worktree create nixos feature-095 ~/projects/nixos-feature-095"
                }
            ]
        }
    }
```

---

## 4. Summary

### Model Count

- **Python Pydantic Models**: 10
  - ProjectConfig, RemoteConfig, WorktreeConfig
  - ApplicationConfig, TerminalAppConfig, PWAConfig
  - FormValidationState, ConflictResolutionState, CLIExecutionResult

- **TypeScript Zod Schemas**: 4
  - ProjectConfigSchema, WorktreeConfigSchema
  - ApplicationConfigSchema, PWAConfigSchema

### Validation Summary

| Model | Key Validators |
|-------|----------------|
| ProjectConfig | name format (lowercase-hyphen), working_dir exists, icon format |
| WorktreeConfig | branch name format, parent exists, path doesn't exist |
| ApplicationConfig | name format, command no metacharacters, workspace 1-50 |
| PWAConfig | ULID format (26 chars, Crockford Base32), URL format, workspace 50+ |
| FormValidationState | Field-level error/warning aggregation |
| ConflictResolutionState | File modification timestamp comparison |
| CLIExecutionResult | Exit code categorization, stderr parsing |

### Storage Mapping

| Model | Storage Location | Format |
|-------|------------------|--------|
| ProjectConfig | `~/.config/i3/projects/<name>.json` | JSON |
| WorktreeConfig | `~/.config/i3/projects/<name>.json` | JSON (with parent_project field) |
| ApplicationConfig | `home-modules/desktop/app-registry-data.nix` | Nix expression |
| PWAConfig | `shared/pwa-sites.nix` | Nix expression |
| FormValidationState | Streamed via deflisten (ephemeral) | JSON (stdout) |
| ConflictResolutionState | Generated on-demand (ephemeral) | JSON |
| CLIExecutionResult | Generated on-demand (ephemeral) | JSON |

### Next Steps

- **Phase 1 (continued)**: Generate API contracts for CRUD operations
- **Phase 1 (continued)**: Generate quickstart guide
- **Phase 2**: Generate tasks.md with implementation plan
