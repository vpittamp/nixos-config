/**
 * Unit tests for SyncManager
 * Feature 069: Synchronization-Based Test Framework
 */

import { assertEquals, assert } from "@std/assert";
import { SyncManager } from "../../src/services/sync-manager.ts";

Deno.test("SyncManager - basic instantiation", () => {
  const manager = new SyncManager();
  assert(manager !== null);
  assert(manager.getSyncStats() !== null);
});

Deno.test("SyncManager - custom config", () => {
  const manager = new SyncManager({
    defaultTimeout: 10000,
    trackStats: false,
  });

  const stats = manager.getSyncStats();
  assertEquals(stats, null, "Stats should be null when tracking disabled");
});

Deno.test("SyncManager - stats reset", () => {
  const manager = new SyncManager();
  manager.resetSyncStats();

  const stats = manager.getSyncStats();
  assert(stats !== null);
  assertEquals(stats.totalSyncs, 0);
  assertEquals(stats.successfulSyncs, 0);
  assertEquals(stats.failedSyncs, 0);
});

// T019: Unit tests for sync() basic functionality
Deno.test("SyncManager - sync() basic success", async () => {
  const manager = new SyncManager();

  // Mock sendCommand that always succeeds
  const mockSendCommand = async (cmd: string) => {
    assert(cmd.startsWith("mark --add sync_") || cmd.startsWith("unmark sync_"));
    return { success: true };
  };

  const result = await manager.sync(mockSendCommand, 5000, "test-basic");

  assert(result.success, "Sync should succeed");
  assert(result.marker.marker.startsWith("sync_"), "Marker should have correct prefix");
  assertEquals(result.marker.testId, "test-basic");
  assert(result.latencyMs >= 0, "Latency should be non-negative");
  assert(result.error === undefined, "Error should be undefined on success");
});

Deno.test("SyncManager - sync() tracks marker generation", async () => {
  const manager = new SyncManager();
  const mockSendCommand = async () => ({ success: true });

  const result1 = await manager.sync(mockSendCommand);
  const result2 = await manager.sync(mockSendCommand);

  assert(result1.marker.marker !== result2.marker.marker, "Markers should be unique");
  assert(result1.marker.timestamp <= result2.marker.timestamp, "Timestamps should be sequential");
});

Deno.test("SyncManager - sync() calls mark and unmark", async () => {
  const manager = new SyncManager();
  const calls: string[] = [];

  const mockSendCommand = async (cmd: string) => {
    calls.push(cmd);
    return { success: true };
  };

  await manager.sync(mockSendCommand);

  assertEquals(calls.length, 2, "Should call mark and unmark");
  assert(calls[0].startsWith("mark --add sync_"), "First call should be mark");
  assert(calls[1].startsWith("unmark sync_"), "Second call should be unmark");
});

// T020: Unit tests for sync() timeout handling
Deno.test({
  name: "SyncManager - sync() timeout on slow command",
  sanitizeResources: false, // Expected resource leak due to intentional timeout
  async fn() {
    const manager = new SyncManager();

    // Mock sendCommand that takes too long
    const mockSendCommand = async () => {
      await new Promise((resolve) => setTimeout(resolve, 200));
      return { success: true };
    };

    const result = await manager.sync(mockSendCommand, 50); // 50ms timeout

    assertEquals(result.success, false, "Sync should fail on timeout");
    assert(result.error !== undefined, "Error should be defined");
    assert(result.error!.includes("timeout"), "Error should mention timeout");
  },
});

Deno.test({
  name: "SyncManager - sync() respects custom timeout",
  sanitizeResources: false, // Expected resource leak due to intentional timeout
  async fn() {
    const manager = new SyncManager({ defaultTimeout: 100 });
    let timeoutOccurred = false;

    const mockSendCommand = async () => {
      await new Promise((resolve) => setTimeout(resolve, 150));
      return { success: true };
    };

    const result = await manager.sync(mockSendCommand); // Uses default 100ms

    if (!result.success && result.error?.includes("timeout")) {
      timeoutOccurred = true;
    }

    assert(timeoutOccurred, "Should timeout using default config");
  },
});

