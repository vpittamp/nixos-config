/**
 * Monitors Command - Workspace-to-Monitor Mapping Management
 * Feature 033: Declarative workspace distribution
 */

import { parseArgs } from "@std/cli/parse-args";
import { DaemonClient } from "../client.ts";
import {
  WorkspaceMonitorConfigSchema,
  ConfigValidationResultSchema,
  ReloadConfigResponseSchema,
  ReassignWorkspacesResponseSchema,
  validateResponse,
  createDefaultConfig,
} from "../models_monitors.ts";

interface MonitorsCommandOptions {
  verbose?: boolean;
  debug?: boolean;
}

function showHelp(): void {
  console.log(`
i3pm monitors - Workspace-to-Monitor mapping management

USAGE:
  i3pm monitors <SUBCOMMAND> [OPTIONS]

SUBCOMMANDS:
  config       Manage configuration file
    show       Display current configuration
    edit       Open configuration in editor
    init       Create default configuration
    validate   Validate configuration file
    reload     Reload configuration without daemon restart

  reassign     Redistribute workspaces based on config
  status       Show current monitor assignments (TODO: Phase 4)
  workspaces   Show workspace assignments (TODO: Phase 4)

CONFIG SUBCOMMANDS:
  i3pm monitors config show              Display configuration with syntax highlighting
  i3pm monitors config edit              Open $EDITOR to edit config
  i3pm monitors config init              Create default config if missing
  i3pm monitors config validate          Validate config and show issues
  i3pm monitors config reload            Hot-reload config without restart

REASSIGN COMMAND:
  i3pm monitors reassign                 Apply workspace distribution now
  i3pm monitors reassign --dry-run       Preview changes without applying

OPTIONS:
  -h, --help       Show this help message
  --dry-run        Preview without applying (reassign only)
  --json           Output as JSON

CONFIGURATION FILE:
  Location: ~/.config/i3/workspace-monitor-mapping.json

  Default distribution:
    1 monitor:  All workspaces on primary
    2 monitors: WS 1-2 primary, WS 3-10 secondary
    3 monitors: WS 1-2 primary, WS 3-5 secondary, WS 6-10 tertiary

EXAMPLES:
  # View current configuration
  i3pm monitors config show

  # Edit configuration
  i3pm monitors config edit

  # Validate before applying
  i3pm monitors config validate

  # Reload and apply changes
  i3pm monitors config reload
  i3pm monitors reassign

  # Preview workspace redistribution
  i3pm monitors reassign --dry-run

For detailed documentation, see:
  /etc/nixos/specs/033-declarative-workspace-to/quickstart.md
`);
  Deno.exit(0);
}

export async function monitorsCommand(
  args: (string | number)[],
  options: MonitorsCommandOptions,
): Promise<void> {
  const parsed = parseArgs(args.map(String), {
    boolean: ["help", "dry-run", "json"],
    alias: { h: "help" },
    stopEarly: true,
  });

  if (parsed.help || parsed._.length === 0) {
    showHelp();
  }

  const subcommand = String(parsed._[0]);
  const subArgs = parsed._.slice(1);

  switch (subcommand) {
    case "config":
      await configSubcommand(subArgs, parsed, options);
      break;

    case "reassign":
      await reassignCommand(parsed, options);
      break;

    case "status":
    case "workspaces":
      console.error(`Error: '${subcommand}' command not yet implemented (Phase 4: US2)`);
      console.error("These commands will be available after User Story 2 is complete.");
      Deno.exit(1);
      break;

    default:
      console.error(`Error: Unknown subcommand '${subcommand}'`);
      console.error("");
      console.error("Run 'i3pm monitors --help' to see available subcommands");
      Deno.exit(1);
  }
}

/**
 * Config subcommand handler
 */
async function configSubcommand(
  args: (string | number)[],
  parsed: any,
  options: MonitorsCommandOptions,
): Promise<void> {
  if (args.length === 0) {
    console.error("Error: Missing config subcommand");
    console.error("");
    console.error("Available subcommands: show, edit, init, validate, reload");
    console.error("Run 'i3pm monitors config --help' for usage information");
    Deno.exit(1);
  }

  const configCmd = String(args[0]);

  switch (configCmd) {
    case "show":
      await configShowCommand(parsed, options);
      break;

    case "edit":
      await configEditCommand(options);
      break;

    case "init":
      await configInitCommand(options);
      break;

    case "validate":
      await configValidateCommand(parsed, options);
      break;

    case "reload":
      await configReloadCommand(parsed, options);
      break;

    default:
      console.error(`Error: Unknown config subcommand '${configCmd}'`);
      console.error("");
      console.error("Available subcommands: show, edit, init, validate, reload");
      Deno.exit(1);
  }
}

