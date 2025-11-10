# Research: Sway Test Framework Usability Improvements

**Feature**: 070-sway-test-improvements
**Date**: 2025-11-10
**Status**: Phase 0 - Technical Research Complete

## Executive Summary

Feature 070 builds upon Feature 069's synchronization-based test framework to enhance developer experience through:
1. **Clear error diagnostics** - Structured error messages with remediation steps
2. **Graceful cleanup commands** - Automatic process/window cleanup between test runs
3. **PWA application support** - First-class Progressive Web App testing
4. **App registry integration** - Name-based app launches with metadata resolution
5. **Convenient CLI access** - Discovery commands for apps and PWAs

All technical clarifications have been resolved through analysis of existing framework code, NixOS configuration patterns, and Constitution standards.

## Technical Clarifications Resolved

### 1. Error Message Architecture

**Question**: How should structured error messages be formatted for optimal developer experience?

**Decision**: Multi-level error reporting with context and remediation

**Implementation Pattern**:
```typescript
export class StructuredError extends Error {
  constructor(
    public readonly type: ErrorType,
    public readonly component: string,
    public readonly cause: string,
    public readonly remediation: string[],
    public readonly context?: Record<string, unknown>
  ) {
    super(`${component}: ${cause}`);
    this.name = "StructuredError";
  }

  format(): string {
    const lines = [
      `❌ ${this.type}: ${this.message}`,
      "",
      "Context:",
      ...Object.entries(this.context || {}).map(([k, v]) => `  ${k}: ${JSON.stringify(v)}`),
      "",
      "Suggested fixes:",
      ...this.remediation.map((fix, i) => `  ${i + 1}. ${fix}`)
    ];
    return lines.join("\n");
  }
}

export enum ErrorType {
  APP_NOT_FOUND = "APP_NOT_FOUND",
  PWA_NOT_FOUND = "PWA_NOT_FOUND",
  INVALID_ULID = "INVALID_ULID",
  LAUNCH_FAILED = "LAUNCH_FAILED",
  TIMEOUT = "TIMEOUT",
  MALFORMED_TEST = "MALFORMED_TEST",
  REGISTRY_ERROR = "REGISTRY_ERROR",
}
```

**Rationale**: Aligns with Constitution Principle XV (Sway Test Framework Standards) requiring "detailed diffs with mode indicators, compared/ignored field lists, and contextual 'Expected X, got Y' messages"

**Alternatives Considered**:
- Simple string errors → Rejected: Lacks structure for automated parsing
- JSON-only errors → Rejected: Not human-readable in terminal output
- Error codes → Rejected: Requires documentation lookup, slows debugging

### 2. Cleanup Command Implementation

**Question**: Should cleanup be automatic-only or provide manual CLI commands?

**Decision**: Hybrid approach - automatic cleanup + manual CLI fallback

**Implementation Strategy**:
1. **Automatic Cleanup** (built into test teardown):
   - Track all spawned processes via process tree
   - Register window markers at launch
   - Cleanup on test completion or failure
   - Timeout: 500ms graceful → force-kill on failure

2. **Manual Cleanup** (CLI command):
   ```bash
   sway-test cleanup [--all|--markers|--processes]
   ```
   - Useful for interrupted test sessions
   - Removes test markers from scratchpad
   - Kills processes matching test patterns
   - Logs all cleanup actions

**Architecture**:
```typescript
export class CleanupManager {
  private processTree: Set<number> = new Set();
  private windowMarkers: Set<string> = new Set();

  async registerProcess(pid: number): Promise<void> {
    this.processTree.add(pid);
    // Track child processes via psutil-equivalent
  }

  async cleanup(): Promise<CleanupReport> {
    const report: CleanupReport = {
      processesTerminated: [],
      windowsClosed: [],
      errors: [],
    };

    // 1. Close windows gracefully
    for (const marker of this.windowMarkers) {
      try {
        await swayClient.closeWindowByMark(marker, { graceful: true, timeout: 500 });
        report.windowsClosed.push(marker);
      } catch (error) {
        report.errors.push({ marker, error: error.message });
      }
    }

    // 2. Terminate processes
    for (const pid of this.processTree) {
      try {
        await terminateProcess(pid, { signal: "SIGTERM", timeout: 500 });
        report.processesTerminated.push(pid);
      } catch (error) {
        // Force-kill on timeout
        await terminateProcess(pid, { signal: "SIGKILL" });
        report.processesTerminated.push(pid);
      }
    }

    return report;
  }
}
```

