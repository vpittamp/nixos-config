# Data Model: Declarative Workspace-to-Monitor Mapping

**Feature**: 033-declarative-workspace-to
**Date**: 2025-10-23
**Status**: Complete

## Overview

This document defines the data models used throughout the workspace-to-monitor mapping system, including:

1. **Configuration Models** - Pydantic models for JSON config file validation
2. **i3 State Models** - Models representing i3 IPC data (outputs, workspaces)
3. **TypeScript Interfaces** - Corresponding TypeScript types for Deno CLI
4. **Zod Validation Schemas** - Runtime validation schemas for type safety

---

## 1. Configuration File Models

### Python (Pydantic)

```python
# home-modules/tools/i3pm-daemon/models.py
from pydantic import BaseModel, Field, field_validator
from typing import Dict, List, Optional
from enum import Enum

class MonitorRole(str, Enum):
    """Monitor role assignment."""
    PRIMARY = "primary"
    SECONDARY = "secondary"
    TERTIARY = "tertiary"

class MonitorDistribution(BaseModel):
    """Workspace distribution for a specific monitor role."""
    primary: List[int] = Field(default_factory=list, description="Workspaces on primary monitor")
    secondary: List[int] = Field(default_factory=list, description="Workspaces on secondary monitor")
    tertiary: List[int] = Field(default_factory=list, description="Workspaces on tertiary monitor")

    @field_validator("primary", "secondary", "tertiary")
    def validate_workspace_numbers(cls, v):
        """Ensure workspace numbers are positive integers."""
        for ws_num in v:
            if ws_num <= 0:
                raise ValueError(f"Workspace number must be positive: {ws_num}")
        return v

class DistributionRules(BaseModel):
    """Distribution rules for different monitor counts."""
    one_monitor: MonitorDistribution = Field(
        alias="1_monitor",
        description="Distribution for 1-monitor setup"
    )
    two_monitors: MonitorDistribution = Field(
        alias="2_monitors",
        description="Distribution for 2-monitor setup"
    )
    three_monitors: MonitorDistribution = Field(
        alias="3_monitors",
        description="Distribution for 3+ monitor setup"
    )

class WorkspaceMonitorConfig(BaseModel):
    """Root configuration model for workspace-to-monitor mapping."""

    version: str = Field(default="1.0", description="Configuration version")

    distribution: DistributionRules = Field(
        description="Default workspace distribution rules by monitor count"
    )

    workspace_preferences: Dict[int, MonitorRole] = Field(
        default_factory=dict,
        description="Explicit workspace-to-role assignments (overrides distribution)"
    )

    output_preferences: Dict[MonitorRole, List[str]] = Field(
        default_factory=dict,
        description="Preferred output names for each role (with fallbacks)"
    )

    debounce_ms: int = Field(
        default=1000,
        ge=0,
        le=5000,
        description="Debounce delay for monitor change events (ms)"
    )

    enable_auto_reassign: bool = Field(
        default=True,
        description="Automatically reassign workspaces on monitor changes"
    )

    @field_validator("workspace_preferences")
    def validate_workspace_preferences(cls, v):
        """Ensure workspace numbers in preferences are positive integers."""
        for ws_num in v.keys():
            if ws_num <= 0:
                raise ValueError(f"Workspace number must be positive: {ws_num}")
        return v

    class Config:
        """Pydantic model configuration."""
        use_enum_values = True
        populate_by_name = True  # Allow both alias and field name
        json_schema_extra = {
            "example": {
                "version": "1.0",
                "distribution": {
                    "1_monitor": {"primary": [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]},
                    "2_monitors": {"primary": [1, 2], "secondary": [3, 4, 5, 6, 7, 8, 9, 10]},
                    "3_monitors": {"primary": [1, 2], "secondary": [3, 4, 5], "tertiary": [6, 7, 8, 9, 10]},
                },
                "workspace_preferences": {18: "secondary", 42: "tertiary"},
                "output_preferences": {
                    "primary": ["rdp0", "DP-1", "eDP-1"],
                    "secondary": ["rdp1", "HDMI-1"],
                    "tertiary": ["rdp2", "HDMI-2"],
                },
                "debounce_ms": 1000,
                "enable_auto_reassign": True,
            }
        }
```

