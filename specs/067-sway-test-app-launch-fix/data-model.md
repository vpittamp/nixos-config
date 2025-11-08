# Data Model: Sway Test Framework Enhancement

**Feature**: 067-sway-test-app-launch-fix
**Date**: 2025-11-08
**Phase**: 1 - Data Model Design

## Overview

This document defines the core entities, their relationships, and validation rules for the enhanced sway-test framework.

---

## Core Entities

### 1. AppRegistryEntry

**Purpose**: Represents an application definition from the I3PM application registry

**Fields**:
```typescript
interface AppRegistryEntry {
  app_name: string;           // Unique identifier (e.g., "firefox", "vscode")
  command: string;            // Launch command (e.g., "firefox", "code")
  preferred_workspace?: number; // Target workspace (1-70, optional)
  scope: "global" | "scoped"; // Visibility scope
  expected_class?: string;    // Expected Wayland app_id or X11 class
  pwas?: PWAEntry[];         // PWA definitions (for Firefox PWAs)
}

interface PWAEntry {
  id: string;                // PWA unique identifier
  expected_class: string;    // Expected window class (e.g., "FFPWA-01JCYF8Z2")
}
```

**Validation Rules**:
- `app_name` MUST be non-empty string, alphanumeric with hyphens
- `command` MUST be non-empty string
- `preferred_workspace` MUST be integer 1-70 if present
- `scope` MUST be exactly "global" or "scoped"
- `expected_class` MUST be non-empty string if present
- `pwas` array items MUST have valid `id` and `expected_class`

**Source**: Loaded from `~/.config/i3/application-registry.json`

**Relationships**:
- Referenced by `LaunchViaWrapperParams.app_name`
- Used to validate workspace assignment in tests

---

### 2. SwayEvent

**Purpose**: Represents an event from Sway IPC event stream

**Fields**:
```typescript
interface SwayEvent {
  change: string;             // Event change type (e.g., "new", "close", "focus")
  container?: SwayContainer;  // Window/container data (for window events)
  current?: SwayWorkspace;    // Workspace data (for workspace events)
  binding?: SwayBinding;      // Binding data (for binding events)
}

interface SwayContainer {
  id: number;                 // Unique container ID
  pid?: number;               // Process ID (if available)
  app_id?: string;            // Wayland app_id (e.g., "firefox")
  window_properties?: {
    class?: string;           // X11 window class
    instance?: string;        // X11 window instance
  };
  name: string;               // Window title
  type: string;               // Container type (e.g., "con", "floating_con")
  workspace?: number;         // Workspace number
}

interface SwayWorkspace {
  num: number;                // Workspace number
  name: string;               // Workspace name
  focused: boolean;           // Is workspace focused
  output: string;             // Output name (e.g., "HEADLESS-1")
}

interface SwayBinding {
  command: string;            // Bound command
  input_type: string;         // Input type (e.g., "keyboard")
  symbol: string;             // Key symbol (e.g., "Return")
  event_state_mask: string[]; // Modifiers (e.g., ["Mod4", "Shift"])
}
```

**Validation Rules**:
- `change` MUST be non-empty string
- For window events: `container` MUST be present
- For workspace events: `current` MUST be present
- For binding events: `binding` MUST be present
- Container `id` MUST be positive integer
- Workspace `num` MUST be positive integer

**Source**: Received from `swaymsg -t subscribe` stdout

**Relationships**:
- Used by `EventSubscription` to match criteria
- Returned by `waitForEvent()` function

---

### 3. EventSubscription

**Purpose**: Manages a Sway IPC event subscription with filtering

**Fields**:
```typescript
interface EventSubscription {
  id: string;                       // Unique subscription ID
  eventTypes: string[];             // Event types to subscribe to (e.g., ["window", "workspace"])
  criteria?: EventCriteria;         // Optional filtering criteria
  callback: (event: SwayEvent) => void; // Event handler function
  process: Deno.ChildProcess;       // swaymsg subprocess
  abortController: AbortController; // For cancellation
}

interface EventCriteria {
  app_id?: string;            // Match by app_id (exact or partial)
  window_class?: string;      // Match by X11 class (exact or partial)
  change?: string;            // Match by change type (e.g., "new", "close")
  workspace?: number;         // Match by workspace number
}
```

**Validation Rules**:
- `id` MUST be unique per subscription
- `eventTypes` MUST be non-empty array of valid Sway event types
- `callback` MUST be callable function
- `process` MUST be active Deno.ChildProcess
- Criteria fields are optional but if present MUST match type constraints

**Lifecycle**:
1. Created by `subscribeToEvents()`
2. Active during test execution
3. Canceled via `abortController.abort()`
4. Cleanup: subprocess terminated, resources freed

**Relationships**:
- Used by `waitForEvent()` to wait for specific events
- Managed by `EventSubscriberService`

---

### 4. WindowEnvironment

**Purpose**: Represents environment variables from a process (read from /proc/<pid>/environ)