// T021: Unit tests for sync() error handling
Deno.test("SyncManager - sync() handles mark command failure", async () => {
  const manager = new SyncManager();

  const mockSendCommand = async (cmd: string) => {
    if (cmd.startsWith("mark")) {
      return { success: false, error: "Mark command failed" };
    }
    return { success: true };
  };

  const result = await manager.sync(mockSendCommand);

  assertEquals(result.success, false);
  assert(result.error !== undefined);
  assert(result.error.includes("Mark command failed"));
});

Deno.test("SyncManager - sync() handles unmark command failure", async () => {
  const manager = new SyncManager();

  const mockSendCommand = async (cmd: string) => {
    if (cmd.startsWith("unmark")) {
      return { success: false, error: "Unmark command failed" };
    }
    return { success: true };
  };

  const result = await manager.sync(mockSendCommand);

  assertEquals(result.success, false);
  assert(result.error !== undefined);
  assert(result.error.includes("Unmark command failed"));
});

Deno.test("SyncManager - sync() tracks failed syncs in stats", async () => {
  const manager = new SyncManager();

  const mockSendCommand = async () => {
    return { success: false, error: "IPC error" };
  };

  await manager.sync(mockSendCommand);
  const stats = manager.getSyncStats();

  assert(stats !== null);
  assertEquals(stats.totalSyncs, 1);
  assertEquals(stats.failedSyncs, 1);
  assertEquals(stats.successfulSyncs, 0);
});

// Latency tracking tests
Deno.test("SyncManager - sync() tracks latency", async () => {
  const manager = new SyncManager();

  const mockSendCommand = async () => {
    await new Promise((resolve) => setTimeout(resolve, 5));
    return { success: true };
  };

  const result = await manager.sync(mockSendCommand);

  assert(result.latencyMs >= 5, "Latency should reflect actual delay");
  assert(result.endTime > result.startTime, "End time should be after start time");
});

Deno.test("SyncManager - sync() updates statistics", async () => {
  const manager = new SyncManager();

  const mockSendCommand = async () => ({ success: true });

  await manager.sync(mockSendCommand);
  await manager.sync(mockSendCommand);
  await manager.sync(mockSendCommand);

  const stats = manager.getSyncStats();
  assert(stats !== null);
  assertEquals(stats.totalSyncs, 3);
  assertEquals(stats.successfulSyncs, 3);
  assertEquals(stats.latencies.length, 3);
  assert(stats.averageLatencyMs >= 0);
});

Deno.test("SyncManager - sync() calculates p95/p99 correctly", async () => {
  const manager = new SyncManager();
  const mockSendCommand = async () => {
    // Variable delay to test percentile calculation
    await new Promise((resolve) => setTimeout(resolve, Math.random() * 5));
    return { success: true };
  };

  // Run 100 syncs to get meaningful percentiles
  for (let i = 0; i < 100; i++) {
    await manager.sync(mockSendCommand);
  }

  const stats = manager.getSyncStats();
  assert(stats !== null);
  assertEquals(stats.totalSyncs, 100);
  assert(stats.p95LatencyMs >= 0, "p95 should be non-negative");
  assert(stats.p99LatencyMs >= 0, "p99 should be non-negative");
  assert(stats.p99LatencyMs >= stats.p95LatencyMs, "p99 should be >= p95");
  assert(stats.maxLatencyMs >= stats.p99LatencyMs, "max should be >= p99");
})

// T052: Unit tests for executeLaunchAppSync()
Deno.test({
  name: "executeLaunchAppSync - launches app and synchronizes",
  sanitizeResources: false, // Disable resource leak detection - launches real app processes
  sanitizeOps: false, // Disable async operation leak detection
  async fn() {
    const { ActionExecutor } = await import("../../src/services/action-executor.ts");
    const { SwayClient } = await import("../../src/services/sway-client.ts");

    // Create mock SwayClient
    class MockSwayClient extends SwayClient {
      syncCalled = false;
      syncParams: { timeout?: number; testId?: string } = {};

      override async sync(timeout?: number, testId?: string) {
        this.syncCalled = true;
        this.syncParams = { timeout, testId };

        return {
          success: true,
          marker: {
            marker: "sync_test_12345",
            testId: testId || "unnamed",
            timestamp: Date.now(),
            randomId: "a7b3c9d",
          },
          latencyMs: 5,
          startTime: performance.now(),
          endTime: performance.now() + 5,
        };
      }
    }

    const mockClient = new MockSwayClient();
    const executor = new ActionExecutor({ swayClient: mockClient, autoSync: false });

    // Execute launch_app_sync action
    const action = {
      type: "launch_app_sync",
      params: {
        app_name: "terminal",
        timeout: 3000,
      },
    };

    await executor.execute([action]);

    // Verify sync was called
    assert(mockClient.syncCalled, "sync() should be called after launching app");
    assertEquals(mockClient.syncParams.timeout, 3000, "timeout should be passed to sync()");
  },
});

