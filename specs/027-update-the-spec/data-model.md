# Data Model: i3pm Deno CLI Type Definitions

**Feature**: Complete i3pm Deno CLI with Extensible Architecture
**Date**: 2025-10-22
**Status**: Design Complete

---

## Overview

This document defines the TypeScript type definitions for all entities in the i3pm CLI. These types serve as contracts between the daemon (via JSON-RPC) and the CLI, ensuring type safety throughout the application. All types include optional Zod schemas for runtime validation.

---

## Core Window Management Entities

### WindowState

Represents a single window with complete state information including project scoping, visibility, and geometry.

**TypeScript Type**:
```typescript
export interface WindowState {
  /** Unique window identifier from i3 */
  id: number;

  /** Window class (application identifier) */
  class: string;

  /** Window instance (optional sub-identifier) */
  instance?: string;

  /** Current window title */
  title: string;

  /** Workspace where window resides (e.g., "1", "2:web", "9") */
  workspace: string;

  /** Output (monitor) where workspace is displayed */
  output: string;

  /** i3 marks assigned to window (including project mark like "project:nixos") */
  marks: string[];

  /** Whether window has focus */
  focused: boolean;

  /** Whether window is currently hidden (scoped to inactive project) */
  hidden: boolean;

  /** Whether window is floating (not tiled) */
  floating: boolean;

  /** Whether window is in fullscreen mode */
  fullscreen: boolean;

  /** Window geometry (position and size) */
  geometry: WindowGeometry;
}

export interface WindowGeometry {
  /** X coordinate in pixels */
  x: number;

  /** Y coordinate in pixels */
  y: number;

  /** Width in pixels */
  width: number;

  /** Height in pixels */
  height: number;
}
```

**Zod Schema**:
```typescript
import { z } from "https://deno.land/x/zod/mod.ts";

export const WindowGeometrySchema = z.object({
  x: z.number(),
  y: z.number(),
  width: z.number(),
  height: z.number(),
});

export const WindowStateSchema = z.object({
  id: z.number(),
  class: z.string(),
  instance: z.string().optional(),
  title: z.string(),
  workspace: z.string(),
  output: z.string(),
  marks: z.array(z.string()),
  focused: z.boolean(),
  hidden: z.boolean(),
  floating: z.boolean(),
  fullscreen: z.boolean(),
  geometry: WindowGeometrySchema,
});

// Runtime type from schema
export type WindowStateValidated = z.infer<typeof WindowStateSchema>;
```

**Validation Rules**:
- `id` must be positive integer
- `class` must be non-empty string
- `workspace` must match pattern: `\d+(:.*)?`
- `output` must be valid output name from i3 (e.g., "eDP-1", "HDMI-1", "Virtual-1")
- `marks` may be empty array
- `geometry` all fields must be non-negative integers

**State Transitions**:
- `focused`: Changes on window focus events
- `hidden`: Changes on project switch (mark addition/removal)
- `floating`/`fullscreen`: Changes on layout mode events
- `title`: Changes on window title update events
- `workspace`/`output`: Changes on window move events

---

### Workspace

Represents an i3 workspace with assigned windows and output mapping.

**TypeScript Type**:
```typescript
export interface Workspace {
  /** Workspace number (1-9 typically) */
  number: number;

  /** Workspace name (e.g., "1:web", "2:code", "3") */
  name: string;

  /** Whether workspace has focus */
  focused: boolean;

  /** Whether workspace is visible on any output */
  visible: boolean;

  /** Output (monitor) where workspace is currently assigned */
  output: string;

  /** Windows contained in this workspace */
  windows: WindowState[];
}
```

**Zod Schema**:
```typescript
export const WorkspaceSchema = z.object({
  number: z.number().int().min(1).max(999),
  name: z.string().min(1),
  focused: z.boolean(),
  visible: z.boolean(),
  output: z.string().min(1),
  windows: z.array(WindowStateSchema),
});

export type WorkspaceValidated = z.infer<typeof WorkspaceSchema>;
```

