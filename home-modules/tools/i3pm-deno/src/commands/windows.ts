/**
 * Window State Visualization Commands
 *
 * Provides multiple visualization formats for window state and
 * window visibility management (Feature 037).
 */

import { parseArgs } from "@std/cli/parse-args";
import { DaemonClient } from "../client.ts";
import { OutputSchema } from "../validation.ts";
import type { Output } from "../models.ts";
import { renderTree, renderLegend as renderTreeLegend } from "../ui/tree.ts";
import { renderTable, renderLegend as renderTableLegend } from "../ui/table.ts";
import { z } from "zod";
import { setup, Spinner } from "@cli-ux";
import { bold, cyan, dim, gray, green, yellow, red, blue } from "../ui/ansi.ts";

interface WindowsCommandOptions {
  verbose?: boolean;
  debug?: boolean;
}

// Initialize CLI-UX formatter for semantic colors
const { formatter } = setup();

/**
 * Show windows command help
 */
function showHelp(): void {
  console.log(`
i3pm windows - Window state visualization and management

USAGE:
  i3pm windows [SUBCOMMAND] [OPTIONS]

SUBCOMMANDS:
  ${bold("Visualization")} (default when no subcommand)
    ${cyan("show")}           Display window state (tree/table/live)
    ${cyan("hidden")}         Show windows hidden in scratchpad
    ${cyan("inspect")}        Inspect detailed state for a window

  ${bold("Management")}
    ${cyan("restore")}        Restore hidden windows for a project

VISUALIZATION OPTIONS:
  --tree            Tree view (default)
  --table           Table view
  --json            JSON output
  --live            Live TUI with real-time updates
  --hidden          Show hidden windows (scoped to inactive projects)
  --project <name>  Filter by project
  --output <name>   Filter by output (monitor)
  --legend          Show legend for status indicators

EXAMPLES:
  ${dim("# Visualization")}
  i3pm windows              ${dim("# Tree view (default)")}
  i3pm windows --table      ${dim("# Table view")}
  i3pm windows --json       ${dim("# JSON output for scripting")}
  i3pm windows --live       ${dim("# Live TUI (press 'q' to quit)")}

  ${dim("# Hidden Windows (Feature 037)")}
  i3pm windows hidden                ${dim("# Show all hidden windows")}
  i3pm windows hidden --project nixos ${dim("# Filter by project")}
  i3pm windows hidden --workspace 5   ${dim("# Filter by workspace")}
  i3pm windows hidden --json          ${dim("# JSON output")}

  ${dim("# Restore Windows")}
  i3pm windows restore nixos          ${dim("# Restore all nixos windows")}
  i3pm windows restore --dry-run nixos ${dim("# Preview without restoring")}
  i3pm windows restore --workspace 5 nixos ${dim("# Override workspace")}

  ${dim("# Inspect Window")}
  i3pm windows inspect 94371598417536  ${dim("# Show detailed window state")}
  i3pm windows inspect --json <id>     ${dim("# JSON output")}

For detailed documentation, run:
  i3pm windows <subcommand> --help
`);
  Deno.exit(0);
}

/**
 * Filter outputs by project or output name
 */
function filterOutputs(
  outputs: Output[],
  filters: { project?: string; output?: string },
): Output[] {
  let filtered = outputs;

  // Filter by output name
  if (filters.output) {
    filtered = filtered.filter((o) => o.name === filters.output);
  }

  // Filter by project (filter windows with project mark)
  if (filters.project) {
    filtered = filtered.map((output) => ({
      ...output,
      workspaces: output.workspaces.map((ws) => ({
        ...ws,
        windows: ws.windows.filter((w) =>
          w.marks.some((m) => m === `project:${filters.project}`)
        ),
      })),
    }));
  }

  return filtered;
}

/**
 * Fetch window state from daemon
 */
async function getWindowState(
  client: DaemonClient,
  options: WindowsCommandOptions,
): Promise<Output[]> {
  try {
    const response = await client.request("get_windows");

    if (options.debug) {
      console.error("DEBUG: Raw response:", JSON.stringify(response, null, 2));
    }

    // Validate response with Zod
    const OutputArraySchema = z.array(OutputSchema);
    const validated = OutputArraySchema.parse(response);

    return validated;
  } catch (err) {
    if (err instanceof z.ZodError) {
      console.error(formatter.error("Invalid daemon response format"));
      if (options.debug) {
        console.error(formatter.dim("Validation errors:"), err.errors);
      }
      console.error(formatter.warning("This may indicate a protocol version mismatch"));
      Deno.exit(1);
    }
    throw err;
  }
}

