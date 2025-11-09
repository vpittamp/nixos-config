#!/usr/bin/env -S deno run --allow-read --allow-write --allow-run --allow-env
/**
 * Workspace Assignment Test Suite
 *
 * Generates and runs tests for each app in app-registry-data.nix
 * to validate that they are assigned to the correct workspace.
 *
 * Features:
 * - Auto-generates test cases from Nix app registry
 * - Runs tests one at a time with live results
 * - Cleans up apps after each test
 * - Uses sync-based test framework for reliability
 */

import { parse as parseJsonc } from "https://deno.land/std@0.224.0/jsonc/mod.ts";

interface AppDefinition {
  name: string;
  display_name: string;
  command: string;
  parameters: string[];
  scope: "scoped" | "global";
  expected_class: string;
  preferred_workspace: number;
  icon: string;
  nix_package: string;
  multi_instance: boolean;
  fallback_behavior: "use_home" | "skip";
  description: string;
  terminal?: boolean;
}

interface TestCase {
  name: string;
  description: string;
  tags: string[];
  timeout: number;
  actions: Array<{
    type: string;
    params?: Record<string, unknown>;
    description?: string;
  }>;
  expectedState: {
    focusedWorkspace: number;
    workspaces: Array<{
      num: number;
      windows: Array<{
        app_id?: string;
        focused?: boolean;
      }>;
    }>;
  };
}

// Apps that are difficult to test or require special setup
const SKIP_APPS = [
  "scratchpad-terminal", // Launched by daemon, not via registry
  "fzf-file-search",     // Interactive search, closes immediately
  "neovim",              // Terminal-based, complex to test
  // Skip PWAs for now (would need firefox-pwa setup)
];

// Apps that need longer timeout
const SLOW_APPS = [
  "firefox",
  "chromium",
  "vscode",
];

async function getAppRegistry(): Promise<AppDefinition[]> {
  // Evaluate Nix expression to get app registry
  const cmd = new Deno.Command("nix-instantiate", {
    args: [
      "--eval",
      "--json",
      "--expr",
      `
      let
        pkgs = import <nixpkgs> {};
        lib = pkgs.lib;
        apps = import /etc/nixos/home-modules/desktop/app-registry-data.nix { inherit lib; };
      in
        builtins.map (app: {
          inherit (app) name display_name command parameters scope expected_class
                        preferred_workspace icon nix_package multi_instance
                        fallback_behavior description;
          terminal = app.terminal or false;
        }) apps
      `,
    ],
    stdout: "piped",
    stderr: "piped",
  });

  const { code, stdout, stderr } = await cmd.output();

  if (code !== 0) {
    const error = new TextDecoder().decode(stderr);
    throw new Error(`Failed to evaluate Nix expression: ${error}`);
  }

  const json = new TextDecoder().decode(stdout);
  return JSON.parse(json);
}

function generateTestCase(app: AppDefinition): TestCase {
  const timeout = SLOW_APPS.includes(app.name) ? 30000 : 15000;

  return {
    name: `${app.display_name} workspace assignment`,
    description: `Verify ${app.display_name} is assigned to workspace ${app.preferred_workspace}`,
    tags: ["workspace-assignment", "integration", app.scope],
    timeout,
    actions: [
      {
        type: "send_ipc_sync",
        params: {
          ipc_command: `[app_id="${app.expected_class}"] kill`,
        },
        description: `Kill any existing ${app.display_name} instances`,
      },
      {
        type: "launch_app_sync",
        params: {
          app_name: app.name,
        },
        description: `Launch ${app.display_name}`,
      },
    ],
    expectedState: {
      focusedWorkspace: app.preferred_workspace,
      workspaces: [
        {
          num: app.preferred_workspace,
          windows: [
            {
              app_id: app.expected_class,
              focused: true,
            },
          ],
        },
      ],
    },
  };
}

async function runTest(testFile: string, appName: string): Promise<{
  success: boolean;
  duration: number;
  error?: string;
}> {
  const startTime = performance.now();

  const cmd = new Deno.Command("./sway-test", {
    args: ["run", testFile],
    stdout: "piped",
    stderr: "piped",
    cwd: "/etc/nixos/home-modules/tools/sway-test",
  });

  const { code, stdout, stderr } = await cmd.output();
  const duration = Math.round(performance.now() - startTime);

  const output = new TextDecoder().decode(stdout);
  const errorOutput = new TextDecoder().decode(stderr);

  return {
    success: code === 0,
    duration,
    error: code !== 0 ? errorOutput || output : undefined,
  };
}

