#!/usr/bin/env -S deno run --allow-read --allow-write
/**
 * Migration Script: Timeout-Based → Sync-Based Tests
 *
 * Purpose: Automatically convert timeout-based wait_event tests to sync-based patterns
 * Feature: 069-sync-test-framework (T091)
 * Constitution Principle XII: Forward-Only Development
 *
 * Usage:
 *   ./scripts/migrate-to-sync.ts <input-file.json> [output-file.json]
 *   ./scripts/migrate-to-sync.ts --dry-run <input-file.json>
 *   ./scripts/migrate-to-sync.ts --all  # Migrate all tests from .migration-inventory.md
 *
 * Migration Patterns:
 *   Pattern 1: launch_app + wait_event → launch_app_sync
 *   Pattern 2: send_ipc + wait_event → send_ipc_sync
 *   Pattern 3: Multiple sequential launches → Multiple launch_app_sync
 */

import { parse } from "@std/path";

interface Action {
  type: string;
  params?: Record<string, unknown>;
}

interface TestCase {
  name: string;
  description?: string;
  tags?: string[];
  priority?: string;
  timeout?: number;
  actions: Action[];
  expectedState?: Record<string, unknown>;
}

interface MigrationResult {
  success: boolean;
  originalActions: number;
  migratedActions: number;
  patternsApplied: string[];
  errors: string[];
  warnings: string[];
}

/**
 * Check if action is a timeout-based wait_event
 */
function isTimeoutWaitEvent(action: Action): boolean {
  if (action.type !== "wait_event") return false;
  const params = action.params || {};
  return "timeout" in params || "timeout_ms" in params;
}

/**
 * Check if action is launch_app (not launch_app_sync)
 */
function isLegacyLaunchApp(action: Action): boolean {
  return action.type === "launch_app";
}

/**
 * Check if action is send_ipc (not send_ipc_sync)
 */
function isLegacySendIpc(action: Action): boolean {
  return action.type === "send_ipc";
}

/**
 * Pattern 1: launch_app + wait_event → launch_app_sync
 */
function migratePattern1(actions: Action[]): {
  actions: Action[];
  count: number;
} {
  const result: Action[] = [];
  let count = 0;
  let i = 0;

  while (i < actions.length) {
    const current = actions[i];
    const next = actions[i + 1];

    // Check for launch_app followed by wait_event
    if (
      isLegacyLaunchApp(current) &&
      next &&
      isTimeoutWaitEvent(next)
    ) {
      // Merge into launch_app_sync
      result.push({
        type: "launch_app_sync",
        params: current.params,
      });
      count++;
      i += 2; // Skip both launch_app and wait_event
    } else {
      result.push(current);
      i++;
    }
  }

  return { actions: result, count };
}

/**
 * Pattern 2: send_ipc + wait_event → send_ipc_sync
 */
function migratePattern2(actions: Action[]): {
  actions: Action[];
  count: number;
} {
  const result: Action[] = [];
  let count = 0;
  let i = 0;

  while (i < actions.length) {
    const current = actions[i];
    const next = actions[i + 1];

    // Check for send_ipc followed by wait_event
    if (
      isLegacySendIpc(current) &&
      next &&
      isTimeoutWaitEvent(next)
    ) {
      // Merge into send_ipc_sync
      result.push({
        type: "send_ipc_sync",
        params: current.params,
      });
      count++;
      i += 2; // Skip both send_ipc and wait_event
    } else {
      result.push(current);
      i++;
    }
  }

  return { actions: result, count };
}

/**
 * Remove standalone timeout-based wait_event actions (if not caught by patterns)
 */
function removeStandaloneTimeoutWaits(actions: Action[]): {
  actions: Action[];
  count: number;
} {
  const result: Action[] = [];
  let count = 0;

  for (const action of actions) {
    if (isTimeoutWaitEvent(action)) {
      count++;
      console.warn(
        `⚠️  Removed standalone timeout wait_event (timeout: ${
          action.params?.timeout || action.params?.timeout_ms
        }ms)`,
      );
      continue;
    }
    result.push(action);
  }

  return { actions: result, count };
}

