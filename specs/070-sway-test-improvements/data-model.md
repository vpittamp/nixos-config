# Data Model: Sway Test Framework Usability Improvements

**Feature**: 070-sway-test-improvements
**Date**: 2025-11-10
**Phase**: 1 - Data Model Design

## Overview

This document defines the data structures for Feature 070's five user stories: error diagnostics, cleanup management, PWA support, app registry integration, and CLI discovery. The model extends Feature 069's test framework with structured error handling, resource tracking, and registry-based application metadata.

## Core Entities

### 1. StructuredError (US1: Clear Error Diagnostics)

Represents a test framework error with diagnostic context and remediation steps.

**TypeScript Interface**:
```typescript
/**
 * Structured error with diagnostic context
 * Replaces generic Error class for test framework exceptions
 */
export interface StructuredError extends Error {
  /** Error category for filtering and reporting */
  type: ErrorType;

  /** Component that raised the error (e.g., "PWA Launch", "Registry Reader") */
  component: string;

  /** Root cause description */
  cause: string;

  /** Ordered list of remediation steps */
  remediation: string[];

  /** Additional diagnostic context (PIDs, ULIDs, file paths, etc.) */
  context?: Record<string, unknown>;
}

/**
 * Error type enumeration
 * Maps to specific failure scenarios in functional requirements
 */
export enum ErrorType {
  /** App name not found in registry (FR-002) */
  APP_NOT_FOUND = "APP_NOT_FOUND",

  /** PWA name not found in registry (FR-002) */
  PWA_NOT_FOUND = "PWA_NOT_FOUND",

  /** Invalid ULID format provided (FR-013) */
  INVALID_ULID = "INVALID_ULID",

  /** Application or PWA failed to launch (FR-004) */
  LAUNCH_FAILED = "LAUNCH_FAILED",

  /** Action or window wait exceeded timeout (FR-004) */
  TIMEOUT = "TIMEOUT",

  /** Test JSON structure invalid (FR-005) */
  MALFORMED_TEST = "MALFORMED_TEST",

  /** Registry file missing or invalid (FR-025) */
  REGISTRY_ERROR = "REGISTRY_ERROR",

  /** Cleanup operation failed (FR-008, FR-010) */
  CLEANUP_FAILED = "CLEANUP_FAILED",
}
```

**Validation Rules** (Zod Schema):
```typescript
export const StructuredErrorSchema = z.object({
  type: z.nativeEnum(ErrorType),
  component: z.string().min(1),
  cause: z.string().min(1),
  remediation: z.array(z.string().min(1)).min(1),
  context: z.record(z.unknown()).optional(),
});
```

**Usage Example**:
```typescript
throw new StructuredError(
  ErrorType.PWA_NOT_FOUND,
  "PWA Launcher",
  `PWA "youtube" not found in registry`,
  [
    "Check PWA name spelling (case-sensitive)",
    "List available PWAs: sway-test list-pwas",
    "Verify registry file: cat ~/.config/i3/pwa-registry.json",
  ],
  { pwa_name: "youtube", registry_path: "~/.config/i3/pwa-registry.json" }
);
```

**Relations**:
- Used by all services that can fail (ActionExecutor, RegistryReader, CleanupManager)
- Caught and formatted by test runner for display

### 2. CleanupReport (US2: Graceful Cleanup Commands)

Tracks cleanup operations for test teardown and manual cleanup commands.

**TypeScript Interface**:
```typescript
/**
 * Result of cleanup operation
 * Returned by CleanupManager for logging and verification
 */
export interface CleanupReport {
  /** Timestamp of cleanup start */
  timestamp: Date;

  /** Duration in milliseconds */
  duration_ms: number;

  /** PIDs successfully terminated */
  processes_terminated: ProcessCleanupEntry[];

  /** Window markers successfully closed */
  windows_closed: WindowCleanupEntry[];

  /** Cleanup errors encountered */
  errors: CleanupError[];

  /** Summary statistics */
  summary: {
    total_processes: number;
    total_windows: number;
    success_rate: number;  // 0.0 to 1.0
  };
}

/**
 * Process cleanup entry
 * Records details of terminated process
 */
export interface ProcessCleanupEntry {
  /** Process ID */
  pid: number;

  /** Process command name */
  command: string;

  /** Termination method used */
  signal: "SIGTERM" | "SIGKILL";

  /** Time taken to terminate (ms) */
  duration_ms: number;
}

/**
 * Window cleanup entry
 * Records details of closed window
 */
export interface WindowCleanupEntry {
  /** Window marker (e.g., "test_firefox_123") */
  marker: string;

  /** Window app_id or class */
  window_class?: string;

  /** Workspace number */
  workspace?: number;

  /** Time taken to close (ms) */
  duration_ms: number;
}

/**
 * Cleanup error
 * Records failures during cleanup
 */
export interface CleanupError {
  /** Resource type that failed to clean */
  type: "process" | "window";

  /** PID or window marker */
  identifier: string;

  /** Error message */
  error: string;

  /** Whether error is critical (blocks cleanup) */
  critical: boolean;
}
```

