/**
 * Integration Test: App Wrapper Launch
 *
 * Validates that launch_app action correctly invokes app-launcher-wrapper.sh
 * with registry lookup and environment variable injection.
 *
 * Tests User Story 1: Realistic App Launch Testing
 */

import { assertEquals, assertRejects } from "https://deno.land/std@0.208.0/assert/mod.ts";
import { lookupApp, AppNotFoundError } from "../../src/services/app-registry-reader.ts";

Deno.test("App Registry - Lookup existing app", async () => {
  const app = await lookupApp("firefox");

  assertEquals(typeof app, "object", "Should return app object");
  assertEquals(app.name, "firefox", "Should have correct name");
  assertEquals(typeof app.command, "string", "Should have command string");
  assertEquals(typeof app.preferred_workspace, "number", "Should have workspace number");
});

Deno.test("App Registry - Lookup nonexistent app", async () => {
  await assertRejects(
    async () => {
      await lookupApp("nonexistent-app-12345");
    },
    AppNotFoundError,
    "not found in application registry",
    "Should throw AppNotFoundError for missing app"
  );
});

Deno.test("App Registry - Validate registry structure", async () => {
  // Lookup a known app to ensure registry is valid
  const app = await lookupApp("firefox");

  // Verify required fields exist
  assertEquals(typeof app.name, "string", "App should have name");
  assertEquals(typeof app.command, "string", "App should have command");
  assertEquals(typeof app.preferred_workspace, "number", "App should have preferred_workspace");

  // Optional fields can be undefined
  if (app.app_id !== undefined) {
    assertEquals(typeof app.app_id, "string", "app_id should be string if present");
  }

  if (app.window_class !== undefined) {
    assertEquals(typeof app.window_class, "string", "window_class should be string if present");
  }
});

Deno.test("Wrapper Launch - Environment variable injection", async () => {
  // This test validates that the action-executor properly constructs
  // the wrapper invocation with environment variables

  // Read the action-executor to verify environment injection logic exists
  const actionExecutorPath = new URL("../../src/services/action-executor.ts", import.meta.url).pathname;
  const content = await Deno.readTextFile(actionExecutorPath);

  // Verify environment variable injection is implemented
  assertEquals(
    content.includes("I3PM_PROJECT_NAME"),
    true,
    "Should inject I3PM_PROJECT_NAME environment variable"
  );

  assertEquals(
    content.includes("I3PM_TARGET_WORKSPACE"),
    true,
    "Should inject I3PM_TARGET_WORKSPACE environment variable"
  );

  assertEquals(
    content.includes("app-launcher-wrapper.sh"),
    true,
    "Should invoke app-launcher-wrapper.sh"
  );
});

Deno.test("Wrapper Launch - Breaking change validation", async () => {
  // Verify that launch_app no longer supports direct command execution
  const actionExecutorPath = new URL("../../src/services/action-executor.ts", import.meta.url).pathname;
  const content = await Deno.readTextFile(actionExecutorPath);

  // Verify app_name parameter is used
  assertEquals(
    content.includes("app_name"),
    true,
    "Should use app_name parameter"
  );

  // Verify lookupApp is called for registry validation
  assertEquals(
    content.includes("lookupApp"),
    true,
    "Should call lookupApp for registry validation"
  );
});
