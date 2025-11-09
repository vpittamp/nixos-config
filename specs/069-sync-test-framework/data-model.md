# Data Model: Synchronization-Based Test Framework

**Feature**: 069-sync-test-framework
**Date**: 2025-11-08
**Purpose**: Define data structures for synchronization primitives, enhanced test actions, and sync state management

## Overview

This data model extends the existing sway-test framework (Feature 068) with synchronization capabilities. Core entities:
1. **SyncMarker** - Unique identifier for synchronization operations
2. **SyncAction** - Enhanced test action types with sync support
3. **SyncResult** - Synchronization operation result with latency tracking
4. **SyncConfig** - Configuration for sync behavior (timeouts, marker format)

All models use TypeScript interfaces with strict typing (Constitution Principle XIII).

---

## 1. SyncMarker

### 1.1 Purpose

Unique identifier for each synchronization operation. Used in Sway's mark/unmark IPC commands to establish X11 state consistency barriers.

### 1.2 Interface

```typescript
/**
 * Unique identifier for a synchronization operation.
 * Format: sync_<timestamp>_<random>
 * Example: sync_1699887123456_a7b3c9d
 */
export interface SyncMarker {
  /**
   * Full marker string used in Sway IPC commands.
   * Format: "sync_<timestamp>_<random>"
   */
  readonly marker: string;

  /**
   * Unix timestamp (milliseconds) when marker was generated.
   * Used for debugging and timeout tracking.
   */
  readonly timestamp: number;

  /**
   * Random component for uniqueness (base36, 7 characters).
   * Ensures parallel tests don't interfere with each other.
   */
  readonly randomId: string;

  /**
   * Optional test ID this marker is associated with.
   * Useful for diagnostic logging.
   */
  readonly testId?: string;
}
```

### 1.3 Generation Logic

```typescript
/**
 * Generate a new SyncMarker with guaranteed uniqueness.
 *
 * @param testId - Optional test identifier for debugging
 * @returns New SyncMarker instance
 *
 * @example
 * const marker = generateSyncMarker("test-firefox-launch");
 * // marker.marker === "sync_1699887123456_a7b3c9d"
 */
export function generateSyncMarker(testId?: string): SyncMarker {
  const timestamp = Date.now();
  const randomId = Math.random().toString(36).substring(2, 9); // 7 chars

  return {
    marker: `sync_${timestamp}_${randomId}`,
    timestamp,
    randomId,
    testId,
  };
}
```

### 1.4 Validation Rules

- **Uniqueness**: timestamp + randomId ensures uniqueness across parallel tests
- **Format**: Must match regex `/^sync_\d+_[a-z0-9]{7}$/`
- **Length**: 24-28 characters (prefix 5 + timestamp 13 + random 7 + underscores 2)
- **Collision probability**: ~1 in 78 billion per millisecond (36^7)

### 1.5 Lifecycle

```
[Generate] → [Use in mark command] → [Use in unmark command] → [Discard]
   ↓              ↓                        ↓
 testId       "mark --add X"          "unmark X"
```

**Note**: Markers are single-use. Generate fresh marker for each sync operation.

---

## 2. SyncAction

### 2.1 Purpose

Enhanced test action types that automatically synchronize Sway IPC state before continuing. Extends existing `ActionType` union from Feature 068.

### 2.2 Interface

```typescript
/**
 * Extended ActionType with sync variants.
 * Compatible with existing test action system.
 */
export type ActionType =
  // Existing actions (Feature 068)
  | "launch_app"
  | "send_ipc"
  | "switch_workspace"
  | "focus_window"
  | "wait_event"
  | "debug_pause"
  | "await_sync"
  | "validate_workspace_assignment"
  | "validate_environment"
  // New sync actions (Feature 069)
  | "sync"               // Explicit synchronization point
  | "launch_app_sync"    // Launch app + auto-sync
  | "send_ipc_sync";     // IPC command + auto-sync

/**
 * Action definition with sync-specific parameters.
 * Extends existing Action interface from Feature 068.
 */
export interface Action {
  type: ActionType;
  params?: ActionParams;
  description?: string; // Optional description for logging
}

/**
 * Parameters for sync-related actions.
 */
export interface SyncActionParams extends ActionParams {
  /**
   * Timeout for sync operation (milliseconds).
   * Default: 5000ms (from SyncConfig.defaultTimeout)
   */
  timeout?: number;

  /**
   * Whether to log sync latency for performance monitoring.
   * Default: false (only log if >10ms)
   */
  logLatency?: boolean;
}
```

