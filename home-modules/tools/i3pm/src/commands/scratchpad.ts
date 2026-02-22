/**
 * Scratchpad Terminal Management Commands
 *
 * Handles project-scoped floating terminal lifecycle: toggle, launch, status, close, cleanup.
 */

import { parseArgs } from "@std/cli/parse-args";
import { createClient } from "../client.ts";
import type {
  ScratchpadCleanupResult,
  ScratchpadCloseResult,
  ScratchpadLaunchResult,
  ScratchpadStatusResult,
  ScratchpadToggleResult,
  ScratchpadToggleParams,
} from "../models.ts";
import { bold, cyan, dim, green, red, yellow } from "../ui/ansi.ts";
import { Spinner } from "@cli-ux";

interface ScratchpadCommandOptions {
  verbose?: boolean;
  debug?: boolean;
}

interface ParsedScratchpadArgs {
  _: Array<string | number>;
  [key: string]: unknown;
}

/**
 * Show scratchpad command help
 */
function showHelp(): void {
  console.log(`
i3pm scratchpad - Project-scoped scratchpad terminal management

USAGE:
  i3pm scratchpad <SUBCOMMAND> [OPTIONS]

SUBCOMMANDS:
  toggle [project]  Toggle scratchpad terminal visibility (show/hide)
  launch [project]  Explicitly launch new scratchpad terminal
  status [project]  Get status of scratchpad terminal(s)
  close [project]   Close scratchpad terminal
  cleanup           Remove invalid terminals from state

OPTIONS:
  -h, --help        Show this help message
  --json            Output results as JSON

EXAMPLES:
  # Toggle current project's terminal (most common usage)
  i3pm scratchpad toggle

  # Toggle specific project's terminal
  i3pm scratchpad toggle nixos

  # Launch terminal for current project
  i3pm scratchpad launch

  # Get status of all terminals
  i3pm scratchpad status

  # Get status of specific terminal
  i3pm scratchpad status nixos --json

  # Close terminal for current project
  i3pm scratchpad close

  # Cleanup invalid terminals
  i3pm scratchpad cleanup

NOTES:
  - Without project/context, targets current active context from active-worktree
  - Optional --context-key allows direct local/ssh context targeting
  - Toggle will launch terminal if it doesn't exist
  - Status shows: PID, window ID, context key, state, health
`);
  Deno.exit(0);
}

function parseTarget(
  parsed: ParsedScratchpadArgs,
): { project_name?: string; context_key?: string } {
  const projectName = parsed._ && parsed._[0]
    ? String(parsed._[0])
    : undefined;
  const contextKeyRaw = parsed["context-key"];
  const contextKey = typeof contextKeyRaw === "string" && contextKeyRaw.trim().length > 0
    ? contextKeyRaw.trim()
    : undefined;
  return { project_name: projectName, context_key: contextKey };
}

function printContextLine(result: {
  context_key?: string;
  execution_mode?: string;
  connection_key?: string | null;
}): void {
  if (result.context_key) {
    console.log(`  ${dim("Context:")} ${result.context_key}`);
  }
  if (result.execution_mode) {
    const connection = result.connection_key || "unknown";
    console.log(`  ${dim("Mode:")} ${result.execution_mode} ${dim(`(${connection})`)}`);
  }
}

/**
 * Toggle scratchpad terminal (show/hide or launch if missing)
 */
