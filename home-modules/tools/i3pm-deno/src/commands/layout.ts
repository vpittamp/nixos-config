/**
 * Layout Persistence Commands
 * Feature 030: User Story 2 - Workspace Layout Persistence
 *
 * Save and restore complex workspace layouts across sessions.
 */

import { parseArgs } from "@std/cli/parse-args";
import { DaemonClient } from "../client.ts";
import type {
  LayoutSnapshot,
  WorkspaceLayout,
  WindowPlaceholder,
} from "../models.ts";
import { setup, Spinner } from "@cli-ux";
import { z } from "zod";

interface LayoutCommandOptions {
  verbose?: boolean;
  debug?: boolean;
}

// Initialize CLI-UX formatter for semantic colors
const { formatter } = setup();

function showHelp(): void {
  console.log(`
i3pm layout - Workspace layout persistence

USAGE:
  i3pm layout <SUBCOMMAND> [OPTIONS]

SUBCOMMANDS:
  save <name>       Save current workspace layout
  restore <name>    Restore saved workspace layout
  list              List saved layouts
  delete <name>     Delete a saved layout
  diff <name>       Compare saved layout with current state
  export <name>     Export layout to portable format
  import <file>     Import layout from file
  info <name>       Show detailed layout information

OPTIONS:
  -h, --help        Show this help message

SAVE OPTIONS:
  --project <name>  Specify project (default: current active project)

RESTORE OPTIONS:
  --dry-run         Validate layout without applying
  --adapt-monitors  Adapt layout to current monitor configuration (default: true)
  --no-adapt        Don't adapt layout to monitor changes
  --project <name>  Specify project (default: current active project)

LIST OPTIONS:
  --project <name>  Filter by project (default: all projects)
  --json            Output as JSON

DELETE OPTIONS:
  --project <name>  Specify project (default: current active project)

DIFF OPTIONS:
  --project <name>  Specify project (default: current active project)

EXPORT OPTIONS:
  --project <name>  Specify project (default: current active project)
  --output <file>   Output file path (default: stdout)

IMPORT OPTIONS:
  --project <name>  Target project (required)
  --name <name>     Layout name (default: from file)

INFO OPTIONS:
  --project <name>  Specify project (default: current active project)
  --json            Output as JSON

EXAMPLES:
  # Save current layout
  i3pm layout save my-layout
  i3pm layout save my-layout --project=nixos

  # Restore layout
  i3pm layout restore my-layout
  i3pm layout restore my-layout --dry-run          # Validate only
  i3pm layout restore my-layout --no-adapt         # Don't adapt to monitors

  # List saved layouts
  i3pm layout list
  i3pm layout list --project=nixos
  i3pm layout list --json

  # Delete layout
  i3pm layout delete my-layout
  i3pm layout delete my-layout --project=nixos

  # Compare with current state
  i3pm layout diff my-layout

  # Export/import for backup or sharing
  i3pm layout export my-layout --output=layout.json
  i3pm layout import layout.json --project=nixos --name=imported-layout

  # Show detailed information
  i3pm layout info my-layout
  i3pm layout info my-layout --json
`);
  Deno.exit(0);
}

/**
 * T041: Implement `i3pm layout save <name>` command
 */