### TypeScript (Zod)

```typescript
// home-modules/tools/i3pm-cli/src/models.ts
import { z } from "zod";

export const MonitorRoleSchema = z.enum(["primary", "secondary", "tertiary"]);
export type MonitorRole = z.infer<typeof MonitorRoleSchema>;

export const MonitorDistributionSchema = z.object({
  primary: z.array(z.number().int().positive()).default([]),
  secondary: z.array(z.number().int().positive()).default([]),
  tertiary: z.array(z.number().int().positive()).default([]),
});
export type MonitorDistribution = z.infer<typeof MonitorDistributionSchema>;

export const DistributionRulesSchema = z.object({
  "1_monitor": MonitorDistributionSchema,
  "2_monitors": MonitorDistributionSchema,
  "3_monitors": MonitorDistributionSchema,
});
export type DistributionRules = z.infer<typeof DistributionRulesSchema>;

export const WorkspaceMonitorConfigSchema = z.object({
  version: z.string().default("1.0"),
  distribution: DistributionRulesSchema,
  workspace_preferences: z.record(z.string(), MonitorRoleSchema).default({}),
  output_preferences: z.record(MonitorRoleSchema, z.array(z.string())).default({}),
  debounce_ms: z.number().int().min(0).max(5000).default(1000),
  enable_auto_reassign: z.boolean().default(true),
}).passthrough(); // Allow unknown fields for forward compatibility

export type WorkspaceMonitorConfig = z.infer<typeof WorkspaceMonitorConfigSchema>;

// Default configuration factory
export function createDefaultConfig(): WorkspaceMonitorConfig {
  return {
    version: "1.0",
    distribution: {
      "1_monitor": {
        primary: [1, 2, 3, 4, 5, 6, 7, 8, 9, 10],
        secondary: [],
        tertiary: [],
      },
      "2_monitors": {
        primary: [1, 2],
        secondary: [3, 4, 5, 6, 7, 8, 9, 10],
        tertiary: [],
      },
      "3_monitors": {
        primary: [1, 2],
        secondary: [3, 4, 5],
        tertiary: [6, 7, 8, 9, 10],
      },
    },
    workspace_preferences: {},
    output_preferences: {},
    debounce_ms: 1000,
    enable_auto_reassign: true,
  };
}
```

---

## 2. i3 State Models

### Monitor/Output Models

**Python (Pydantic)**:
```python
# home-modules/tools/i3pm-daemon/models.py
from pydantic import BaseModel, Field
from typing import Optional

class OutputRect(BaseModel):
    """Output geometry (position and size)."""
    x: int
    y: int
    width: int
    height: int

class MonitorConfig(BaseModel):
    """Represents a physical monitor/output."""

    name: str = Field(description="Output name from i3 IPC (e.g., rdp0, DP-1)")
    active: bool = Field(description="Whether output is currently active")
    primary: bool = Field(description="Whether this is the xrandr primary output")
    role: Optional[MonitorRole] = Field(None, description="Assigned role (primary/secondary/tertiary)")
    rect: OutputRect = Field(description="Output position and size")
    current_workspace: Optional[str] = Field(None, description="Workspace currently visible on this output")

    # Additional i3 output fields
    make: Optional[str] = Field(None, description="Monitor manufacturer")
    model: Optional[str] = Field(None, description="Monitor model")
    serial: Optional[str] = Field(None, description="Monitor serial number")

    @classmethod
    def from_i3_output(cls, output: object) -> "MonitorConfig":
        """Create MonitorConfig from i3ipc Output object."""
        return cls(
            name=output.name,
            active=output.active,
            primary=output.primary,
            rect=OutputRect(
                x=output.rect.x,
                y=output.rect.y,
                width=output.rect.width,
                height=output.rect.height,
            ),
            current_workspace=output.current_workspace,
            make=output.make,
            model=output.model,
            serial=output.serial,
        )
```

