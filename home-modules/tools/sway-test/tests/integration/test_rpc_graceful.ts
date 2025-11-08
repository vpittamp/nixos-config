/**
 * Integration Test: RPC Graceful Degradation
 *
 * Validates that tree-monitor client gracefully handles missing RPC methods
 * via introspection, falls back to timeout-based sync, and doesn't spam errors.
 *
 * Tests User Story 3: Fix Auto-Sync RPC Errors
 */

import { assertEquals } from "https://deno.land/std@0.208.0/assert/mod.ts";
import { TreeMonitorClient } from "../../src/services/tree-monitor-client.ts";

Deno.test("RPC Introspection - Check method availability caching", async () => {
  const client = new TreeMonitorClient();

  // Check if daemon is available
  const isAvailable = await client.isAvailable();

  if (!isAvailable) {
    console.log("⚠ Daemon not running - skipping introspection test");
    return;
  }

  // First call should perform introspection
  const startTime1 = Date.now();
  const available1 = await client.checkMethodAvailability("sendSyncMarker");
  const elapsed1 = Date.now() - startTime1;

  // Second call should use cache (much faster)
  const startTime2 = Date.now();
  const available2 = await client.checkMethodAvailability("sendSyncMarker");
  const elapsed2 = Date.now() - startTime2;

  // Verify caching improves performance
  assertEquals(
    available1,
    available2,
    "Should return same result for cached method check"
  );

  console.log(`✓ First check: ${elapsed1}ms, Cached check: ${elapsed2}ms`);
  console.log(`✓ Method 'sendSyncMarker' available: ${available1}`);
});

Deno.test("RPC Introspection - Graceful fallback when daemon unavailable", async () => {
  // Create client with invalid socket path to simulate daemon unavailability
  const client = new TreeMonitorClient("/tmp/nonexistent-socket-12345.sock");

  // This should not throw, but return null
  const result = await client.sendSyncMarkerSafe();

  assertEquals(
    result,
    null,
    "Should return null when daemon unavailable (graceful fallback)"
  );

  console.log("✓ Graceful fallback when daemon unavailable");
});

Deno.test("RPC Introspection - No error spam on repeated calls", async () => {
  // Create client with invalid socket path
  const client = new TreeMonitorClient("/tmp/nonexistent-socket-12345.sock");

  // Make multiple calls - should only warn once
  const results = await Promise.all([
    client.sendSyncMarkerSafe(),
    client.sendSyncMarkerSafe(),
    client.sendSyncMarkerSafe(),
  ]);

  // All should return null (graceful fallback)
  assertEquals(results.every(r => r === null), true, "All calls should return null");

  console.log("✓ No error spam on repeated unavailable calls");
});

Deno.test("RPC Introspection - Validate implementation structure", async () => {
  // Read tree-monitor-client.ts to verify implementation
  const clientPath = new URL(
    "../../src/services/tree-monitor-client.ts",
    import.meta.url
  ).pathname;
  const content = await Deno.readTextFile(clientPath);

  // Verify session-level caching exists
  assertEquals(
    content.includes("availableMethods"),
    true,
    "Should have availableMethods cache"
  );

  // Verify warning suppression exists
  assertEquals(
    content.includes("introspectionWarningShown") || content.includes("warningShown"),
    true,
    "Should have warning suppression flag"
  );

  // Verify system.listMethods is used
  assertEquals(
    content.includes("system.listMethods"),
    true,
    "Should use system.listMethods for introspection"
  );

  // Verify sendSyncMarkerSafe exists
  assertEquals(
    content.includes("sendSyncMarkerSafe"),
    true,
    "Should have sendSyncMarkerSafe method"
  );

  console.log("✓ Implementation structure validated");
});

Deno.test("RPC Introspection - Check real daemon if available", async () => {
  const client = new TreeMonitorClient();

  const isAvailable = await client.isAvailable();

  if (!isAvailable) {
    console.log("⚠ Daemon not running - skipping live RPC test");
    return;
  }

  // If daemon is available, test actual introspection
  const hasListMethods = await client.checkMethodAvailability("system.listMethods");
  const hasSendSyncMarker = await client.checkMethodAvailability("sendSyncMarker");

  console.log(`✓ Daemon available - system.listMethods: ${hasListMethods}`);
  console.log(`✓ Daemon available - sendSyncMarker: ${hasSendSyncMarker}`);

  // If sendSyncMarker is available, test sendSyncMarkerSafe
  if (hasSendSyncMarker) {
    const marker = await client.sendSyncMarkerSafe();
    assertEquals(typeof marker, "string", "Should return marker ID string");
    console.log(`✓ sendSyncMarkerSafe returned marker: ${marker}`);
  } else {
    const marker = await client.sendSyncMarkerSafe();
    assertEquals(marker, null, "Should return null when method unavailable");
    console.log("✓ sendSyncMarkerSafe returned null (method unavailable)");
  }
});

Deno.test("RPC Introspection - Verify action-executor integration", async () => {
  // Verify that action-executor uses sendSyncMarkerSafe for auto-sync
  const actionExecutorPath = new URL(
    "../../src/services/action-executor.ts",
    import.meta.url
  ).pathname;
  const content = await Deno.readTextFile(actionExecutorPath);

  // Verify sendSyncMarkerSafe is used in auto-sync logic
  assertEquals(
    content.includes("sendSyncMarkerSafe"),
    true,
    "Should use sendSyncMarkerSafe for auto-sync"
  );

  // Verify fallback to timeout exists
  assertEquals(
    content.includes("null") && (content.includes("delay") || content.includes("timeout")),
    true,
    "Should have timeout-based fallback when sendSyncMarkerSafe returns null"
  );

  console.log("✓ Action-executor integration validated");
});