async function saveCommand(
  client: DaemonClient,
  args: (string | number)[],
  options: LayoutCommandOptions,
): Promise<void> {
  const parsed = parseArgs(args.map(String), {
    string: ["project"],
    stopEarly: true,
  });

  if (parsed._.length === 0) {
    console.error(formatter.error("Error: Layout name is required"));
    console.error("Usage: i3pm layout save <name> [--project=<project>]");
    Deno.exit(1);
  }

  const layoutName = parsed._[0] as string;
  let projectName = parsed.project as string | undefined;

  const spinner = new Spinner({
    message: "Saving layout...",
    showAfter: 0,
  });
  spinner.start();

  try {
    // If no project specified, get the active project from daemon
    if (!projectName) {
      const statusResponse = await client.request("get_status");
      const activeProject = statusResponse.active_project as string | null;

      if (!activeProject) {
        spinner.stop();
        console.error(formatter.error("Error: No active project"));
        console.error("Either switch to a project first or specify --project=<name>");
        Deno.exit(1);
      }

      projectName = activeProject;
    }

    const params: { name: string; project: string } = {
      name: layoutName,
      project: projectName,
    };

    const response = await client.request("layout.save", params, 10000);

    if (options.debug) {
      console.error("DEBUG: Raw response:", JSON.stringify(response, null, 2));
    }

    // Validate response
    const SaveResponseSchema = z.object({
      success: z.boolean(),
      name: z.string(),
      project: z.string(),
      file_path: z.string(),
      total_windows: z.number(),
      total_workspaces: z.number(),
      total_monitors: z.number(),
    });

    const result = SaveResponseSchema.parse(response);
    spinner.stop();

    if (result.success) {
      console.log(formatter.success("\n✓ Layout saved successfully"));
      console.log(formatter.dim("─".repeat(60)));
      console.log(`  Name:       ${formatter.bold(result.name)}`);
      console.log(`  Project:    ${formatter.bold(result.project)}`);
      console.log(`  Windows:    ${result.total_windows}`);
      console.log(`  Workspaces: ${result.total_workspaces}`);
      console.log(`  Monitors:   ${result.total_monitors}`);
      console.log(`  Saved to:   ${formatter.dim(result.file_path)}`);
      console.log(formatter.dim("─".repeat(60)));
    } else {
      console.error(formatter.error("Failed to save layout"));
      Deno.exit(1);
    }
  } catch (err) {
    spinner.stop();

    if (err instanceof z.ZodError) {
      console.error(formatter.error("Invalid daemon response format"));
      if (options.debug) {
        console.error(formatter.dim("Validation errors:"), err.errors);
      }
      Deno.exit(1);
    }
    throw err;
  }
}

/**
 * T042: Implement `i3pm layout restore <name>` command
 */
async function restoreCommand(
  client: DaemonClient,
  args: (string | number)[],
  options: LayoutCommandOptions,
): Promise<void> {
  const parsed = parseArgs(args.map(String), {
    string: ["project"],
    boolean: ["dry-run", "adapt-monitors", "no-adapt"],
    default: { "adapt-monitors": true },
  });

  if (parsed._.length === 0) {
    console.error(formatter.error("Error: Layout name is required"));
    console.error("Usage: i3pm layout restore <name> [OPTIONS]");
    Deno.exit(1);
  }

  const layoutName = parsed._[0] as string;
  const projectName = parsed.project as string | undefined;
  const dryRun = parsed["dry-run"] as boolean;
  const adaptMonitors = parsed["no-adapt"] ? false : parsed["adapt-monitors"] as boolean;

  const spinner = new Spinner({
    message: dryRun ? "Validating layout..." : "Restoring layout...",
    showAfter: 0,
  });
  spinner.start();

  try {
    const params: {
      name: string;
      project?: string;
      dry_run?: boolean;
      adapt_monitors?: boolean;
    } = {
      name: layoutName,
      dry_run: dryRun,
      adapt_monitors: adaptMonitors,
    };

    if (projectName) {
      params.project = projectName;
    }

    // Longer timeout for restore operations (may need to launch applications)
    const response = await client.request("layout.restore", params, 60000);

    if (options.debug) {
      console.error("DEBUG: Raw response:", JSON.stringify(response, null, 2));
    }

    // Validate response
    const RestoreResponseSchema = z.object({
      success: z.boolean(),
      name: z.string(),
      project: z.string(),
      dry_run: z.boolean().optional(),
      windows_launched: z.number().optional(),
      windows_swallowed: z.number().optional(),
      windows_failed: z.number().optional(),
      total_windows: z.number().optional(),
      total_workspaces: z.number().optional(),
      duration_seconds: z.number().optional(),
      errors: z.array(z.string()).optional(),
    });

    const result = RestoreResponseSchema.parse(response);
    spinner.stop();

    if (result.dry_run) {
      // Dry run validation
      console.log(formatter.success("\n✓ Layout validation successful"));
      console.log(formatter.dim("─".repeat(60)));
      console.log(`  Name:       ${formatter.bold(result.name)}`);
      console.log(`  Project:    ${formatter.bold(result.project)}`);
      console.log(`  Windows:    ${result.total_windows}`);
      console.log(`  Workspaces: ${result.total_workspaces}`);
      console.log(formatter.dim("─".repeat(60)));
      console.log(formatter.info("\nLayout is valid and ready to restore"));
      console.log(formatter.dim("Run without --dry-run to apply the layout"));
    } else {
      // Actual restoration
      if (result.success) {
        console.log(formatter.success("\n✓ Layout restored successfully"));
        console.log(formatter.dim("─".repeat(60)));
        console.log(`  Name:       ${formatter.bold(result.name)}`);
        console.log(`  Project:    ${formatter.bold(result.project)}`);
        console.log(`  Launched:   ${result.windows_launched || 0} application(s)`);
        console.log(
          `  Restored:   ${result.windows_swallowed || 0} window(s)`
        );

        if ((result.windows_failed || 0) > 0) {
          console.log(
            `  Failed:     ${formatter.warning(String(result.windows_failed))} window(s)`
          );
        }

        if (result.duration_seconds !== undefined) {
          console.log(
            `  Duration:   ${formatter.dim(result.duration_seconds.toFixed(1) + "s")}`
          );
        }

        console.log(formatter.dim("─".repeat(60)));

        // Show errors if any
        if (result.errors && result.errors.length > 0) {
          console.log(formatter.warning("\nWarnings:"));
          for (const error of result.errors) {
            console.log(formatter.dim(`  - ${error}`));
          }
        }
      } else {
        console.error(formatter.error("\nFailed to restore layout"));
        if (result.errors && result.errors.length > 0) {
          console.error(formatter.error("\nErrors:"));
          for (const error of result.errors) {
            console.error(formatter.dim(`  - ${error}`));
          }
        }
        Deno.exit(1);
      }
    }
  } catch (err) {
    spinner.stop();

    if (err instanceof z.ZodError) {
      console.error(formatter.error("Invalid daemon response format"));
      if (options.debug) {
        console.error(formatter.dim("Validation errors:"), err.errors);
      }
      Deno.exit(1);
    }
    throw err;
  }
}