**TypeScript (Zod)**:
```typescript
// home-modules/tools/i3pm-cli/src/models.ts
export const OutputRectSchema = z.object({
  x: z.number().int(),
  y: z.number().int(),
  width: z.number().int().positive(),
  height: z.number().int().positive(),
});
export type OutputRect = z.infer<typeof OutputRectSchema>;

export const MonitorConfigSchema = z.object({
  name: z.string().min(1),
  active: z.boolean(),
  primary: z.boolean(),
  role: MonitorRoleSchema.nullable(),
  rect: OutputRectSchema,
  current_workspace: z.string().nullable(),
  make: z.string().nullable().optional(),
  model: z.string().nullable().optional(),
  serial: z.string().nullable().optional(),
});
export type MonitorConfig = z.infer<typeof MonitorConfigSchema>;
```

### Workspace Models

**Python (Pydantic)**:
```python
# home-modules/tools/i3pm-daemon/models.py
class WorkspaceAssignment(BaseModel):
    """Represents the assignment of a workspace to an output."""

    workspace_num: int = Field(description="Workspace number")
    output_name: Optional[str] = Field(None, description="Current output name (from i3 IPC)")
    target_role: Optional[MonitorRole] = Field(None, description="Target role (from config)")
    target_output: Optional[str] = Field(None, description="Resolved target output name")
    source: str = Field(description="Assignment source: 'default', 'explicit', 'runtime'")
    visible: bool = Field(description="Whether workspace is visible on an active output")
    window_count: int = Field(default=0, description="Number of windows on this workspace")

    @classmethod
    def from_i3_workspace(cls, workspace: object, target_role: Optional[MonitorRole] = None) -> "WorkspaceAssignment":
        """Create WorkspaceAssignment from i3ipc Workspace object."""
        return cls(
            workspace_num=workspace.num,
            output_name=workspace.output,
            target_role=target_role,
            source="runtime",  # Will be updated by assignment logic
            visible=workspace.visible,
        )
```

**TypeScript (Zod)**:
```typescript
// home-modules/tools/i3pm-cli/src/models.ts
export const WorkspaceAssignmentSchema = z.object({
  workspace_num: z.number().int().positive(),
  output_name: z.string().nullable(),
  target_role: MonitorRoleSchema.nullable(),
  target_output: z.string().nullable(),
  source: z.enum(["default", "explicit", "runtime"]),
  visible: z.boolean(),
  window_count: z.number().int().nonnegative().default(0),
});
export type WorkspaceAssignment = z.infer<typeof WorkspaceAssignmentSchema>;
```

---

## 3. System State Models

### Monitor System State

**Python (Pydantic)**:
```python
# home-modules/tools/i3pm-daemon/models.py
from typing import List

class MonitorSystemState(BaseModel):
    """Complete monitor and workspace state."""

    monitors: List[MonitorConfig] = Field(description="All detected monitors")
    workspaces: List[WorkspaceAssignment] = Field(description="All workspace assignments")
    active_monitor_count: int = Field(description="Number of active monitors")
    primary_output: Optional[str] = Field(None, description="Primary output name")
    last_updated: float = Field(description="Timestamp of last state update (Unix epoch)")

    @property
    def active_monitors(self) -> List[MonitorConfig]:
        """Get only active monitors."""
        return [m for m in self.monitors if m.active]

    @property
    def orphaned_workspaces(self) -> List[WorkspaceAssignment]:
        """Get workspaces on inactive outputs."""
        active_output_names = {m.name for m in self.active_monitors}
        return [ws for ws in self.workspaces if ws.output_name not in active_output_names]
```

**TypeScript (Zod)**:
```typescript
// home-modules/tools/i3pm-cli/src/models.ts
export const MonitorSystemStateSchema = z.object({
  monitors: z.array(MonitorConfigSchema),
  workspaces: z.array(WorkspaceAssignmentSchema),
  active_monitor_count: z.number().int().nonnegative(),
  primary_output: z.string().nullable(),
  last_updated: z.number(),
});
export type MonitorSystemState = z.infer<typeof MonitorSystemStateSchema>;
```

