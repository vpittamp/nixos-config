/**
 * Unit tests for test helper functions (User Story 3)
 *
 * Validates that helper functions correctly:
 * - Execute commands
 * - Sync to ensure completion
 * - Query and return expected state
 * - Handle errors gracefully
 *
 * @file test-helpers.test.ts
 */

import { assertEquals, assertRejects } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { focusAfter, focusedWorkspaceAfter, windowCountAfter } from "../../src/services/test-helpers.ts";
import { SwayClient } from "../../src/services/sway-client.ts";
import type { SyncResult } from "../../src/models/sync-marker.ts";
import type { StateSnapshot } from "../../src/models/state-snapshot.ts";

// ============================================================================
// Mock SwayClient for Testing
// ============================================================================

class MockSwayClient extends SwayClient {
  lastCommand = "";
  syncCalled = false;
  syncSuccess = true;
  mockTree: StateSnapshot = createEmptyTree();

  override async sendCommand(command: string) {
    this.lastCommand = command;
    return { success: true, output: "" };
  }

  override async sync(_timeout?: number, testId?: string): Promise<SyncResult> {
    this.syncCalled = true;
    return {
      success: this.syncSuccess,
      marker: {
        marker: "sync_test_mock",
        testId: testId || "unnamed",
        timestamp: Date.now(),
        randomId: "abc123",
      },
      latencyMs: 5,
      startTime: performance.now(),
      endTime: performance.now() + 5,
    };
  }

  override async getTree(): Promise<StateSnapshot> {
    return this.mockTree;
  }
}

/**
 * Create an empty Sway tree for testing
 */
function createEmptyTree(): StateSnapshot {
  return {
    id: 1,
    name: "root",
    type: "root",
    orientation: "horizontal",
    rect: { x: 0, y: 0, width: 1920, height: 1080 },
    nodes: [],
    floating_nodes: [],
    focus: [],
  };
}

// ============================================================================
// Tests for focusAfter()
// ============================================================================

Deno.test({
  name: "focusAfter() - executes command, syncs, and returns focused node",
  async fn() {
    const mockClient = new MockSwayClient();
    mockClient.mockTree = {
      id: 1,
      name: "root",
      type: "root",
      orientation: "horizontal",
      rect: { x: 0, y: 0, width: 1920, height: 1080 },
      focus: [],
      floating_nodes: [],
      nodes: [
        {
          id: 2,
          name: "output1",
          type: "output",
          rect: { x: 0, y: 0, width: 1920, height: 1080 },
          focus: [],
          floating_nodes: [],
          nodes: [
            {
              id: 3,
              name: "1",
              type: "workspace",
              num: 1,
              rect: { x: 0, y: 0, width: 1920, height: 1080 },
              focus: [],
              floating_nodes: [],
              nodes: [
                {
                  id: 4,
                  name: "ghostty",
                  type: "con",
                  app_id: "ghostty",
                  focused: true,
                  rect: { x: 0, y: 0, width: 800, height: 600 },
                  focus: [],
                  floating_nodes: [],
                  nodes: [],
                },
              ],
            },
          ],
        },
      ],
    };

    const result = await focusAfter(mockClient, "focus left");

    // Verify command was executed
    assertEquals(mockClient.lastCommand, "focus left");

    // Verify sync was called
    assertEquals(mockClient.syncCalled, true);

    // Verify focused node was returned
    assertEquals(result?.app_id, "ghostty");
    assertEquals(result?.focused, true);
  },
});

Deno.test({
  name: "focusAfter() - returns null when no node is focused",
  async fn() {
    const mockClient = new MockSwayClient();
    mockClient.mockTree = {
      type: "root",
      nodes: [
        {
          type: "workspace",
          num: 1,
          nodes: [
            {
              type: "con",
              app_id: "ghostty",
              focused: false,
              window: 12345,
            },
          ],
        },
      ],
    };

    const result = await focusAfter(mockClient, "focus left");

    // No focused node in tree
    assertEquals(result, null);
  },
});

Deno.test({
  name: "focusAfter() - throws error when sync fails",
  async fn() {
    const mockClient = new MockSwayClient();
    mockClient.syncSuccess = false;

    await assertRejects(
      async () => {
        await focusAfter(mockClient, "focus left");
      },
      Error,
      'Sync failed after command "focus left"',
    );
  },
});

// ============================================================================
// Tests for focusedWorkspaceAfter()
// ============================================================================

