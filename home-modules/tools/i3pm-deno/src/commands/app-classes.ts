/**
 * Application Class Management Command
 */

import { parseArgs } from "@std/cli/parse-args";

interface AppClassesCommandOptions {
  verbose?: boolean;
  debug?: boolean;
}

function showHelp(): void {
  console.log(`
i3pm app-classes - Application class management

USAGE:
  i3pm app-classes [OPTIONS]

OPTIONS:
  -h, --help        Show this help message

DESCRIPTION:
  Shows all configured application classes with their scoping information.

EXAMPLE:
  i3pm app-classes
`);
  Deno.exit(0);
}

export async function appClassesCommand(
  args: (string | number)[],
  options: AppClassesCommandOptions,
): Promise<void> {
  const parsed = parseArgs(args.map(String), {
    boolean: ["help"],
    alias: { h: "help" },
  });

  if (parsed.help) {
    showHelp();
  }

  console.log("Application classes - Coming soon in Phase 7");
}
