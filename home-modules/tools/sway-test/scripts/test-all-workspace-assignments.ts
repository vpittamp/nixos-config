#!/usr/bin/env -S deno run --allow-read --allow-write --allow-run --allow-env
/**
 * Comprehensive Workspace Assignment Test Suite
 *
 * Tests workspace assignments for all apps in the registry using the same
 * launch mechanism that users would use (app-launcher-wrapper).
 *
 * Features:
 * - Reads apps from ~/.config/i3/app-registry.json (generated from Nix)
 * - Launches apps via app-launcher-wrapper (user-facing mechanism)
 * - Proper cleanup including Firefox PWAs
 * - Validates workspace assignments match registry
 * - Skips apps that are difficult to test (scratchpad, fzf, PWAs)
 */

interface AppDefinition {
  name: string;
  display_name: string;
  expected_class: string;
  preferred_workspace: number;
  scope: "scoped" | "global";
  multi_instance: boolean;
}

interface TestResult {
  app: string;
  workspace: number;
  success: boolean;
  duration: number;
  error?: string;
}

// Apps that should not be tested
const SKIP_APPS = [
  "scratchpad-terminal", // Launched by daemon, not via wrapper
  "fzf-file-search",     // Interactive, closes immediately
  "neovim",              // Complex terminal app with nvim session
];

// Apps that need longer timeout
const SLOW_APPS = {
  "firefox": 15000,
  "chromium": 15000,
  "vscode": 15000,
  "thunar": 8000,
};

// Default timeout for most apps
const DEFAULT_TIMEOUT = 8000;

async function loadAppRegistry(): Promise<AppDefinition[]> {
  const registryPath = `${Deno.env.get("HOME")}/.config/i3/application-registry.json`;
  const content = await Deno.readTextFile(registryPath);
  const registry = JSON.parse(content);
  return registry.applications;
}

async function killAllAppInstances(expectedClass: string, appName: string): Promise<void> {
  // Kill by app_id
  await new Deno.Command("swaymsg", {
    args: ["-t", "command", `[app_id="${expectedClass}"] kill`],
    stdout: "piped",
    stderr: "piped",
  }).output();

  // For Firefox, also kill all processes to avoid PWA interference
  if (appName === "firefox") {
    await new Deno.Command("pkill", {
      args: ["-9", "firefox"],
      stdout: "piped",
      stderr: "piped",
    }).output();

    // Wait longer for Firefox to fully terminate
    await new Promise((resolve) => setTimeout(resolve, 3000));
  } else {
    // Standard cleanup wait
    await new Promise((resolve) => setTimeout(resolve, 1000));
  }
}

async function launchApp(appName: string, timeout: number): Promise<{
  success: boolean;
  error?: string;
}> {
  console.log(`  🚀 Launching ${appName} via app-launcher-wrapper...`);

  const cmd = new Deno.Command("app-launcher-wrapper", {
    args: [appName],
    stdout: "piped",
    stderr: "piped",
  });

  const process = cmd.spawn();

  // Don't wait for the process to complete (apps run in background)
  // Just give it time to start
  await new Promise((resolve) => setTimeout(resolve, timeout));

  return { success: true };
}

async function checkWorkspaceAssignment(
  appName: string,
  expectedWorkspace: number
): Promise<{
  success: boolean;
  actualWorkspace?: number;
  error?: string;
}> {
  const cmd = new Deno.Command("swaymsg", {
    args: ["-t", "get_tree"],
    stdout: "piped",
    stderr: "piped",
  });

  const { code, stdout, stderr } = await cmd.output();

  if (code !== 0) {
    const error = new TextDecoder().decode(stderr);
    return { success: false, error: `Failed to get Sway tree: ${error}` };
  }

  const tree = JSON.parse(new TextDecoder().decode(stdout));

  // Find workspace with the app by reading environment variables
  let foundWorkspace: number | undefined;
  let matchedPid: number | undefined;

  function findInTree(node: any): void {
    if (node.type === "workspace" && node.num && node.nodes) {
      for (const child of node.nodes) {
        if (child.pid) {
          // Read environment variables from /proc/<pid>/environ
          try {
            const envContent = Deno.readTextFileSync(`/proc/${child.pid}/environ`);
            const envVars = new Map<string, string>();

            // Parse null-separated environment variables
            envContent.split('\0').forEach(line => {
              const [key, ...valueParts] = line.split('=');
              if (key && valueParts.length > 0) {
                envVars.set(key, valueParts.join('='));
              }
            });

            // Check if I3PM_APP_NAME matches
            const i3pmAppName = envVars.get('I3PM_APP_NAME');
            if (i3pmAppName === appName) {
              foundWorkspace = node.num;
              matchedPid = child.pid;
              return;
            }
          } catch (_e) {
            // /proc/<pid>/environ may not be readable, skip
          }
        }
      }
    }

    if (node.nodes) {
      for (const child of node.nodes) {
        findInTree(child);
      }
    }

    if (node.floating_nodes) {
      for (const child of node.floating_nodes) {
        findInTree(child);
      }
    }
  }

  findInTree(tree);

  if (foundWorkspace === undefined) {
    return {
      success: false,
      error: `Window with I3PM_APP_NAME="${appName}" not found in Sway tree`,
    };
  }

  if (foundWorkspace !== expectedWorkspace) {
    return {
      success: false,
      actualWorkspace: foundWorkspace,
      error: `Expected workspace ${expectedWorkspace}, found on workspace ${foundWorkspace} (PID: ${matchedPid})`,
    };
  }

  return { success: true, actualWorkspace: foundWorkspace };
}