### 2.3 Action Types

#### 2.3.1 `sync` Action

**Purpose**: Explicit synchronization point in test.

**Params**: None (or SyncActionParams for custom timeout)

**Behavior**:
1. Generate SyncMarker
2. Send `mark --add <marker>` via Sway IPC
3. Send `unmark <marker>` via Sway IPC
4. Wait for IPC response (guarantees X11 state consistency)
5. Return control to test

**Example**:
```json
{
  "type": "sync",
  "description": "Ensure window manager state is consistent"
}
```

#### 2.3.2 `launch_app_sync` Action

**Purpose**: Launch application and synchronize before continuing.

**Params**: Same as `launch_app` + optional SyncActionParams

**Behavior**:
1. Execute `launch_app` logic (existing)
2. Automatically call `sync()`
3. Return when app is launched AND state is synchronized

**Example**:
```json
{
  "type": "launch_app_sync",
  "params": {
    "app_name": "firefox",
    "workspace": 3
  },
  "description": "Launch Firefox on workspace 3 with sync"
}
```

**Replaces**:
```json
// OLD (two actions)
{"type": "launch_app", "params": {"app_name": "firefox"}},
{"type": "wait_event", "params": {"timeout": 10000}}

// NEW (one action)
{"type": "launch_app_sync", "params": {"app_name": "firefox"}}
```

#### 2.3.3 `send_ipc_sync` Action

**Purpose**: Send Sway IPC command and synchronize.

**Params**: `ipc_command` (string) + optional SyncActionParams

**Behavior**:
1. Execute IPC command via SwayClient.sendCommand()
2. Validate response (success === true)
3. Automatically call `sync()`
4. Return when command executed AND state synchronized

**Example**:
```json
{
  "type": "send_ipc_sync",
  "params": {
    "ipc_command": "workspace 5"
  },
  "description": "Switch to workspace 5 with sync"
}
```

### 2.4 Backward Compatibility

**Existing tests continue working**:
- Tests without sync actions behave identically
- `wait_event` still functions (deprecated, will be removed in future)
- State comparison modes unchanged (partial, exact, assertions, empty)

---

## 3. SyncResult

### 3.1 Purpose

Result of a synchronization operation with latency tracking for performance monitoring.

### 3.2 Interface

```typescript
/**
 * Result of a sync operation with performance metrics.
 */
export interface SyncResult {
  /**
   * Whether sync completed successfully.
   * False indicates timeout or IPC error.
   */
  success: boolean;

  /**
   * Sync marker used for this operation.
   * Useful for debugging and log correlation.
   */
  marker: SyncMarker;

  /**
   * Sync operation latency (milliseconds).
   * Includes: IPC round-trip + X11 processing time.
   * Target: <10ms (95th percentile)
   */
  latencyMs: number;

  /**
   * Error message if sync failed.
   * Only present when success === false.
   */
  error?: string;

  /**
   * Timestamp when sync operation started.
   * For debugging and timeline reconstruction.
   */
  startTime: number;

  /**
   * Timestamp when sync operation completed.
   * For debugging and timeline reconstruction.
   */
  endTime: number;
}
```

### 3.3 Usage Example

```typescript
const result = await swayClient.sync();

if (!result.success) {
  console.error(`Sync failed: ${result.error}`);
  throw new Error(`Sync timeout after ${result.latencyMs}ms`);
}

if (result.latencyMs > 10) {
  console.warn(`Slow sync: ${result.latencyMs}ms (marker: ${result.marker.marker})`);
}
```