**Validation Rules** (Zod Schema):
```typescript
export const ProcessCleanupEntrySchema = z.object({
  pid: z.number().int().positive(),
  command: z.string().min(1),
  signal: z.enum(["SIGTERM", "SIGKILL"]),
  duration_ms: z.number().nonnegative(),
});

export const WindowCleanupEntrySchema = z.object({
  marker: z.string().min(1),
  window_class: z.string().optional(),
  workspace: z.number().int().positive().optional(),
  duration_ms: z.number().nonnegative(),
});

export const CleanupErrorSchema = z.object({
  type: z.enum(["process", "window"]),
  identifier: z.string().min(1),
  error: z.string().min(1),
  critical: z.boolean(),
});

export const CleanupReportSchema = z.object({
  timestamp: z.date(),
  duration_ms: z.number().nonnegative(),
  processes_terminated: z.array(ProcessCleanupEntrySchema),
  windows_closed: z.array(WindowCleanupEntrySchema),
  errors: z.array(CleanupErrorSchema),
  summary: z.object({
    total_processes: z.number().int().nonnegative(),
    total_windows: z.number().int().nonnegative(),
    success_rate: z.number().min(0).max(1),
  }),
});
```

**Usage Example**:
```typescript
const report = await cleanupManager.cleanup();

if (report.errors.length > 0) {
  logger.warn(`Cleanup completed with ${report.errors.length} errors`);
  for (const error of report.errors) {
    logger.error(`  ${error.type} ${error.identifier}: ${error.error}`);
  }
}

logger.info(`Cleanup summary: ${report.summary.total_processes} processes, ${report.summary.total_windows} windows`);
```

**Relations**:
- Produced by CleanupManager service
- Logged by test runner in teardown phase
- Displayed by CLI cleanup command

### 3. PWADefinition (US3: PWA Application Support)

**Already Implemented** in pwa-definition.ts (Phase 1, T001)

**Key Fields**:
- `name: string` - Friendly name (e.g., "youtube")
- `url: string` - PWA URL
- `ulid: string` - 26-character base32 identifier
- `preferred_workspace?: number` - Target workspace
- `preferred_monitor_role?: "primary" | "secondary" | "tertiary"` - Monitor assignment

**Validation**: Zod schema with ULID regex: `/^[0123456789ABCDEFGHJKMNPQRSTVWXYZ]{26}$/`

**Usage**: Loaded by ActionExecutor for launch_pwa_sync actions

### 4. AppDefinition (US4: App Registry Integration)

**Already Implemented** in app-definition.ts (Phase 1, T002)

**Key Fields**:
- `name: string` - App name (e.g., "firefox", "code")
- `command: string` - Launch command
- `expected_class?: string` - Window class for detection
- `preferred_workspace?: number` - Target workspace
- `scope: "global" | "scoped"` - Project scope

**Validation**: Zod schema with name regex: `/^[a-z0-9-]+$/`

**Usage**: Loaded by ActionExecutor for launch_app_sync actions

### 5. AppListEntry (US5: CLI Access)

Display model for list-apps command output.

**TypeScript Interface** (Already in app-definition.ts:100-119):
```typescript
export interface AppListEntry {
  /** App name */
  name: string;

  /** Display name */
  display_name: string;

  /** App command */
  command: string;

  /** Workspace assignment or "none" */
  workspace: string;

  /** Monitor role or "none" */
  monitor: string;

  /** Scope (global or scoped) */
  scope: string;
}
```

**Transform Logic**:
```typescript
function toAppListEntry(app: AppDefinition): AppListEntry {
  return {
    name: app.name,
    display_name: app.display_name || app.name,
    command: app.command,
    workspace: app.preferred_workspace?.toString() || "none",
    monitor: app.preferred_monitor_role || "none",
    scope: app.scope,
  };
}
```