async function testApp(app: AppDefinition): Promise<TestResult> {
  const startTime = performance.now();
  const timeout = (SLOW_APPS as any)[app.name] || DEFAULT_TIMEOUT;

  try {
    // 1. Cleanup: Kill any existing instances
    console.log(`  🧹 Cleaning up existing ${app.display_name} instances...`);
    await killAllAppInstances(app.expected_class, app.name);

    // 2. Launch the app
    const launchResult = await launchApp(app.name, timeout);
    if (!launchResult.success) {
      return {
        app: app.display_name,
        workspace: app.preferred_workspace,
        success: false,
        duration: Math.round(performance.now() - startTime),
        error: launchResult.error,
      };
    }

    // 3. Check workspace assignment
    console.log(`  🔍 Checking workspace assignment...`);
    const checkResult = await checkWorkspaceAssignment(
      app.name,
      app.preferred_workspace
    );

    const duration = Math.round(performance.now() - startTime);

    if (checkResult.success) {
      console.log(
        `  ✅ SUCCESS - ${app.display_name} on workspace ${app.preferred_workspace}`
      );
      return {
        app: app.display_name,
        workspace: app.preferred_workspace,
        success: true,
        duration,
      };
    } else {
      console.log(`  ❌ FAIL - ${checkResult.error}`);
      return {
        app: app.display_name,
        workspace: app.preferred_workspace,
        success: false,
        duration,
        error: checkResult.error,
      };
    }
  } catch (error) {
    const duration = Math.round(performance.now() - startTime);
    console.log(`  ❌ ERROR - ${error.message}`);
    return {
      app: app.display_name,
      workspace: app.preferred_workspace,
      success: false,
      duration,
      error: error.message,
    };
  }
}

async function main() {
  console.log("🧪 Comprehensive Workspace Assignment Test Suite\n");
  console.log("Loading app registry...");

  const allApps = await loadAppRegistry();
  console.log(`Found ${allApps.length} apps in registry\n`);

  // Filter out PWAs and apps to skip
  const testableApps = allApps.filter(
    (app) =>
      !SKIP_APPS.includes(app.name) &&
      !app.name.endsWith("-pwa") // Skip PWAs for now
  );

  console.log(`Testing ${testableApps.length} apps (${allApps.length - testableApps.length} skipped)\n`);
  console.log(`Skipped: ${SKIP_APPS.join(", ")}, PWAs\n`);

  const results: TestResult[] = [];
  let passed = 0;
  let failed = 0;

  for (let i = 0; i < testableApps.length; i++) {
    const app = testableApps[i];
    const testNum = i + 1;

    console.log(`\n${"=".repeat(80)}`);
    console.log(
      `Test ${testNum}/${testableApps.length}: ${app.display_name} → WS${app.preferred_workspace}`
    );
    console.log(`${"=".repeat(80)}\n`);

    const result = await testApp(app);
    results.push(result);

    if (result.success) {
      passed++;
    } else {
      failed++;
    }

    // Cleanup after test
    console.log(`  🧹 Final cleanup of ${app.display_name}...`);
    await killAllAppInstances(app.expected_class, app.name);

    // Delay between tests (longer for Firefox)
    if (i < testableApps.length - 1) {
      const delay = app.name === "firefox" ? 3000 : 2000;
      console.log(`\n  ⏳ Waiting ${delay / 1000} seconds before next test...`);
      await new Promise((resolve) => setTimeout(resolve, delay));
    }
  }

  // Print summary
  console.log(`\n\n${"=".repeat(80)}`);
  console.log("📊 TEST SUMMARY");
  console.log(`${"=".repeat(80)}\n`);

  console.log(`Total tests: ${testableApps.length}`);
  console.log(`✅ Passed: ${passed}`);
  console.log(`❌ Failed: ${failed}`);
  console.log(
    `Success rate: ${((passed / testableApps.length) * 100).toFixed(1)}%\n`
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
    if (!result.success && result.error) {
      console.log(`  └─ ${result.error}`);
    }
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
