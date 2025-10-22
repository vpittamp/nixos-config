/**
 * Interactive Monitoring Dashboard Command
 */

import { parseArgs } from "@std/cli/parse-args";
import { DaemonClient } from "../client.ts";
import { MonitorDashboard } from "../ui/monitor-dashboard.ts";

interface MonitorCommandOptions {
  verbose?: boolean;
  debug?: boolean;
}

function showHelp(): void {
  console.log(`
i3pm monitor - Interactive monitoring dashboard

USAGE:
  i3pm monitor [OPTIONS]

OPTIONS:
  -h, --help        Show this help message

DESCRIPTION:
  Launches a multi-pane TUI showing:
  - Daemon status (real-time)
  - Event stream (scrolling)
  - Window state (tree view)

KEYS:
  Tab       Cycle pane focus
  S         Focus status pane
  E         Focus events pane
  W         Focus windows pane
  Q         Quit
  Ctrl+C    Exit

EXAMPLE:
  i3pm monitor
`);
  Deno.exit(0);
}

export async function monitorCommand(
  args: (string | number)[],
  options: MonitorCommandOptions,
): Promise<void> {
  const parsed = parseArgs(args.map(String), {
    boolean: ["help"],
    alias: { h: "help" },
  });

  if (parsed.help) {
    showHelp();
  }

  // Create daemon client
  const client = new DaemonClient();

  try {
    // Connect to daemon
    await client.connect();

    // Create and run dashboard
    const dashboard = new MonitorDashboard(client);
    await dashboard.run();
  } catch (err) {
    if (err instanceof Error) {
      console.error(`Failed to start monitor: ${err.message}`);
      Deno.exit(1);
    }
    throw err;
  }
}