/**
 * Show hidden windows (Feature 037 T038)
 */
async function hiddenCommand(
  args: (string | number)[],
  options: WindowsCommandOptions,
): Promise<void> {
  const parsed = parseArgs(args.map(String), {
    boolean: ["help", "json", "tree", "table"],
    string: ["project", "workspace", "app"],
    alias: { h: "help" },
    default: { tree: true },
  });

  if (parsed.help) {
    console.log(`
i3pm windows hidden - Show hidden windows in scratchpad

USAGE:
  i3pm windows hidden [OPTIONS]

OPTIONS:
  --project <name>     Filter by project name
  --workspace <num>    Filter by tracked workspace number
  --app <name>         Filter by application name
  --tree               Tree view (default)
  --table              Table view
  --json               JSON output for scripting
  -h, --help           Show this help message

EXAMPLES:
  i3pm windows hidden                 ${dim("# Show all hidden windows")}
  i3pm windows hidden --project nixos ${dim("# Show hidden windows for nixos project")}
  i3pm windows hidden --workspace 5   ${dim("# Show windows tracked to workspace 5")}
  i3pm windows hidden --app vscode    ${dim("# Show hidden VS Code windows")}
  i3pm windows hidden --json          ${dim("# JSON output")}
`);
    Deno.exit(0);
  }

  const client = new DaemonClient();
  const spinner = new Spinner({ message: "Querying hidden windows...", showAfter: 100 });
  spinner.start();

  try {
    await client.connect();

    // Build params for daemon request
    const params: Record<string, string | number> = {};
    if (parsed.project) params.project_name = String(parsed.project);
    if (parsed.workspace) params.workspace = Number(parsed.workspace);
    if (parsed.app) params.app_name = String(parsed.app);

    // Request hidden windows from daemon
    const result = await client.request<{
      projects: Record<string, Array<{
        window_id: number;
        app_name: string;
        window_class: string;
        window_title: string;
        tracked_workspace: number;
        floating: boolean;
        last_seen: number;
      }>>;
      total_hidden: number;
      duration_ms: number;
    }>("windows.getHidden", params);

    spinner.stop();

    // JSON output
    if (parsed.json) {
      console.log(JSON.stringify(result, null, 2));
      return;
    }

    // Check if any windows found
    if (result.total_hidden === 0) {
      console.log(bold("No hidden windows found"));
      if (parsed.project) console.log(`  Project filter: ${cyan(String(parsed.project))}`);
      if (parsed.workspace) console.log(`  Workspace filter: ${cyan(String(parsed.workspace))}`);
      if (parsed.app) console.log(`  App filter: ${cyan(String(parsed.app))}`);
      return;
    }

    // Render based on format
    if (parsed.table) {
      // Table view
      console.log(bold("Hidden Windows") + dim(` (${result.total_hidden} total)`));
      console.log("");

      // Create table rows
      const rows: string[][] = [];
      for (const [projectName, windows] of Object.entries(result.projects)) {
        for (const window of windows) {
          rows.push([
            String(window.window_id),
            cyan(projectName),
            window.app_name,
            window.window_class,
            truncate(window.window_title, 40),
            `WS ${window.tracked_workspace}`,
            window.floating ? "⬜" : "",
          ]);
        }
      }

      // Print table header
      const header = ["ID", "Project", "App", "Class", "Title", "Workspace", "Float"];
      console.log(bold(header.map((h, i) => padEnd(h, getColumnWidth(i, header, rows))).join("  ")));
      console.log(dim("─".repeat(120)));

      // Print rows
      for (const row of rows) {
        console.log(row.map((cell, i) => padEnd(cell, getColumnWidth(i, header, rows))).join("  "));
      }
    } else {
      // Tree view (default)
      console.log(bold("Hidden Windows") + dim(` (${result.total_hidden} total)`));
      console.log("");

      for (const [projectName, windows] of Object.entries(result.projects)) {
        console.log(cyan(`📦 ${projectName}`) + dim(` (${windows.length} windows)`));
        for (const window of windows) {
          const floatIndicator = window.floating ? " ⬜" : "";
          console.log(`  ${window.app_name} ${dim("-")} ${truncate(window.window_title, 50)}`);
          console.log(`    ${gray("Class:")} ${window.window_class} ${gray("WS:")} ${window.tracked_workspace}${floatIndicator}`);
          console.log(`    ${gray("ID:")} ${dim(String(window.window_id))}`);
        }
        console.log("");
      }
    }

    // Footer
    console.log(dim(`Query completed in ${result.duration_ms.toFixed(1)}ms`));
  } catch (err) {
    spinner.stop();
    if (err instanceof Error) {
      console.error(red("✗ Error: ") + err.message);
      if (err.message.includes("Failed to connect")) {
        console.error(dim("\nThe daemon is not running. Start it with:"));
        console.error(dim("  systemctl --user start i3-project-event-listener"));
      }
    } else {
      console.error(red("✗ Error: ") + String(err));
    }
    Deno.exit(1);
  } finally {
    await client.close();
    Deno.exit(0);
  }
}