async function toggleTerminal(
  args: (string | number)[],
  options: ScratchpadCommandOptions,
): Promise<void> {
  const parsed = parseArgs(args.map(String), {
    boolean: ["json", "help"],
    string: ["context-key"],
    alias: { h: "help" },
  }) as ParsedScratchpadArgs;

  if (parsed.help) {
    console.log(`
i3pm scratchpad toggle - Toggle terminal visibility

USAGE:
  i3pm scratchpad toggle [project_name] [OPTIONS]

OPTIONS:
  --context-key <key>  Explicit context key (account/repo:branch::variant::identity)
  --json        Output result as JSON
  -h, --help    Show this help

EXAMPLES:
  i3pm scratchpad toggle
  i3pm scratchpad toggle vpittamp/nixos-config:main
  i3pm scratchpad toggle --context-key vpittamp/nixos-config:main::ssh::vpittamp@ryzen:22
`);
    Deno.exit(0);
  }

  const client = createClient();
  const params: ScratchpadToggleParams = parseTarget(parsed);

  try {
    const result = await client.request<ScratchpadToggleResult>("scratchpad.toggle", params);

    if (parsed.json) {
      console.log(JSON.stringify(result, null, 2));
    } else {
      const project = result.project_name || "current";
      const status = result.status;

      if (status === "launched" || status === "relaunched") {
        console.log(`${green("✓")} ${status} scratchpad terminal for ${cyan(project)}`);
        if (result.pid) {
          console.log(`  ${dim("PID:")} ${result.pid} ${dim("| Window ID:")} ${result.window_id}`);
        } else {
          console.log(`  ${dim("Window ID:")} ${result.window_id}`);
        }
      } else if (status === "shown") {
        console.log(`${green("✓")} Shown scratchpad terminal for ${cyan(project)}`);
        console.log(`  ${dim("Window ID:")} ${result.window_id}`);
      } else if (status === "hidden") {
        console.log(`${yellow("●")} Hidden scratchpad terminal for ${cyan(project)}`);
        console.log(`  ${dim("Window ID:")} ${result.window_id}`);
      } else {
        console.log(`${green("✓")} ${result.message}`);
      }

      if (options.verbose) {
        printContextLine(result);
      }
    }
  } catch (error) {
    const errorMessage = error instanceof Error ? error.message : String(error);
    if (parsed.json) {
      console.error(JSON.stringify({ error: String(error) }, null, 2));
    } else {
      console.error(`${red("✗")} Error toggling terminal: ${errorMessage}`);
    }
    Deno.exit(1);
  }
}

/**
 * Launch scratchpad terminal explicitly
 */
async function launchTerminal(
  args: (string | number)[],
): Promise<void> {
  const parsed = parseArgs(args.map(String), {
    boolean: ["json", "help"],
    string: ["dir", "context-key"],
    alias: { h: "help", d: "dir" },
  }) as ParsedScratchpadArgs;

  if (parsed.help) {
    console.log(`
i3pm scratchpad launch - Launch new scratchpad terminal

USAGE:
  i3pm scratchpad launch [project_name] [OPTIONS]

OPTIONS:
  --dir <path>  Working directory (default: project root)
  --context-key <key>  Explicit context key (account/repo:branch::variant::identity)
  --json        Output result as JSON
  -h, --help    Show this help

EXAMPLES:
  i3pm scratchpad launch
  i3pm scratchpad launch vpittamp/nixos-config:main
  i3pm scratchpad launch --context-key vpittamp/nixos-config:main::local::local@thinkpad
  i3pm scratchpad launch --dir /tmp/test
`);
    Deno.exit(0);
  }

  const client = createClient();
  const baseTarget = parseTarget(parsed);
  const params = {
    ...baseTarget,
    working_dir: parsed.dir ? String(parsed.dir) : undefined,
  };

  const spinner = new Spinner({ message: "Launching scratchpad terminal...", showAfter: 100 });
  if (!parsed.json) {
    spinner.start();
  }

  try {
    const result = await client.request<ScratchpadLaunchResult>("scratchpad.launch", params);

    if (!parsed.json) {
      spinner.stop();
    }

    if (parsed.json) {
      console.log(JSON.stringify(result, null, 2));
    } else {
      const project = result.project_name || "current";
      console.log(`${green("✓")} Launched scratchpad terminal for ${cyan(project)}`);
      console.log(`  ${dim("PID:")} ${result.pid} ${dim("| Window ID:")} ${result.window_id}`);
      console.log(`  ${dim("Working dir:")} ${result.working_dir}`);
      console.log(`  ${dim("Mark:")} ${result.mark}`);
      printContextLine(result);
      if (result.tmux_session_name) {
        console.log(`  ${dim("Tmux session:")} ${result.tmux_session_name}`);
      }
    }
  } catch (error) {
    const errorMessage = error instanceof Error ? error.message : String(error);
    if (!parsed.json) {
      spinner.stop();
    }

    if (parsed.json) {
      console.error(JSON.stringify({ error: String(error) }, null, 2));
    } else {
      console.error(`${red("✗")} Error launching terminal: ${errorMessage}`);

      // Provide helpful error messages
      if (errorMessage.includes("already exists")) {
        console.error(
          `  ${dim("Hint:")} Use 'i3pm scratchpad toggle' to show existing terminal`,
        );
      } else if (errorMessage.includes("does not exist")) {
        console.error(`  ${dim("Hint:")} Check that the directory path is correct`);
      }
    }
    Deno.exit(1);
  }
}

