/**
 * Window State Visualization Commands
 *
 * Provides multiple visualization formats for window state.
 */

import { parseArgs } from "@std/cli/parse-args";
import { DaemonClient } from "../client.ts";
import { OutputSchema } from "../validation.ts";
import type { Output } from "../models.ts";
import { renderTree, renderLegend as renderTreeLegend } from "../ui/tree.ts";
import { renderTable, renderLegend as renderTableLegend } from "../ui/table.ts";
import { z } from "zod";
import { setup, Spinner } from "@cli-ux";

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
i3pm windows - Window state visualization

USAGE:
  i3pm windows [OPTIONS]

OPTIONS:
  --tree            Tree view (default)
  --table           Table view
  --json            JSON output
  --live            Live TUI with real-time updates
  --hidden          Show hidden windows (scoped to inactive projects)
  --project <name>  Filter by project
  --output <name>   Filter by output (monitor)
  --legend          Show legend for status indicators
  -h, --help        Show this help message

EXAMPLES:
  i3pm windows              # Tree view (default)
  i3pm windows --table      # Table view
  i3pm windows --json       # JSON output for scripting
  i3pm windows --live       # Live TUI (press 'q' to quit)
  i3pm windows --hidden     # Show all windows including hidden

LIVE TUI KEYS:
  Tab       Switch between tree and table view
  H         Toggle hidden windows
  Q         Quit
  Ctrl+C    Exit
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
 * Windows command router
 */
export async function windowsCommand(
  args: (string | number)[],
  options: WindowsCommandOptions,
): Promise<void> {
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