/**
 * Restore windows for a project (Feature 037 T041)
 */
async function restoreCommand(
  args: (string | number)[],
  options: WindowsCommandOptions,
): Promise<void> {
  const parsed = parseArgs(args.map(String), {
    boolean: ["help", "json", "dry-run"],
    string: ["workspace"],
    alias: { h: "help" },
  });

  if (parsed.help) {
    console.log(`
i3pm windows restore - Restore hidden windows for a project

USAGE:
  i3pm windows restore [OPTIONS] <PROJECT>

ARGUMENTS:
  <PROJECT>            Project name whose windows to restore

OPTIONS:
  --dry-run            Preview what would be restored without restoring
  --workspace <num>    Override tracked workspace (restore all to this workspace)
  --json               JSON output for scripting
  -h, --help           Show this help message

EXAMPLES:
  i3pm windows restore nixos            ${dim("# Restore all nixos windows")}
  i3pm windows restore --dry-run nixos  ${dim("# Preview without restoring")}
  i3pm windows restore --workspace 5 nixos ${dim("# Restore all to workspace 5")}
`);
    Deno.exit(0);
  }

  // Get project name from positional arg
  const projectName = String(parsed._[0] || "");
  if (!projectName) {
    console.error(red("✗ Error: ") + "Project name required");
    console.error(dim("\nUsage: i3pm windows restore <PROJECT>"));
    console.error(dim("Example: i3pm windows restore nixos"));
    Deno.exit(1);
  }

  const client = new DaemonClient();
  const isDryRun = parsed["dry-run"] === true;
  const workspaceOverride = parsed.workspace ? Number(parsed.workspace) : undefined;

  const spinner = new Spinner({
    message: isDryRun ? "Querying hidden windows..." : "Restoring windows...",
    showAfter: 100,
  });
  spinner.start();

  try {
    await client.connect();

    if (isDryRun) {
      // Dry run - query hidden windows
      const result = await client.request<{
        projects: Record<string, Array<{
          window_id: number;
          app_name: string;
          window_class: string;
          window_title: string;
          tracked_workspace: number;
          floating: boolean;
        }>>;
        total_hidden: number;
      }>("windows.getHidden", { project_name: projectName });

      spinner.stop();

      if (parsed.json) {
        console.log(JSON.stringify(result, null, 2));
        return;
      }

      const windows = result.projects[projectName] || [];
      if (windows.length === 0) {
        console.log(yellow("⚠ No hidden windows found for project '") + cyan(projectName) + yellow("'"));
        return;
      }

      console.log(yellow("🔍 DRY RUN") + dim(` - Would restore ${windows.length} windows:`));
      console.log("");

      for (const window of windows) {
        const ws = workspaceOverride !== undefined ? workspaceOverride : window.tracked_workspace;
        const overrideIndicator = workspaceOverride !== undefined ? yellow(" (override)") : "";
        console.log(`  ${green("✓")} ${window.app_name} ${dim("→")} ${bold(`WS ${ws}`)}${overrideIndicator}`);
        console.log(`    ${gray(window.window_class)} - ${truncate(window.window_title, 60)}`);
      }
    } else {
      // Actual restore
      const fallbackWorkspace = workspaceOverride !== undefined ? workspaceOverride : 1;
      const result = await client.request<{
        windows_restored: number;
        fallback_warnings: string[];
        errors: string[];
        duration_ms: number;
      }>("project.restoreWindows", {
        project_name: projectName,
        fallback_workspace: fallbackWorkspace,
      });

      spinner.stop();

      if (parsed.json) {
        console.log(JSON.stringify(result, null, 2));
        return;
      }

      if (result.windows_restored === 0) {
        console.log(yellow("⚠ No hidden windows found for project '") + cyan(projectName) + yellow("'"));
        return;
      }

      console.log(green("✓ Restored ") + bold(String(result.windows_restored)) + green(" windows for project '") + cyan(projectName) + green("'"));

      // Show fallback warnings
      if (result.fallback_warnings && result.fallback_warnings.length > 0) {
        console.log("");
        console.log(yellow(`⚠ ${result.fallback_warnings.length} windows used fallback workspace:`));
        const displayCount = Math.min(5, result.fallback_warnings.length);
        for (let i = 0; i < displayCount; i++) {
          console.log(`  ${dim("•")} ${result.fallback_warnings[i]}`);
        }
        if (result.fallback_warnings.length > 5) {
          console.log(dim(`  ... and ${result.fallback_warnings.length - 5} more`));
        }
      }

      // Show errors
      if (result.errors && result.errors.length > 0) {
        console.log("");
        console.log(red(`✗ ${result.errors.length} errors occurred:`));
        const displayCount = Math.min(3, result.errors.length);
        for (let i = 0; i < displayCount; i++) {
          console.log(`  ${red("✗")} ${result.errors[i]}`);
        }
        if (result.errors.length > 3) {
          console.log(dim(`  ... and ${result.errors.length - 3} more`));
        }
      }

      console.log("");
      console.log(dim(`Completed in ${result.duration_ms.toFixed(1)}ms`));
    }
  } catch (err) {
    spinner.stop();
    if (err instanceof Error) {
      console.error(red("✗ Error: ") + err.message);
      if (err.message.includes("Failed to connect")) {
        console.error(dim("\nThe daemon is not running. Start it with:"));
        console.error(dim("  systemctl --user start i3-project-event-listener"));
      }
    } else {
      console.error(red("✗ Error: ") + String(err));
    }
    Deno.exit(1);
  } finally {
    await client.close();
    Deno.exit(0);
  }
}