### Configuration Validation Result

**Python (Pydantic)**:
```python
# home-modules/tools/i3pm-daemon/models.py
class ValidationIssue(BaseModel):
    """Single validation issue."""
    severity: str = Field(description="Severity: 'error' or 'warning'")
    field: str = Field(description="Field path (e.g., 'distribution.2_monitors.primary')")
    message: str = Field(description="Human-readable error message")

class ConfigValidationResult(BaseModel):
    """Result of configuration validation."""
    valid: bool = Field(description="Whether configuration is valid")
    issues: List[ValidationIssue] = Field(default_factory=list, description="Validation issues")
    config: Optional[WorkspaceMonitorConfig] = Field(None, description="Parsed config if valid")

    @property
    def errors(self) -> List[ValidationIssue]:
        return [issue for issue in self.issues if issue.severity == "error"]

    @property
    def warnings(self) -> List[ValidationIssue]:
        return [issue for issue in self.issues if issue.severity == "warning"]
```

**TypeScript (Zod)**:
```typescript
// home-modules/tools/i3pm-cli/src/models.ts
export const ValidationIssueSchema = z.object({
  severity: z.enum(["error", "warning"]),
  field: z.string(),
  message: z.string(),
});
export type ValidationIssue = z.infer<typeof ValidationIssueSchema>;

export const ConfigValidationResultSchema = z.object({
  valid: z.boolean(),
  issues: z.array(ValidationIssueSchema).default([]),
  config: WorkspaceMonitorConfigSchema.nullable(),
});
export type ConfigValidationResult = z.infer<typeof ConfigValidationResultSchema>;
```

---

## 4. Daemon JSON-RPC API Models

### Request/Response Models

**TypeScript (Zod)**:
```typescript
// home-modules/tools/i3pm-cli/src/models.ts

// JSON-RPC Base
export const JsonRpcRequestSchema = z.object({
  jsonrpc: z.literal("2.0"),
  method: z.string(),
  params: z.unknown().optional(),
  id: z.number().int(),
});
export type JsonRpcRequest = z.infer<typeof JsonRpcRequestSchema>;

export const JsonRpcErrorSchema = z.object({
  code: z.number().int(),
  message: z.string(),
  data: z.unknown().optional(),
});
export type JsonRpcError = z.infer<typeof JsonRpcErrorSchema>;

export const JsonRpcResponseSchema = z.object({
  jsonrpc: z.literal("2.0"),
  result: z.unknown().optional(),
  error: JsonRpcErrorSchema.optional(),
  id: z.number().int(),
});
export type JsonRpcResponse = z.infer<typeof JsonRpcResponseSchema>;

// Specific Method Responses
export const GetMonitorsResponseSchema = z.array(MonitorConfigSchema);
export type GetMonitorsResponse = z.infer<typeof GetMonitorsResponseSchema>;

export const GetWorkspacesResponseSchema = z.array(WorkspaceAssignmentSchema);
export type GetWorkspacesResponse = z.infer<typeof GetWorkspacesResponseSchema>;

export const GetSystemStateResponseSchema = MonitorSystemStateSchema;
export type GetSystemStateResponse = z.infer<typeof GetSystemStateResponseSchema>;

export const GetConfigResponseSchema = WorkspaceMonitorConfigSchema;
export type GetConfigResponse = z.infer<typeof GetConfigResponseSchema>;

export const ValidateConfigResponseSchema = ConfigValidationResultSchema;
export type ValidateConfigResponse = z.infer<typeof ValidateConfigResponseSchema>;

export const ReassignWorkspacesResponseSchema = z.object({
  success: z.boolean(),
  assignments_made: z.number().int().nonnegative(),
  errors: z.array(z.string()).default([]),
});
export type ReassignWorkspacesResponse = z.infer<typeof ReassignWorkspacesResponseSchema>;

export const MoveWorkspaceResponseSchema = z.object({
  success: z.boolean(),
  workspace_num: z.number().int().positive(),
  from_output: z.string().nullable(),
  to_output: z.string(),
  error: z.string().nullable(),
});
export type MoveWorkspaceResponse = z.infer<typeof MoveWorkspaceResponseSchema>;
```

