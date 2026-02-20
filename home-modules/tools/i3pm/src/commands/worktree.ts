/**
 * Worktree Command Dispatcher
 * Feature 100: Structured Git Repository Management
 *
 * Main entry point for all worktree-related commands.
 * Operates on bare repository structure: ~/repos/<account>/<repo>/.bare/
 */

import { parseArgs } from "@std/cli/parse-args";
import { worktreeCreate } from "./worktree/create.ts";
import { worktreeRemove } from "./worktree/remove.ts";
import { worktreeList } from "./worktree/list.ts";
import { worktreeSwitch } from "./worktree/switch.ts";
import { worktreeRemote } from "./worktree/remote.ts";
import { worktreeRename } from "./worktree/rename.ts";

/**
 * Show worktree command help
 */
function showHelp(): void {
  console.log(`
i3pm worktree - Git worktree management for bare repositories

USAGE:
  i3pm worktree <SUBCOMMAND> [OPTIONS]

SUBCOMMANDS:
  create <branch>       Create a new worktree (Feature 100)
  remove <branch>       Remove a worktree (Feature 100)
  rename <old> <new>    Rename worktree and branch via git gtr
  list [repo]           List worktrees for a repository (Feature 100)
  switch <name>         Switch to a worktree by qualified name (Feature 101)
  remote <subcommand>   Manage SSH remote profiles for worktrees (Feature 087)

OPTIONS:
  -h, --help            Show this help message

EXAMPLES:
  # Create worktree for new feature branch
  i3pm worktree create 100-feature
  i3pm worktree create 101-bugfix --from develop

  # List worktrees
  i3pm worktree list
  i3pm worktree list vpittamp/nixos

  # Remove a worktree
  i3pm worktree remove 100-feature
  i3pm worktree remove 100-feature --force
  i3pm worktree rename 100-feature 100-feature-v2
  i3pm worktree remote set vpittamp/nixos-config:main --dir /home/vpittamp/repos/vpittamp/nixos-config/main

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

  let exitCode = 0;

  switch (subcommand) {
    case "create":
      exitCode = await worktreeCreate(subcommandArgs);
      break;

    case "remove":
    case "delete":
      exitCode = await worktreeRemove(subcommandArgs);
      break;

    case "rename":
    case "mv":
      exitCode = await worktreeRename(subcommandArgs);
      break;

    case "list":
      exitCode = await worktreeList(subcommandArgs);
      break;

    case "switch":
      exitCode = await worktreeSwitch(subcommandArgs);
      break;

    case "remote":
      exitCode = await worktreeRemote(subcommandArgs);
      break;

    default:
      console.error(`Error: Unknown subcommand '${subcommand}'`);
      console.error("");
      console.error("Available subcommands: create, remove, rename, list, switch, remote");
      console.error("Run 'i3pm worktree --help' for more information");
      Deno.exit(1);
  }

  Deno.exit(exitCode);
}