async function cleanupApp(appId: string): Promise<void> {
  const cmd = new Deno.Command("swaymsg", {
    args: ["-t", "command", `[app_id="${appId}"] kill`],
    stdout: "piped",
    stderr: "piped",
  });

  await cmd.output();
  // Wait a bit for cleanup
  await new Promise((resolve) => setTimeout(resolve, 500));
}

async function main() {
  console.log("🧪 Workspace Assignment Test Suite\n");
  console.log("Loading app registry from Nix...");

  const apps = await getAppRegistry();
  console.log(`Found ${apps.length} apps in registry\n`);

  // Filter out apps we want to skip
  const testableApps = apps.filter(
    (app) =>
      !SKIP_APPS.includes(app.name) &&
      !app.name.endsWith("-pwa") // Skip PWAs for now
  );

  console.log(`Testing ${testableApps.length} apps:\n`);

  const results: Array<{
    app: string;
    workspace: number;
    success: boolean;
    duration: number;
    error?: string;
  }> = [];

  let passed = 0;
  let failed = 0;

  for (let i = 0; i < testableApps.length; i++) {
    const app = testableApps[i];
    const testNum = i + 1;

    console.log(
      `\n[${"=".repeat(70)}]`
    );
    console.log(
      `Test ${testNum}/${testableApps.length}: ${app.display_name} → WS${app.preferred_workspace}`
    );
    console.log(`[${"=".repeat(70)}]\n`);

    // Generate test file
    const testCase = generateTestCase(app);
    const testFile = `/tmp/test_${app.name}_workspace.json`;
    await Deno.writeTextFile(testFile, JSON.stringify(testCase, null, 2));

    console.log(`📝 Test file: ${testFile}`);
    console.log(`🎯 Expected workspace: ${app.preferred_workspace}`);
    console.log(`🔍 Expected app_id: ${app.expected_class}`);
    console.log(`\n🚀 Running test...\n`);

    // Run test
    const result = await runTest(testFile, app.name);

    // Display result
    if (result.success) {
      console.log(`✅ PASS - ${app.display_name} correctly assigned to WS${app.preferred_workspace}`);
      console.log(`⏱️  Duration: ${result.duration}ms`);
      passed++;
    } else {
      console.log(`❌ FAIL - ${app.display_name} workspace assignment failed`);
      console.log(`⏱️  Duration: ${result.duration}ms`);
      if (result.error) {
        console.log(`\n📋 Error details:\n${result.error}`);
      }
      failed++;
    }

    results.push({
      app: app.display_name,
      workspace: app.preferred_workspace,
      success: result.success,
      duration: result.duration,
      error: result.error,
    });

    // Cleanup
    console.log(`\n🧹 Cleaning up ${app.display_name}...`);
    await cleanupApp(app.expected_class);

    // Clean up test file
    try {
      await Deno.remove(testFile);
    } catch {
      // Ignore cleanup errors
    }

    // Small delay between tests
    if (i < testableApps.length - 1) {
      console.log("\n⏳ Waiting 2 seconds before next test...");
      await new Promise((resolve) => setTimeout(resolve, 2000));
    }
  }

  // Final summary
  console.log(`\n\n${"=".repeat(80)}`);
  console.log("📊 TEST SUMMARY");
  console.log(`${"=".repeat(80)}\n`);

  console.log(`Total tests: ${testableApps.length}`);
  console.log(`✅ Passed: ${passed}`);
  console.log(`❌ Failed: ${failed}`);
  console.log(`Success rate: ${((passed / testableApps.length) * 100).toFixed(1)}%\n`);

  // Detailed results table
  console.log("Detailed Results:");
  console.log("-".repeat(80));
  console.log(
    String("App").padEnd(25) +
      String("WS").padEnd(6) +
      String("Result").padEnd(10) +
      String("Duration").padEnd(12)
  );
  console.log("-".repeat(80));

  for (const result of results) {
    const status = result.success ? "✅ PASS" : "❌ FAIL";
    console.log(
      String(result.app).padEnd(25) +
        String(`WS${result.workspace}`).padEnd(6) +
        String(status).padEnd(10) +
        String(`${result.duration}ms`).padEnd(12)
    );
  }
  console.log("-".repeat(80));

  // Exit with appropriate code
  Deno.exit(failed > 0 ? 1 : 0);
}

if (import.meta.main) {
  main().catch((error) => {
    console.error("Fatal error:", error);
    Deno.exit(1);
  });
}