---

## 5. CLI Display Models

### Table Display Models

**TypeScript**:
```typescript
// home-modules/tools/i3pm-cli/src/ui/models.ts

export interface MonitorTableRow {
  output: string;
  active: string;
  primary: string;
  role: string;
  resolution: string;
  workspace: string;
}

export interface WorkspaceTableRow {
  workspace: string;
  output: string;
  role: string;
  windows: number;
  visible: string;
  source: string;
}

export interface DiagnosticReport {
  timestamp: string;
  active_monitors: number;
  total_workspaces: number;
  orphaned_workspaces: number;
  issues: Array<{
    severity: "error" | "warning" | "info";
    category: string;
    message: string;
    suggested_fix?: string;
  }>;
  recommendations: string[];
}
```

---

## 6. State Relationships

### Entity Relationship Diagram

```
WorkspaceMonitorConfig (JSON file)
  │
  ├─→ DistributionRules
  │     ├─→ MonitorDistribution (1_monitor)
  │     ├─→ MonitorDistribution (2_monitors)
  │     └─→ MonitorDistribution (3_monitors)
  │
  ├─→ workspace_preferences: Map<int, MonitorRole>
  └─→ output_preferences: Map<MonitorRole, List<str>>

MonitorSystemState (Runtime i3 IPC data)
  │
  ├─→ List<MonitorConfig> (from GET_OUTPUTS)
  │     ├─→ name, active, primary
  │     ├─→ role (assigned from config)
  │     └─→ rect (geometry)
  │
  └─→ List<WorkspaceAssignment> (from GET_WORKSPACES + config)
        ├─→ workspace_num
        ├─→ output_name (current, from i3)
        ├─→ target_role (from config)
        ├─→ target_output (resolved from role + output_preferences)
        └─→ source (default/explicit/runtime)
```

### Data Flow

```
1. Configuration Load
   JSON file → Pydantic validation → WorkspaceMonitorConfig

2. Monitor Detection
   i3 IPC GET_OUTPUTS → List<i3ipc.Output> → List<MonitorConfig>

3. Role Assignment
   MonitorConfig + output_preferences → MonitorConfig.role

4. Workspace Assignment Calculation
   workspace_num + config.distribution + config.workspace_preferences → target_role
   target_role + output_preferences + active MonitorConfigs → target_output

5. Workspace Redistribution
   WorkspaceAssignment.target_output → i3 IPC COMMAND (move workspace to output)

6. State Query (CLI)
   Daemon JSON-RPC → MonitorSystemState → TypeScript models → TUI rendering
```

---

## 7. Validation Rules

### Configuration Validation