/**
 * Get status of scratchpad terminal(s)
 */
async function statusTerminal(
  args: (string | number)[],
): Promise<void> {
  const parsed = parseArgs(args.map(String), {
    boolean: ["json", "help", "all"],
    string: ["context-key"],
    alias: { h: "help", a: "all" },
  }) as ParsedScratchpadArgs;

  if (parsed.help) {
    console.log(`
i3pm scratchpad status - Get terminal status

USAGE:
  i3pm scratchpad status [project_name] [OPTIONS]

OPTIONS:
  --all         Show all terminals
  --context-key <key>  Explicit context key for a single terminal
  --json        Output result as JSON
  -h, --help    Show this help

EXAMPLES:
  i3pm scratchpad status
  i3pm scratchpad status --all
  i3pm scratchpad status vpittamp/nixos-config:main
  i3pm scratchpad status --context-key vpittamp/nixos-config:main::ssh::vpittamp@ryzen:22
`);
    Deno.exit(0);
  }

  const client = createClient();
  const params = parsed.all ? {} : parseTarget(parsed);

  try {
    const result = await client.request<ScratchpadStatusResult>("scratchpad.status", params);

    if (parsed.json) {
      console.log(JSON.stringify(result, null, 2));
    } else {
      if (result.terminals && result.terminals.length > 0) {
        console.log(bold("Scratchpad Terminals:"));
        console.log();

        for (const terminal of result.terminals) {
          const healthy = terminal.process_running && terminal.window_exists;
          const statusIcon = healthy
            ? (terminal.state === "visible" ? green("●") : yellow("○"))
            : red("✗");

          console.log(
            `${statusIcon} ${cyan(terminal.project_name)} ${
              dim(`(${terminal.state})`)
            }`,
          );
          console.log(`  ${dim("Context:")} ${terminal.context_key}`);
          console.log(
            `  ${dim("Mode:")} ${terminal.execution_mode} ${
              dim(`(${terminal.connection_key || "unknown"})`)
            }`,
          );
          console.log(`  ${dim("PID:")} ${terminal.pid}`);
          console.log(`  ${dim("Window ID:")} ${terminal.window_id}`);
          console.log(`  ${dim("Working dir:")} ${terminal.working_dir}`);
          if (terminal.tmux_session_name) {
            console.log(`  ${dim("Tmux session:")} ${terminal.tmux_session_name}`);
          }
          console.log(`  ${dim("Mark:")} ${terminal.mark}`);
          console.log(
            `  ${dim("Health:")} process=${terminal.process_running ? "up" : "down"} ` +
            `window=${terminal.window_exists ? "present" : "missing"}`,
          );
          console.log(
            `  ${dim("Created:")} ${
              new Date(terminal.created_at * 1000).toLocaleString()
            }`,
          );
          if (terminal.last_shown_at) {
            console.log(
              `  ${dim("Last shown:")} ${
                new Date(terminal.last_shown_at * 1000).toLocaleString()
              }`,
            );
          }
          console.log();
        }
      } else {
        console.log(
          `${dim("No scratchpad terminals found")}`,
        );
      }
    }
  } catch (error) {
    const errorMessage = error instanceof Error ? error.message : String(error);
    if (parsed.json) {
      console.error(JSON.stringify({ error: String(error) }, null, 2));
    } else {
      console.error(`${red("✗")} Error getting status: ${errorMessage}`);
    }
    Deno.exit(1);
  }
}

/**
 * Close scratchpad terminal
 */
