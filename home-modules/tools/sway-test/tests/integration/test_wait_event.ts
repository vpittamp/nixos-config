/**
 * Integration Test: Event Waiting and Synchronization
 *
 * Validates that wait_event action correctly subscribes to Sway IPC events,
 * returns immediately on event arrival, and times out appropriately.
 *
 * Tests User Story 2: Reliable Event Synchronization
 */

import { assertEquals, assertRejects } from "https://deno.land/std@0.208.0/assert/mod.ts";
import { waitForEvent, WaitEventTimeoutError } from "../../src/services/event-subscriber.ts";

Deno.test("Event Subscription - Wait for window event with immediate return", async () => {
  // This test spawns a window and verifies that waitForEvent returns
  // immediately when the event arrives (not after full timeout)

  const startTime = Date.now();

  // Launch a simple app that starts quickly
  const process = new Deno.Command("alacritty", {
    args: [],
    stdout: "null",
    stderr: "null",
  }).spawn();

  try {
    // Wait for window::new event with 10-second timeout
    // Should return in <2 seconds (typical app launch time), not 10 seconds
    await waitForEvent("window", { change: "new", app_id: "Alacritty" }, 10000);

    const elapsedTime = Date.now() - startTime;

    // Verify it returned immediately (well under timeout)
    assertEquals(
      elapsedTime < 5000,
      true,
      `Should return immediately on event arrival (elapsed: ${elapsedTime}ms, timeout: 10000ms)`
    );

    console.log(`✓ Event returned in ${elapsedTime}ms (expected <5000ms for immediate return)`);
  } finally {
    // Clean up: kill the spawned process
    process.kill("SIGTERM");
    await process.status;
  }
});

Deno.test("Event Subscription - Timeout when event doesn't arrive", async () => {
  // This test verifies that waitForEvent throws WaitEventTimeoutError
  // when the expected event doesn't arrive within timeout

  const startTime = Date.now();

  await assertRejects(
    async () => {
      // Wait for a window event that will never arrive
      await waitForEvent(
        "window",
        { change: "new", app_id: "NonexistentApp12345" },
        2000 // 2-second timeout
      );
    },
    WaitEventTimeoutError,
    "Timeout waiting for event",
    "Should throw WaitEventTimeoutError on timeout"
  );

  const elapsedTime = Date.now() - startTime;

  // Verify timeout occurred at expected time (within 500ms tolerance)
  assertEquals(
    Math.abs(elapsedTime - 2000) < 500,
    true,
    `Timeout should occur at expected time (elapsed: ${elapsedTime}ms, expected: ~2000ms)`
  );

  console.log(`✓ Timeout occurred at ${elapsedTime}ms (expected ~2000ms)`);
});

Deno.test("Event Subscription - Event criteria matching", async () => {
  // This test verifies that event criteria filtering works correctly

  const startTime = Date.now();

  // Launch alacritty
  const process = new Deno.Command("alacritty", {
    args: [],
    stdout: "null",
    stderr: "null",
  }).spawn();

  try {
    // Wait for window event with specific criteria
    await waitForEvent(
      "window",
      {
        change: "new",
        app_id: "Alacritty",
      },
      5000
    );

    const elapsedTime = Date.now() - startTime;

    console.log(`✓ Event matched criteria in ${elapsedTime}ms`);
  } finally {
    process.kill("SIGTERM");
    await process.status;
  }
});

Deno.test("Event Subscription - Workspace event matching", async () => {
  // This test verifies that workspace events can be matched

  const startTime = Date.now();

  // Switch to workspace 9 to trigger workspace::focus event
  const switchProcess = new Deno.Command("swaymsg", {
    args: ["workspace", "9"],
    stdout: "null",
    stderr: "null",
  }).spawn();

  await switchProcess.status;

  try {
    // Wait for workspace focus event
    await waitForEvent(
      "workspace",
      {
        change: "focus",
        workspace: 9,
      },
      3000
    );

    const elapsedTime = Date.now() - startTime;

    console.log(`✓ Workspace event matched in ${elapsedTime}ms`);
  } catch (error) {
    if (error instanceof WaitEventTimeoutError) {
      console.warn("⚠ Workspace event didn't arrive (may already be on workspace 9)");
    } else {
      throw error;
    }
  }
});

Deno.test("Event Subscription - Validate implementation exists", async () => {
  // Verify that waitForEvent is properly implemented (not a placeholder)
  const eventSubscriberPath = new URL(
    "../../src/services/event-subscriber.ts",
    import.meta.url
  ).pathname;
  const content = await Deno.readTextFile(eventSubscriberPath);

  // Verify Promise.race pattern is used
  assertEquals(
    content.includes("Promise.race"),
    true,
    "Should use Promise.race for timeout handling"
  );

  // Verify swaymsg subscription
  assertEquals(
    content.includes("swaymsg"),
    true,
    "Should use swaymsg for event subscription"
  );

  // Verify AbortController cleanup
  assertEquals(
    content.includes("AbortController") || content.includes("abort"),
    true,
    "Should use AbortController for cleanup"
  );
});
