/**
 * Unit tests for ActionExecutor - Sync actions (Feature 069)
 */

import { assertEquals, assert } from "@std/assert";
import { ActionExecutor } from "../../src/services/action-executor.ts";
import { SwayClient } from "../../src/services/sway-client.ts";
import type { Action } from "../../src/models/test-case.ts";

// T038: Unit test for executeSync() action
Deno.test("ActionExecutor - sync action execution", async () => {
  // Create mock SwayClient with sync() method
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

  const syncAction: Action = {
    type: "sync",
    params: {
      timeout: 3000,
    },
  };

  // Execute sync action
  await executor.execute([syncAction]);

  // Verify sync was called
  assert(mockClient.syncCalled, "sync() should be called");
  assertEquals(mockClient.syncParams.timeout, 3000, "timeout should be passed");
});

Deno.test("ActionExecutor - sync action with default timeout", async () => {
  class MockSwayClient extends SwayClient {
    syncTimeout?: number;

    override async sync(timeout?: number) {
      this.syncTimeout = timeout;

      return {
        success: true,
        marker: {
          marker: "sync_default_12345",
          testId: "unnamed",
          timestamp: Date.now(),
          randomId: "abc1234",
        },
        latencyMs: 3,
        startTime: performance.now(),
        endTime: performance.now() + 3,
      };
    }
  }

  const mockClient = new MockSwayClient();
  const executor = new ActionExecutor({ swayClient: mockClient, autoSync: false });

  const syncAction: Action = {
    type: "sync",
    params: {},
  };

  await executor.execute([syncAction]);

  // Default timeout is 5000 when not specified
  assertEquals(mockClient.syncTimeout, 5000);
});

Deno.test("ActionExecutor - sync action failure", async () => {
  class MockSwayClient extends SwayClient {
    override async sync() {
      return {
        success: false,
        marker: {
          marker: "sync_fail_12345",
          testId: "unnamed",
          timestamp: Date.now(),
          randomId: "fail123",
        },
        latencyMs: 100,
        error: "Sync timeout - Sway may be unresponsive",
        startTime: performance.now(),
        endTime: performance.now() + 100,
      };
    }
  }

  const mockClient = new MockSwayClient();
  const executor = new ActionExecutor({ swayClient: mockClient, autoSync: false });

  const syncAction: Action = {
    type: "sync",
    params: {},
  };

  // Execute should throw error on sync failure
  try {
    await executor.execute([syncAction]);
    assert(false, "Should have thrown error");
  } catch (error) {
    assert((error as Error).message.includes("Sync failed"));
    assert((error as Error).message.includes("Sync timeout"));
  }
});
