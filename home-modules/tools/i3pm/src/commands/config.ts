/**
 * Config command - Manage Sway configuration
 * Feature 047: Dynamic Sway Configuration Management Architecture
 * User Story 2: Clear Configuration Responsibility Boundaries
 */

import { DaemonClient } from "../services/daemon-client.ts";

export async function configCommand(args: string[], flags: Record<string, unknown>): Promise<number> {
  const [subcommand] = args;

  try {
    switch (subcommand) {
      case "show":
        return await configShow(flags);
      case "conflicts":
        return await configConflicts(flags);
      case "rollback":
        return await configRollback(args.slice(1), flags);
      case "list-versions":
      case "versions":
        return await configListVersions(flags);
      case "validate":
        return await configValidate(args.slice(1), flags);
      case "edit":
        return await configEdit(args.slice(1), flags);
      default:
        console.error("Usage: i3pm config <show|conflicts|rollback|list-versions|validate|edit>");
        console.error("\nAvailable subcommands:");
        console.error("  show          Display current configuration with source attribution");
        console.error("  conflicts     Show configuration conflicts across precedence levels");
        console.error("  rollback      Rollback configuration to a previous version (Feature 047 US4)");
        console.error("  list-versions List configuration version history (Feature 047 US4)");
        console.error("  validate      Validate configuration files (Feature 047 US5)");
        console.error("  edit          Edit configuration files with automatic validation (Feature 047 Phase 8 T056)");
        return 1;
    }
  } catch (error) {
    console.error(`Error: ${error instanceof Error ? error.message : String(error)}`);
    return 1;
  }
}

async function configShow(flags: Record<string, unknown>): Promise<number> {
  // Feature 047: Sway config manager uses separate socket
  const configSocket = `${Deno.env.get("HOME")}/.cache/sway-config-manager/ipc.sock`;
  const client = new DaemonClient(configSocket);
  await client.connect();

  const params: Record<string, unknown> = {};

  // Parse options
  if (flags.category) {
    params.category = String(flags.category);
  }

  if (flags.sources !== undefined) {
    params.include_sources = Boolean(flags.sources);
  }

  if (flags.project) {
    params.project_context = String(flags.project);
  }

  try {
    const result = await client.request<{
      keybindings?: Array<{
        key_combo: string;
        command: string;
        description?: string;
        source: string;
        mode: string;
        file_path?: string;
        precedence_level?: number;
      }>;
      window_rules?: Array<{
        id: string;
        criteria: Record<string, unknown>;
        actions: string[];
        scope: string;
        source: string;
        file_path?: string;
      }>;
      workspace_assignments?: Array<{
        workspace_number: number;
        primary_output: string;
        source: string;
        file_path?: string;
      }>;
      active_project?: string | null;
      config_version?: string;
      project_overrides?: {
        window_rules?: Array<{
          base_rule_id?: string | null;
          override_properties: Record<string, unknown>;
          enabled: boolean;
          override_type: "modify" | "new";
        }>;
        keybindings?: Record<string, {
          command?: string | null;
          description?: string;
          enabled: boolean;
          override_type: "modify" | "new" | "disable";
        }>;
      };
    }>("config_show", params);

    if (flags.json) {
      console.log(JSON.stringify(result, null, 2));
    } else {
      printConfigTable(result, flags);
    }

    client.disconnect();
    return 0;
  } catch (error) {
    if (error instanceof Error && error.message.includes("not responding")) {
      console.error("✗ Daemon is not responding");
      console.error("Start the daemon with: systemctl --user start i3-project-event-listener");
      return 3;
    }
    throw error;
  }
}