/**
 * Inspect detailed window state (Feature 037 T043)
 */
async function inspectCommand(
  args: (string | number)[],
  options: WindowsCommandOptions,
): Promise<void> {
  const parsed = parseArgs(args.map(String), {
    boolean: ["help", "json"],
    alias: { h: "help" },
  });

  if (parsed.help) {
    console.log(`
i3pm windows inspect - Inspect detailed window state

USAGE:
  i3pm windows inspect [OPTIONS] <WINDOW_ID>

ARGUMENTS:
  <WINDOW_ID>          Window ID to inspect

OPTIONS:
  --json               JSON output for scripting
  -h, --help           Show this help message

EXAMPLES:
  i3pm windows inspect 94371598417536  ${dim("# Show detailed window state")}
  i3pm windows inspect --json <id>     ${dim("# JSON output")}

TIP: Get window IDs with: i3pm windows --tree
`);
    Deno.exit(0);
  }

  // Get window ID from positional arg
  const windowIdStr = String(parsed._[0] || "");
  if (!windowIdStr) {
    console.error(red("✗ Error: ") + "Window ID required");
    console.error(dim("\nUsage: i3pm windows inspect <WINDOW_ID>"));
    console.error(dim("Example: i3pm windows inspect 94371598417536"));
    console.error(dim("\nTip: Get window IDs with: i3pm windows --tree"));
    Deno.exit(1);
  }

  const windowId = Number(windowIdStr);
  if (isNaN(windowId)) {
    console.error(red("✗ Error: ") + "Invalid window ID (must be a number)");
    Deno.exit(1);
  }

  const client = new DaemonClient();
  const spinner = new Spinner({ message: "Inspecting window...", showAfter: 100 });
  spinner.start();

  try {
    await client.connect();

    const result = await client.request<{
      window_id: number;
      visible: boolean;
      window_class: string;
      window_title: string;
      pid: number;
      i3pm_env: Record<string, string>;
      tracking: {
        workspace_number: number;
        floating: boolean;
        last_seen: number;
        project_name: string;
        app_name: string;
      };
      i3_state: {
        workspace: number;
        output: string;
        floating: string;
        focused: boolean;
      };
      duration_ms: number;
    }>("windows.getState", { window_id: windowId });

    spinner.stop();

    if (parsed.json) {
      console.log(JSON.stringify(result, null, 2));
      return;
    }

    // Display formatted output
    console.log("");
    console.log(bold("Window Inspection: ") + cyan(String(windowId)));
    console.log(dim("═".repeat(70)));
    console.log("");

    // Basic info
    console.log(bold("Basic Information"));
    console.log(`  ${gray("Class:")}   ${result.window_class}`);
    console.log(`  ${gray("Title:")}   ${result.window_title}`);
    console.log(`  ${gray("PID:")}     ${result.pid}`);
    const visibleStatus = result.visible ? green("Yes") : red("No (in scratchpad)");
    console.log(`  ${gray("Visible:")} ${visibleStatus}`);
    console.log("");

    // I3PM environment variables
    console.log(bold("I3PM Environment Variables"));
    if (Object.keys(result.i3pm_env).length > 0) {
      for (const [key, value] of Object.entries(result.i3pm_env)) {
        console.log(`  ${cyan(key)}: ${value}`);
      }
    } else {
      console.log(dim("  (none found - window may not be launched via i3pm)"));
    }
    console.log("");

    // Workspace tracking
    console.log(bold("Workspace Tracking"));
    if (result.tracking && Object.keys(result.tracking).length > 0) {
      console.log(`  ${gray("Workspace:")} ${result.tracking.workspace_number}`);
      console.log(`  ${gray("Floating:")}  ${result.tracking.floating}`);
      console.log(`  ${gray("Project:")}   ${result.tracking.project_name || dim("(none)")}`);
      console.log(`  ${gray("App:")}       ${result.tracking.app_name || dim("(none)")}`);
      if (result.tracking.last_seen) {
        const timeDiff = Date.now() / 1000 - result.tracking.last_seen;
        let lastSeenStr;
        if (timeDiff < 60) {
          lastSeenStr = `${Math.floor(timeDiff)}s ago`;
        } else if (timeDiff < 3600) {
          lastSeenStr = `${Math.floor(timeDiff / 60)}m ago`;
        } else {
          lastSeenStr = `${Math.floor(timeDiff / 3600)}h ago`;
        }
        console.log(`  ${gray("Last seen:")} ${lastSeenStr}`);
      }
    } else {
      console.log(dim("  (no tracking info - window not moved yet)"));
    }
    console.log("");

    // Current i3 state
    console.log(bold("Current i3 State"));
    if (result.i3_state && Object.keys(result.i3_state).length > 0) {
      console.log(`  ${gray("Workspace:")} ${result.i3_state.workspace}`);
      console.log(`  ${gray("Output:")}    ${result.i3_state.output}`);
      console.log(`  ${gray("Floating:")}  ${result.i3_state.floating}`);
      console.log(`  ${gray("Focused:")}   ${result.i3_state.focused}`);
    } else {
      console.log(dim("  (unable to query i3 state)"));
    }
    console.log("");

    console.log(dim(`Completed in ${result.duration_ms.toFixed(1)}ms`));
    console.log("");
  } catch (err) {
    spinner.stop();
    if (err instanceof Error) {
      console.error(red("✗ Error: ") + err.message);
      if (err.message.includes("not found")) {
        console.error(dim("\nWindow not found. Use 'i3pm windows --tree' to see all windows and their IDs"));
      } else if (err.message.includes("Failed to connect")) {
        console.error(dim("\nThe daemon is not running. Start it with:"));
        console.error(dim("  systemctl --user start i3-project-event-listener"));
      }
    } else {
      console.error(red("✗ Error: ") + String(err));
    }
    Deno.exit(1);
  } finally {
    await client.close();
    Deno.exit(0);
  }
}

