/**
 * Unit Tests for i3pm apps Commands
 *
 * Tests the application registry management CLI commands:
 * - list: List applications with filtering
 * - launch: Launch applications with project context
 * - info: Show application details
 * - validate: Validate registry file
 * - add: Add applications to registry
 * - remove: Remove applications from registry
 */

import {
  assertEquals,
  assertStringIncludes,
} from "jsr:@std/assert";
import { exists } from "jsr:@std/fs";

interface ApplicationEntry {
  name: string;
  display_name: string;
  command: string;
  parameters?: string;
  scope?: "scoped" | "global";
  expected_class?: string;
  preferred_workspace?: number;
  icon?: string;
  nix_package?: string;
  multi_instance?: boolean;
  fallback_behavior?: "skip" | "use_home" | "error";
  description?: string;
}

interface ApplicationRegistry {
  version: string;
  applications: ApplicationEntry[];
}

// Helper to create a temporary test registry
async function createTestRegistry(apps: ApplicationEntry[]): Promise<string> {
  const tempDir = await Deno.makeTempDir();
  const registryPath = `${tempDir}/application-registry.json`;

  const registry: ApplicationRegistry = {
    version: "1.0",
    applications: apps,
  };

  await Deno.writeTextFile(registryPath, JSON.stringify(registry, null, 2));
  return registryPath;
}

// Helper to run i3pm apps command with test registry
async function runAppsCommand(
  registryPath: string,
  args: string[]
): Promise<{ stdout: string; stderr: string; code: number }> {
  // Set HOME to temp directory so command uses test registry
  const tempHome = registryPath.replace("/application-registry.json", "");
  const configDir = `${tempHome}/.config/i3`;
  await Deno.mkdir(configDir, { recursive: true });

  const symlinkPath = `${configDir}/application-registry.json`;

  // Remove existing symlink/file if it exists
  try {
    await Deno.remove(symlinkPath);
  } catch {
    // File doesn't exist, that's fine
  }

  await Deno.symlink(registryPath, symlinkPath);

  const cmd = new Deno.Command("deno", {
    args: [
      "run",
      "--allow-read",
      "--allow-write",
      "--allow-env",
      "--allow-run",
      "--allow-net",
      "/etc/nixos/home-modules/tools/i3pm-deno/main.ts",
      "apps",
      ...args,
    ],
    env: {
      HOME: tempHome,
      XDG_RUNTIME_DIR: Deno.env.get("XDG_RUNTIME_DIR") || "/tmp",
    },
    stdout: "piped",
    stderr: "piped",
  });

  const output = await cmd.output();

  return {
    stdout: new TextDecoder().decode(output.stdout),
    stderr: new TextDecoder().decode(output.stderr),
    code: output.code,
  };
}

// Test data
const testApps: ApplicationEntry[] = [
  {
    name: "vscode",
    display_name: "VS Code",
    command: "code",
    parameters: "$PROJECT_DIR",
    scope: "scoped",
    preferred_workspace: 1,
    expected_class: "Code",
    description: "Visual Studio Code editor",
  },
  {
    name: "firefox",
    display_name: "Firefox",
    command: "firefox",
    scope: "global",
    preferred_workspace: 2,
    expected_class: "firefox",
    multi_instance: true,
  },
  {
    name: "ghostty",
    display_name: "Ghostty Terminal",
    command: "ghostty",
    parameters: "--session=$SESSION_NAME",
    scope: "scoped",
    preferred_workspace: 3,
    expected_class: "ghostty",
  },
];

// ============================================================================
// List Command Tests (T064)
// ============================================================================

Deno.test({
  name: "apps list - shows all applications in table format",
  async fn() {
    const registryPath = await createTestRegistry(testApps);

    try {
      const result = await runAppsCommand(registryPath, ["list"]);

      assertEquals(result.code, 0, "Should exit successfully");
      assertStringIncludes(result.stdout, "Application Registry");
      assertStringIncludes(result.stdout, "vscode");
      assertStringIncludes(result.stdout, "firefox");
      assertStringIncludes(result.stdout, "ghostty");
    } finally {
      await Deno.remove(registryPath.replace("/application-registry.json", ""), {
        recursive: true,
      });
    }
  },
});