**Validation Rules**:
- `number` must be integer between 1 and 999
- `name` must be non-empty string
- `output` must be valid output name
- `windows` may be empty array
- Only one workspace per output can be `visible: true` at a time

**Relationships**:
- **Workspace → Output**: Many-to-one (many workspaces assigned to one output)
- **Workspace → Windows**: One-to-many (workspace contains multiple windows)

---

### Output

Represents a monitor/display with assigned workspaces and active state.

**TypeScript Type**:
```typescript
export interface Output {
  /** Output name from i3 (e.g., "eDP-1", "HDMI-1", "Virtual-1") */
  name: string;

  /** Whether output is currently active (connected and enabled) */
  active: boolean;

  /** Whether output is the primary monitor */
  primary: boolean;

  /** Output geometry (position and resolution) */
  geometry: OutputGeometry;

  /** Name of currently visible workspace on this output */
  current_workspace: string;

  /** All workspaces assigned to this output */
  workspaces: Workspace[];
}

export interface OutputGeometry {
  /** X coordinate in virtual screen space */
  x: number;

  /** Y coordinate in virtual screen space */
  y: number;

  /** Width in pixels (resolution) */
  width: number;

  /** Height in pixels (resolution) */
  height: number;
}
```

**Zod Schema**:
```typescript
export const OutputGeometrySchema = z.object({
  x: z.number(),
  y: z.number(),
  width: z.number().int().positive(),
  height: z.number().int().positive(),
});

export const OutputSchema = z.object({
  name: z.string().min(1),
  active: z.boolean(),
  primary: z.boolean(),
  geometry: OutputGeometrySchema,
  current_workspace: z.string().min(1),
  workspaces: z.array(WorkspaceSchema),
});

export type OutputValidated = z.infer<typeof OutputSchema>;
```

**Validation Rules**:
- `name` must be non-empty string (typically "eDP-1", "HDMI-1", "Virtual-1", etc.)
- `geometry.width` and `geometry.height` must be positive integers
- `current_workspace` must reference a workspace in `workspaces` array
- Only one output can be `primary: true` at a time
- `workspaces` may be empty array for inactive outputs

**Relationships**:
- **Output → Workspaces**: One-to-many (output has multiple assigned workspaces)
- **Output → Current Workspace**: One-to-one (output shows one visible workspace)

---

## Project Management Entities

### Project

Represents a project context with directory, icon, and scoped window classes.

**TypeScript Type**:
```typescript
export interface Project {
  /** Unique project identifier (slug) */
  name: string;

  /** Human-readable display name */
  display_name: string;

  /** Emoji or Unicode icon for visual identification */
  icon: string;

  /** Absolute path to project directory */
  directory: string;

  /** List of window classes that are scoped to this project */
  scoped_classes: string[];

  /** Unix timestamp when project was created */
  created_at: number;

  /** Unix timestamp when project was last activated */
  last_used_at: number;
}
```

**Zod Schema**:
```typescript
export const ProjectSchema = z.object({
  name: z.string().regex(/^[a-z0-9-]+$/, "Project name must be lowercase alphanumeric with hyphens"),
  display_name: z.string().min(1),
  icon: z.string().max(4), // Unicode emoji typically 1-4 bytes
  directory: z.string().min(1).regex(/^\//, "Directory must be absolute path"),
  scoped_classes: z.array(z.string()),
  created_at: z.number().int().positive(),
  last_used_at: z.number().int().positive(),
});

export type ProjectValidated = z.infer<typeof ProjectSchema>;
```

**Validation Rules**:
- `name` must be lowercase alphanumeric with hyphens only (URL-safe)
- `display_name` must be non-empty string
- `icon` must be single emoji or Unicode character (max 4 bytes)
- `directory` must be absolute path starting with `/`
- `directory` should exist (validated at creation, warned if missing during switch)
- `scoped_classes` may be empty array (project with no scoped windows)
- `created_at` and `last_used_at` must be Unix timestamps (seconds since epoch)

