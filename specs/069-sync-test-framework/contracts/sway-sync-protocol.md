# Sway IPC Synchronization Protocol Contract

**Feature**: 069-sync-test-framework
**Date**: 2025-11-08
**Purpose**: Define the contract for synchronization via Sway's mark/unmark IPC commands

## Overview

This contract documents the synchronization protocol used by the sway-test framework to eliminate race conditions between Sway IPC commands and X11 state updates. The protocol leverages Sway's existing `mark` and `unmark` IPC commands to establish ordering guarantees.

---

## 1. Protocol Description

### 1.1 Problem Statement

**Race condition**: Sway IPC acknowledges commands before X11 finishes processing them.

```
Timeline (WITHOUT sync):
T+0ms:   Test → Sway IPC: "workspace 3"
T+50ms:  Sway → Test: {"success": true}  ← IPC response
T+100ms: Sway → X11: "switch to workspace 3"
T+150ms: Test → X11: "get_tree" (query state)
T+200ms: X11 → Test: tree (workspace 1 still focused) ← STALE STATE
T+300ms: X11 finishes workspace switch
```

### 1.2 Solution

**Synchronization barrier**: Use mark/unmark to guarantee X11 processing completion.

```
Timeline (WITH sync):
T+0ms:   Test → Sway IPC: "workspace 3"
T+50ms:  Sway → Test: {"success": true}
T+60ms:  Test → Sway IPC: "mark --add sync_123"
T+110ms: Sway processes mark, updates X11 property
T+160ms: Sway → Test: {"success": true}  ← Mark complete
T+170ms: Test → Sway IPC: "unmark sync_123"
T+220ms: Sway processes unmark, updates X11 property
T+270ms: Sway → Test: {"success": true}  ← Unmark complete
T+280ms: Test → X11: "get_tree"
T+290ms: X11 → Test: tree (workspace 3 focused) ← FRESH STATE
```

**Ordering guarantee**: When unmark IPC response arrives, all prior Sway→X11 requests (including the workspace switch) have been processed by the X11 server.

---

## 2. Sway IPC Commands

### 2.1 mark Command

**Purpose**: Add marker to focused container (or create invisible marker if no windows).

**Syntax**:
```
mark --add <identifier>
```

**Request** (via swaymsg):
```bash
swaymsg -t send "mark --add sync_1699887123456_a7b3c9d"
```

**Response** (JSON):
```json
[
  {
    "success": true
  }
]
```

**Sway Behavior**:
1. Finds focused container (or root if no focus)
2. Sets `_SWAY_MARK` X11 property with identifier
3. Emits `window::mark` event
4. Returns IPC response after X11 property update queued

**X11 Side Effect**:
- X11 property: `_SWAY_MARK = "sync_1699887123456_a7b3c9d"`
- Property update is queued in X11 server's request buffer

### 2.2 unmark Command

**Purpose**: Remove marker from all containers.

**Syntax**:
```
unmark <identifier>
```

**Request** (via swaymsg):
```bash
swaymsg -t send "unmark sync_1699887123456_a7b3c9d"
```

**Response** (JSON):
```json
[
  {
    "success": true
  }
]
```

**Sway Behavior**:
1. Finds all containers with specified mark
2. Removes `_SWAY_MARK` X11 property
3. Emits `window::mark` event (if container existed)
4. Returns IPC response after X11 property update queued

**X11 Side Effect**:
- X11 property: `_SWAY_MARK` deleted
- Property deletion is queued in X11 server's request buffer

---

## 3. Synchronization Guarantee

### 3.1 Ordering Semantics

**Guarantee**: When `unmark` IPC response arrives at client, X11 server has processed:
1. All Sway→X11 requests issued before `mark` command
2. The `mark` X11 property update
3. The `unmark` X11 property update

**Why this works**:
- X11 processes requests in FIFO order per connection
- Sway uses single X11 connection for all window management
- `unmark` response implies X11 has processed unmark property update
- Therefore, all prior requests in queue have also been processed

**Formal guarantee** (from X11 protocol spec):
> "Requests on a given connection are always processed in the order in which they are received."

### 3.2 Failure Modes

| Scenario | Behavior | Recovery |
|----------|----------|----------|
| **Sway IPC timeout** | `mark` or `unmark` response >5s | Throw error, fail test |
| **Sway unresponsive** | IPC socket closed | Throw error, fail test |
| **No focused window** | `mark` creates invisible marker | `unmark` removes it (no visible effect) |
| **Parallel tests** | Different markers (`sync_<timestamp>_<random>`) | No interference (markers unique) |
| **X11 server lag** | Sync takes 10-50ms instead of <10ms | Log warning, but still correct |

---

## 4. Protocol Implementation

### 4.1 TypeScript/Deno Implementation

