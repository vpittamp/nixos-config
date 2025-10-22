/**
 * Daemon Status and Event Monitoring Commands
 */

import { parseArgs } from "@std/cli/parse-args";

interface DaemonCommandOptions {
  verbose?: boolean;
  debug?: boolean;
}

function showHelp(): void {
  console.log(`
i3pm daemon - Daemon status and event monitoring

USAGE:
  i3pm daemon <SUBCOMMAND> [OPTIONS]

SUBCOMMANDS:
  status            Show daemon status
  events            Show recent events

OPTIONS:
  -h, --help        Show this help message

EXAMPLES:
  i3pm daemon status
  i3pm daemon events --limit=50 --type=window
`);
  Deno.exit(0);
}

export async function daemonCommand(
  args: (string | number)[],
  options: DaemonCommandOptions,
): Promise<void> {
  const parsed = parseArgs(args.map(String), {
    boolean: ["help"],
    alias: { h: "help" },
  });

  if (parsed.help || parsed._.length === 0) {
    showHelp();
  }

  console.log("Daemon monitoring - Coming soon in Phase 6");
}