**Python Implementation**:
```python
# home-modules/tools/i3pm-daemon/monitor_config_manager.py
from typing import List
from pathlib import Path
import json

class MonitorConfigManager:
    """Manages workspace-to-monitor configuration."""

    @staticmethod
    def validate_config_file(config_path: Path) -> ConfigValidationResult:
        """Validate configuration file and return structured result."""
        issues: List[ValidationIssue] = []

        # Check file exists
        if not config_path.exists():
            issues.append(ValidationIssue(
                severity="error",
                field="<root>",
                message=f"Configuration file not found: {config_path}"
            ))
            return ConfigValidationResult(valid=False, issues=issues)

        # Parse JSON
        try:
            with open(config_path) as f:
                data = json.load(f)
        except json.JSONDecodeError as e:
            issues.append(ValidationIssue(
                severity="error",
                field="<root>",
                message=f"Invalid JSON: {e.msg} at line {e.lineno}"
            ))
            return ConfigValidationResult(valid=False, issues=issues)

        # Validate with Pydantic
        try:
            config = WorkspaceMonitorConfig.model_validate(data)
        except ValidationError as e:
            for error in e.errors():
                issues.append(ValidationIssue(
                    severity="error",
                    field=".".join(str(loc) for loc in error["loc"]),
                    message=error["msg"]
                ))
            return ConfigValidationResult(valid=False, issues=issues)

        # Logical validation
        issues.extend(MonitorConfigManager._validate_distribution_logic(config))
        issues.extend(MonitorConfigManager._validate_workspace_preferences(config))

        has_errors = any(issue.severity == "error" for issue in issues)
        return ConfigValidationResult(
            valid=not has_errors,
            issues=issues,
            config=config if not has_errors else None
        )

    @staticmethod
    def _validate_distribution_logic(config: WorkspaceMonitorConfig) -> List[ValidationIssue]:
        """Validate distribution rules for logical consistency."""
        issues = []

        # Check for duplicate workspace assignments
        for monitor_count in ["1_monitor", "2_monitors", "3_monitors"]:
            dist = getattr(config.distribution, monitor_count.replace("-", "_"))
            all_workspaces = dist.primary + dist.secondary + dist.tertiary

            if len(all_workspaces) != len(set(all_workspaces)):
                duplicates = [ws for ws in all_workspaces if all_workspaces.count(ws) > 1]
                issues.append(ValidationIssue(
                    severity="error",
                    field=f"distribution.{monitor_count}",
                    message=f"Duplicate workspace assignments: {set(duplicates)}"
                ))

        return issues

    @staticmethod
    def _validate_workspace_preferences(config: WorkspaceMonitorConfig) -> List[ValidationIssue]:
        """Validate workspace preferences for conflicts."""
        issues = []

        # Warn if workspace preference conflicts with default distribution
        for ws_num, role in config.workspace_preferences.items():
            for monitor_count in ["1_monitor", "2_monitors", "3_monitors"]:
                dist = getattr(config.distribution, monitor_count.replace("-", "_"))
                role_workspaces = getattr(dist, role)

                if ws_num not in role_workspaces:
                    issues.append(ValidationIssue(
                        severity="warning",
                        field=f"workspace_preferences.{ws_num}",
                        message=(
                            f"Workspace {ws_num} assigned to '{role}' but not in "
                            f"{monitor_count}.{role} distribution. Explicit preference takes precedence."
                        )
                    ))

        return issues
```

---

## 8. Default Values

### Default Configuration

```json
{
  "version": "1.0",
  "distribution": {
    "1_monitor": {
      "primary": [1, 2, 3, 4, 5, 6, 7, 8, 9, 10],
      "secondary": [],
      "tertiary": []
    },
    "2_monitors": {
      "primary": [1, 2],
      "secondary": [3, 4, 5, 6, 7, 8, 9, 10],
      "tertiary": []
    },
    "3_monitors": {
      "primary": [1, 2],
      "secondary": [3, 4, 5],
      "tertiary": [6, 7, 8, 9, 10]
    }
  },
  "workspace_preferences": {},
  "output_preferences": {},
  "debounce_ms": 1000,
  "enable_auto_reassign": true
}
```

### Generated via NixOS Module

```nix
# home-modules/tools/i3pm-daemon/default.nix
{ config, lib, pkgs, ... }:

{
  xdg.configFile."i3/workspace-monitor-mapping.json" = {
    text = builtins.toJSON {
      version = "1.0";
      distribution = {
        "1_monitor" = {
          primary = [ 1 2 3 4 5 6 7 8 9 10 ];
          secondary = [];
          tertiary = [];
        };
        "2_monitors" = {
          primary = [ 1 2 ];
          secondary = [ 3 4 5 6 7 8 9 10 ];
          tertiary = [];
        };
        "3_monitors" = {
          primary = [ 1 2 ];
          secondary = [ 3 4 5 ];
          tertiary = [ 6 7 8 9 10 ];
        };
      };
      workspace_preferences = {};
      output_preferences = {};
      debounce_ms = 1000;
      enable_auto_reassign = true;
    };
  };
}
```

---

## 9. Model Testing

### Python Unit Tests