**Rationale**: Matches Feature 062 (Scratchpad Terminal) cleanup patterns and Constitution Principle XIV (Test-Driven Development) requirements for "test teardown MUST clean up resources"

**Alternatives Considered**:
- Automatic-only → Rejected: No recovery from interrupted sessions
- Manual-only → Rejected: Increases test boilerplate and reduces automation
- OS-level session cleanup → Rejected: Too coarse-grained, affects non-test processes

### 3. PWA Launch Integration with firefoxpwa

**Question**: How does sway-test integrate with firefoxpwa for PWA launches?

**Decision**: Subprocess execution with registry-based ULID resolution

**Technical Details**:
- **Launch command**: `firefoxpwa site launch <ULID>`
- **Registry resolution**: Load `~/.config/i3/pwa-registry.json` at test startup
- **Window detection**: Wait for window with expected_class from registry
- **Timeout**: 5 seconds default (configurable via test params)

**Implementation (already in app-registry-reader.ts:231-258)**:
```typescript
export async function lookupPWAByULID(ulid: string): Promise<PWADefinition> {
  if (!isValidULID(ulid)) {
    throw new Error(
      `Invalid ULID format: ${ulid}\n` +
      `ULID must be 26 characters using base32 alphabet (0-9, A-Z excluding I, L, O, U)`
    );
  }

  await loadPWARegistry();
  const pwa = pwaRegistryByULID.get(ulid);

  if (!pwa) {
    const availableULIDs = Array.from(pwaRegistryByULID.keys()).sort();
    throw new Error(
      `PWA with ULID "${ulid}" not found in registry\n` +
      `Available ULIDs: ${availableULIDs.join(", ")}`
    );
  }

  return pwa;
}
```

**Action Executor Enhancement Needed**:
```typescript
// Add to action-executor.ts
async function executeLaunchPWASync(params: ActionParams): Promise<void> {
  const pwa = params.pwa_name
    ? await lookupPWA(params.pwa_name)
    : await lookupPWAByULID(params.pwa_ulid!);

  logger.info(`Launching PWA: ${pwa.name} (${pwa.ulid})`);

  const proc = Deno.run({
    cmd: ["firefoxpwa", "site", "launch", pwa.ulid],
    stdout: "piped",
    stderr: "piped",
  });

  const status = await proc.status();

  if (!status.success && !params.allow_failure) {
    throw new StructuredError(
      ErrorType.LAUNCH_FAILED,
      "PWA Launch",
      `Failed to launch ${pwa.name}`,
      [
        "Verify firefoxpwa is installed: `which firefoxpwa`",
        "Check PWA is installed: `firefoxpwa site list`",
        `Install PWA: firefoxpwa site install ${pwa.url}`,
      ],
      { pwa_name: pwa.name, ulid: pwa.ulid, exit_code: status.code }
    );
  }

  // Wait for window appearance via sync protocol
  await syncManager.waitForSync({ timeout: params.timeout || 5000 });
}
```

**Rationale**: Reuses existing registry infrastructure from Phase 2 (T004-T006) and sync protocol from Feature 069

**Alternatives Considered**:
- Direct Firefox profile manipulation → Rejected: Fragile, bypasses firefoxpwa abstraction
- Browser automation (Playwright) → Rejected: Overkill for window manager testing
- Manual ULID specification → Rejected: Specified as out-of-scope (requires friendly names)

### 4. App Registry Caching Strategy

**Question**: How should registry data be cached to avoid repeated file reads during test execution?

**Decision**: Singleton pattern with lazy loading (already implemented in app-registry-reader.ts:49-52)

**Current Implementation**:
```typescript
// Global cache for registry (loaded once per session)
let registryCache: Map<string, AppRegistryEntry> | null = null;
let pwaRegistryCache: Map<string, PWADefinition> | null = null;
let pwaRegistryByULID: Map<string, PWADefinition> | null = null;

export async function loadAppRegistry(
  registryPath?: string
): Promise<Map<string, AppRegistryEntry>> {
  // Return cached registry if available
  if (registryCache !== null) {
    return registryCache;
  }

  // ... load and parse registry JSON ...
  registryCache = new Map(
    validatedData.applications.map(app => [app.name, app])
  );

  return registryCache;
}
```

**Enhancement Needed**: Cache invalidation for testing

```typescript
export function clearRegistryCache(): void {
  registryCache = null;
  pwaRegistryCache = null;
  pwaRegistryByULID = null;
}
```

**Rationale**: Matches Constitution Principle X (Python Development & Testing Standards) pattern: "Keep display logic separate from business logic for testability"