/**
 * Update test description to indicate sync migration
 */
function updateDescription(testCase: TestCase): string {
  const original = testCase.description || testCase.name;
  if (original.includes("sync")) return original;

  return `${original} (migrated to sync pattern - eliminates race conditions and arbitrary timeouts)`;
}

/**
 * Add sync-related tags
 */
function updateTags(testCase: TestCase): string[] {
  const tags = testCase.tags || [];
  const syncTags = ["sync", "migrated"];

  // Add sync-related tags if not present
  const result = [...tags];
  for (const tag of syncTags) {
    if (!result.includes(tag)) {
      result.push(tag);
    }
  }

  return result;
}

/**
 * Migrate a single test case
 */
function migrateTestCase(testCase: TestCase): MigrationResult {
  const result: MigrationResult = {
    success: false,
    originalActions: testCase.actions.length,
    migratedActions: 0,
    patternsApplied: [],
    errors: [],
    warnings: [],
  };

  try {
    let actions = [...testCase.actions];

    // Apply Pattern 1: launch_app + wait_event → launch_app_sync
    const pattern1 = migratePattern1(actions);
    if (pattern1.count > 0) {
      actions = pattern1.actions;
      result.patternsApplied.push(
        `Pattern 1 (launch_app_sync): ${pattern1.count} conversions`,
      );
    }

    // Apply Pattern 2: send_ipc + wait_event → send_ipc_sync
    const pattern2 = migratePattern2(actions);
    if (pattern2.count > 0) {
      actions = pattern2.actions;
      result.patternsApplied.push(
        `Pattern 2 (send_ipc_sync): ${pattern2.count} conversions`,
      );
    }

    // Remove any remaining timeout-based wait_events
    const cleanup = removeStandaloneTimeoutWaits(actions);
    if (cleanup.count > 0) {
      actions = cleanup.actions;
      result.warnings.push(
        `Removed ${cleanup.count} standalone timeout wait_event(s)`,
      );
    }

    // Update test case
    testCase.actions = actions;
    testCase.description = updateDescription(testCase);
    testCase.tags = updateTags(testCase);

    result.migratedActions = actions.length;
    result.success = true;

    // Validation warnings
    if (result.patternsApplied.length === 0) {
      result.warnings.push("No migration patterns applied - test may already be sync-based");
    }
  } catch (error) {
    result.success = false;
    result.errors.push(`Migration failed: ${error.message}`);
  }

  return result;
}

/**
 * Main migration function
 */
async function migrateTest(
  inputPath: string,
  outputPath?: string,
  dryRun = false,
): Promise<MigrationResult> {
  console.log(`📝 Reading test: ${inputPath}`);

  // Read input file
  const content = await Deno.readTextFile(inputPath);
  const testCase: TestCase = JSON.parse(content);

  console.log(`📊 Original test: ${testCase.name}`);
  console.log(`   Actions: ${testCase.actions.length}`);

  // Migrate
  const result = migrateTestCase(testCase);

  // Report results
  console.log("\n🔄 Migration Results:");
  console.log(`   Success: ${result.success ? "✅" : "❌"}`);
  console.log(`   Original actions: ${result.originalActions}`);
  console.log(`   Migrated actions: ${result.migratedActions}`);
  console.log(`   Reduction: ${result.originalActions - result.migratedActions} actions`);

  if (result.patternsApplied.length > 0) {
    console.log("\n✨ Patterns Applied:");
    for (const pattern of result.patternsApplied) {
      console.log(`   - ${pattern}`);
    }
  }

  if (result.warnings.length > 0) {
    console.log("\n⚠️  Warnings:");
    for (const warning of result.warnings) {
      console.log(`   - ${warning}`);
    }
  }

  if (result.errors.length > 0) {
    console.log("\n❌ Errors:");
    for (const error of result.errors) {
      console.log(`   - ${error}`);
    }
  }

  // Write output
  if (!dryRun && result.success) {
    const output = outputPath || inputPath.replace(".json", "_sync.json");
    const formatted = JSON.stringify(testCase, null, 2);
    await Deno.writeTextFile(output, formatted + "\n");
    console.log(`\n💾 Saved migrated test: ${output}`);
  } else if (dryRun) {
    console.log("\n🔍 Dry run - no files written");
    console.log("\nMigrated test would be:");
    console.log(JSON.stringify(testCase, null, 2));
  }

  return result;
}

