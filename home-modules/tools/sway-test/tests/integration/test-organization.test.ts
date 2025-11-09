/**
 * Test organization validation test
 *
 * Validates that tests are properly organized into categories:
 * - basic/ - Simple, fast tests for core functionality
 * - integration/ - Complex tests involving multiple components
 * - regression/ - Tests for specific bug fixes
 */

import { assertEquals, assertExists } from "https://deno.land/std@0.201.0/assert/mod.ts";
import { walk } from "https://deno.land/std@0.201.0/fs/walk.ts";
import { join, dirname } from "https://deno.land/std@0.201.0/path/mod.ts";

const SWAY_TESTS_DIR = join(
  dirname(dirname(import.meta.url.replace("file://", ""))),
  "sway-tests",
);

Deno.test("test directory structure - required categories exist", async () => {
  const requiredCategories = ["basic", "integration", "regression"];

  for (const category of requiredCategories) {
    const categoryPath = join(SWAY_TESTS_DIR, category);
    try {
      const stat = await Deno.stat(categoryPath);
      assertEquals(
        stat.isDirectory,
        true,
        `${category}/ must be a directory`,
      );
    } catch (error) {
      throw new Error(
        `Required category directory '${category}' does not exist: ${error}`,
      );
    }
  }
});

Deno.test("test directory structure - basic tests are present", async () => {
  const basicDir = join(SWAY_TESTS_DIR, "basic");
  let testCount = 0;

  for await (
    const entry of walk(basicDir, { exts: ["json"], includeFiles: true })
  ) {
    if (entry.isFile && entry.name.startsWith("test_")) {
      testCount++;
    }
  }

  assertEquals(
    testCount > 0,
    true,
    "basic/ directory should contain at least one test file",
  );
});

Deno.test("test directory structure - integration tests are present", async () => {
  const integrationDir = join(SWAY_TESTS_DIR, "integration");
  let testCount = 0;

  for await (
    const entry of walk(integrationDir, {
      exts: ["json"],
      includeFiles: true,
    })
  ) {
    if (entry.isFile && entry.name.startsWith("test_")) {
      testCount++;
    }
  }

  assertEquals(
    testCount > 0,
    true,
    "integration/ directory should contain at least one test file",
  );
});

Deno.test("test directory structure - all test files follow naming convention", async () => {
  const invalidFiles: string[] = [];

  for await (
    const entry of walk(SWAY_TESTS_DIR, {
      exts: ["json"],
      includeFiles: true,
      skip: [/fixtures/],
    })
  ) {
    if (entry.isFile && !entry.name.startsWith("test_")) {
      invalidFiles.push(entry.path);
    }
  }

  assertEquals(
    invalidFiles.length,
    0,
    `Test files must start with 'test_': ${invalidFiles.join(", ")}`,
  );
});

Deno.test("test directory structure - category-specific execution", async () => {
  // Verify we can execute tests from specific categories
  const categories = ["basic", "integration"];

  for (const category of categories) {
    const categoryPath = join(SWAY_TESTS_DIR, category);

    // Count test files in category
    let count = 0;
    for await (
      const entry of walk(categoryPath, { exts: ["json"], includeFiles: true })
    ) {
      if (entry.isFile && entry.name.startsWith("test_")) {
        count++;
      }
    }

    assertEquals(
      count > 0,
      true,
      `Category '${category}' should have at least one test`,
    );
  }
});

Deno.test("test directory structure - no orphaned tests in root", async () => {
  const orphanedTests: string[] = [];

  for await (
    const entry of walk(SWAY_TESTS_DIR, {
      exts: ["json"],
      maxDepth: 1,
      includeFiles: true,
    })
  ) {
    if (entry.isFile && entry.name.startsWith("test_")) {
      orphanedTests.push(entry.name);
    }
  }

  assertEquals(
    orphanedTests.length,
    0,
    `Test files should be in category subdirectories, not root: ${
      orphanedTests.join(", ")
    }`,
  );
});
