# API Functions Contract

**Feature**: 067-sway-test-app-launch-fix
**Date**: 2025-11-08

## Overview

This document defines the public API contracts for functions added or modified in this feature.

---

## Event Subscription Functions

### `subscribeToEvents()`

**Purpose**: Subscribe to Sway IPC events with filtering criteria

**Signature**:
```typescript
function subscribeToEvents(
  eventTypes: string[],
  criteria?: EventCriteria,
  callback: (event: SwayEvent) => void
): EventSubscription
```

**Parameters**:
- `eventTypes`: Array of Sway event types ("window", "workspace", "binding", "shutdown", "tick")
- `criteria`: Optional filtering criteria (app_id, window_class, change, workspace)
- `callback`: Function called for each matching event

**Returns**: `EventSubscription` object with `unsubscribe()` method

**Errors**:
- Throws `Error` if swaymsg subprocess fails to start
- Throws `Error` if eventTypes is empty array

**Example**:
```typescript
const subscription = subscribeToEvents(
  ["window"],
  { change: "new", app_id: "firefox" },
  (event) => {
    console.log("Firefox window created:", event.container.id);
  }
);

// Later: cleanup
subscription.unsubscribe();
```

---

### `waitForEvent()`

**Purpose**: Wait for a specific Sway IPC event with timeout

**Signature**:
```typescript
async function waitForEvent(
  eventType: string,
  criteria?: EventCriteria,
  timeoutMs: number = 10000
): Promise<SwayEvent>
```

**Parameters**:
- `eventType`: Single Sway event type to wait for
- `criteria`: Optional filtering criteria
- `timeoutMs`: Timeout in milliseconds (default 10000, max 60000)

**Returns**: Promise that resolves to the matching `SwayEvent`

**Errors**:
- Throws `WaitEventTimeoutError` if timeout expires before event arrives
- Throws `Error` if eventType is invalid

**Behavior**:
- Returns immediately when matching event arrives (does not wait for full timeout)
- Cleans up subscription automatically on success or failure
- Captures last Sway tree state on timeout for diagnostics

**Example**:
```typescript
try {
  const event = await waitForEvent(
    "window",
    { change: "new", app_id: "firefox" },
    8000
  );
  console.log("Firefox window appeared:", event.container.pid);
} catch (error) {
  if (error instanceof WaitEventTimeoutError) {
    console.error("Timeout waiting for Firefox window");
  }
}
```

---

## App Registry Functions

### `loadAppRegistry()`

**Purpose**: Load and validate application registry from JSON file

**Signature**:
```typescript
async function loadAppRegistry(
  registryPath?: string
): Promise<Map<string, AppRegistryEntry>>
```

**Parameters**:
- `registryPath`: Optional path to registry file (default: `~/.config/i3/application-registry.json`)

**Returns**: Map of app_name → AppRegistryEntry

**Errors**:
- Throws `Error` if registry file not found
- Throws `ZodError` if registry JSON is invalid
- Throws `Error` if file is not readable

**Caching**: Loaded once per test run, cached in memory

**Example**:
```typescript
const registry = await loadAppRegistry();
const firefoxEntry = registry.get("firefox");
console.log("Firefox workspace:", firefoxEntry?.preferred_workspace);
```

---

### `lookupApp()`

**Purpose**: Lookup a single app entry from registry by name

**Signature**:
```typescript
async function lookupApp(appName: string): Promise<AppRegistryEntry>
```

**Parameters**:
- `appName`: App name to lookup (e.g., "firefox", "vscode")

**Returns**: AppRegistryEntry for the app

**Errors**:
- Throws `AppNotFoundError` if app doesn't exist in registry
- Throws `Error` if registry file cannot be loaded

**Example**:
```typescript
try {
  const app = await lookupApp("firefox");
  console.log("Firefox command:", app.command);
} catch (error) {
  if (error instanceof AppNotFoundError) {
    console.error("Firefox not found in registry");
  }
}
```

---

## App Launch Functions

### `launchApp()`

**Purpose**: Launch an application using app-launcher-wrapper.sh (only method)

**Signature**:
```typescript
async function launchApp(
  appName: string,
  options?: LaunchAppOptions
): Promise<Deno.ChildProcess>
```