/**
 * T043: Implement `i3pm layout list` command
 */
async function listCommand(
  client: DaemonClient,
  args: (string | number)[],
  options: LayoutCommandOptions,
): Promise<void> {
  const parsed = parseArgs(args.map(String), {
    string: ["project"],
    boolean: ["json"],
  });

  const projectName = parsed.project as string | undefined;
  const jsonOutput = parsed.json as boolean;

  const spinner = new Spinner({
    message: "Fetching layouts...",
    showAfter: 0,
  });
  spinner.start();

  try {
    const params: { project?: string } = {};
    if (projectName) {
      params.project = projectName;
    }

    const response = await client.request("layout.list", params, 5000);

    if (options.debug) {
      console.error("DEBUG: Raw response:", JSON.stringify(response, null, 2));
    }

    // Validate response
    const LayoutInfoSchema = z.object({
      name: z.string(),
      project: z.string(),
      created_at: z.string(),
      total_windows: z.number(),
      total_workspaces: z.number(),
      total_monitors: z.number(),
    });

    const ListResponseSchema = z.object({
      layouts: z.array(LayoutInfoSchema),
    });

    const result = ListResponseSchema.parse(response);
    spinner.stop();

    if (jsonOutput) {
      console.log(JSON.stringify(result.layouts, null, 2));
      return;
    }

    if (result.layouts.length === 0) {
      console.log("\nNo saved layouts found");
      if (projectName) {
        console.log(formatter.dim(`(Project: ${projectName})`));
      }
      return;
    }

    // Group layouts by project
    const layoutsByProject = new Map<string, typeof result.layouts>();
    for (const layout of result.layouts) {
      if (!layoutsByProject.has(layout.project)) {
        layoutsByProject.set(layout.project, []);
      }
      layoutsByProject.get(layout.project)!.push(layout);
    }

    console.log(formatter.bold(`\nSaved Layouts (${result.layouts.length} total):`));
    console.log(formatter.dim("─".repeat(80)));

    for (const [project, layouts] of layoutsByProject) {
      console.log(`\n${formatter.bold("📁 " + project)}`);

      for (const layout of layouts) {
        const createdDate = new Date(layout.created_at).toLocaleString();
        console.log(
          `  ${formatter.success("●")} ${formatter.bold(layout.name)} ` +
          formatter.dim(
            `(${layout.total_windows}w, ${layout.total_workspaces}ws, ${layout.total_monitors}m)`
          )
        );
        console.log(`    ${formatter.dim("Created: " + createdDate)}`);
      }
    }

    console.log(formatter.dim("\n" + "─".repeat(80)));
  } catch (err) {
    spinner.stop();

    if (err instanceof z.ZodError) {
      console.error(formatter.error("Invalid daemon response format"));
      if (options.debug) {
        console.error(formatter.dim("Validation errors:"), err.errors);
      }
      Deno.exit(1);
    }
    throw err;
  }
}