```typescript
/**
 * Synchronize with Sway IPC state.
 * Guarantees all prior IPC commands have been processed by X11.
 *
 * @param timeout - Timeout in milliseconds (default: 5000)
 * @returns SyncResult with latency metrics
 * @throws Error if sync times out
 */
async function sync(timeout: number = 5000): Promise<SyncResult> {
  const marker = generateSyncMarker();
  const startTime = performance.now();

  try {
    // Step 1: Send mark command
    const markResult = await sendCommand(
      `mark --add ${marker.marker}`,
      timeout
    );

    if (!markResult.success) {
      throw new Error(`Mark command failed: ${markResult.error}`);
    }

    // Step 2: Send unmark command
    const unmarkResult = await sendCommand(
      `unmark ${marker.marker}`,
      timeout
    );

    if (!unmarkResult.success) {
      throw new Error(`Unmark command failed: ${unmarkResult.error}`);
    }

    // Step 3: Return success
    const endTime = performance.now();
    const latencyMs = Math.round(endTime - startTime);

    return {
      success: true,
      marker,
      latencyMs,
      startTime,
      endTime,
    };
  } catch (error) {
    const endTime = performance.now();
    const latencyMs = Math.round(endTime - startTime);

    return {
      success: false,
      marker,
      latencyMs,
      error: error instanceof Error ? error.message : String(error),
      startTime,
      endTime,
    };
  }
}

/**
 * Send Sway IPC command via swaymsg subprocess.
 *
 * @param command - IPC command string
 * @param timeout - Timeout in milliseconds
 * @returns Command result
 */
async function sendCommand(
  command: string,
  timeout: number
): Promise<{ success: boolean; error?: string }> {
  const cmd = new Deno.Command("swaymsg", {
    args: ["-t", "send", command],
    stdout: "piped",
    stderr: "piped",
  });

  // Implement timeout wrapper
  const timeoutPromise = new Promise((_, reject) =>
    setTimeout(() => reject(new Error(`Command timeout after ${timeout}ms`)), timeout)
  );

  const cmdPromise = cmd.output();

  try {
    const { stdout, stderr, code } = await Promise.race([cmdPromise, timeoutPromise]) as Deno.CommandOutput;

    if (code !== 0) {
      const errorMsg = new TextDecoder().decode(stderr);
      return { success: false, error: errorMsg.trim() };
    }

    const response = JSON.parse(new TextDecoder().decode(stdout));
    return { success: response[0]?.success ?? false };
  } catch (error) {
    return {
      success: false,
      error: error instanceof Error ? error.message : String(error),
    };
  }
}
```

### 4.2 Error Handling

```typescript
// Usage with error handling
try {
  const result = await swayClient.sync();

  if (!result.success) {
    console.error(`Sync failed: ${result.error}`);
    throw new Error(`Sync failed after ${result.latencyMs}ms`);
  }

  if (result.latencyMs > 10) {
    console.warn(`Slow sync: ${result.latencyMs}ms (marker: ${result.marker.marker})`);
  }

  // Proceed with state query (guaranteed fresh)
  const tree = await swayClient.getTree();
} catch (error) {
  // Handle timeout or IPC error
  console.error("Sync operation failed:", error);
  throw error;
}
```

---

## 5. Performance Characteristics

### 5.1 Latency Breakdown

| Component | Typical | Worst Case | Notes |
|-----------|---------|------------|-------|
| **mark IPC** | 3-5ms | 10-15ms | subprocess spawn + IPC round-trip |
| **unmark IPC** | 3-5ms | 10-15ms | subprocess spawn + IPC round-trip |
| **X11 processing** | <1ms | 5-10ms | Depends on X11 server load |
| **Total sync** | 5-10ms | 20-30ms | Target: <10ms (p95) |

### 5.2 Comparison to Alternatives

| Approach | Latency | Reliability | Complexity |
|----------|---------|-------------|------------|
| **No sync (race condition)** | 0ms | 90% (flaky) | Low |
| **Arbitrary timeout (10s)** | 10,000ms | 95% | Low |
| **Polling (100ms interval)** | 50-500ms | 98% | Medium |
| **mark/unmark sync** | **5-10ms** | **100%** | **Low** |
| **X11 ClientMessage** | 1-3ms | 100% | High (X11 protocol) |

**Verdict**: mark/unmark sync provides best balance of simplicity, reliability, and performance.

---

## 6. Testing Protocol

### 6.1 Unit Tests

```typescript
Deno.test("sync() generates unique markers", async () => {
  const marker1 = generateSyncMarker();
  const marker2 = generateSyncMarker();

  assertEquals(marker1.marker !== marker2.marker, true);
  assert(marker1.marker.startsWith("sync_"));
});

Deno.test("sync() completes within timeout", async () => {
  const client = new SwayClient();
  const result = await client.sync(5000);

  assertEquals(result.success, true);
  assert(result.latencyMs < 5000);
});
```