### 3.4 Performance Tracking

```typescript
/**
 * Track sync latency distribution for performance monitoring.
 */
export interface SyncStats {
  totalSyncs: number;
  successfulSyncs: number;
  failedSyncs: number;
  averageLatencyMs: number;
  p95LatencyMs: number; // 95th percentile
  p99LatencyMs: number; // 99th percentile
  maxLatencyMs: number;
  latencies: number[]; // Ring buffer, max 100 entries
}
```

---

## 4. SyncConfig

### 4.1 Purpose

Configuration for synchronization behavior. Allows customization of timeouts, logging, and marker format.

### 4.2 Interface

```typescript
/**
 * Configuration for sync operations.
 * Global defaults that can be overridden per-action.
 */
export interface SyncConfig {
  /**
   * Default timeout for sync operations (milliseconds).
   * Default: 5000 (5 seconds)
   * Range: 100-30000 (0.1s to 30s)
   */
  defaultTimeout: number;

  /**
   * Whether to log all sync operations.
   * Default: false (only log slow ops >10ms)
   */
  logAllSyncs: boolean;

  /**
   * Latency threshold for warning logs (milliseconds).
   * Default: 10 (log if sync >10ms)
   */
  warnThresholdMs: number;

  /**
   * Whether to track sync statistics.
   * Default: true (enabled for performance monitoring)
   */
  trackStats: boolean;

  /**
   * Maximum number of latencies to keep in stats.
   * Default: 100 (ring buffer)
   */
  maxLatencyHistory: number;

  /**
   * Custom marker prefix (for testing/debugging).
   * Default: "sync"
   * Example: "test_sync" → "test_sync_1699887123456_a7b3c9d"
   */
  markerPrefix?: string;
}
```

### 4.3 Default Config

```typescript
export const DEFAULT_SYNC_CONFIG: SyncConfig = {
  defaultTimeout: 5000,
  logAllSyncs: false,
  warnThresholdMs: 10,
  trackStats: true,
  maxLatencyHistory: 100,
  markerPrefix: "sync",
};
```

### 4.4 Configuration Override

```typescript
// Test-level config override
{
  "name": "Custom sync timeout test",
  "syncConfig": {
    "defaultTimeout": 10000,  // 10 seconds for slow systems
    "logAllSyncs": true        // Debug mode
  },
  "actions": [
    {"type": "sync"}  // Uses custom timeout
  ]
}
```

---

## 5. SwayClient Extension

### 5.1 New Methods

```typescript
export interface SwayClient {
  // Existing methods (Feature 068)
  getTree(): Promise<StateSnapshot>;
  getWorkspaces(): Promise<Workspace[]>;
  getOutputs(): Promise<Output[]>;
  sendCommand(command: string): Promise<{ success: boolean; error?: string }>;

  // New sync methods (Feature 069)

  /**
   * Synchronize with Sway IPC state.
   * Guarantees all prior IPC commands have been processed by X11.
   *
   * @param timeout - Optional timeout in milliseconds (default: 5000)
   * @returns SyncResult with latency metrics
   * @throws Error if sync times out
   *
   * @example
   * await swayClient.sendCommand("workspace 3");
   * await swayClient.sync(); // Wait for workspace switch to complete
   * const tree = await swayClient.getTree(); // Tree reflects workspace 3
   */
  sync(timeout?: number): Promise<SyncResult>;

  /**
   * Get tree with automatic sync before capture.
   * Convenience method for common pattern.
   *
   * @returns StateSnapshot with guaranteed fresh state
   *
   * @example
   * const tree = await swayClient.getTreeSynced();
   * // tree reflects latest Sway state (no race condition)
   */
  getTreeSynced(): Promise<StateSnapshot>;

  /**
   * Send command and sync automatically.
   * Convenience method for common pattern.
   *
   * @param command - Sway IPC command string
   * @returns Result with sync completion
   *
   * @example
   * await swayClient.sendCommandSync("workspace 5");
   * // Workspace switch is complete (X11 processed)
   */
  sendCommandSync(command: string): Promise<{ success: boolean; error?: string }>;

  /**
   * Get current sync statistics.
   * For performance monitoring and diagnostics.
   *
   * @returns SyncStats or null if tracking disabled
   */
  getSyncStats(): SyncStats | null;

  /**
   * Reset sync statistics.
   * Useful for per-test benchmarking.
   */
  resetSyncStats(): void;
}
```