**Fields**:
```typescript
interface WindowEnvironment {
  // I3PM-specific variables
  I3PM_APP_NAME?: string;         // App name from registry (e.g., "firefox")
  I3PM_APP_ID?: string;           // Full app ID (e.g., "firefox-nixos-123-456")
  I3PM_TARGET_WORKSPACE?: string; // Target workspace as string (e.g., "3")
  I3PM_PROJECT_NAME?: string;     // Project name (e.g., "nixos")
  I3PM_SCOPE?: string;            // Scope (e.g., "global", "scoped")

  // Generic environment variables
  [key: string]: string | undefined;
}
```

**Validation Rules**:
- All I3PM_* variables are optional (may not be present)
- `I3PM_TARGET_WORKSPACE` MUST be numeric string if present (e.g., "3", not "three")
- `I3PM_SCOPE` MUST be "global" or "scoped" if present
- Generic variables can be any key-value pairs

**Source**: Read from `/proc/<pid>/environ` file (null-separated pairs)

**Relationships**:
- Extracted by `readWindowEnvironment(pid)` function
- Validated by `validateI3pmEnvironment()` function
- Used in test assertions to verify environment variable injection

---

### 5. LaunchAppParams

**Purpose**: Parameters for launching an application (always via app-launcher-wrapper)

**Fields**:
```typescript
interface LaunchAppParams {
  app_name: string;          // App name from registry (e.g., "firefox") - REQUIRED
  args?: string[];           // Additional command-line arguments
  project?: string;          // Optional project context (sets I3PM_PROJECT_NAME)
  workspace?: number;        // Optional workspace override (sets I3PM_TARGET_WORKSPACE)
}
```

**Validation Rules**:
- `app_name` MUST exist in application registry (lookup fails if not found)
- `app_name` MUST be non-empty string, alphanumeric with hyphens
- `args` array items MUST be strings if provided
- `project` MUST be non-empty string if present
- `workspace` MUST be integer 1-70 if present

**Derived Values**:
- Wrapper script path: `~/.local/bin/app-launcher-wrapper.sh` (fails if not exists)
- Registry path: `~/.config/i3/application-registry.json` (fails if not exists)
- Environment variables injected by wrapper based on registry + params

**Relationships**:
- Used by `executeLaunchApp()` (only code path)
- References `AppRegistryEntry` by `app_name`

**Breaking Change**: Previously used `command` parameter with optional `via_wrapper` flag. Now ALWAYS uses wrapper with `app_name` parameter.

---

### 6. WaitEventParams

**Purpose**: Parameters for waiting for a Sway IPC event

**Fields**:
```typescript
interface WaitEventParams {
  event_type: string;        // Event type (e.g., "window", "workspace")
  timeout: number;           // Timeout in milliseconds (max 60000)
  criteria?: EventCriteria;  // Optional filtering criteria
}
```

**Validation Rules**:
- `event_type` MUST be valid Sway event type: "window", "workspace", "binding", "shutdown", "tick"
- `timeout` MUST be positive integer, max 60000 (60 seconds)
- `criteria` follows EventCriteria validation rules if present

**Behavior**:
- Returns immediately when matching event arrives
- Throws timeout error if timeout expires before event
- Cleans up subscription on success or failure

**Relationships**:
- Used by `executeWaitEvent()` action executor
- Creates `EventSubscription` internally

---

### 7. RPCMethodCache

**Purpose**: Caches available RPC methods from tree-monitor daemon

**Fields**:
```typescript
interface RPCMethodCache {
  available: Set<string> | null; // Set of method names, null = not loaded
  lastChecked: number;           // Timestamp of last check (ms since epoch)
  checkInterval: number;         // Recheck interval (default: never, session-level)
}
```

**Validation Rules**:
- `available` is `null` before first introspection call
- `available` is empty Set if introspection fails or daemon unavailable
- `lastChecked` is 0 before first check

**Behavior**:
- Lazy initialization: check on first method call
- Session-level caching: check once per framework run
- Fallback: empty set on introspection failure

**Relationships**:
- Used by `TreeMonitorClient.checkMethodAvailability()`
- Prevents repeated "Method not found" errors

---

## Entity Relationships Diagram

```
AppRegistryEntry
    ↑
    | (referenced by)
    |
LaunchAppParams -----> executeLaunchApp() -----> app-launcher-wrapper.sh
                                                       ↓
                                                  (spawns process)
                                                       ↓
                                                  Sway window
                                                       ↓
                                                  (emits event)
                                                       ↓
swaymsg -t subscribe -----> EventSubscription -----> SwayEvent
         ↓                       ↓                       ↓
    (stdout)               (filters)              (matches criteria)
                                ↓                       ↓
                          waitForEvent() <-------- WaitEventParams
                                ↓
                           (returns event)

Window PID -----> /proc/<pid>/environ -----> WindowEnvironment
                                                    ↓
                                              (validate I3PM_*)
```

---

## Validation Examples

### Valid AppRegistryEntry
```json
{
  "app_name": "firefox",
  "command": "firefox",
  "preferred_workspace": 3,
  "scope": "global",
  "expected_class": "firefox"
}
```

