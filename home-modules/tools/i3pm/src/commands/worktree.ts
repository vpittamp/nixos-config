/**
 * Worktree Command Dispatcher
 * Feature 077: Git Worktree Project Management
 *
 * Main entry point for all worktree-related commands.
 */

import { parseArgs } from "@std/cli/parse-args";
import { createWorktreeCommand } from "./worktree/create.ts";
import { removeWorktreeCommand } from "./worktree/remove.ts";
import { listWorktreesCommand } from "./worktree/list.ts";

/**
 * Show worktree command help
 */
function showHelp(): void {
  console.log(`
i3pm worktree - Git worktree project management

USAGE:
  i3pm worktree <SUBCOMMAND> [OPTIONS]

SUBCOMMANDS:
  create <branch>       Create a new worktree and register as i3pm project
  remove <name>         Remove a worktree and clean up all resources
  list                  List all worktrees with metadata
  discover              Discover and register manually created worktrees

OPTIONS:
  -h, --help            Show this help message

EXAMPLES:
  # Create worktree for new feature branch
  i3pm worktree create feature-auth-refactor

  # List all worktrees
  i3pm worktree list

  # Remove a worktree project
  i3pm worktree remove 078-feature-auth-refactor

  # Discover manually created worktrees
  i3pm worktree discover

For detailed help on a specific subcommand:
  i3pm worktree <subcommand> --help
`);
  Deno.exit(0);
}

/**
 * Main worktree command handler
 */
export async function worktreeCommand(args: string[]): Promise<void> {
  const parsed = parseArgs(args, {
    boolean: ["help"],
    alias: { h: "help" },
    stopEarly: true,
  });

  if (parsed.help || parsed._.length === 0) {
    showHelp();
  }

  const subcommand = String(parsed._[0]);
  const subcommandArgs = parsed._.slice(1).map(String);

  switch (subcommand) {
    case "create":
      await createWorktreeCommand(subcommandArgs);
      break;

    case "remove":
    case "delete":
      await removeWorktreeCommand(subcommandArgs);
      break;

    case "list":
      // Feature 079: US6 - T046-T049
      await listWorktreesCommand(subcommandArgs);
      break;

    case "discover":
      console.error("Error: 'worktree discover' not yet implemented");
      console.error("This will be available in a future update");
      Deno.exit(1);
      break;

    default:
      console.error(`Error: Unknown subcommand '${subcommand}'`);
      console.error("");
      console.error("Available subcommands: create, remove, list, discover");
      console.error("Run 'i3pm worktree --help' for more information");
      Deno.exit(1);
  }
}