**Parameters**:
- `appName`: App name from registry (e.g., "firefox") - REQUIRED, must exist in registry
- `options`: Optional launch configuration
  - `args?: string[]` - Additional command-line arguments
  - `project?: string` - Project context (sets I3PM_PROJECT_NAME)
  - `workspace?: number` - Workspace override (sets I3PM_TARGET_WORKSPACE)

**Returns**: Deno.ChildProcess handle (for cleanup if needed)

**Errors**:
- Throws `AppNotFoundError` if app not in registry (no fallback)
- Throws `Error` if wrapper script not found at `~/.local/bin/app-launcher-wrapper.sh`
- Throws `Error` if wrapper script exits with non-zero code
- Throws `Error` if registry file not found or invalid

**Behavior**:
- Validates app exists in registry (fails fast if not)
- Invokes `~/.local/bin/app-launcher-wrapper.sh <appName>`
- Wrapper loads app from registry
- Wrapper injects I3PM environment variables
- Wrapper sends launch notification to daemon
- Wrapper executes app via `swaymsg exec`

**Breaking Change**: No direct command execution support. ALL apps must be in registry.

**Example**:
```typescript
// Launch with minimal config
const process = await launchApp("firefox");

// Launch with full config
const process = await launchApp("vscode", {
  args: ["--folder-uri", "/etc/nixos"],
  project: "nixos",
  workspace: 2
});

// App is now launching, wait for window event
const event = await waitForEvent("window", { change: "new", app_id: "Code" }, 10000);
```

---

## Environment Validation Functions

### `readWindowEnvironment()`

**Purpose**: Read environment variables from a process via /proc/<pid>/environ

**Signature**:
```typescript
async function readWindowEnvironment(pid: number): Promise<WindowEnvironment>
```

**Parameters**:
- `pid`: Process ID to read environment from

**Returns**: WindowEnvironment object with all environment variables

**Errors**:
- Throws `Error` if `/proc/<pid>/environ` doesn't exist or is not readable
- Throws `Error` if PID is not a positive integer

**Example**:
```typescript
const env = await readWindowEnvironment(12345);
console.log("App name:", env.I3PM_APP_NAME);
console.log("Target workspace:", env.I3PM_TARGET_WORKSPACE);
```

---

### `validateI3pmEnvironment()`

**Purpose**: Validate that required I3PM environment variables are present

**Signature**:
```typescript
function validateI3pmEnvironment(
  env: WindowEnvironment,
  required?: string[]
): ValidationResult
```

**Parameters**:
- `env`: WindowEnvironment object from readWindowEnvironment()
- `required`: Optional array of required variable names (default: ["I3PM_APP_NAME", "I3PM_APP_ID", "I3PM_TARGET_WORKSPACE"])

**Returns**:
```typescript
interface ValidationResult {
  valid: boolean;
  missing: string[];
  present: string[];
}
```

**Example**:
```typescript
const env = await readWindowEnvironment(12345);
const result = validateI3pmEnvironment(env);

if (!result.valid) {
  console.error("Missing variables:", result.missing.join(", "));
}
```

---

## RPC Functions

### `checkMethodAvailability()`

**Purpose**: Check if an RPC method is available on tree-monitor daemon

**Signature**:
```typescript
async function checkMethodAvailability(
  client: TreeMonitorClient,
  methodName: string
): Promise<boolean>
```

**Parameters**:
- `client`: TreeMonitorClient instance
- `methodName`: Method name to check (e.g., "sendSyncMarker")

**Returns**: true if method available, false otherwise

**Behavior**:
- First call: performs `system.listMethods` RPC introspection
- Subsequent calls: returns cached result
- Fallback: returns false if introspection fails or daemon unavailable

**Caching**: Session-level (check once per test run)

**Example**:
```typescript
const client = new TreeMonitorClient();

if (await checkMethodAvailability(client, "sendSyncMarker")) {
  console.log("Auto-sync available");
} else {
  console.log("Auto-sync unavailable, using timeout-based fallback");
}
```

---

### `sendSyncMarkerSafe()`

**Purpose**: Send sync marker to daemon with graceful fallback

**Signature**:
```typescript
async function sendSyncMarkerSafe(
  client: TreeMonitorClient
): Promise<string | null>
```

**Parameters**:
- `client`: TreeMonitorClient instance