### 6. PWAListEntry (US5: CLI Access)

Display model for list-pwas command output.

**TypeScript Interface** (Already in pwa-definition.ts:48-64):
```typescript
export interface PWAListEntry {
  /** Friendly name */
  name: string;

  /** PWA URL */
  url: string;

  /** ULID identifier */
  ulid: string;

  /** Workspace assignment or "none" */
  workspace: string;

  /** Monitor role or "none" */
  monitor: string;
}
```

**Transform Logic**:
```typescript
function toPWAListEntry(pwa: PWADefinition): PWAListEntry {
  return {
    name: pwa.name,
    url: pwa.url,
    ulid: pwa.ulid,
    workspace: pwa.preferred_workspace?.toString() || "none",
    monitor: pwa.preferred_monitor_role || "none",
  };
}
```

## Service State Models

### 1. CleanupManager State

Tracks resources to clean up during test execution.

**Internal State**:
```typescript
class CleanupManager {
  /** Process IDs spawned by test */
  private processTree: Set<number> = new Set();

  /** Window markers registered by test */
  private windowMarkers: Set<string> = new Set();

  /** Cleanup operations in progress */
  private inProgress: boolean = false;
}
```

**Lifecycle**:
1. `registerProcess(pid: number)` - Called by ActionExecutor on app launch
2. `registerWindow(marker: string)` - Called after sync completes
3. `cleanup()` - Called in test teardown or manual CLI command
4. `reset()` - Called after cleanup completes

### 2. RegistryCache State

Singleton cache for app and PWA registries.

**Internal State** (Already in app-registry-reader.ts:49-52):
```typescript
// Global cache for registry (loaded once per session)
let registryCache: Map<string, AppRegistryEntry> | null = null;
let pwaRegistryCache: Map<string, PWADefinition> | null = null;
let pwaRegistryByULID: Map<string, PWADefinition> | null = null;
```

**Lifecycle**:
1. `loadAppRegistry()` - Loads and caches application registry
2. `loadPWARegistry()` - Loads and caches PWA registry (by name and ULID)
3. `clearRegistryCache()` - Clears cache (for testing)

## Data Relationships

```
TestCase (from test-case.ts)
  ├─> Action[] (actions to execute)
  │     ├─> launch_pwa_sync → PWADefinition (registry lookup)
  │     └─> launch_app_sync → AppDefinition (registry lookup)
  │
  ├─> ExpectedState (validation target)
  │
  └─> CleanupManager (resource tracking)
        ├─> ProcessCleanupEntry[] (terminated processes)
        ├─> WindowCleanupEntry[] (closed windows)
        └─> CleanupReport (summary)

StructuredError (thrown by any service)
  ├─> ErrorType (category)
  ├─> remediation[] (fix steps)
  └─> context{} (diagnostic data)

AppRegistry (JSON file)
  └─> AppDefinition[] (applications)
        ├─> AppListEntry (CLI display)
        └─> launch_app_sync (test action)

PWARegistry (JSON file)
  └─> PWADefinition[] (PWAs)
        ├─> PWAListEntry (CLI display)
        └─> launch_pwa_sync (test action)
```

## State Transitions

### Test Execution Flow

```
1. Test Start
   ├─> Load registries (AppRegistry, PWARegistry)
   ├─> Initialize CleanupManager
   └─> Parse test JSON (validate with Zod)

2. Action Execution
   ├─> launch_pwa_sync
   │     ├─> Lookup PWA (by name or ULID)
   │     ├─> Execute firefoxpwa command
   │     ├─> Register process (CleanupManager)
   │     └─> Wait for sync (SyncManager)
   │
   └─> launch_app_sync
         ├─> Lookup app (by name)
         ├─> Execute command
         ├─> Register process (CleanupManager)
         └─> Wait for sync (SyncManager)

3. Test Completion / Failure
   ├─> Execute cleanup
   │     ├─> Close windows (graceful → force)
   │     ├─> Terminate processes (SIGTERM → SIGKILL)
   │     └─> Generate CleanupReport
   │
   └─> Report results

4. Error Handling
   ├─> Catch StructuredError
   ├─> Format error message
   ├─> Execute cleanup (best-effort)
   └─> Exit with error code
```

### Cleanup State Machine