### Valid LaunchAppParams
```json
{
  "app_name": "vscode",
  "args": ["--folder-uri", "/etc/nixos"],
  "project": "nixos"
}
```

### Invalid LaunchAppParams (Breaking Change Examples)
```json
// OLD (no longer supported)
{
  "command": "firefox",
  "via_wrapper": true
}

// NEW (required format)
{
  "app_name": "firefox"
}

// OLD (no longer supported)
{
  "command": "bash",
  "args": ["-c", "echo hello"]
}

// NEW (must be in registry)
{
  "app_name": "terminal",  // Must exist in application-registry.json
  "args": ["-e", "echo hello"]
}
```

### Valid WaitEventParams
```json
{
  "event_type": "window",
  "timeout": 8000,
  "criteria": {
    "change": "new",
    "app_id": "firefox"
  }
}
```

### Valid WindowEnvironment
```typescript
{
  "I3PM_APP_NAME": "firefox",
  "I3PM_APP_ID": "firefox-global-1730000000-12345",
  "I3PM_TARGET_WORKSPACE": "3",
  "I3PM_SCOPE": "global",
  "HOME": "/home/user",
  "DISPLAY": ":0"
}
```

---

## Error States

### Missing App in Registry
```typescript
{
  error: "AppNotFoundError",
  app_name: "nonexistent-app",
  registry_path: "/home/user/.config/i3/application-registry.json",
  available_apps: ["firefox", "vscode", "thunar"]
}
```

### Wait Event Timeout
```typescript
{
  error: "WaitEventTimeoutError",
  event_type: "window",
  criteria: { change: "new", app_id: "firefox" },
  timeout_ms: 10000,
  last_tree_state: { workspaces: [...], windows: [...] }
}
```

### RPC Method Not Available
```typescript
{
  error: "RPCMethodUnavailableError",
  method: "sendSyncMarker",
  available_methods: ["ping", "getTree", "getEvents"],
  fallback: "timeout-based synchronization"
}
```

### Environment Variable Missing
```typescript
{
  error: "EnvironmentValidationError",
  pid: 12345,
  missing_variables: ["I3PM_APP_NAME", "I3PM_TARGET_WORKSPACE"],
  actual_env: { "HOME": "/home/user", ... }
}
```

---

## State Transitions

### Event Subscription Lifecycle
```
[Not Started] --subscribe()--> [Active]
                                  ↓
                          (event matches)
                                  ↓
                              [Matched] --callback()--> [Active]
                                  ↓
                           (timeout or abort)
                                  ↓
                            [Terminated] --cleanup()
```

### App Launch Lifecycle
```
[Test Action] --executeLaunchApp()--> [Validate Registry]
                                           ↓
                                      [Load App Entry]
                                           ↓
                                    [Invoke Wrapper Script]
                                           ↓
                                    [Wrapper Injects Env]
                                           ↓
                                    [Daemon Notification]
                                           ↓
                                    [swaymsg exec App]
                                           ↓
                                    [Window Appears]
                                           ↓
                                    [Event Emitted] --waitForEvent()--> [Test Continues]
```

### RPC Method Check Lifecycle
```
[First RPC Call] --checkMethodAvailability()--> [Introspection]
                                                       ↓
                                                (system.listMethods)
                                                       ↓
                                                  [Cache Methods]
                                                       ↓
                              [Subsequent Calls] --check cache--> [Use Method or Fallback]
```

---

## Zod Schemas (Implementation Reference)

```typescript
import { z } from "zod";

export const AppRegistryEntrySchema = z.object({
  app_name: z.string().min(1).regex(/^[a-z0-9-]+$/),
  command: z.string().min(1),
  preferred_workspace: z.number().int().min(1).max(70).optional(),
  scope: z.enum(["global", "scoped"]),
  expected_class: z.string().min(1).optional(),
  pwas: z.array(z.object({
    id: z.string().min(1),
    expected_class: z.string().min(1),
  })).optional(),
});

export const EventCriteriaSchema = z.object({
  app_id: z.string().optional(),
  window_class: z.string().optional(),
  change: z.string().optional(),
  workspace: z.number().int().min(1).max(70).optional(),
}).partial();

export const WaitEventParamsSchema = z.object({
  event_type: z.enum(["window", "workspace", "binding", "shutdown", "tick"]),
  timeout: z.number().int().min(1).max(60000),
  criteria: EventCriteriaSchema.optional(),
});

export const LaunchAppParamsSchema = z.object({
  app_name: z.string().min(1).regex(/^[a-z0-9-]+$/),  // Must match registry format
  args: z.array(z.string()).optional(),
  project: z.string().min(1).optional(),
  workspace: z.number().int().min(1).max(70).optional(),
});
```

---

## Notes

- All timestamps use milliseconds since epoch (JavaScript Date.now())
- Process IDs (PIDs) are positive integers from Linux kernel
- Workspace numbers are 1-indexed (Sway convention)
- Event types follow Sway IPC documentation (man 7 sway-ipc)
- Environment variables follow I3PM naming convention (I3PM_* prefix)