Deno.test({
  name: "apps list --json - outputs valid JSON",
  async fn() {
    const registryPath = await createTestRegistry(testApps);

    try {
      const result = await runAppsCommand(registryPath, ["list", "--json"]);

      assertEquals(result.code, 0, "Should exit successfully");

      // Parse JSON output
      const apps = JSON.parse(result.stdout);
      assertEquals(Array.isArray(apps), true, "Should return an array");
      assertEquals(apps.length, 3, "Should return all 3 applications");

      // Verify structure
      const vscode = apps.find((a: ApplicationEntry) => a.name === "vscode");
      assertEquals(vscode.display_name, "VS Code");
      assertEquals(vscode.scope, "scoped");
    } finally {
      await Deno.remove(registryPath.replace("/application-registry.json", ""), {
        recursive: true,
      });
    }
  },
});

Deno.test({
  name: "apps list --scope=scoped - filters scoped applications",
  async fn() {
    const registryPath = await createTestRegistry(testApps);

    try {
      const result = await runAppsCommand(registryPath, [
        "list",
        "--json",
        "--scope=scoped",
      ]);

      assertEquals(result.code, 0, "Should exit successfully");

      const apps = JSON.parse(result.stdout);
      assertEquals(apps.length, 2, "Should return 2 scoped applications");
      assertEquals(apps.every((a: ApplicationEntry) => a.scope === "scoped"), true);
    } finally {
      await Deno.remove(registryPath.replace("/application-registry.json", ""), {
        recursive: true,
      });
    }
  },
});

Deno.test({
  name: "apps list --scope=global - filters global applications",
  async fn() {
    const registryPath = await createTestRegistry(testApps);

    try {
      const result = await runAppsCommand(registryPath, [
        "list",
        "--json",
        "--scope=global",
      ]);

      assertEquals(result.code, 0, "Should exit successfully");

      const apps = JSON.parse(result.stdout);
      assertEquals(apps.length, 1, "Should return 1 global application");
      assertEquals(apps[0].name, "firefox");
    } finally {
      await Deno.remove(registryPath.replace("/application-registry.json", ""), {
        recursive: true,
      });
    }
  },
});

Deno.test({
  name: "apps list --workspace=1 - filters by workspace",
  async fn() {
    const registryPath = await createTestRegistry(testApps);

    try {
      const result = await runAppsCommand(registryPath, [
        "list",
        "--json",
        "--workspace=1",
      ]);

      assertEquals(result.code, 0, "Should exit successfully");

      const apps = JSON.parse(result.stdout);
      assertEquals(apps.length, 1, "Should return 1 application for workspace 1");
      assertEquals(apps[0].name, "vscode");
    } finally {
      await Deno.remove(registryPath.replace("/application-registry.json", ""), {
        recursive: true,
      });
    }
  },
});

// ============================================================================
// Info Command Tests (T071)
// ============================================================================

Deno.test({
  name: "apps info - shows application details",
  async fn() {
    const registryPath = await createTestRegistry(testApps);

    try {
      const result = await runAppsCommand(registryPath, ["info", "vscode"]);

      assertEquals(result.code, 0, "Should exit successfully");
      assertStringIncludes(result.stdout, "VS Code");
      assertStringIncludes(result.stdout, "vscode");
      assertStringIncludes(result.stdout, "code");
      assertStringIncludes(result.stdout, "scoped");
    } finally {
      await Deno.remove(registryPath.replace("/application-registry.json", ""), {
        recursive: true,
      });
    }
  },
});

Deno.test({
  name: "apps info - fails for non-existent application",
  async fn() {
    const registryPath = await createTestRegistry(testApps);

    try {
      const result = await runAppsCommand(registryPath, [
        "info",
        "nonexistent",
      ]);

      assertEquals(result.code, 1, "Should exit with error");
      assertStringIncludes(result.stderr, "not found");
    } finally {
      await Deno.remove(registryPath.replace("/application-registry.json", ""), {
        recursive: true,
      });
    }
  },
});

// ============================================================================
// Validate Command Tests (T075)
// ============================================================================

Deno.test({
  name: "apps validate - passes for valid registry",
  async fn() {
    const registryPath = await createTestRegistry(testApps);

    try {
      const result = await runAppsCommand(registryPath, ["validate"]);

      assertEquals(result.code, 0, "Should exit successfully");
      assertStringIncludes(result.stdout, "validation passed");
    } finally {
      await Deno.remove(registryPath.replace("/application-registry.json", ""), {
        recursive: true,
      });
    }
  },
});