/**
 * T024: Config show command
 */
async function configShowCommand(
  parsed: any,
  _options: MonitorsCommandOptions,
): Promise<void> {
  const client = new DaemonClient();

  try {
    await client.connect();

    const response = await client.request("get_monitor_config");
    const config = validateResponse(WorkspaceMonitorConfigSchema, response);

    if (parsed.json) {
      console.log(JSON.stringify(config, null, 2));
    } else {
      // Pretty-print with colors
      console.log("\n📋 Workspace-to-Monitor Configuration\n");
      console.log(`Version: ${config.version}`);
      console.log(`Auto-reassign: ${config.enable_auto_reassign ? "✓ enabled" : "✗ disabled"}`);
      console.log(`Debounce: ${config.debounce_ms}ms\n`);

      console.log("Distribution Rules:");
      console.log("  1 monitor:");
      console.log(`    Primary:   ${config.distribution["1_monitor"].primary.join(", ")}`);
      console.log("  2 monitors:");
      console.log(`    Primary:   ${config.distribution["2_monitors"].primary.join(", ")}`);
      console.log(`    Secondary: ${config.distribution["2_monitors"].secondary.join(", ")}`);
      console.log("  3 monitors:");
      console.log(`    Primary:   ${config.distribution["3_monitors"].primary.join(", ")}`);
      console.log(`    Secondary: ${config.distribution["3_monitors"].secondary.join(", ")}`);
      console.log(`    Tertiary:  ${config.distribution["3_monitors"].tertiary.join(", ")}`);

      if (Object.keys(config.workspace_preferences).length > 0) {
        console.log("\nWorkspace Preferences:");
        for (const [ws, role] of Object.entries(config.workspace_preferences)) {
          console.log(`  Workspace ${ws}: ${role}`);
        }
      }

      if (Object.keys(config.output_preferences).length > 0) {
        console.log("\nOutput Preferences:");
        for (const [role, outputs] of Object.entries(config.output_preferences)) {
          console.log(`  ${role}: ${outputs.join(", ")}`);
        }
      }

      console.log("\nConfig file: ~/.config/i3/workspace-monitor-mapping.json\n");
    }
  } catch (err) {
    if (err instanceof Error) {
      console.error(`Error: ${err.message}`);
      Deno.exit(1);
    }
    throw err;
  }
}

/**
 * T025: Config edit command
 */
async function configEditCommand(_options: MonitorsCommandOptions): Promise<void> {
  const configPath = `${Deno.env.get("HOME")}/.config/i3/workspace-monitor-mapping.json`;
  const editor = Deno.env.get("EDITOR") || "vi";

  try {
    const command = new Deno.Command(editor, {
      args: [configPath],
      stdin: "inherit",
      stdout: "inherit",
      stderr: "inherit",
    });

    const status = await command.output();

    if (!status.success) {
      console.error(`Error: Editor exited with code ${status.code}`);
      Deno.exit(status.code);
    }

    console.log("\n✓ Configuration file saved");
    console.log("\nNext steps:");
    console.log("  1. Validate: i3pm monitors config validate");
    console.log("  2. Reload:   i3pm monitors config reload");
    console.log("  3. Apply:    i3pm monitors reassign");
  } catch (err) {
    if (err instanceof Error) {
      console.error(`Error opening editor: ${err.message}`);
      Deno.exit(1);
    }
    throw err;
  }
}

/**
 * T026: Config init command
 */
async function configInitCommand(_options: MonitorsCommandOptions): Promise<void> {
  const configPath = `${Deno.env.get("HOME")}/.config/i3/workspace-monitor-mapping.json`;

  try {
    // Check if file already exists
    try {
      await Deno.stat(configPath);
      console.error(`Error: Configuration file already exists at ${configPath}`);
      console.error("\nUse 'i3pm monitors config edit' to modify existing configuration");
      Deno.exit(1);
    } catch {
      // File doesn't exist, continue
    }

    // Create default configuration
    const defaultConfig = createDefaultConfig();
    const configJson = JSON.stringify(defaultConfig, null, 2);

    // Ensure directory exists
    const configDir = `${Deno.env.get("HOME")}/.config/i3`;
    await Deno.mkdir(configDir, { recursive: true });

    // Write configuration file
    await Deno.writeTextFile(configPath, configJson + "\n");

    console.log(`✓ Created default configuration at ${configPath}`);
    console.log("\nDefault distribution:");
    console.log("  1 monitor:  All workspaces on primary");
    console.log("  2 monitors: WS 1-2 primary, WS 3-10 secondary");
    console.log("  3 monitors: WS 1-2 primary, WS 3-5 secondary, WS 6-10 tertiary");
    console.log("\nNext steps:");
    console.log("  1. Edit:   i3pm monitors config edit");
    console.log("  2. Reload: i3pm monitors config reload");
    console.log("  3. Apply:  i3pm monitors reassign");
  } catch (err) {
    if (err instanceof Error) {
      console.error(`Error creating configuration: ${err.message}`);
      Deno.exit(1);
    }
    throw err;
  }
}

