/**
 * Scratchpad Terminal Management Commands
 *
 * Handles project-scoped floating terminal lifecycle: toggle, launch, status, close, cleanup.
 */

import { parseArgs } from "@std/cli/parse-args";
import { createClient } from "../client.ts";
import type {
  ScratchpadTerminal,
  ScratchpadStatusResult,
} from "../models.ts";
import { validateResponse } from "../validation.ts";
import { bold, cyan, dim, gray, green, red, yellow } from "../ui/ansi.ts";
import { Spinner } from "@cli-ux";

interface ScratchpadCommandOptions {
  verbose?: boolean;
  debug?: boolean;
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
  - Without project name, operates on currently active project
  - Toggle will launch terminal if it doesn't exist
  - Status shows: PID, window ID, working directory, state, timestamps
`);
  Deno.exit(0);
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
    alias: { h: "help" },
  });

  if (parsed.help) {
    console.log(`
i3pm scratchpad toggle - Toggle terminal visibility

USAGE:
  i3pm scratchpad toggle [project_name] [OPTIONS]

OPTIONS:
  --json        Output result as JSON
  -h, --help    Show this help

EXAMPLES:
  i3pm scratchpad toggle              # Toggle current project
  i3pm scratchpad toggle nixos        # Toggle nixos project
`);
    Deno.exit(0);
  }

  const projectName = parsed._[0] ? String(parsed._[0]) : undefined;

  const client = createClient();

  try {
    const result = await client.request("scratchpad.toggle", {
      project_name: projectName,
    });

    if (parsed.json) {
      console.log(JSON.stringify(result, null, 2));
    } else {
      const project = result.project_name || "current";
      const action = result.action;
      const state = result.state;

      if (action === "launched") {
        console.log(
          `${green("✓")} Launched scratchpad terminal for ${cyan(project)}`,
        );
        console.log(
          `  ${dim("PID:")} ${result.terminal.pid} ${
            dim("| Window ID:")
          } ${result.terminal.window_id}`,
        );
        console.log(`  ${dim("Working dir:")} ${result.terminal.working_dir}`);
      } else if (action === "shown") {
        console.log(`${green("✓")} Shown scratchpad terminal for ${cyan(project)}`);
      } else if (action === "hidden") {
        console.log(`${yellow("●")} Hidden scratchpad terminal for ${cyan(project)}`);
      }

      if (options.verbose && result.terminal) {
        console.log(`  ${dim("Mark:")} ${result.terminal.mark}`);
        console.log(`  ${dim("Created:")} ${new Date(result.terminal.created_at * 1000).toISOString()}`);
        if (result.terminal.last_shown_at) {
          console.log(
            `  ${dim("Last shown:")} ${
              new Date(result.terminal.last_shown_at * 1000).toISOString()
            }`,
          );
        }
      }
    }
  } catch (error) {
    if (parsed.json) {
      console.error(JSON.stringify({ error: String(error) }, null, 2));
    } else {
      console.error(`${red("✗")} Error toggling terminal: ${error.message}`);
    }
    Deno.exit(1);
  }
}

/**
 * Launch scratchpad terminal explicitly
 */
async function launchTerminal(
  args: (string | number)[],
  options: ScratchpadCommandOptions,
): Promise<void> {
  const parsed = parseArgs(args.map(String), {
    boolean: ["json", "help"],
    string: ["dir"],
    alias: { h: "help", d: "dir" },
  });

  if (parsed.help) {
    console.log(`
i3pm scratchpad launch - Launch new scratchpad terminal

USAGE:
  i3pm scratchpad launch [project_name] [OPTIONS]

OPTIONS:
  --dir <path>  Working directory (default: project root)
  --json        Output result as JSON
  -h, --help    Show this help

EXAMPLES:
  i3pm scratchpad launch                    # Launch for current project
  i3pm scratchpad launch nixos              # Launch for nixos project
  i3pm scratchpad launch --dir /tmp/test    # Launch with custom directory
`);
    Deno.exit(0);
  }

  const projectName = parsed._[0] ? String(parsed._[0]) : undefined;
  const workingDir = parsed.dir;

  const client = createClient();

  const spinner = new Spinner();
  if (!parsed.json) {
    spinner.start("Launching scratchpad terminal...");
  }

  try {
    const result = await client.request("scratchpad.launch", {
      project_name: projectName,
      working_dir: workingDir,
    });

    if (!parsed.json) {
      spinner.stop();
    }

    if (parsed.json) {
      console.log(JSON.stringify(result, null, 2));
    } else {
      const project = result.project_name || "current";
      console.log(
        `${green("✓")} Launched scratchpad terminal for ${cyan(project)}`,
      );
      console.log(
        `  ${dim("PID:")} ${result.terminal.pid} ${
          dim("| Window ID:")
        } ${result.terminal.window_id}`,
      );
      console.log(`  ${dim("Working dir:")} ${result.terminal.working_dir}`);
      console.log(`  ${dim("Mark:")} ${result.terminal.mark}`);
    }
  } catch (error) {
    if (!parsed.json) {
      spinner.stop();
    }

    if (parsed.json) {
      console.error(JSON.stringify({ error: String(error) }, null, 2));
    } else {
      console.error(`${red("✗")} Error launching terminal: ${error.message}`);

      // Provide helpful error messages
      if (error.message.includes("already exists")) {
        console.error(
          `  ${dim("Hint:")} Use 'i3pm scratchpad toggle' to show existing terminal`,
        );
      } else if (error.message.includes("does not exist")) {
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
  options: ScratchpadCommandOptions,
): Promise<void> {
  const parsed = parseArgs(args.map(String), {
    boolean: ["json", "help", "all"],
    alias: { h: "help", a: "all" },
  });

  if (parsed.help) {
    console.log(`
i3pm scratchpad status - Get terminal status

USAGE:
  i3pm scratchpad status [project_name] [OPTIONS]

OPTIONS:
  --all         Show all terminals
  --json        Output result as JSON
  -h, --help    Show this help

EXAMPLES:
  i3pm scratchpad status              # Status of current project
  i3pm scratchpad status --all        # Status of all terminals
  i3pm scratchpad status nixos        # Status of specific project
`);
    Deno.exit(0);
  }

  const projectName = parsed._[0] ? String(parsed._[0]) : undefined;

  const client = createClient();

  try {
    const result = await client.request("scratchpad.status", {
      project_name: projectName,
    });

    if (parsed.json) {
      console.log(JSON.stringify(result, null, 2));
    } else {
      if (result.terminals && result.terminals.length > 0) {
        console.log(bold("Scratchpad Terminals:"));
        console.log();

        for (const terminal of result.terminals) {
          const statusIcon = terminal.valid
            ? (terminal.state === "visible" ? green("●") : yellow("○"))
            : red("✗");

          console.log(
            `${statusIcon} ${cyan(terminal.project_name)} ${
              dim(`(${terminal.state})`)
            }`,
          );
          console.log(`  ${dim("PID:")} ${terminal.pid}`);
          console.log(`  ${dim("Window ID:")} ${terminal.window_id}`);
          console.log(`  ${dim("Working dir:")} ${terminal.working_dir}`);
          console.log(`  ${dim("Mark:")} ${terminal.mark}`);
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
          if (!terminal.valid) {
            console.log(`  ${red("⚠ Invalid:")} ${terminal.validation_error}`);
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
    if (parsed.json) {
      console.error(JSON.stringify({ error: String(error) }, null, 2));
    } else {
      console.error(`${red("✗")} Error getting status: ${error.message}`);
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
    alias: { h: "help", f: "force" },
  });

  if (parsed.help) {
    console.log(`
i3pm scratchpad close - Close scratchpad terminal

USAGE:
  i3pm scratchpad close [project_name] [OPTIONS]

OPTIONS:
  --force       Force close even if invalid
  --json        Output result as JSON
  -h, --help    Show this help

EXAMPLES:
  i3pm scratchpad close              # Close current project terminal
  i3pm scratchpad close nixos        # Close nixos terminal
  i3pm scratchpad close --force      # Force close
`);
    Deno.exit(0);
  }

  const projectName = parsed._[0] ? String(parsed._[0]) : undefined;

  const client = createClient();

  try {
    const result = await client.request("scratchpad.close", {
      project_name: projectName,
    });

    if (parsed.json) {
      console.log(JSON.stringify(result, null, 2));
    } else {
      const project = result.project_name || "current";
      console.log(`${green("✓")} Closed scratchpad terminal for ${cyan(project)}`);
    }
  } catch (error) {
    if (parsed.json) {
      console.error(JSON.stringify({ error: String(error) }, null, 2));
    } else {
      console.error(`${red("✗")} Error closing terminal: ${error.message}`);
    }
    Deno.exit(1);
  }
}

/**
 * Cleanup invalid terminals
 */
async function cleanupTerminals(
  args: (string | number)[],
  options: ScratchpadCommandOptions,
): Promise<void> {
  const parsed = parseArgs(args.map(String), {
    boolean: ["json", "help"],
    alias: { h: "help" },
  });

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

  const spinner = new Spinner();
  if (!parsed.json) {
    spinner.start("Cleaning up invalid terminals...");
  }

  try {
    const result = await client.request("scratchpad.cleanup", {});

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
        if (result.cleaned_projects && result.cleaned_projects.length > 0) {
          console.log(`  ${dim("Projects:")} ${result.cleaned_projects.join(", ")}`);
        }
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
      console.error(`${red("✗")} Error during cleanup: ${error.message}`);
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
  });

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
      await launchTerminal(subArgs, options);
      break;

    case "status":
      await statusTerminal(subArgs, options);
      break;

    case "close":
      await closeTerminal(subArgs, options);
      break;

    case "cleanup":
      await cleanupTerminals(subArgs, options);
      break;

    default:
      console.error(`${red("✗")} Unknown subcommand: ${subcommand}`);
      console.error(`Run 'i3pm scratchpad --help' for usage information`);
      Deno.exit(1);
  }
}