**Returns**: Sync marker ID if successful, null if method unavailable

**Errors**: Does not throw - returns null on any failure

**Behavior**:
- Checks method availability first via `checkMethodAvailability()`
- If available: calls `sendSyncMarker()` and returns marker ID
- If unavailable: logs warning (once per session) and returns null
- Caller should fall back to timeout-based synchronization when null returned

**Example**:
```typescript
const client = new TreeMonitorClient();
const markerId = await sendSyncMarkerSafe(client);

if (markerId) {
  // Wait for sync marker via events
  await waitForEvent("tick", { payload: markerId }, 5000);
} else {
  // Fallback to timeout
  await delay(500);
}
```

---

## Action Executor Functions

### `executeAction()` (enhanced)

**Purpose**: Execute a test action (enhanced to support via_wrapper and proper wait_event)

**Signature**:
```typescript
async function executeAction(action: Action): Promise<void>
```

**Parameters**:
- `action`: Test action object with `type` and `params`

**Action Types Supported**:
- `launch_app`: Launch application (supports `via_wrapper` parameter)
- `wait_event`: Wait for Sway IPC event (now properly implemented)
- `validate_workspace_assignment`: Validate window on workspace (new helper)
- `validate_environment`: Validate I3PM environment variables (new helper)
- (existing action types unchanged)

**Errors**:
- Throws action-specific errors (AppNotFoundError, WaitEventTimeoutError, etc.)
- Throws `Error` if action type is unknown

**Example**:
```typescript
await executeAction({
  type: "launch_app",
  params: {
    app_name: "firefox"  // BREAKING: app_name required, no command parameter
  }
});

await executeAction({
  type: "wait_event",
  params: {
    event_type: "window",
    timeout: 8000,
    criteria: { change: "new", app_id: "firefox" }
  }
});
```

---

## Error Types

### `WaitEventTimeoutError`

```typescript
class WaitEventTimeoutError extends Error {
  constructor(
    public eventType: string,
    public criteria: EventCriteria | undefined,
    public timeoutMs: number,
    public lastTreeState: SwayTree
  )
}
```

### `AppNotFoundError`

```typescript
class AppNotFoundError extends Error {
  constructor(
    public appName: string,
    public registryPath: string,
    public availableApps: string[]
  )
}
```

### `EnvironmentValidationError`

```typescript
class EnvironmentValidationError extends Error {
  constructor(
    public pid: number,
    public missingVariables: string[],
    public actualEnv: WindowEnvironment
  )
}
```

### `RPCMethodUnavailableError`

```typescript
class RPCMethodUnavailableError extends Error {
  constructor(
    public methodName: string,
    public availableMethods: string[],
    public fallbackStrategy: string
  )
}
```

---

## Type Definitions

All type definitions are documented in [data-model.md](./data-model.md).

---

## Breaking Changes Summary

### launch_app Action (BREAKING)
- **Old**: `{ "type": "launch_app", "params": { "command": "firefox" } }`
- **New**: `{ "type": "launch_app", "params": { "app_name": "firefox" } }`
- **Impact**: ALL tests must update to use `app_name` parameter
- **Benefit**: Tests now validate production app launch flow with I3PM integration
- **No fallback**: Direct command execution removed entirely

### wait_event Action (BREAKING)
- **Old**: Placeholder that sleeps max 1 second regardless of timeout parameter
- **New**: Proper event subscription that respects timeout up to 60 seconds
- **Impact**: Tests may complete faster (event-driven) or expose bugs in app launch timing
- **Benefit**: 0% false timeouts, immediate return when event arrives

### RPC Client (IMPROVEMENT)
- **Old**: Throws "Method not found" error on every test
- **New**: Checks method availability once, falls back gracefully
- **Impact**: Clean test output, no repeated errors
- **Benefit**: Tests work with or without daemon support

---

## Testing Requirements

### Unit Tests
- Test each function with valid inputs
- Test each function with invalid inputs (error cases)
- Test caching behavior (loadAppRegistry, checkMethodAvailability)
- Test timeout handling (waitForEvent)

### Integration Tests
- Test wrapper launch with real registry
- Test event subscription with real Sway events
- Test environment reading with real processes
- Test RPC introspection with real daemon

### Example Tests
See [quickstart.md](./quickstart.md) for complete test examples.