/**
 * T027: Config validate command
 */
async function configValidateCommand(
  parsed: any,
  _options: MonitorsCommandOptions,
): Promise<void> {
  const client = new DaemonClient();

  try {
    await client.connect();

    const response = await client.request("validate_monitor_config");
    const validation = validateResponse(ConfigValidationResultSchema, response);

    if (parsed.json) {
      console.log(JSON.stringify(validation, null, 2));
    } else {
      if (validation.valid) {
        console.log("✓ Configuration is valid");
        console.log("\nNo issues found");
      } else {
        console.error("✗ Configuration validation failed\n");

        const errors = validation.issues.filter((i) => i.severity === "error");
        const warnings = validation.issues.filter((i) => i.severity === "warning");

        if (errors.length > 0) {
          console.error(`Errors (${errors.length}):`);
          for (const issue of errors) {
            console.error(`  ✗ ${issue.field}: ${issue.message}`);
          }
          console.error("");
        }

        if (warnings.length > 0) {
          console.log(`Warnings (${warnings.length}):`);
          for (const issue of warnings) {
            console.log(`  ⚠ ${issue.field}: ${issue.message}`);
          }
          console.log("");
        }

        Deno.exit(1);
      }
    }
  } catch (err) {
    if (err instanceof Error) {
      console.error(`Error: ${err.message}`);
      Deno.exit(1);
    }
    throw err;
  }
}

/**
 * T028: Config reload command
 */
async function configReloadCommand(
  parsed: any,
  _options: MonitorsCommandOptions,
): Promise<void> {
  const client = new DaemonClient();

  try {
    await client.connect();

    const response = await client.request("reload_monitor_config");
    const result = validateResponse(ReloadConfigResponseSchema, response);

    if (parsed.json) {
      console.log(JSON.stringify(result, null, 2));
    } else {
      if (result.success) {
        console.log("✓ Configuration reloaded successfully\n");
        if (result.changes && result.changes.length > 0) {
          console.log("Changes:");
          for (const change of result.changes) {
            console.log(`  • ${change}`);
          }
        }
        console.log("\nRun 'i3pm monitors reassign' to apply the new configuration");
      } else {
        console.error("✗ Failed to reload configuration");
        if (result.error) {
          console.error(`\nError: ${result.error}`);
        }
        Deno.exit(1);
      }
    }
  } catch (err) {
    if (err instanceof Error) {
      console.error(`Error: ${err.message}`);
      Deno.exit(1);
    }
    throw err;
  }
}

/**
 * T029: Reassign workspaces command
 */
async function reassignCommand(
  parsed: any,
  _options: MonitorsCommandOptions,
): Promise<void> {
  const client = new DaemonClient();

  try {
    await client.connect();

    const dryRun = parsed["dry-run"] || false;

    const response = await client.request("reassign_workspaces", {
      dry_run: dryRun,
    });
    const result = validateResponse(ReassignWorkspacesResponseSchema, response);

    if (parsed.json) {
      console.log(JSON.stringify(result, null, 2));
    } else {
      if (result.success) {
        if (dryRun) {
          console.log(`✓ Would reassign ${result.assignments_made} workspace(s)`);
          console.log("\nThis is a dry-run. No changes were made.");
          console.log("Run without --dry-run to apply changes");
        } else {
          console.log(`✓ Successfully reassigned ${result.assignments_made} workspace(s)`);
        }
      } else {
        console.error("✗ Failed to reassign workspaces");
        if (result.errors && result.errors.length > 0) {
          console.error("\nErrors:");
          for (const error of result.errors) {
            console.error(`  • ${error}`);
          }
        }
        Deno.exit(1);
      }
    }
  } catch (err) {
    if (err instanceof Error) {
      console.error(`Error: ${err.message}`);
      Deno.exit(1);
    }
    throw err;
  }
}