```
IDLE
  ├─> registerProcess(pid) → TRACKING
  └─> registerWindow(marker) → TRACKING

TRACKING
  ├─> cleanup() → CLEANING
  └─> reset() → IDLE

CLEANING
  ├─> closeWindows()
  │     ├─> graceful (500ms timeout) → success
  │     └─> force-kill → success
  │
  ├─> terminateProcesses()
  │     ├─> SIGTERM (500ms timeout) → success
  │     └─> SIGKILL → success
  │
  └─> generateReport() → IDLE
```

## Validation Rules Summary

### StructuredError
- ✅ `type` must be valid ErrorType enum value
- ✅ `component` must be non-empty string
- ✅ `cause` must be non-empty string
- ✅ `remediation` must have at least 1 step
- ✅ `context` must be valid JSON object

### CleanupReport
- ✅ `timestamp` must be valid ISO 8601 date
- ✅ `duration_ms` must be non-negative
- ✅ `processes_terminated` PIDs must be positive integers
- ✅ `windows_closed` markers must be non-empty strings
- ✅ `success_rate` must be between 0.0 and 1.0

### PWADefinition (from pwa-definition.ts)
- ✅ `name` must be non-empty string
- ✅ `url` must be valid URL
- ✅ `ulid` must match `/^[0123456789ABCDEFGHJKMNPQRSTVWXYZ]{26}$/`
- ✅ `preferred_workspace` must be positive integer (if provided)
- ✅ `preferred_monitor_role` must be "primary", "secondary", or "tertiary" (if provided)

### AppDefinition (from app-definition.ts)
- ✅ `name` must match `/^[a-z0-9-]+$/`
- ✅ `command` must be non-empty string
- ✅ `scope` must be "global" or "scoped"
- ✅ `preferred_workspace` must be positive integer (if provided)
- ✅ `preferred_monitor_role` must be "primary", "secondary", or "tertiary" (if provided)

## Performance Constraints

### Registry Loading (FR-020)
- **Target**: <50ms total for both registries
- **Measurement**: `performance.now()` around `loadAppRegistry()` and `loadPWARegistry()`
- **Cache invalidation**: Only on explicit `clearRegistryCache()` call

### Cleanup Operations (SC-003)
- **Target**: <2 seconds for 10 processes + 10 windows
- **Timeout**: 500ms graceful, immediate force-kill fallback
- **Parallelization**: Close windows and terminate processes concurrently

### Error Formatting (FR-001)
- **Target**: <10ms per error (negligible in test context)
- **Format**: Human-readable with ANSI colors, structured JSON for --json flag

## Storage & Persistence

### Application Registry
- **Location**: `~/.config/i3/application-registry.json`
- **Generated by**: NixOS home-manager (app-registry.nix)
- **Update mechanism**: System rebuild only
- **Format**: JSON with Zod validation

### PWA Registry
- **Location**: `~/.config/i3/pwa-registry.json`
- **Generated by**: NixOS home-manager (app-registry.nix)
- **Update mechanism**: System rebuild only
- **Format**: JSON with Zod validation

### Cleanup State
- **Persistence**: In-memory only (per test session)
- **Reset**: After each test completion
- **Logging**: CleanupReport written to test log

### Error Context
- **Persistence**: Logged to test output
- **Format**: Structured text (default) or JSON (--json flag)
- **Retention**: Per test runner invocation

## Implementation Notes

### Error Handling Best Practices

1. **Always include remediation steps** - Every StructuredError must guide developers to resolution
2. **Enrich context progressively** - Add diagnostic data at each layer (PID, ULID, file path)
3. **Fail fast with clear messages** - Validate inputs early (ULID format, registry existence)
4. **Log errors at multiple levels** - Console output + framework log file

### Cleanup Best Practices

1. **Track resources at creation time** - Register processes/windows immediately after spawn
2. **Cleanup on all exit paths** - Success, failure, and interrupt (signal handlers)
3. **Parallelize cleanup operations** - Don't block on individual window closes
4. **Force-kill as last resort** - Always attempt graceful termination first

### Registry Best Practices

1. **Cache aggressively** - Registries don't change during test execution
2. **Validate at load time** - Use Zod schemas to fail early on malformed JSON
3. **Provide clear errors** - If registry missing, show exact path and setup instructions
4. **Index by multiple keys** - PWAs indexed by both name and ULID for fast lookup

## Next Steps

Phase 1 complete. Ready for contract generation in `/contracts/` directory:
1. Error message format specification
2. Cleanup report JSON schema
3. CLI command interface definitions
4. Registry JSON schemas (already exist from Phase 2)

After contracts, Phase 2 will generate detailed task breakdown in `tasks.md`.