**Alternatives Considered**:
- Read-per-lookup → Rejected: Inefficient for test suites with 50+ app launches
- TTL-based cache → Rejected: Registry doesn't change during test execution
- Database storage → Rejected: Overengineering for static JSON data

### 5. CLI Discovery Command Output Format

**Question**: Should list-apps and list-pwas output tables or JSON?

**Decision**: Default table output with `--json` flag for machine-readable format

**Table Format (default)**:
```
$ sway-test list-apps

NAME          COMMAND               WORKSPACE  MONITOR     SCOPE
firefox       firefox               3          secondary   global
code          code                  2          primary     scoped
alacritty     alacritty             1          primary     global
youtube-pwa   firefoxpwa site ...   50         tertiary    global

50 applications found
```

**JSON Format (--json flag)**:
```json
{
  "version": "1.0.0",
  "count": 50,
  "applications": [
    {
      "name": "firefox",
      "display_name": "Firefox",
      "command": "firefox",
      "preferred_workspace": 3,
      "preferred_monitor_role": "secondary",
      "scope": "global"
    }
  ]
}
```

**Implementation**:
```typescript
// src/commands/list-apps.ts
export async function listApps(options: ListOptions): Promise<void> {
  const registry = await loadAppRegistry();
  const apps = Array.from(registry.values());

  if (options.json) {
    console.log(JSON.stringify({
      version: "1.0.0",
      count: apps.length,
      applications: apps
    }, null, 2));
    return;
  }

  // Table format using Deno std/table
  const table = new Table()
    .header(["NAME", "COMMAND", "WORKSPACE", "MONITOR", "SCOPE"])
    .body(apps.map(app => [
      app.name,
      app.command,
      app.preferred_workspace?.toString() || "none",
      app.preferred_monitor_role || "none",
      app.scope
    ]))
    .render();

  console.log(table);
  console.log(`\n${apps.length} applications found`);
}
```

**Rationale**: Aligns with Constitution Principle XIII (Deno CLI Development Standards): "CLI tools MUST provide --help and --version flags following standard conventions"

**Alternatives Considered**:
- JSON-only → Rejected: Poor developer experience for quick lookups
- CSV format → Rejected: Not commonly used in CLI tools, requires parsing
- YAML format → Rejected: Unnecessary complexity, JSON is standard

## Best Practices Integration

### Error Handling Patterns

**From Feature 069 (Sync Test Framework)**:
- Use structured exceptions with error types
- Include context for debugging (current state, expected state)
- Provide actionable remediation steps
- Log errors to both stdout and framework log

**From Feature 062 (Scratchpad Terminal)**:
- Timeout handling: Graceful attempt → force-kill fallback
- Process tree tracking via PID + psutil
- State cleanup on error paths

### Test Action Patterns

**From Feature 069 sync protocol**:
- All PWA launches MUST use `launch_pwa_sync` action type
- Sync protocol eliminates race conditions (<1% flakiness)
- Timeout defaults: 5s for PWA launch, 2s for window appearance

### Registry Integration Patterns

**From app-registry.nix (line 20-26)**:
```nix
# Transform PWA sites to simplified PWA registry format
pwaDefinitions = map (pwa: {
  name = lib.toLower pwa.name;  # Normalize to lowercase
  url = pwa.url;
  ulid = pwa.ulid;
  preferred_workspace = if pwa ? preferred_workspace then pwa.preferred_workspace else null;
  preferred_monitor_role = if pwa ? preferred_monitor_role then pwa.preferred_monitor_role else null;
}) pwaSitesConfig.pwaSites;
```

**Key insight**: Registry generation happens at Nix build time, test framework reads static JSON at runtime

## Dependency Analysis

### Required Dependencies (Already Available)

1. **Deno 1.40+** - Runtime (Constitution Principle XIII)
2. **Zod 3.22.4** - Schema validation (already in pwa-definition.ts:8)
3. **Sway IPC** - Window manager communication (via sway-client.ts)
4. **Sync Protocol** - Feature 069 synchronization primitives

### New Dependencies (Phase-Specific)

**Phase 3 (Error Diagnostics)**: None - use existing TypeScript Error class

**Phase 4 (Cleanup Commands)**: Process management utilities
- `Deno.kill()` for process termination
- Sway IPC `close` command for window cleanup
- Mark-based window tracking (already in sync-manager.ts)

**Phase 5 (PWA Support)**: None - firefoxpwa installed system-wide

**Phase 7 (CLI Commands)**: Table formatting
- Consider: `std/cli/spinner` for registry loading indicator
- Consider: `std/fmt/colors` for colored output