/**
 * T044: Implement `i3pm layout delete <name>` command
 */
async function deleteCommand(
  client: DaemonClient,
  args: (string | number)[],
  options: LayoutCommandOptions,
): Promise<void> {
  const parsed = parseArgs(args.map(String), {
    string: ["project"],
  });

  if (parsed._.length === 0) {
    console.error(formatter.error("Error: Layout name is required"));
    console.error("Usage: i3pm layout delete <name> [--project=<project>]");
    Deno.exit(1);
  }

  const layoutName = parsed._[0] as string;
  const projectName = parsed.project as string | undefined;

  const spinner = new Spinner({
    message: "Deleting layout...",
    showAfter: 0,
  });
  spinner.start();

  try {
    const params: { name: string; project?: string } = {
      name: layoutName,
    };

    if (projectName) {
      params.project = projectName;
    }

    const response = await client.request("layout.delete", params, 5000);

    if (options.debug) {
      console.error("DEBUG: Raw response:", JSON.stringify(response, null, 2));
    }

    // Validate response
    const DeleteResponseSchema = z.object({
      success: z.boolean(),
      name: z.string(),
      project: z.string(),
    });

    const result = DeleteResponseSchema.parse(response);
    spinner.stop();

    if (result.success) {
      console.log(formatter.success("\n✓ Layout deleted successfully"));
      console.log(formatter.dim("─".repeat(60)));
      console.log(`  Name:    ${formatter.bold(result.name)}`);
      console.log(`  Project: ${formatter.bold(result.project)}`);
      console.log(formatter.dim("─".repeat(60)));
    } else {
      console.error(formatter.error("Failed to delete layout"));
      Deno.exit(1);
    }
  } catch (err) {
    spinner.stop();

    if (err instanceof z.ZodError) {
      console.error(formatter.error("Invalid daemon response format"));
      if (options.debug) {
        console.error(formatter.dim("Validation errors:"), err.errors);
      }
      Deno.exit(1);
    }
    throw err;
  }
}

/**
 * T048: Implement `i3pm layout info <name>` command
 */