**Example**:
```typescript
const nixosProject: Project = {
  name: "nixos",
  display_name: "NixOS",
  icon: "",
  directory: "/etc/nixos",
  scoped_classes: ["Ghostty", "code-url-handler"],
  created_at: 1698000000,
  last_used_at: 1698012345,
};
```

---

## Event System Entities

### EventNotification

Represents a real-time update from the daemon via JSON-RPC notification.

**TypeScript Type**:
```typescript
export interface EventNotification {
  /** Sequential event ID (monotonically increasing) */
  event_id: number;

  /** Type of i3 event */
  event_type: EventType;

  /** Specific change within event type */
  change: string;

  /** Affected container/window/workspace data */
  container: WindowState | Workspace | Output | null;

  /** Unix timestamp when event occurred (milliseconds) */
  timestamp: number;
}

export enum EventType {
  Window = "window",
  Workspace = "workspace",
  Output = "output",
  Binding = "binding",
  Shutdown = "shutdown",
  Tick = "tick",
}

export const WindowChangeType = {
  New: "new",
  Close: "close",
  Focus: "focus",
  Title: "title",
  FullscreenMode: "fullscreen_mode",
  Move: "move",
  Floating: "floating",
  Urgent: "urgent",
  Mark: "mark",
} as const;

export const WorkspaceChangeType = {
  Focus: "focus",
  Init: "init",
  Empty: "empty",
  Urgent: "urgent",
  Rename: "rename",
  Move: "move",
  Reload: "reload",
} as const;
```

**Zod Schema**:
```typescript
export const EventTypeSchema = z.enum(["window", "workspace", "output", "binding", "shutdown", "tick"]);

export const EventNotificationSchema = z.object({
  event_id: z.number().int().nonnegative(),
  event_type: EventTypeSchema,
  change: z.string(),
  container: z.union([WindowStateSchema, WorkspaceSchema, OutputSchema, z.null()]),
  timestamp: z.number().int().positive(),
});

export type EventNotificationValidated = z.infer<typeof EventNotificationSchema>;
```

**Validation Rules**:
- `event_id` must be non-negative integer (starts at 0)
- `event_type` must be one of: window, workspace, output, binding, shutdown, tick
- `change` must be non-empty string (specific to event_type)
- `container` may be null for certain event types (e.g., tick, shutdown)
- `timestamp` must be Unix timestamp in milliseconds

**Event Processing**:
- Events are processed sequentially by `event_id`
- Live TUI subscribes to `window`, `workspace`, `output` events
- Monitor dashboard subscribes to all event types

---

## Daemon Status Entities

### DaemonStatus

Represents current daemon state and connection information.

**TypeScript Type**:
```typescript
export interface DaemonStatus {
  /** Status string: "running" or "stopped" */
  status: "running" | "stopped";

  /** Whether daemon is connected to i3 IPC */
  connected: boolean;

  /** Daemon uptime in seconds */
  uptime: number;

  /** Name of currently active project (or null for global mode) */
  active_project: string | null;

  /** Total number of tracked windows */
  window_count: number;

  /** Total number of workspaces */
  workspace_count: number;

  /** Total number of processed events since daemon start */
  event_count: number;

  /** Number of errors encountered since daemon start */
  error_count: number;

  /** Daemon version string */
  version: string;

  /** Unix socket path for IPC */
  socket_path: string;
}
```

**Zod Schema**:
```typescript
export const DaemonStatusSchema = z.object({
  status: z.enum(["running", "stopped"]),
  connected: z.boolean(),
  uptime: z.number().nonnegative(),
  active_project: z.string().nullable(),
  window_count: z.number().int().nonnegative(),
  workspace_count: z.number().int().nonnegative(),
  event_count: z.number().int().nonnegative(),
  error_count: z.number().int().nonnegative(),
  version: z.string(),
  socket_path: z.string().min(1),
});

export type DaemonStatusValidated = z.infer<typeof DaemonStatusSchema>;
```