function printConfigTable(result: {
  keybindings?: Array<{
    key_combo: string;
    command: string;
    description?: string;
    source: string;
    mode: string;
    file_path?: string;
    precedence_level?: number;
  }>;
  window_rules?: Array<{
    id: string;
    criteria: Record<string, unknown>;
    actions: string[];
    scope: string;
    source: string;
    file_path?: string;
  }>;
  workspace_assignments?: Array<{
    workspace_number: number;
    primary_output: string;
    source: string;
    file_path?: string;
  }>;
  active_project?: string | null;
  config_version?: string;
  project_overrides?: {
    window_rules?: Array<{
      base_rule_id?: string | null;
      override_properties: Record<string, unknown>;
      enabled: boolean;
      override_type: "modify" | "new";
    }>;
    keybindings?: Record<string, {
      command?: string | null;
      description?: string;
      enabled: boolean;
      override_type: "modify" | "new" | "disable";
    }>;
  };
}, flags: Record<string, unknown>): void {
  const includeSource = flags.sources !== false;

  // Print keybindings
  if (result.keybindings && result.keybindings.length > 0) {
    console.log("═".repeat(80));
    console.log("                    KEYBINDINGS");
    console.log("═".repeat(80));
    console.log(
      includeSource
        ? "Key Combo         Command                    Source      File"
        : "Key Combo         Command                    Description",
    );
    console.log("─".repeat(80));

    for (const kb of result.keybindings) {
      const keyCombo = kb.key_combo.padEnd(16);
      const command = truncate(kb.command, 25).padEnd(26);

      if (includeSource) {
        const source = kb.source.padEnd(10);
        const filePath = kb.file_path ? extractFileName(kb.file_path) : "N/A";
        console.log(`${keyCombo} ${command} ${source} ${filePath}`);
      } else {
        const desc = truncate(kb.description || "", 30);
        console.log(`${keyCombo} ${command} ${desc}`);
      }
    }
    console.log("─".repeat(80));
    console.log();
  }

  // Print window rules
  if (result.window_rules && result.window_rules.length > 0) {
    console.log("═".repeat(80));
    console.log("                    WINDOW RULES");
    console.log("═".repeat(80));
    console.log(
      includeSource
        ? "ID           Criteria              Actions         Scope    Source"
        : "ID           Criteria              Actions         Scope",
    );
    console.log("─".repeat(80));

    for (const rule of result.window_rules) {
      const id = rule.id.padEnd(12);
      const criteria = formatCriteria(rule.criteria).padEnd(20);
      const actions = truncate(rule.actions.join(", "), 14).padEnd(15);
      const scope = rule.scope.padEnd(8);

      if (includeSource) {
        const source = rule.source;
        console.log(`${id} ${criteria} ${actions} ${scope} ${source}`);
      } else {
        console.log(`${id} ${criteria} ${actions} ${scope}`);
      }
    }
    console.log("─".repeat(80));
    console.log();
  }

  // Print workspace assignments
  if (result.workspace_assignments && result.workspace_assignments.length > 0) {
    console.log("═".repeat(80));
    console.log("                    WORKSPACE ASSIGNMENTS");
    console.log("═".repeat(80));
    console.log(
      includeSource
        ? "Workspace    Output             Source      File"
        : "Workspace    Output",
    );
    console.log("─".repeat(80));

    for (const ws of result.workspace_assignments) {
      const workspace = String(ws.workspace_number).padEnd(12);
      const output = ws.primary_output.padEnd(18);

      if (includeSource) {
        const source = ws.source.padEnd(10);
        const filePath = ws.file_path ? extractFileName(ws.file_path) : "N/A";
        console.log(`${workspace} ${output} ${source} ${filePath}`);
      } else {
        console.log(`${workspace} ${output}`);
      }
    }
    console.log("─".repeat(80));
    console.log();
  }

  // Feature 047 US3 T039: Print project overrides section
  if (result.project_overrides) {
    const hasWindowRules = result.project_overrides.window_rules && result.project_overrides.window_rules.length > 0;
    const hasKeybindings = result.project_overrides.keybindings && Object.keys(result.project_overrides.keybindings).length > 0;

    if (hasWindowRules || hasKeybindings) {
      console.log("═".repeat(80));
      console.log("                    PROJECT OVERRIDES");
      console.log(`                    Project: ${result.active_project || "unknown"}`);
      console.log("═".repeat(80));
      console.log();

      // Print window rule overrides
      if (hasWindowRules) {
        console.log("WINDOW RULE OVERRIDES:");
        console.log("─".repeat(80));
        console.log("Type     Base Rule ID    Override Properties           Enabled");
        console.log("─".repeat(80));

        for (const override of result.project_overrides.window_rules!) {
          const type = override.override_type.padEnd(8);
          const baseId = (override.base_rule_id || "new").padEnd(15);
          const props = truncate(JSON.stringify(override.override_properties), 28).padEnd(29);
          const enabled = override.enabled ? "✓" : "✗";

          console.log(`${type} ${baseId} ${props} ${enabled}`);
        }
        console.log("─".repeat(80));
        console.log();
      }

      // Print keybinding overrides
      if (hasKeybindings) {
        console.log("KEYBINDING OVERRIDES:");
        console.log("─".repeat(80));
        console.log("Type     Key Combo         Command                    Enabled");
        console.log("─".repeat(80));

        for (const [keyCombo, override] of Object.entries(result.project_overrides.keybindings!)) {
          const type = override.override_type.padEnd(8);
          const key = keyCombo.padEnd(16);
          const command = truncate(override.command || "disabled", 25).padEnd(26);
          const enabled = override.enabled ? "✓" : "✗";

          console.log(`${type} ${key} ${command} ${enabled}`);
        }
        console.log("─".repeat(80));
        console.log();
      }

      console.log(`Total Overrides: ${(result.project_overrides.window_rules?.length || 0) + (Object.keys(result.project_overrides.keybindings || {}).length)}`);
      console.log();
    }
  }

  // Print footer
  if (result.active_project !== undefined) {
    console.log(`Active Project: ${result.active_project || "none"}`);
  }
  if (result.config_version) {
    console.log(`Config Version: ${result.config_version.substring(0, 7)} (${new Date().toISOString().split("T")[0]})`);
  }
  console.log();
}