Deno.test({
  name: "focusedWorkspaceAfter() - executes command, syncs, and returns focused workspace number",
  async fn() {
    const mockClient = new MockSwayClient();
    mockClient.mockTree = {
      type: "root",
      nodes: [
        {
          type: "workspace",
          num: 7,
          focused: true,
          nodes: [],
        },
      ],
    };

    const result = await focusedWorkspaceAfter(mockClient, "workspace 7");

    // Verify command was executed
    assertEquals(mockClient.lastCommand, "workspace 7");

    // Verify sync was called
    assertEquals(mockClient.syncCalled, true);

    // Verify focused workspace number was returned
    assertEquals(result, 7);
  },
});

Deno.test({
  name: "focusedWorkspaceAfter() - returns null when no workspace is focused",
  async fn() {
    const mockClient = new MockSwayClient();
    mockClient.mockTree = {
      type: "root",
      nodes: [
        {
          type: "workspace",
          num: 7,
          focused: false,
          nodes: [],
        },
      ],
    };

    const result = await focusedWorkspaceAfter(mockClient, "workspace 7");

    // No focused workspace in tree
    assertEquals(result, null);
  },
});

Deno.test({
  name: "focusedWorkspaceAfter() - throws error when sync fails",
  async fn() {
    const mockClient = new MockSwayClient();
    mockClient.syncSuccess = false;

    await assertRejects(
      async () => {
        await focusedWorkspaceAfter(mockClient, "workspace 7");
      },
      Error,
      'Sync failed after command "workspace 7"',
    );
  },
});

// ============================================================================
// Tests for windowCountAfter()
// ============================================================================

Deno.test({
  name: "windowCountAfter() - executes command, syncs, and returns total window count",
  async fn() {
    const mockClient = new MockSwayClient();
    mockClient.mockTree = {
      type: "root",
      nodes: [
        {
          type: "workspace",
          num: 1,
          nodes: [
            {
              type: "con",
              app_id: "ghostty",
              window: 12345,
              nodes: [],
            },
            {
              type: "con",
              app_id: "ghostty",
              window: 67890,
              nodes: [],
            },
          ],
        },
      ],
    };

    const result = await windowCountAfter(mockClient, "nop");

    // Verify command was executed
    assertEquals(mockClient.lastCommand, "nop");

    // Verify sync was called
    assertEquals(mockClient.syncCalled, true);

    // Verify window count
    assertEquals(result, 2);
  },
});

Deno.test({
  name: "windowCountAfter() - filters by workspace when workspace parameter provided",
  async fn() {
    const mockClient = new MockSwayClient();
    mockClient.mockTree = {
      type: "root",
      nodes: [
        {
          type: "workspace",
          num: 1,
          nodes: [
            {
              type: "con",
              app_id: "ghostty",
              window: 12345,
              nodes: [],
            },
          ],
        },
        {
          type: "workspace",
          num: 5,
          nodes: [
            {
              type: "con",
              app_id: "firefox",
              window: 67890,
              nodes: [],
            },
            {
              type: "con",
              app_id: "code",
              window: 11111,
              nodes: [],
            },
          ],
        },
      ],
    };

    // Count windows on workspace 5
    const result = await windowCountAfter(mockClient, "nop", 5);

    // Verify only workspace 5 windows are counted
    assertEquals(result, 2);
  },
});

Deno.test({
  name: "windowCountAfter() - returns 0 when no windows exist",
  async fn() {
    const mockClient = new MockSwayClient();
    mockClient.mockTree = {
      type: "root",
      nodes: [
        {
          type: "workspace",
          num: 1,
          nodes: [],
        },
      ],
    };

    const result = await windowCountAfter(mockClient, "nop");

    // No windows in tree
    assertEquals(result, 0);
  },
});

Deno.test({
  name: "windowCountAfter() - throws error when sync fails",
  async fn() {
    const mockClient = new MockSwayClient();
    mockClient.syncSuccess = false;

    await assertRejects(
      async () => {
        await windowCountAfter(mockClient, "nop");
      },
      Error,
      'Sync failed after command "nop"',
    );
  },
});

Deno.test({
  name: "windowCountAfter() - counts floating windows",
  async fn() {
    const mockClient = new MockSwayClient();
    mockClient.mockTree = {
      type: "root",
      nodes: [
        {
          type: "workspace",
          num: 1,
          nodes: [
            {
              type: "con",
              app_id: "ghostty",
              window: 12345,
              nodes: [],
            },
          ],
          floating_nodes: [
            {
              type: "con",
              app_id: "calculator",
              window: 99999,
              nodes: [],
            },
          ],
        },
      ],
    };

    const result = await windowCountAfter(mockClient, "nop");

    // Should count both tiled and floating windows
    assertEquals(result, 2);
  },
});