**Validation Rules**:
- `status` must be "running" or "stopped"
- `uptime` must be non-negative number (seconds)
- `active_project` may be null (global mode)
- All count fields must be non-negative integers
- `version` follows semantic versioning (e.g., "1.0.0")
- `socket_path` must be non-empty string (typically absolute path)

---

## Window Classification Entities

### WindowRule

Represents a rule for classifying windows as scoped or global.

**TypeScript Type**:
```typescript
export interface WindowRule {
  /** Unique rule identifier */
  rule_id: string;

  /** Window class pattern (regex) */
  class_pattern: string;

  /** Window instance pattern (optional regex) */
  instance_pattern?: string;

  /** Scope assignment: "scoped" or "global" */
  scope: "scoped" | "global";

  /** Rule priority (higher priority wins on conflicts) */
  priority: number;

  /** Whether rule is enabled */
  enabled: boolean;
}
```

**Zod Schema**:
```typescript
export const WindowRuleSchema = z.object({
  rule_id: z.string().uuid(),
  class_pattern: z.string().min(1),
  instance_pattern: z.string().optional(),
  scope: z.enum(["scoped", "global"]),
  priority: z.number().int().nonnegative(),
  enabled: z.boolean(),
});

export type WindowRuleValidated = z.infer<typeof WindowRuleSchema>;
```

**Validation Rules**:
- `rule_id` must be valid UUID v4
- `class_pattern` must be valid regex pattern
- `instance_pattern` must be valid regex pattern if provided
- `scope` must be "scoped" or "global"
- `priority` must be non-negative integer (higher = higher priority)
- Rules with higher priority override lower priority on conflicts

---

### ApplicationClass

Represents an application with classification metadata.

**TypeScript Type**:
```typescript
export interface ApplicationClass {
  /** Window class name (from i3) */
  class_name: string;

  /** Human-readable display name */
  display_name: string;

  /** Scope: "scoped" (project-specific) or "global" (always visible) */
  scope: "scoped" | "global";

  /** Icon for visual identification (emoji or Unicode) */
  icon?: string;

  /** Description of application purpose */
  description?: string;
}
```

**Zod Schema**:
```typescript
export const ApplicationClassSchema = z.object({
  class_name: z.string().min(1),
  display_name: z.string().min(1),
  scope: z.enum(["scoped", "global"]),
  icon: z.string().max(4).optional(),
  description: z.string().optional(),
});

export type ApplicationClassValidated = z.infer<typeof ApplicationClassSchema>;
```

**Validation Rules**:
- `class_name` must be non-empty string (matches window class from i3)
- `display_name` must be non-empty string
- `scope` must be "scoped" or "global"
- `icon` optional emoji (max 4 bytes)
- `description` optional text

**Example**:
```typescript
const ghosttyApp: ApplicationClass = {
  class_name: "Ghostty",
  display_name: "Ghostty Terminal",
  scope: "scoped",
  icon: "",
  description: "Project-scoped terminal emulator",
};

const firefoxApp: ApplicationClass = {
  class_name: "firefox",
  display_name: "Firefox Browser",
  scope: "global",
  icon: "",
  description: "Global web browser always visible",
};
```

---

## JSON-RPC Protocol Types

### Request Types

Request messages sent from CLI to daemon.

**TypeScript Type**:
```typescript
export interface JsonRpcRequest<P = unknown> {
  jsonrpc: "2.0";
  method: string;
  params?: P;
  id: number;
}

// Specific request parameter types
export interface GetWindowsParams {
  filter?: {
    workspace?: string;
    output?: string;
    project?: string;
    hidden?: boolean;
  };
}

export interface SwitchProjectParams {
  project_name: string;
}

export interface GetEventsParams {
  limit?: number;
  since_id?: number;
  event_type?: EventType;
}
```

### Response Types

Response messages received from daemon.