async function configConflicts(flags: Record<string, unknown>): Promise<number> {
  // Feature 047: Sway config manager uses separate socket
  const configSocket = `${Deno.env.get("HOME")}/.cache/sway-config-manager/ipc.sock`;
  const client = new DaemonClient(configSocket);
  await client.connect();

  try {
    const result = await client.request<{
      conflicts: Array<{
        setting_path: string;
        conflict_type: string;
        sources: Array<{
          source: string;
          value: string;
          file_path?: string;
          precedence_level?: number;
          active: boolean;
        }>;
        resolution: string;
        severity: string;
      }>;
      total_conflicts?: number;
    }>("config_get_conflicts", {});

    if (flags.json) {
      console.log(JSON.stringify(result, null, 2));
    } else {
      printConflictsTable(result);
    }

    client.disconnect();

    // Exit code: 0 for warnings only, 1 for critical conflicts
    const hasCritical = result.conflicts && result.conflicts.some((c) => c.severity === "critical");
    return hasCritical ? 1 : 0;
  } catch (error) {
    if (error instanceof Error && error.message.includes("not responding")) {
      console.error("✗ Daemon is not responding");
      console.error("Start the daemon with: systemctl --user start i3-project-event-listener");
      return 3;
    }
    throw error;
  }
}

function printConflictsTable(result: {
  conflicts: Array<{
    setting_path: string;
    conflict_type: string;
    sources: Array<{
      source: string;
      value: string;
      file_path?: string;
      precedence_level?: number;
      active: boolean;
    }>;
    resolution: string;
    severity: string;
  }>;
  total_conflicts?: number;
}): void {
  console.log("═".repeat(80));
  console.log("                 CONFIGURATION CONFLICTS");
  console.log("═".repeat(80));
  console.log();

  const totalConflicts = result.total_conflicts ?? (result.conflicts ? result.conflicts.length : 0);
  if (totalConflicts === 0) {
    console.log("✅ No configuration conflicts found");
    console.log();
    return;
  }

  for (const conflict of result.conflicts) {
    const icon = conflict.severity === "critical" ? "❌" : "⚠️";
    console.log(`${icon}  ${conflict.setting_path}`);
    console.log();
    console.log("  Source      Value                    File                Active");
    console.log("  " + "─".repeat(76));

    for (const source of conflict.sources) {
      const sourceStr = source.source.padEnd(10);
      const value = truncate(source.value, 23).padEnd(24);
      const file = source.file_path ? truncate(extractFileName(source.file_path), 18).padEnd(19) : "N/A".padEnd(19);
      const active = source.active ? "✓" : "✗";
      console.log(`  ${sourceStr} ${value} ${file} ${active}`);
    }

    console.log();
    console.log(`  Resolution: ${conflict.resolution}`);
    console.log(`  Severity: ${conflict.severity}`);
    console.log();
    console.log("─".repeat(80));
    console.log();
  }

  console.log(`Total Conflicts: ${totalConflicts}`);
  console.log();
}