async function infoCommand(
  client: DaemonClient,
  args: (string | number)[],
  options: LayoutCommandOptions,
): Promise<void> {
  const parsed = parseArgs(args.map(String), {
    string: ["project"],
    boolean: ["json"],
  });

  if (parsed._.length === 0) {
    console.error(formatter.error("Error: Layout name is required"));
    console.error("Usage: i3pm layout info <name> [OPTIONS]");
    Deno.exit(1);
  }

  const layoutName = parsed._[0] as string;
  const projectName = parsed.project as string | undefined;
  const jsonOutput = parsed.json as boolean;

  const spinner = new Spinner({
    message: "Fetching layout info...",
    showAfter: 0,
  });
  spinner.start();

  try {
    const params: { name: string; project?: string } = {
      name: layoutName,
    };

    if (projectName) {
      params.project = projectName;
    }

    const response = await client.request("layout.info", params, 5000);

    if (options.debug) {
      console.error("DEBUG: Raw response:", JSON.stringify(response, null, 2));
    }

    // Validate response
    const InfoResponseSchema = z.object({
      name: z.string(),
      project: z.string(),
      created_at: z.string(),
      total_windows: z.number(),
      total_workspaces: z.number(),
      total_monitors: z.number(),
      workspaces: z.array(z.object({
        workspace_num: z.number(),
        workspace_name: z.string().optional(),
        output: z.string(),
        window_count: z.number(),
      })),
      monitors: z.array(z.object({
        name: z.string(),
        width: z.number(),
        height: z.number(),
        primary: z.boolean(),
      })),
    });

    const result = InfoResponseSchema.parse(response);
    spinner.stop();

    if (jsonOutput) {
      console.log(JSON.stringify(result, null, 2));
      return;
    }

    // Display formatted information
    console.log(formatter.bold(`\nLayout Information: ${result.name}`));
    console.log(formatter.dim("─".repeat(80)));
    console.log(`  Project:    ${formatter.bold(result.project)}`);
    console.log(`  Created:    ${new Date(result.created_at).toLocaleString()}`);
    console.log(`  Windows:    ${result.total_windows}`);
    console.log(`  Workspaces: ${result.total_workspaces}`);
    console.log(`  Monitors:   ${result.total_monitors}`);

    console.log(formatter.bold("\n  Workspaces:"));
    for (const ws of result.workspaces) {
      const name = ws.workspace_name || String(ws.workspace_num);
      console.log(
        `    ${formatter.success("●")} ${formatter.bold(name)} ` +
        formatter.dim(`on ${ws.output} (${ws.window_count} windows)`)
      );
    }

    console.log(formatter.bold("\n  Monitors:"));
    for (const mon of result.monitors) {
      const resolution = `${mon.width}x${mon.height}`;
      const primary = mon.primary ? formatter.success(" [primary]") : "";
      console.log(
        `    ${formatter.success("●")} ${formatter.bold(mon.name)} ` +
        formatter.dim(resolution) + primary
      );
    }

    console.log(formatter.dim("\n" + "─".repeat(80)));
  } catch (err) {
    spinner.stop();

    if (err instanceof z.ZodError) {
      console.error(formatter.error("Invalid daemon response format"));
      if (options.debug) {
        console.error(formatter.dim("Validation errors:"), err.errors);
      }
      Deno.exit(1);
    }
    throw err;
  }
}

/**
 * Layout command router
 */
export async function layoutCommand(
  args: (string | number)[],
  options: LayoutCommandOptions,
): Promise<void> {
  const parsed = parseArgs(args.map(String), {
    boolean: ["help"],
    alias: { h: "help" },
    stopEarly: true,
  });

  if (parsed.help || parsed._.length === 0) {
    showHelp();
  }

  const subcommand = parsed._[0] as string;
  const subcommandArgs = parsed._.slice(1);

  // Connect to daemon
  const client = new DaemonClient();

  try {
    await client.connect();

    if (options.verbose) {
      console.error("Connected to daemon");
    }

    // Route to subcommand
    switch (subcommand) {
      case "save":
        await saveCommand(client, subcommandArgs, options);
        break;

      case "restore":
        await restoreCommand(client, subcommandArgs, options);
        break;

      case "list":
        await listCommand(client, subcommandArgs, options);
        break;

      case "delete":
        await deleteCommand(client, subcommandArgs, options);
        break;

      case "info":
        await infoCommand(client, subcommandArgs, options);
        break;

      case "diff":
      case "export":
      case "import":
        console.error(
          formatter.warning(`Subcommand '${subcommand}' is not yet implemented`)
        );
        console.error(
          formatter.dim("Coming soon in future iterations of Feature 030")
        );
        Deno.exit(1);
        break;

      default:
        console.error(formatter.error(`Unknown subcommand: ${subcommand}`));
        console.error('Run "i3pm layout --help" for usage information');
        Deno.exit(1);
    }
  } catch (err) {
    if (err instanceof Error) {
      console.error(formatter.error(err.message));

      if (err.message.includes("Failed to connect")) {
        console.error(
          formatter.info("\nThe daemon is not running. Start it with:")
        );
        console.error(
          formatter.dim("  systemctl --user start i3-project-event-listener")
        );
      }
    } else {
      console.error(formatter.error(String(err)));
    }

    Deno.exit(1);
  } finally {
    await client.close();
    // Force exit to avoid event loop blocking
    Deno.exit(0);
  }
}