```python
# tests/i3pm-monitors/python/unit/test_models.py
import pytest
from pydantic import ValidationError
from models import WorkspaceMonitorConfig, MonitorConfig, OutputRect

def test_valid_config():
    """Test valid configuration parses successfully."""
    config_data = {
        "version": "1.0",
        "distribution": {
            "1_monitor": {"primary": [1, 2, 3]},
            "2_monitors": {"primary": [1, 2], "secondary": [3]},
            "3_monitors": {"primary": [1], "secondary": [2], "tertiary": [3]},
        },
        "debounce_ms": 500,
    }
    config = WorkspaceMonitorConfig.model_validate(config_data)
    assert config.version == "1.0"
    assert config.debounce_ms == 500

def test_invalid_workspace_number():
    """Test validation rejects negative workspace numbers."""
    config_data = {
        "distribution": {
            "1_monitor": {"primary": [1, -5, 3]},  # Invalid: -5
            "2_monitors": {"primary": [1], "secondary": [2]},
            "3_monitors": {"primary": [1], "secondary": [2], "tertiary": [3]},
        }
    }
    with pytest.raises(ValidationError) as exc:
        WorkspaceMonitorConfig.model_validate(config_data)
    assert "positive" in str(exc.value).lower()

def test_monitor_config_from_i3_output():
    """Test creating MonitorConfig from i3ipc Output mock."""
    # Mock i3ipc.Output
    class MockOutput:
        def __init__(self):
            self.name = "rdp0"
            self.active = True
            self.primary = True
            self.current_workspace = "1"
            self.rect = type('obj', (object,), {'x': 0, 'y': 0, 'width': 1920, 'height': 1080})()
            self.make = "Generic"
            self.model = "Monitor"
            self.serial = "12345"

    output = MockOutput()
    monitor = MonitorConfig.from_i3_output(output)

    assert monitor.name == "rdp0"
    assert monitor.active is True
    assert monitor.primary is True
    assert monitor.rect.width == 1920
```

### TypeScript Unit Tests

```typescript
// tests/i3pm-monitors/typescript/models_test.ts
import { assertEquals, assertThrows } from "@std/assert";
import { WorkspaceMonitorConfigSchema, createDefaultConfig } from "../src/models.ts";

Deno.test("Valid config parses successfully", () => {
  const configData = {
    version: "1.0",
    distribution: {
      "1_monitor": { primary: [1, 2, 3], secondary: [], tertiary: [] },
      "2_monitors": { primary: [1, 2], secondary: [3], tertiary: [] },
      "3_monitors": { primary: [1], secondary: [2], tertiary: [3] },
    },
    workspace_preferences: {},
    output_preferences: {},
    debounce_ms: 500,
    enable_auto_reassign: true,
  };

  const config = WorkspaceMonitorConfigSchema.parse(configData);
  assertEquals(config.version, "1.0");
  assertEquals(config.debounce_ms, 500);
});

Deno.test("Invalid debounce_ms rejected", () => {
  const configData = {
    ...createDefaultConfig(),
    debounce_ms: 10000, // Exceeds max 5000
  };

  assertThrows(
    () => WorkspaceMonitorConfigSchema.parse(configData),
    Error,
    "too_big"
  );
});

Deno.test("Default config creation", () => {
  const config = createDefaultConfig();
  assertEquals(config.version, "1.0");
  assertEquals(config.distribution["1_monitor"].primary.length, 10);
  assertEquals(config.distribution["2_monitors"].primary.length, 2);
  assertEquals(config.distribution["2_monitors"].secondary.length, 8);
});
```

---

## Summary

This data model specification provides:

1. **Type Safety**: Pydantic (Python) and Zod (TypeScript) for compile-time and runtime validation
2. **Consistency**: Matching models across Python daemon and Deno CLI
3. **Validation**: Comprehensive field validation with clear error messages
4. **Extensibility**: `.passthrough()` for forward compatibility
5. **Documentation**: Inline field descriptions for generated documentation
6. **Testability**: Unit tests for all critical validation paths

**Next Steps**: Generate API contracts (JSON-RPC method definitions) based on these models.