// Helper functions
function truncate(str: string, maxLen: number): string {
  if (str.length <= maxLen) return str;
  return str.substring(0, maxLen - 3) + "...";
}

function extractFileName(path: string | undefined): string {
  if (!path) return "";
  const parts = path.split("/");
  return parts[parts.length - 1] || path;
}

function formatCriteria(criteria: Record<string, unknown>): string {
  const entries = Object.entries(criteria);
  if (entries.length === 0) return "none";

  const [key, value] = entries[0];
  return `${key}: ${truncate(String(value), 12)}`;
}

/**
 * Feature 047 US4: Rollback configuration to a previous version
 * T043: Deno CLI command for configuration rollback
 */
async function configRollback(args: string[], flags: Record<string, unknown>): Promise<number> {
  const [commitHash] = args;

  if (!commitHash) {
    console.error("Error: Commit hash is required");
    console.error("Usage: i3pm config rollback <commit-hash> [--no-reload]");
    console.error("\nOptions:");
    console.error("  --no-reload  Don't reload configuration after rollback");
    console.error("\nExample:");
    console.error("  i3pm config rollback a1b2c3d4");
    console.error("  i3pm config list-versions  # Show available versions");
    return 1;
  }

  const configSocket = `${Deno.env.get("HOME")}/.cache/sway-config-manager/ipc.sock`;
  const client = new DaemonClient(configSocket);
  await client.connect();

  try {
    const params: Record<string, unknown> = {
      commit_hash: commitHash,
      reload_after: !flags["no-reload"],
    };

    console.log(`Rolling back configuration to ${commitHash}...`);

    const result = await client.request<{
      success: boolean;
      message: string;
      rollback_duration_ms?: number;
      files_changed?: string[];
    }>("config_rollback", params);

    if (result.success) {
      console.log(`✓ ${result.message}`);
      if (result.rollback_duration_ms) {
        console.log(`  Duration: ${result.rollback_duration_ms}ms`);
      }
      if (result.files_changed && result.files_changed.length > 0) {
        console.log(`  Files changed: ${result.files_changed.join(", ")}`);
      }
      return 0;
    } else {
      console.error(`✗ Rollback failed: ${result.message}`);
      return 1;
    }
  } finally {
    await client.disconnect();
  }
}

/**
 * Feature 047 US4: List configuration version history
 * T044: Deno CLI command for listing configuration versions
 */