// Helper functions
function truncate(text: string, maxLength: number): string {
  if (text.length <= maxLength) return text;
  return text.substring(0, maxLength - 3) + "...";
}

function padEnd(text: string, width: number): string {
  return text + " ".repeat(Math.max(0, width - text.length));
}

function getColumnWidth(colIndex: number, header: string[], rows: string[][]): number {
  let max = header[colIndex].length;
  for (const row of rows) {
    if (row[colIndex] && row[colIndex].length > max) {
      max = row[colIndex].length;
    }
  }
  return max;
}

/**
 * Windows command router
 */
export async function windowsCommand(
  args: (string | number)[],
  options: WindowsCommandOptions,
): Promise<void> {
  // Check if first arg is a subcommand
  const firstArg = String(args[0] || "");
  const subcommands = ["hidden", "restore", "inspect", "show"];

  if (subcommands.includes(firstArg)) {
    const subcommand = firstArg;
    const subArgs = args.slice(1);

    switch (subcommand) {
      case "hidden":
        return await hiddenCommand(subArgs, options);
      case "restore":
        return await restoreCommand(subArgs, options);
      case "inspect":
        return await inspectCommand(subArgs, options);
      case "show":
        // Fall through to default visualization
        args = subArgs;
        break;
    }
  }

  // Default visualization command (original behavior)
  const parsed = parseArgs(args.map(String), {
    boolean: ["help", "tree", "table", "json", "live", "hidden", "legend"],
    string: ["project", "output"],
    alias: { h: "help" },
    default: {},
  });

  if (parsed.help) {
    showHelp();
  }

  // Show legend if requested
  if (parsed.legend) {
    console.log(parsed.table ? renderTableLegend() : renderTreeLegend());
    return;
  }

  // Determine output mode (default to tree)
  const isLive = parsed.live === true;
  const isTable = parsed.table === true;
  const isJson = parsed.json === true;
  const isTree = !isTable && !isJson && !isLive;

  // Live mode is handled separately (T023)
  if (isLive) {
    const spinner = new Spinner({ message: "Connecting to daemon...", showAfter: 0 });
    spinner.start();

    const client = new DaemonClient();

    try {
      await client.connect();
      spinner.finish(formatter.success("Connected to daemon"));

      // Import and launch live TUI
      const { LiveTUI } = await import("../ui/live.ts");
      const tui = new LiveTUI(client);
      await tui.run();

      return;
    } catch (err) {
      spinner.stop();

      if (err instanceof Error) {
        console.error(formatter.error(err.message));

        if (err.message.includes("Failed to connect")) {
          console.error(formatter.info("\nThe daemon is not running. Start it with:"));
          console.error(formatter.dim("  systemctl --user start i3-project-event-listener"));
        }
      } else {
        console.error(formatter.error(String(err)));
      }

      Deno.exit(1);
    }
  }

  // Connect to daemon with progress indicator
  const spinner = new Spinner({ message: "Fetching window state...", showAfter: 100 });
  spinner.start();

  const client = new DaemonClient();

  try {
    await client.connect();

    // Fetch window state
    const outputs = await getWindowState(client, options);
    spinner.stop();

    if (options.verbose) {
      console.error(formatter.success("Window state retrieved"));
    }

    // Apply filters
    const filtered = filterOutputs(outputs, {
      project: parsed.project as string | undefined,
      output: parsed.output as string | undefined,
    });

    // Render output based on mode
    if (isJson) {
      // JSON mode (T021)
      console.log(JSON.stringify(filtered, null, 2));
    } else if (isTable) {
      // Table mode (T020)
      console.log(renderTable(filtered, { showHidden: parsed.hidden === true }));
    } else {
      // Tree mode (T019) - default
      console.log(renderTree(filtered, { showHidden: parsed.hidden === true }));
    }
  } catch (err) {
    spinner.stop();

    if (err instanceof Error) {
      console.error(formatter.error(err.message));

      if (err.message.includes("Failed to connect")) {
        console.error(formatter.info("\nThe daemon is not running. Start it with:"));
        console.error(formatter.dim("  systemctl --user start i3-project-event-listener"));
      }
    } else {
      console.error(formatter.error(String(err)));
    }

    Deno.exit(1);
  } finally {
    await client.close();
    // Force exit to avoid event loop blocking from pending read operations
    // See: https://github.com/denoland/deno/issues/4284
    Deno.exit(0);
  }
}