Deno.test({
  name: "apps validate - fails for missing required fields",
  async fn() {
    const invalidApps = [
      {
        name: "test",
        // Missing display_name
        command: "echo",
      } as ApplicationEntry,
    ];

    const registryPath = await createTestRegistry(invalidApps);

    try {
      const result = await runAppsCommand(registryPath, ["validate"]);

      assertEquals(result.code, 1, "Should exit with error");
      assertStringIncludes(result.stderr, "display_name");
    } finally {
      await Deno.remove(registryPath.replace("/application-registry.json", ""), {
        recursive: true,
      });
    }
  },
});

Deno.test({
  name: "apps validate - fails for duplicate names",
  async fn() {
    const duplicateApps = [
      {
        name: "test",
        display_name: "Test 1",
        command: "echo",
      },
      {
        name: "test", // Duplicate
        display_name: "Test 2",
        command: "echo",
      },
    ];

    const registryPath = await createTestRegistry(duplicateApps);

    try {
      const result = await runAppsCommand(registryPath, ["validate"]);

      assertEquals(result.code, 1, "Should exit with error");
      assertStringIncludes(result.stderr, "Duplicate");
    } finally {
      await Deno.remove(registryPath.replace("/application-registry.json", ""), {
        recursive: true,
      });
    }
  },
});

Deno.test({
  name: "apps validate - fails for invalid workspace",
  async fn() {
    const invalidWorkspace = [
      {
        name: "test",
        display_name: "Test",
        command: "echo",
        preferred_workspace: 10, // Invalid (must be 1-9)
      },
    ];

    const registryPath = await createTestRegistry(invalidWorkspace);

    try {
      const result = await runAppsCommand(registryPath, ["validate"]);

      assertEquals(result.code, 1, "Should exit with error");
      assertStringIncludes(result.stderr, "workspace");
    } finally {
      await Deno.remove(registryPath.replace("/application-registry.json", ""), {
        recursive: true,
      });
    }
  },
});

Deno.test({
  name: "apps validate - fails for invalid scope",
  async fn() {
    const invalidScope = [
      {
        name: "test",
        display_name: "Test",
        command: "echo",
        scope: "invalid" as any, // Invalid scope
      },
    ];

    const registryPath = await createTestRegistry(invalidScope);

    try {
      const result = await runAppsCommand(registryPath, ["validate"]);

      assertEquals(result.code, 1, "Should exit with error");
      assertStringIncludes(result.stderr, "scope");
    } finally {
      await Deno.remove(registryPath.replace("/application-registry.json", ""), {
        recursive: true,
      });
    }
  },
});

Deno.test({
  name: "apps validate - fails for invalid fallback_behavior",
  async fn() {
    const invalidFallback = [
      {
        name: "test",
        display_name: "Test",
        command: "echo",
        fallback_behavior: "invalid" as any,
      },
    ];

    const registryPath = await createTestRegistry(invalidFallback);

    try {
      const result = await runAppsCommand(registryPath, ["validate"]);

      assertEquals(result.code, 1, "Should exit with error");
      assertStringIncludes(result.stderr, "fallback_behavior");
    } finally {
      await Deno.remove(registryPath.replace("/application-registry.json", ""), {
        recursive: true,
      });
    }
  },
});

// ============================================================================
// Launch Command Tests (T068)
// ============================================================================

Deno.test({
  name: "apps launch --dry-run - shows command without executing",
  permissions: {
    read: true,
    write: true,
    env: true,
    run: true,
  },
  async fn() {
    const registryPath = await createTestRegistry(testApps);
    const tempHome = registryPath.replace("/application-registry.json", "");

    try {
      // Need to create the wrapper script in the temp home
      const binDir = `${tempHome}/.local/bin`;
      await Deno.mkdir(binDir, { recursive: true });

      const wrapperScript = `${binDir}/app-launcher-wrapper.sh`;
      await Deno.writeTextFile(
        wrapperScript,
        `#!/usr/bin/env bash
if [ "$DRY_RUN" = "1" ]; then
  echo "DRY RUN: Would launch $1"
  exit 0
fi
echo "Launching $1"
`,
      );

      await Deno.chmod(wrapperScript, 0o755);

      const result = await runAppsCommand(registryPath, [
        "launch",
        "vscode",
        "--dry-run",
      ]);

      assertEquals(result.code, 0, "Should exit successfully");
      assertStringIncludes(result.stdout, "DRY RUN");
    } finally {
      await Deno.remove(tempHome, { recursive: true });
    }
  },
});

