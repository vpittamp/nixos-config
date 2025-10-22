/**
 * Interactive Monitoring Dashboard Command
 */

import { parseArgs } from "@std/cli/parse-args";

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
  - Window state (tree/table)

KEYS:
  Tab       Switch pane focus
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

  console.log("Interactive monitor dashboard - Coming soon in Phase 8");
}
