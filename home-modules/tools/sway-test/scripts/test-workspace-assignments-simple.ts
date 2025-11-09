#!/usr/bin/env -S deno run --allow-read --allow-write --allow-run --allow-env
/**
 * Simple Workspace Assignment Test Suite
 *
 * Tests workspace assignments for key apps from app-registry-data.nix
 * Runs tests one at a time with live results and cleanup.
 */

interface AppTest {
  name: string;
  display_name: string;
  app_id: string;
  workspace: number;
  timeout?: number;
}

// Core apps to test (extracted from app-registry-data.nix)
const APPS_TO_TEST: AppTest[] = [
  {
    name: "firefox",
    display_name: "Firefox",
    app_id: "firefox",
    workspace: 3,
    timeout: 30000,
  },
  {
    name: "vscode",
    display_name: "VS Code",
    app_id: "Code",
    workspace: 2,
    timeout: 30000,
  },
  {
    name: "terminal",
    display_name: "Ghostty Terminal",
    app_id: "com.mitchellh.ghostty",
    workspace: 1,
  },
  {
    name: "lazygit",
    display_name: "Lazygit",
    app_id: "com.mitchellh.ghostty",
    workspace: 5,
  },
  {
    name: "yazi",
    display_name: "Yazi File Manager",
    app_id: "com.mitchellh.ghostty",
    workspace: 8,
  },
  {
    name: "btop",
    display_name: "btop",
    app_id: "btop",
    workspace: 7,
  },
  {
    name: "htop",
    display_name: "htop",
    app_id: "htop",
    workspace: 7,
  },
  {
    name: "k9s",
    display_name: "K9s",
    app_id: "k9s",
    workspace: 9,
  },
  {
    name: "ghostty",
    display_name: "Ghostty Terminal (WS12)",
    app_id: "com.mitchellh.ghostty",
    workspace: 12,
  },
];

function generateTestCase(app: AppTest) {
  const timeout = app.timeout || 15000;

  return {
    name: `${app.display_name} workspace assignment`,
    description: `Verify ${app.display_name} is assigned to workspace ${app.workspace}`,
    tags: ["workspace-assignment", "integration"],
    timeout,
    actions: [
      {
        type: "launch_app",
        params: {
          app_name: app.name,
        },
        description: `Launch ${app.display_name}`,
      },
      {
        type: "wait_event",
        params: {
          event_type: "window",
          criteria: {
            change: "new",
          },
          timeout,
        },
        description: "Wait for window to appear",
      },
    ],
    expectedState: {
      focusedWorkspace: app.workspace,
      workspaces: [
        {
          num: app.workspace,
          windows: [
            {
              app_id: app.app_id,
              focused: true,
            },
          ],
        },
      ],
    },
  };
}

async function runTest(testFile: string): Promise<{
  success: boolean;
  duration: number;
  output: string;
}> {
  const startTime = performance.now();

  const cmd = new Deno.Command("deno", {
    args: ["run", "--allow-all", "--no-check", "main.ts", "run", testFile],
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
    output: code !== 0 ? (errorOutput || output) : output,
  };
}

async function cleanupApp(appId: string): Promise<void> {
  const cmd = new Deno.Command("swaymsg", {
    args: ["-t", "command", `[app_id="${appId}"] kill`],
    stdout: "piped",
    stderr: "piped",
  });

  await cmd.output();
  // Wait for cleanup
  await new Promise((resolve) => setTimeout(resolve, 1000));
}

async function main() {
  console.log("🧪 Workspace Assignment Test Suite\n");
  console.log(`Testing ${APPS_TO_TEST.length} apps:\n`);

  const results: Array<{
    app: string;
    workspace: number;
    success: boolean;
    duration: number;
    output?: string;
  }> = [];

  let passed = 0;
  let failed = 0;

  for (let i = 0; i < APPS_TO_TEST.length; i++) {
    const app = APPS_TO_TEST[i];
    const testNum = i + 1;

    console.log(`\n${"=".repeat(80)}`);
    console.log(
      `Test ${testNum}/${APPS_TO_TEST.length}: ${app.display_name} → WS${app.workspace}`
    );
    console.log(`${"=".repeat(80)}\n`);

    // Generate test file
    const testCase = generateTestCase(app);
    const testFile = `/tmp/test_${app.name}_workspace.json`;
    await Deno.writeTextFile(testFile, JSON.stringify(testCase, null, 2));

    console.log(`📝 Test: ${app.display_name}`);
    console.log(`🎯 Expected workspace: ${app.workspace}`);
    console.log(`🔍 Expected app_id: ${app.app_id}`);
    console.log(`\n🚀 Running test...\n`);

    // Run test
    const result = await runTest(testFile);

    // Display result
    if (result.success) {
      console.log(
        `✅ PASS - ${app.display_name} correctly assigned to WS${app.workspace}`
      );
      console.log(`⏱️  Duration: ${result.duration}ms`);
      passed++;
    } else {
      console.log(`❌ FAIL - ${app.display_name} workspace assignment failed`);
      console.log(`⏱️  Duration: ${result.duration}ms`);
      console.log(`\n📋 Test output:\n${result.output.slice(0, 500)}`);
      failed++;
    }

    results.push({
      app: app.display_name,
      workspace: app.workspace,
      success: result.success,
      duration: result.duration,
      output: result.success ? undefined : result.output,
    });

    // Cleanup
    console.log(`\n🧹 Cleaning up ${app.display_name}...`);
    await cleanupApp(app.app_id);

    // Clean up test file
    try {
      await Deno.remove(testFile);
    } catch {
      // Ignore cleanup errors
    }

    // Delay between tests
    if (i < APPS_TO_TEST.length - 1) {
      console.log("\n⏳ Waiting 2 seconds before next test...");
      await new Promise((resolve) => setTimeout(resolve, 2000));
    }
  }

  // Final summary
  console.log(`\n\n${"=".repeat(80)}`);
  console.log("📊 TEST SUMMARY");
  console.log(`${"=".repeat(80)}\n`);

  console.log(`Total tests: ${APPS_TO_TEST.length}`);
  console.log(`✅ Passed: ${passed}`);
  console.log(`❌ Failed: ${failed}`);
  console.log(
    `Success rate: ${((passed / APPS_TO_TEST.length) * 100).toFixed(1)}%\n`
  );

  // Detailed results table
  console.log("Detailed Results:");
  console.log("-".repeat(80));
  console.log(
    String("App").padEnd(30) +
      String("WS").padEnd(6) +
      String("Result").padEnd(12) +
      String("Duration")
  );
  console.log("-".repeat(80));

  for (const result of results) {
    const status = result.success ? "✅ PASS" : "❌ FAIL";
    console.log(
      String(result.app).padEnd(30) +
        String(`WS${result.workspace}`).padEnd(6) +
        String(status).padEnd(12) +
        String(`${result.duration}ms`)
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