async function configListVersions(flags: Record<string, unknown>): Promise<number> {
  const configSocket = `${Deno.env.get("HOME")}/.cache/sway-config-manager/ipc.sock`;
  const client = new DaemonClient(configSocket);
  await client.connect();

  try {
    const params: Record<string, unknown> = {};

    if (flags.limit) {
      params.limit = Number(flags.limit);
    }

    if (flags.since) {
      params.since = String(flags.since);
    }

    const result = await client.request<{
      versions: Array<{
        commit_hash: string;
        timestamp: string;
        message: string;
        author: string;
        is_active: boolean;
        files_changed: string[];
      }>;
      total_count: number;
    }>("config_get_versions", params);

    if (flags.json) {
      console.log(JSON.stringify(result, null, 2));
      return 0;
    }

    // Print version history table
    console.log("\n┌─ Configuration Version History ─────────────────────────────────────┐");
    console.log("│");

    if (result.versions.length === 0) {
      console.log("│  No configuration versions found");
      console.log("│");
      console.log("└──────────────────────────────────────────────────────────────────────┘\n");
      return 0;
    }

    for (const version of result.versions) {
      const date = new Date(version.timestamp);
      const dateStr = date.toISOString().replace("T", " ").substring(0, 19);
      const hash = version.commit_hash.substring(0, 8);
      const active = version.is_active ? " ← ACTIVE" : "";
      const filesCount = version.files_changed.length;

      console.log(`│  ${hash}  ${dateStr}${active}`);
      console.log(`│  ${version.message}`);
      console.log(`│  Author: ${version.author}, Files: ${filesCount}`);
      console.log("│");
    }

    console.log(`└─ Total: ${result.total_count} versions ────────────────────────────────┘\n`);

    if (result.versions.length > 0) {
      console.log("To rollback to a version:");
      console.log(`  i3pm config rollback ${result.versions[0].commit_hash.substring(0, 8)}`);
      console.log("\nOptions:");
      console.log("  --limit <n>     Limit number of versions (default: 10)");
      console.log("  --since <date>  Show versions since date (e.g., '2025-01-01')");
      console.log("  --json          Output in JSON format");
    }

    return 0;
  } finally {
    await client.disconnect();
  }
}

/**
 * Feature 047 US5: Validate configuration files
 * T052: Deno CLI command for configuration validation
 */
async function configValidate(args: string[], flags: Record<string, unknown>): Promise<number> {
  const configSocket = `${Deno.env.get("HOME")}/.cache/sway-config-manager/ipc.sock`;
  const client = new DaemonClient(configSocket);
  await client.connect();

  try {
    const params: Record<string, unknown> = {};

    // Parse files to validate
    if (args.length > 0) {
      params.files = args;
    }

    // Parse flags
    if (flags.strict !== undefined) {
      params.strict = Boolean(flags.strict);
    }

    console.log("Validating configuration...\n");

    const result = await client.request<{
      valid: boolean;  // Daemon returns "valid" not "success"
      errors: Array<{
        file_path: string;
        line_number?: number | null;
        error_type: string;
        message: string;
        suggestion?: string | null;
      }>;
      warnings: Array<{
        file_path: string;
        message: string;
        suggestion?: string | null;
      }>;
      validation_duration_ms?: number;
      files_validated?: string[];
    }>("config_validate", params);

    // Format validation results (Feature 047 US5 T054)
    if (flags.json) {
      console.log(JSON.stringify(result, null, 2));
      return result.valid ? 0 : 1;
    }

    // Display results with color-coded output
    console.log("┌─ Validation Results ────────────────────────────────────────────────┐");
    console.log("│");

    if (result.errors.length === 0 && result.warnings.length === 0) {
      console.log("│  ✅ Configuration is valid");
    } else {
      // Display errors
      if (result.errors.length > 0) {
        console.log(`│  ❌ Found ${result.errors.length} error(s):`);
        console.log("│");

        for (const error of result.errors) {
          const location = error.line_number
            ? `${error.file_path}:${error.line_number}`
            : error.file_path;

          console.log(`│  [${error.error_type.toUpperCase()}] ${location}`);
          console.log(`│  ${error.message}`);

          if (error.suggestion) {
            console.log(`│  💡 Suggestion: ${error.suggestion}`);
          }

          console.log("│");
        }
      }

      // Display warnings
      if (result.warnings.length > 0) {
        console.log(`│  ⚠️  Found ${result.warnings.length} warning(s):`);
        console.log("│");

        for (const warning of result.warnings) {
          console.log(`│  [WARNING] ${warning.file_path}`);
          console.log(`│  ${warning.message}`);

          if (warning.suggestion) {
            console.log(`│  💡 Suggestion: ${warning.suggestion}`);
          }

          console.log("│");
        }
      }
    }

    // Summary statistics
    console.log("│");
    console.log(`│  Files validated: ${(result.files_validated || []).length}`);
    console.log(`│  Duration: ${result.validation_duration_ms || 0}ms`);
    console.log(`│  Status: ${result.valid ? "✅ PASS" : "❌ FAIL"}`);
    console.log("│");
    console.log("└──────────────────────────────────────────────────────────────────────┘\n");

    if (!result.valid) {
      console.log("Fix the errors above before reloading configuration.");
      console.log("Use 'i3pm config reload' after fixing errors.\n");
      return 1;
    }

    console.log("Configuration is ready to reload!");
    console.log("Run 'i3pm config reload' to apply changes.\n");

    return 0;
  } finally {
    await client.disconnect();
  }
}