/**
 * Migrate all tests from migration inventory
 */
async function migrateAll(dryRun = false): Promise<void> {
  console.log("🚀 Migrating all timeout-based tests from inventory...\n");

  const testsToMigrate = [
    "tests/sway-tests/basic/test_walker_app_launch.json",
    "tests/sway-tests/integration/test_env_validation.json",
    "tests/sway-tests/integration/test_firefox_simple.json",
    "tests/sway-tests/integration/test_vscode_scoped.json",
    "tests/sway-tests/integration/test_pwa_workspace.json",
    "tests/sway-tests/basic/test_app_workspace_launch.json",
    "tests/sway-tests/integration/test_multi_app_workspaces.json",
  ];

  let totalSuccess = 0;
  let totalFailed = 0;

  for (const testPath of testsToMigrate) {
    console.log(`\n${"=".repeat(80)}`);
    try {
      const result = await migrateTest(testPath, undefined, dryRun);
      if (result.success) {
        totalSuccess++;
      } else {
        totalFailed++;
      }
    } catch (error) {
      console.error(`❌ Failed to migrate ${testPath}: ${error.message}`);
      totalFailed++;
    }
  }

  console.log(`\n${"=".repeat(80)}`);
  console.log("\n📊 Migration Summary:");
  console.log(`   Total tests: ${testsToMigrate.length}`);
  console.log(`   ✅ Successful: ${totalSuccess}`);
  console.log(`   ❌ Failed: ${totalFailed}`);

  if (totalSuccess === testsToMigrate.length) {
    console.log("\n✨ All tests migrated successfully!");
  }
}

/**
 * CLI entry point
 */
if (import.meta.main) {
  const args = Deno.args;

  if (args.length === 0) {
    console.log(`
Migration Script: Timeout-Based → Sync-Based Tests

Usage:
  ./scripts/migrate-to-sync.ts <input-file.json> [output-file.json]
  ./scripts/migrate-to-sync.ts --dry-run <input-file.json>
  ./scripts/migrate-to-sync.ts --all [--dry-run]

Examples:
  # Migrate single test (creates test_firefox_simple_sync.json)
  ./scripts/migrate-to-sync.ts tests/sway-tests/integration/test_firefox_simple.json

  # Migrate with custom output name
  ./scripts/migrate-to-sync.ts test_old.json test_new_sync.json

  # Dry run (show changes without writing)
  ./scripts/migrate-to-sync.ts --dry-run test_old.json

  # Migrate all tests from inventory
  ./scripts/migrate-to-sync.ts --all

  # Dry run all migrations
  ./scripts/migrate-to-sync.ts --all --dry-run
    `);
    Deno.exit(0);
  }

  const dryRun = args.includes("--dry-run");
  const all = args.includes("--all");

  if (all) {
    await migrateAll(dryRun);
  } else {
    const inputPath = args.find((arg) => !arg.startsWith("--"));
    const outputPath = args[args.indexOf(inputPath!) + 1];

    if (!inputPath) {
      console.error("❌ Error: Input file path required");
      Deno.exit(1);
    }

    await migrateTest(inputPath, outputPath, dryRun);
  }
}