**TypeScript Type**:
```typescript
export interface JsonRpcResponse<T = unknown> {
  jsonrpc: "2.0";
  result?: T;
  error?: JsonRpcError;
  id: number;
}

export interface JsonRpcError {
  code: number;
  message: string;
  data?: unknown;
}

// Standard JSON-RPC error codes
export enum JsonRpcErrorCode {
  ParseError = -32700,
  InvalidRequest = -32600,
  MethodNotFound = -32601,
  InvalidParams = -32602,
  InternalError = -32603,
  ServerError = -32000,
}
```

### Notification Types

Server-initiated notifications (events) sent from daemon to CLI.

**TypeScript Type**:
```typescript
export interface JsonRpcNotification<P = unknown> {
  jsonrpc: "2.0";
  method: string;
  params?: P;
}

// Event notification params
export interface EventNotificationParams {
  event: EventNotification;
}
```

---

## CLI-Specific Types

### Command Options

Options for CLI command parsing.

**TypeScript Type**:
```typescript
// Global CLI options (available on all commands)
export interface GlobalOptions {
  help: boolean;
  version: boolean;
  verbose: boolean;
  debug: boolean;
}

// Parent command: i3pm windows
export interface WindowsOptions extends GlobalOptions {
  tree: boolean;
  table: boolean;
  json: boolean;
  live: boolean;
  hidden: boolean;
  project?: string;
  output?: string;
}

// Parent command: i3pm project
export interface ProjectOptions extends GlobalOptions {
  name?: string;
  dir?: string;
  icon?: string;
  displayName?: string;
}

// Parent command: i3pm daemon
export interface DaemonOptions extends GlobalOptions {
  limit?: number;
  type?: EventType;
  sinceId?: number;
}
```

---

## Type Exports Module Structure

**File**: `src/models.ts`

```typescript
// Core entities
export type {
  WindowState,
  WindowGeometry,
  Workspace,
  Output,
  OutputGeometry,
  Project,
};

// Event system
export type { EventNotification };
export { EventType, WindowChangeType, WorkspaceChangeType };

// Daemon status
export type { DaemonStatus };

// Window classification
export type { WindowRule, ApplicationClass };

// JSON-RPC protocol
export type {
  JsonRpcRequest,
  JsonRpcResponse,
  JsonRpcNotification,
  JsonRpcError,
};
export { JsonRpcErrorCode };

// Request/Response params
export type {
  GetWindowsParams,
  SwitchProjectParams,
  GetEventsParams,
  EventNotificationParams,
};

// CLI options
export type {
  GlobalOptions,
  WindowsOptions,
  ProjectOptions,
  DaemonOptions,
};

// Zod schemas (optional validation)
export {
  WindowStateSchema,
  WorkspaceSchema,
  OutputSchema,
  ProjectSchema,
  EventNotificationSchema,
  DaemonStatusSchema,
  WindowRuleSchema,
  ApplicationClassSchema,
};
```

---

## Entity Relationships Diagram

```
Output (Monitor)
├── has many Workspaces
│   ├── has one current_workspace (visible)
│   └── Workspace
│       └── has many Windows
│           └── WindowState
│               ├── has many marks (including project mark)
│               └── belongs to Workspace
│                   └── assigned to Output

Project
├── has many scoped_classes (ApplicationClass references)
└── creates marks on Windows (project:nixos)

WindowRule
├── matches WindowState by class/instance pattern
└── assigns scope (scoped or global)

EventNotification
├── references WindowState | Workspace | Output (container)
└── triggers UI updates in live mode
```

---

## Summary

This data model provides:
1. **Type Safety**: All daemon responses validated at compile-time and optionally at runtime
2. **Clear Contracts**: Explicit interfaces between CLI and daemon via JSON-RPC
3. **Extensibility**: Easy to add new entity types or fields without breaking existing code
4. **Validation**: Zod schemas for runtime validation of untrusted data
5. **Documentation**: TypeScript types serve as executable documentation

All types align with Key Entities from spec.md and support all functional requirements (FR-001 through FR-060).