---

## 6. ActionExecutor Extension

### 6.1 New Executor Functions

```typescript
/**
 * Execute sync action.
 * @throws Error if sync times out
 */
export async function executeSync(
  action: Action,
  swayClient: SwayClient
): Promise<void> {
  const timeout = action.params?.timeout || DEFAULT_SYNC_CONFIG.defaultTimeout;
  const result = await swayClient.sync(timeout);

  if (!result.success) {
    throw new Error(`Sync failed: ${result.error} (latency: ${result.latencyMs}ms)`);
  }

  if (action.params?.logLatency) {
    console.log(`Sync completed in ${result.latencyMs}ms (marker: ${result.marker.marker})`);
  }
}

/**
 * Execute launch_app_sync action.
 * Combines app launch with automatic sync.
 */
export async function executeLaunchAppSync(
  action: Action,
  swayClient: SwayClient
): Promise<void> {
  // Execute existing launch_app logic
  await executeLaunchApp(action, swayClient);

  // Automatically sync
  await swayClient.sync(action.params?.timeout);
}

/**
 * Execute send_ipc_sync action.
 * Combines IPC command with automatic sync.
 */
export async function executeSendIpcSync(
  action: Action,
  swayClient: SwayClient
): Promise<void> {
  const command = action.params?.ipc_command;
  if (!command) {
    throw new Error("send_ipc_sync requires ipc_command parameter");
  }

  // Send IPC command
  const result = await swayClient.sendCommand(command);
  if (!result.success) {
    throw new Error(`IPC command failed: ${result.error}`);
  }

  // Automatically sync
  await swayClient.sync(action.params?.timeout);
}
```

---

## 7. State Transitions

### 7.1 Sync Operation State Machine

```
[Idle]
  ↓ sync() called
[Generate Marker]
  ↓ marker = sync_<timestamp>_<random>
[Send Mark Command]
  ↓ IPC: "mark --add <marker>"
[Await Mark Response]
  ↓ success || timeout
[Send Unmark Command]
  ↓ IPC: "unmark <marker>"
[Await Unmark Response]
  ↓ success || timeout
[Complete] → SyncResult
  ↓
[Idle]
```

### 7.2 Error States

```
[Send Mark] → [Timeout] → SyncResult{success: false, error: "Mark timeout"}
[Send Unmark] → [Timeout] → SyncResult{success: false, error: "Unmark timeout"}
[Send Mark] → [IPC Error] → SyncResult{success: false, error: <error msg>}
```

---

## 8. Validation Rules

### 8.1 SyncMarker Validation

```typescript
/**
 * Validate SyncMarker format.
 * @param marker - Marker string to validate
 * @returns true if valid, throws Error if invalid
 */
export function validateSyncMarker(marker: string): boolean {
  const regex = /^sync_\d+_[a-z0-9]{7}$/;
  if (!regex.test(marker)) {
    throw new Error(`Invalid sync marker format: ${marker}`);
  }
  return true;
}
```

### 8.2 SyncConfig Validation

