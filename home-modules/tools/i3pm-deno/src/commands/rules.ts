/**
 * Window Classification Rules Commands
 */

import { parseArgs } from "@std/cli/parse-args";

interface RulesCommandOptions {
  verbose?: boolean;
  debug?: boolean;
}

function showHelp(): void {
  console.log(`
i3pm rules - Window classification rules management

USAGE:
  i3pm rules <SUBCOMMAND> [OPTIONS]

SUBCOMMANDS:
  list              List all classification rules
  classify          Test window classification
  validate          Validate all rules
  test              Test rule matching

OPTIONS:
  -h, --help        Show this help message

EXAMPLES:
  i3pm rules list
  i3pm rules classify --class Ghostty
  i3pm rules validate
`);
  Deno.exit(0);
}

export async function rulesCommand(
  args: (string | number)[],
  options: RulesCommandOptions,
): Promise<void> {
  const parsed = parseArgs(args.map(String), {
    boolean: ["help"],
    alias: { h: "help" },
  });

  if (parsed.help || parsed._.length === 0) {
    showHelp();
  }

  console.log("Rules management - Coming soon in Phase 7");
}