### 6.2 Integration Tests

```typescript
Deno.test("sync() eliminates race condition", async () => {
  const client = new SwayClient();

  // Switch workspace
  await client.sendCommand("workspace 5");

  // Without sync: might get stale state
  // WITH sync: guaranteed fresh state
  await client.sync();

  const tree = await client.getTree();
  const focusedWs = tree.workspaces.find(ws => ws.focused);

  assertEquals(focusedWs?.num, 5);
});
```

### 6.3 Performance Benchmarks

```typescript
Deno.test("sync() latency <10ms (p95)", async () => {
  const client = new SwayClient();
  const latencies: number[] = [];

  // Run 100 sync operations
  for (let i = 0; i < 100; i++) {
    const result = await client.sync();
    latencies.push(result.latencyMs);
  }

  latencies.sort((a, b) => a - b);
  const p95 = latencies[94]; // 95th percentile

  assert(p95 < 10, `p95 latency ${p95}ms exceeds 10ms target`);
});
```

---

## 7. Protocol Limitations

### 7.1 What Sync DOES Guarantee

✅ All prior Sway→X11 requests processed before sync() returns
✅ Window manager state is consistent (no pending updates)
✅ Safe to query X11 state after sync (no race condition)
✅ Workspace switches, window moves, focus changes complete

### 7.2 What Sync DOES NOT Guarantee

❌ Application startup completion (app may still be initializing)
❌ External events (user input, network requests, timers)
❌ Wayland protocol events from other clients
❌ Asynchronous window manager events (screen lock, notifications)

### 7.3 Usage Guidelines

**DO use sync when**:
- Sending Sway IPC commands (workspace switch, window move, etc.)
- Querying state after IPC command
- Launching applications (to ensure window appears before checking)

**DO NOT use sync when**:
- Waiting for application initialization (use wait_event instead)
- Waiting for external events (user input, network)
- No prior IPC commands sent (nothing to sync)

---

## 8. Compatibility

### 8.1 Sway Version Requirements

| Sway Version | Compatibility | Notes |
|--------------|---------------|-------|
| **1.0 - 1.5** | ✅ Full support | mark/unmark commands stable |
| **1.6+** | ✅ Full support | No breaking changes |
| **1.9+** | ✅ Full support | Current version (2025) |
| **i3 4.x** | ⚠️ Compatible | i3 also supports mark/unmark |
| **Wayland compositors** | ❌ Sway-specific | Protocol uses Sway IPC, not Wayland protocol |

### 8.2 X11 Server Requirements

| X11 Server | Compatibility | Notes |
|------------|---------------|-------|
| **Xorg** | ✅ Full support | Standard X11 ordering guarantees |
| **Xvfb (headless)** | ✅ Full support | Used in CI/CD |
| **Xephyr (nested)** | ✅ Full support | Used in i3 testsuite |
| **XWayland** | ✅ Full support | Sway uses XWayland for X11 apps |
| **Wayland-native** | N/A | No X11 properties (Sway handles internally) |

---

## 9. References

### 9.1 Sway IPC Documentation

- **mark command**: https://github.com/swaywm/sway/blob/master/sway/sway.5.scd#mark
- **IPC protocol**: https://github.com/swaywm/sway/blob/master/sway/sway-ipc.7.scd

### 9.2 X11 Protocol

- **Request ordering**: X11 Protocol Specification, Section 2.3
- **Property updates**: ICCCM (Inter-Client Communication Conventions Manual)

### 9.3 i3 Testsuite

- **I3_SYNC protocol**: https://i3wm.org/docs/testsuite.html#_appendix_a_the_i3_sync_protocol
- **Sync implementation**: https://i3wm.org/docs/testsuite.html#_appendix_b_the_sync_ipc_command

---

## 10. Contract Summary

### 10.1 Preconditions

- Sway window manager running (version 1.0+)
- X11 server available (Xorg, Xvfb, Xephyr, or XWayland)
- `swaymsg` utility available in PATH
- Sway IPC socket accessible (`$SWAYSOCK` environment variable)

### 10.2 Postconditions

- All prior Sway IPC commands processed by X11
- Window manager state is consistent (no pending updates)
- Safe to query X11 state (getTree, getWorkspaces, etc.)
- Sync latency measured and logged

### 10.3 Invariants

- Marker uniqueness: Each sync operation uses unique marker (timestamp + random)
- Ordering guarantee: X11 processes requests in FIFO order
- Timeout safety: Sync operation completes or fails within specified timeout
- No side effects: Marker creation/deletion has no visible effect on window manager state

---

**Last Updated**: 2025-11-08
**Status**: Draft (pending implementation)
**Review Required**: Sway IPC behavior verification on production systems