```typescript
/**
 * Validate SyncConfig values.
 * @param config - Config to validate
 * @returns true if valid, throws Error if invalid
 */
export function validateSyncConfig(config: Partial<SyncConfig>): boolean {
  if (config.defaultTimeout !== undefined) {
    if (config.defaultTimeout < 100 || config.defaultTimeout > 30000) {
      throw new Error(`defaultTimeout out of range (100-30000): ${config.defaultTimeout}`);
    }
  }

  if (config.warnThresholdMs !== undefined) {
    if (config.warnThresholdMs < 1 || config.warnThresholdMs > 1000) {
      throw new Error(`warnThresholdMs out of range (1-1000): ${config.warnThresholdMs}`);
    }
  }

  if (config.maxLatencyHistory !== undefined) {
    if (config.maxLatencyHistory < 10 || config.maxLatencyHistory > 1000) {
      throw new Error(`maxLatencyHistory out of range (10-1000): ${config.maxLatencyHistory}`);
    }
  }

  return true;
}
```

---

## 9. Relationships

### 9.1 Entity Diagram

```
┌──────────────┐
│  TestCase    │ (Feature 068)
└──────┬───────┘
       │
       │ contains
       ↓
┌──────────────┐
│   Action     │ (Feature 068 + 069)
│ type: sync   │
│ type: ...sync│
└──────┬───────┘
       │
       │ executes
       ↓
┌──────────────┐     ┌──────────────┐
│ SwayClient   │────→│  SyncMarker  │ (Feature 069)
│ sync()       │     │  marker str  │
└──────┬───────┘     └──────────────┘
       │
       │ returns
       ↓
┌──────────────┐     ┌──────────────┐
│  SyncResult  │─────│  SyncStats   │ (Feature 069)
│  success     │     │  p95 latency │
│  latencyMs   │     └──────────────┘
└──────────────┘
```

### 9.2 Dependency Graph

```
TestCase → Action → ActionExecutor → SwayClient
                    ↓                     ↓
               executeSync()          sync()
                    ↓                     ↓
                SyncResult ← generateSyncMarker()
                    ↓
                SyncStats (if tracking enabled)
```

---

## 10. Example: Complete Test with Sync

```json
{
  "name": "Firefox workspace assignment with sync (no race conditions)",
  "description": "Validates Feature 053 workspace assignment using sync primitives",
  "tags": ["integration", "workspace-assignment", "firefox", "sync"],
  "priority": "P1",
  "timeout": 15000,
  "syncConfig": {
    "logAllSyncs": true
  },
  "actions": [
    {
      "type": "send_ipc_sync",
      "params": {
        "ipc_command": "[app_id=\"firefox\"] kill"
      },
      "description": "Kill existing Firefox instances"
    },
    {
      "type": "launch_app_sync",
      "params": {
        "app_name": "firefox"
      },
      "description": "Launch Firefox with sync"
    }
  ],
  "expectedState": {
    "focusedWorkspace": 3,
    "workspaces": [
      {
        "num": 3,
        "windows": [
          {
            "app_id": "firefox",
            "focused": true
          }
        ]
      }
    ]
  }
}
```

**Execution flow**:
1. Parse test definition
2. Execute send_ipc_sync: kill Firefox → sync
3. Execute launch_app_sync: launch Firefox → sync
4. Capture state via getTreeSynced()
5. Compare state (partial mode, Feature 068)
6. Report pass/fail

**Performance**:
- OLD (timeout-based): ~15 seconds (10s + 5s waits)
- NEW (sync-based): ~2 seconds (actual operation time + <20ms sync)
- **7.5x faster**

---

## 11. Performance Targets

| Metric | Target | Current | Source |
|--------|--------|---------|--------|
| Sync latency (p50) | <5ms | 5-10ms | swaymsg overhead |
| Sync latency (p95) | <10ms | 8-12ms | subprocess spawn |
| Sync latency (p99) | <20ms | 15-25ms | loaded system |
| Test suite runtime | 25s | ~50s | i3 testsuite comparison |
| Individual test speedup | 5-10x | 1x | timeout removal |
| Flakiness rate | <1% | 5-10% | race condition elimination |

**Success Criteria (from spec)**:
- ✅ SC-004: 95% of sync operations <10ms
- ✅ SC-002: Test suite 50s → 25s (50% improvement)
- ✅ SC-003: Individual tests 5-10x faster

---

**Last Updated**: 2025-11-08
**Next Steps**: Generate contracts/ and quickstart.md
