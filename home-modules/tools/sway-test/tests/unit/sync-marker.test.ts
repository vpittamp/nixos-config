/**
 * Unit tests for SyncMarker model
 * Feature 069: Synchronization-Based Test Framework
 */

import { assertEquals, assert, assertThrows } from "@std/assert";
import {
  generateSyncMarker,
  validateSyncMarker,
  validateSyncConfig,
  DEFAULT_SYNC_CONFIG,
} from "../../src/models/sync-marker.ts";

Deno.test("generateSyncMarker - basic generation", () => {
  const marker = generateSyncMarker();

  assert(marker.marker.startsWith("sync_"), "Marker should start with sync_");
  assert(marker.timestamp > 0, "Timestamp should be positive");
  assertEquals(marker.randomId.length, 7, "Random ID should be 7 characters");
  assert(/^[a-z0-9]{7}$/.test(marker.randomId), "Random ID should be base36");
});

Deno.test("generateSyncMarker - uniqueness", () => {
  const marker1 = generateSyncMarker();
  const marker2 = generateSyncMarker();

  assert(
    marker1.marker !== marker2.marker,
    "Markers should be unique",
  );
  assert(
    marker1.randomId !== marker2.randomId,
    "Random IDs should be different",
  );
});

Deno.test("generateSyncMarker - with testId", () => {
  const testId = "test-firefox-launch";
  const marker = generateSyncMarker(testId);

  assertEquals(marker.testId, testId, "Test ID should be stored");
});

Deno.test("generateSyncMarker - format validation", () => {
  const marker = generateSyncMarker();
  assert(
    /^sync_\d+_[a-z0-9]{7}$/.test(marker.marker),
    "Marker should match expected format",
  );
});

Deno.test("validateSyncMarker - valid marker", () => {
  const result = validateSyncMarker("sync_1699887123456_a7b3c9d");
  assertEquals(result, true);
});

Deno.test("validateSyncMarker - invalid format", () => {
  assertThrows(
    () => validateSyncMarker("invalid_marker"),
    Error,
    "Invalid sync marker format",
  );
});

Deno.test("validateSyncMarker - wrong prefix", () => {
  assertThrows(
    () => validateSyncMarker("wrong_1699887123456_a7b3c9d"),
    Error,
    "Invalid sync marker format",
  );
});

Deno.test("validateSyncMarker - short random ID", () => {
  assertThrows(
    () => validateSyncMarker("sync_1699887123456_abc"),
    Error,
    "Invalid sync marker format",
  );
});

Deno.test("validateSyncConfig - valid config", () => {
  const result = validateSyncConfig({
    defaultTimeout: 5000,
    warnThresholdMs: 10,
    maxLatencyHistory: 100,
  });
  assertEquals(result, true);
});

Deno.test("validateSyncConfig - timeout out of range (too low)", () => {
  assertThrows(
    () => validateSyncConfig({ defaultTimeout: 50 }),
    Error,
    "defaultTimeout out of range",
  );
});

Deno.test("validateSyncConfig - timeout out of range (too high)", () => {
  assertThrows(
    () => validateSyncConfig({ defaultTimeout: 40000 }),
    Error,
    "defaultTimeout out of range",
  );
});

Deno.test("validateSyncConfig - warnThresholdMs out of range", () => {
  assertThrows(
    () => validateSyncConfig({ warnThresholdMs: 2000 }),
    Error,
    "warnThresholdMs out of range",
  );
});

Deno.test("validateSyncConfig - maxLatencyHistory out of range", () => {
  assertThrows(
    () => validateSyncConfig({ maxLatencyHistory: 5 }),
    Error,
    "maxLatencyHistory out of range",
  );
});

Deno.test("DEFAULT_SYNC_CONFIG - expected values", () => {
  assertEquals(DEFAULT_SYNC_CONFIG.defaultTimeout, 5000);
  assertEquals(DEFAULT_SYNC_CONFIG.logAllSyncs, false);
  assertEquals(DEFAULT_SYNC_CONFIG.warnThresholdMs, 10);
  assertEquals(DEFAULT_SYNC_CONFIG.trackStats, true);
  assertEquals(DEFAULT_SYNC_CONFIG.maxLatencyHistory, 100);
  assertEquals(DEFAULT_SYNC_CONFIG.markerPrefix, "sync");
});