Deno.test({
  name: "executeLaunchAppSync - uses default timeout when not specified",
  sanitizeResources: false, // Disable resource leak detection - launches real app processes
  sanitizeOps: false, // Disable async operation leak detection
  async fn() {
    const { ActionExecutor } = await import("../../src/services/action-executor.ts");
    const { SwayClient } = await import("../../src/services/sway-client.ts");

    class MockSwayClient extends SwayClient {
      syncCalled = false;
      syncParams: { timeout?: number; testId?: string } = {};

      override async sync(timeout?: number, testId?: string) {
        this.syncCalled = true;
        this.syncParams = { timeout, testId };

        return {
          success: true,
          marker: {
            marker: "sync_test_default",
            testId: testId || "unnamed",
            timestamp: Date.now(),
            randomId: "xyz123",
          },
          latencyMs: 3,
          startTime: performance.now(),
          endTime: performance.now() + 3,
        };
      }
    }

    const mockClient = new MockSwayClient();
    const executor = new ActionExecutor({ swayClient: mockClient, autoSync: false });

    const action = {
      type: "launch_app_sync",
      params: {
        app_name: "terminal",
        // No timeout specified - should use default
      },
    };

    await executor.execute([action]);

    assert(mockClient.syncCalled, "sync() should be called");
    // Default timeout is undefined, which means use SwayClient's default
    assertEquals(mockClient.syncParams.timeout, undefined, "should use default timeout");
  },
});

// T053: Unit tests for executeSendIpcSync()
Deno.test({
  name: "executeSendIpcSync - sends IPC command and synchronizes",
  async fn() {
    const { ActionExecutor } = await import("../../src/services/action-executor.ts");
    const { SwayClient } = await import("../../src/services/sway-client.ts");

    class MockSwayClient extends SwayClient {
      syncCalled = false;
      syncParams: { timeout?: number; testId?: string } = {};
      sendCommandCalled = false;
      lastCommand = "";

      override async sendCommand(command: string) {
        this.sendCommandCalled = true;
        this.lastCommand = command;
        return { success: true, output: "" };
      }

      override async sync(timeout?: number, testId?: string) {
        this.syncCalled = true;
        this.syncParams = { timeout, testId };

        return {
          success: true,
          marker: {
            marker: "sync_ipc_test",
            testId: testId || "unnamed",
            timestamp: Date.now(),
            randomId: "abc789",
          },
          latencyMs: 4,
          startTime: performance.now(),
          endTime: performance.now() + 4,
        };
      }
    }

    const mockClient = new MockSwayClient();
    const executor = new ActionExecutor({ swayClient: mockClient, autoSync: false });

    const action = {
      type: "send_ipc_sync",
      params: {
        ipc_command: "workspace 5",
        timeout: 2000,
      },
    };

    await executor.execute([action]);

    // Verify IPC command was sent
    assert(mockClient.sendCommandCalled, "sendCommand() should be called");
    assertEquals(mockClient.lastCommand, "workspace 5", "should send correct command");

    // Verify sync was called after IPC command
    assert(mockClient.syncCalled, "sync() should be called after IPC command");
    assertEquals(mockClient.syncParams.timeout, 2000, "timeout should be passed to sync()");
  },
});

Deno.test({
  name: "executeSendIpcSync - requires ipc_command parameter",
  async fn() {
    const { ActionExecutor } = await import("../../src/services/action-executor.ts");
    const { SwayClient } = await import("../../src/services/sway-client.ts");

    const mockClient = new SwayClient();
    const executor = new ActionExecutor({ swayClient: mockClient, autoSync: false });

    const action = {
      type: "send_ipc_sync",
      params: {
        // Missing ipc_command
        timeout: 2000,
      },
    };

    let errorThrown = false;
    try {
      await executor.execute([action]);
    } catch (error) {
      errorThrown = true;
      assert((error as Error).message.includes("ipc_command"), "should require ipc_command parameter");
    }

    assert(errorThrown, "should throw error when ipc_command is missing");
  },
});