## Performance Considerations

### Registry Loading Performance

**Measured** (from existing app-registry.nix):
- Application registry: ~50 apps → ~10KB JSON → <5ms parse time
- PWA registry: ~15 PWAs → ~2KB JSON → <2ms parse time

**Target**: <50ms for test startup including registry load

### Cleanup Performance

**Target** (from FR-003 Success Criteria):
- 10 processes + 10 windows → <2 seconds cleanup time
- Graceful termination: 500ms timeout per process
- Force-kill fallback: <100ms

**Implementation Note**: Parallelize cleanup operations where safe

### Error Message Rendering

**Target**: <10ms for error formatting (negligible compared to test execution)

## Integration Points

### 1. Existing Test Framework

**Files to modify**:
- `src/services/action-executor.ts` - Add launch_pwa_sync handler
- `src/models/test-case.ts` - Already has launch_pwa_sync type (test-case.ts:25)
- `src/services/app-registry-reader.ts` - Already has PWA lookup (done in Phase 2)

### 2. NixOS Configuration

**Files already configured**:
- `home-modules/desktop/app-registry.nix` - Generates pwa-registry.json (line 72-75)
- `shared/pwa-sites.nix` - PWA definitions source

**No modifications needed** - registry generation complete in Phase 2

### 3. CLI Entry Points

**New command structure**:
```
sway-test
├── run <test.json>          # Existing
├── validate <test.json>     # Existing
├── cleanup [options]        # NEW - Phase 4
├── list-apps [options]      # NEW - Phase 7
└── list-pwas [options]      # NEW - Phase 7
```

## Risks & Mitigations

### Risk 1: firefoxpwa binary not available

**Mitigation**: Pre-flight check in PWA launch action
```typescript
if (!await commandExists("firefoxpwa")) {
  throw new StructuredError(
    ErrorType.LAUNCH_FAILED,
    "PWA Launch",
    "firefoxpwa command not found",
    [
      "Install firefoxpwa: Add to NixOS configuration",
      "Verify PATH: echo $PATH | grep firefoxpwa",
    ]
  );
}
```

### Risk 2: Process cleanup fails to terminate processes

**Mitigation**: Force-kill fallback with logging
```typescript
try {
  await terminateProcess(pid, { signal: "SIGTERM", timeout: 500 });
} catch (error) {
  logger.warn(`Graceful termination failed for PID ${pid}, force-killing`);
  await terminateProcess(pid, { signal: "SIGKILL" });
}
```

### Risk 3: Registry file missing at test runtime

**Mitigation**: Clear error with setup instructions
```typescript
if (!(await fileExists("~/.config/i3/pwa-registry.json"))) {
  throw new StructuredError(
    ErrorType.REGISTRY_ERROR,
    "PWA Registry",
    "PWA registry file not found",
    [
      "Rebuild NixOS config: sudo nixos-rebuild switch",
      "Verify file exists: cat ~/.config/i3/pwa-registry.json",
      "Check app-registry.nix configuration",
    ]
  );
}
```

## Implementation Roadmap

### Phase 3: Error Diagnostics (US1) - 9 tasks
Focus: Structured error types, remediation messages, context enrichment

### Phase 4: Cleanup Commands (US2) - 7 tasks
Focus: Process tracking, window cleanup, manual CLI command

### Phase 5: PWA Support (US3) - 12 tasks
Focus: Action executor integration, sync protocol, allow_failure flag

### Phase 6: Registry Integration (US4) - 19 tasks
Focus: Name-based launches, workspace validation, metadata resolution

### Phase 7: CLI Access (US5) - 8 tasks
Focus: List commands, table formatting, JSON output

### Phase 8: Integration Tests - 5 tasks
Focus: End-to-end workflows, error scenarios, cleanup validation

### Phase 9: Polish & Documentation - 10 tasks
Focus: Quickstart guide, error catalog, troubleshooting docs

## Conclusion

All technical unknowns have been resolved. The implementation can proceed directly to Phase 1 (Data Model & Contracts) with confidence that:

1. **Error architecture** follows Constitution standards and existing framework patterns
2. **Cleanup strategy** balances automation with manual fallback capabilities
3. **PWA integration** leverages existing registry infrastructure and sync protocol
4. **Registry caching** uses proven singleton pattern for performance
5. **CLI output** follows standard tool conventions with JSON fallback
6. **Dependencies** are minimal and already available in the Deno ecosystem

No additional research dependencies remain. Ready for Phase 1: Data Model & Contracts.