/**
 * Feature 047 Phase 8: Edit configuration files with automatic validation
 * T056: Configuration editor integration with auto-validation
 */
async function configEdit(args: string[], flags: Record<string, unknown>): Promise<number> {
  const [configType] = args;

  if (!configType) {
    console.error("Error: Configuration type is required");
    console.error("Usage: i3pm config edit <keybindings|window-rules|workspace-assignments>");
    console.error("\nExamples:");
    console.error("  i3pm config edit keybindings");
    console.error("  i3pm config edit window-rules");
    console.error("  i3pm config edit workspace-assignments");
    return 1;
  }

  // Map config type to file path
  const configHome = Deno.env.get("HOME");
  let filePath: string;

  switch (configType) {
    case "keybindings":
      filePath = `${configHome}/.config/sway/keybindings.toml`;
      break;
    case "window-rules":
      filePath = `${configHome}/.config/sway/window-rules.json`;
      break;
    case "workspace-assignments":
      filePath = `${configHome}/.config/sway/workspace-assignments.json`;
      break;
    default:
      console.error(`Error: Unknown configuration type '${configType}'`);
      console.error("Available types: keybindings, window-rules, workspace-assignments");
      return 1;
  }

  // Check if file exists
  try {
    await Deno.stat(filePath);
  } catch (error) {
    if (error instanceof Deno.errors.NotFound) {
      console.error(`Error: Configuration file not found: ${filePath}`);
      console.error("Run 'i3pm config reload' to generate default configuration files.");
      return 1;
    }
    throw error;
  }

  // Get editor from environment (with fallbacks)
  const editor = Deno.env.get("EDITOR") || Deno.env.get("VISUAL") || "nvim";

  console.log(`Opening ${configType} configuration in ${editor}...`);
  console.log(`File: ${filePath}\n`);

  // Open editor
  const editorProcess = new Deno.Command(editor, {
    args: [filePath],
    stdin: "inherit",
    stdout: "inherit",
    stderr: "inherit",
  });

  const editorStatus = await editorProcess.output();

  if (!editorStatus.success) {
    console.error("\nEditor exited with error");
    return 1;
  }

  console.log("\n✓ Editor closed");

  // Auto-validate after editing
  console.log("Running automatic validation...\n");

  const validateResult = await configValidate([filePath], flags);

  if (validateResult === 0) {
    console.log("✓ Configuration is valid!");
    console.log("\nNext steps:");
    console.log("  - Run 'i3pm config reload' to apply changes");
    console.log("  - Or wait for automatic reload (if file watcher is enabled)");
    return 0;
  } else {
    console.error("\n⚠️  Validation failed - please fix errors before reloading");
    console.error("Edit again with: i3pm config edit " + configType);
    return 1;
  }
}