Deno.test({
  name: "apps launch - fails for non-existent application",
  async fn() {
    const registryPath = await createTestRegistry(testApps);

    try {
      const result = await runAppsCommand(registryPath, [
        "launch",
        "nonexistent",
      ]);

      assertEquals(result.code, 1, "Should exit with error");
      assertStringIncludes(result.stderr, "not found");
    } finally {
      await Deno.remove(registryPath.replace("/application-registry.json", ""), {
        recursive: true,
      });
    }
  },
});

// ============================================================================
// Add Command Tests
// ============================================================================

Deno.test({
  name: "apps add --non-interactive - adds application successfully",
  async fn() {
    const registryPath = await createTestRegistry(testApps);
    const tempHome = registryPath.replace("/application-registry.json", "");

    try {
      const result = await runAppsCommand(registryPath, [
        "add",
        "--non-interactive",
        "--name=test-app",
        "--display-name=Test Application",
        "--command=echo",
        "--description=Test application for unit tests",
      ]);

      assertEquals(result.code, 0, "Should exit successfully");
      assertStringIncludes(result.stdout, "Added application");
      assertStringIncludes(result.stdout, "test-app");

      // Verify app was added by reading the registry file directly
      // (The add command converts the symlink to a regular file)
      const actualRegistryPath = `${tempHome}/.config/i3/application-registry.json`;
      const content = await Deno.readTextFile(actualRegistryPath);
      const registry = JSON.parse(content) as ApplicationRegistry;

      const testApp = registry.applications.find((a) => a.name === "test-app");

      assertEquals(testApp !== undefined, true, "App should exist in registry");
      assertEquals(testApp?.display_name, "Test Application");
      assertEquals(testApp?.command, "echo");
    } finally {
      await Deno.remove(tempHome, {
        recursive: true,
      });
    }
  },
});

Deno.test({
  name: "apps add - fails for duplicate application name",
  async fn() {
    const registryPath = await createTestRegistry(testApps);

    try {
      const result = await runAppsCommand(registryPath, [
        "add",
        "--non-interactive",
        "--name=vscode", // Already exists
        "--display-name=VS Code Duplicate",
        "--command=code",
      ]);

      assertEquals(result.code, 1, "Should exit with error");
      assertStringIncludes(result.stderr, "already exists");
    } finally {
      await Deno.remove(registryPath.replace("/application-registry.json", ""), {
        recursive: true,
      });
    }
  },
});

// ============================================================================
// Remove Command Tests
// ============================================================================

Deno.test({
  name: "apps remove --force - removes application successfully",
  async fn() {
    const registryPath = await createTestRegistry(testApps);
    const tempHome = registryPath.replace("/application-registry.json", "");

    try {
      const result = await runAppsCommand(registryPath, [
        "remove",
        "firefox",
        "--force",
      ]);

      assertEquals(result.code, 0, "Should exit successfully");
      assertStringIncludes(result.stdout, "Removed application");
      assertStringIncludes(result.stdout, "firefox");

      // Verify app was removed by reading the registry file directly
      // (The remove command converts the symlink to a regular file)
      const actualRegistryPath = `${tempHome}/.config/i3/application-registry.json`;
      const content = await Deno.readTextFile(actualRegistryPath);
      const registry = JSON.parse(content) as ApplicationRegistry;

      const firefox = registry.applications.find((a) => a.name === "firefox");

      assertEquals(firefox, undefined, "Firefox should be removed");
      assertEquals(registry.applications.length, 2, "Should have 2 apps remaining");
    } finally {
      await Deno.remove(tempHome, {
        recursive: true,
      });
    }
  },
});

Deno.test({
  name: "apps remove - fails for non-existent application",
  async fn() {
    const registryPath = await createTestRegistry(testApps);

    try {
      const result = await runAppsCommand(registryPath, [
        "remove",
        "nonexistent",
        "--force",
      ]);

      assertEquals(result.code, 1, "Should exit with error");
      assertStringIncludes(result.stderr, "not found");
    } finally {
      await Deno.remove(registryPath.replace("/application-registry.json", ""), {
        recursive: true,
      });
    }
  },
});