async function closeTerminal(
  args: (string | number)[],
  options: ScratchpadCommandOptions,
): Promise<void> {
  const parsed = parseArgs(args.map(String), {
    boolean: ["json", "help", "force"],
    string: ["context-key"],
    alias: { h: "help", f: "force" },
  }) as ParsedScratchpadArgs;

  if (parsed.help) {
    console.log(`
i3pm scratchpad close - Close scratchpad terminal

USAGE:
  i3pm scratchpad close [project_name] [OPTIONS]

OPTIONS:
  --force       Force close even if invalid
  --context-key <key>  Explicit context key (account/repo:branch::variant::identity)
  --json        Output result as JSON
  -h, --help    Show this help

EXAMPLES:
  i3pm scratchpad close              # Close current project terminal
  i3pm scratchpad close nixos        # Close nixos terminal
  i3pm scratchpad close --force      # Force close
`);
    Deno.exit(0);
  }

  const client = createClient();
  const params = parseTarget(parsed);

  try {
    const result = await client.request<ScratchpadCloseResult>("scratchpad.close", params);

    if (parsed.json) {
      console.log(JSON.stringify(result, null, 2));
    } else {
      const project = result.project_name || "current";
      console.log(`${green("✓")} Closed scratchpad terminal for ${cyan(project)}`);
      if (options.verbose) {
        console.log(`  ${dim("Context:")} ${result.context_key}`);
      }
    }
  } catch (error) {
    const errorMessage = error instanceof Error ? error.message : String(error);
    if (parsed.json) {
      console.error(JSON.stringify({ error: String(error) }, null, 2));
    } else {
      console.error(`${red("✗")} Error closing terminal: ${errorMessage}`);
    }
    Deno.exit(1);
  }
}

/**
 * Cleanup invalid terminals
 */
async function cleanupTerminals(
  args: (string | number)[],
): Promise<void> {
  const parsed = parseArgs(args.map(String), {
    boolean: ["json", "help"],
    alias: { h: "help" },
  }) as ParsedScratchpadArgs;

  if (parsed.help) {
    console.log(`
i3pm scratchpad cleanup - Remove invalid terminals

USAGE:
  i3pm scratchpad cleanup [OPTIONS]

OPTIONS:
  --json        Output result as JSON
  -h, --help    Show this help

DESCRIPTION:
  Removes terminals with dead processes or missing windows from state.

EXAMPLES:
  i3pm scratchpad cleanup
  i3pm scratchpad cleanup --json
`);
    Deno.exit(0);
  }

  const client = createClient();

  const spinner = new Spinner({ message: "Cleaning up invalid terminals...", showAfter: 100 });
  if (!parsed.json) {
    spinner.start();
  }

  try {
    const result = await client.request<ScratchpadCleanupResult>("scratchpad.cleanup", {});

    if (!parsed.json) {
      spinner.stop();
    }

    if (parsed.json) {
      console.log(JSON.stringify(result, null, 2));
    } else {
      if (result.cleaned_count > 0) {
        console.log(
          `${green("✓")} Cleaned up ${result.cleaned_count} invalid terminal(s)`,
        );
        if (result.contexts_cleaned && result.contexts_cleaned.length > 0) {
          console.log(`  ${dim("Contexts:")} ${result.contexts_cleaned.join(", ")}`);
        }
        console.log(`  ${dim("Remaining:")} ${result.remaining}`);
      } else {
        console.log(`${green("✓")} No invalid terminals found`);
      }
    }
  } catch (error) {
    if (!parsed.json) {
      spinner.stop();
    }

    if (parsed.json) {
      console.error(JSON.stringify({ error: String(error) }, null, 2));
    } else {
      const errorMessage = error instanceof Error ? error.message : String(error);
      console.error(`${red("✗")} Error during cleanup: ${errorMessage}`);
    }
    Deno.exit(1);
  }
}

/**
 * Main scratchpad command router
 */
export async function scratchpadCommand(
  args: (string | number)[],
  options: ScratchpadCommandOptions,
): Promise<void> {
  const parsed = parseArgs(args.map(String), {
    boolean: ["help"],
    alias: { h: "help" },
    stopEarly: true,
  }) as ParsedScratchpadArgs;

  if (parsed.help || args.length === 0) {
    showHelp();
    return;
  }

  const subcommand = parsed._[0];
  const subArgs = parsed._.slice(1);

  switch (subcommand) {
    case "toggle":
      await toggleTerminal(subArgs, options);
      break;

    case "launch":
      await launchTerminal(subArgs);
      break;

    case "status":
      await statusTerminal(subArgs);
      break;

    case "close":
      await closeTerminal(subArgs, options);
      break;

    case "cleanup":
      await cleanupTerminals(subArgs);
      break;

    default:
      console.error(`${red("✗")} Unknown subcommand: ${subcommand}`);
      console.error(`Run 'i3pm scratchpad --help' for usage information`);
      Deno.exit(1);
  }
}
