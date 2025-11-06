/**
 * Run-Raise-Hide Application Launching - Feature 051
 *
 * Smart application toggle with intelligent state detection: launch if not running,
 * focus if visible, summon to current workspace, or hide to scratchpad.
 */

import { parseArgs } from "@std/cli/parse-args";
import { createClient } from "../client.ts";
import { bold, cyan, dim, gray, green, red, yellow } from "../ui/ansi.ts";

interface RunCommandOptions {
  verbose?: boolean;
  debug?: boolean;
}

/**
 * Show run command help
 */
function showHelp(): void {
  console.log(`
i3pm run - Smart application launcher with run-raise-hide state machine

USAGE:
  i3pm run <app_name> [OPTIONS]

OPTIONS:
  --summon      Bring window to current workspace (default)
  --hide        Toggle visibility (hide if focused, show if hidden)
  --nohide      Never hide, only raise/focus (idempotent)
  --force       Always launch new instance
  --json        Output result as JSON
  -h, --help    Show this help message

MODES:
  summon (default)  Switch to window's workspace OR bring to current workspace
  hide             Toggle visibility (hide focused window, show hidden window)
  nohide           Focus window without hiding (safe for repeated calls)

EXAMPLES:
  # Toggle Firefox (launch if not running, focus if visible)
  i3pm run firefox

  # Bring window to current workspace
  i3pm run firefox --summon

  # Toggle terminal visibility (hide/show)
  i3pm run alacritty --hide

  # Focus without ever hiding (idempotent)
  i3pm run code --nohide

  # Force new instance (even if already running)
  i3pm run alacritty --force

STATE MACHINE:
  NOT_FOUND                  → Launch new instance
  DIFFERENT_WORKSPACE        → Switch to workspace and focus
  SAME_WORKSPACE_UNFOCUSED   → Focus window
  SAME_WORKSPACE_FOCUSED     → Hide (if --hide mode), else no-op
  SCRATCHPAD                 → Show from scratchpad

NOTES:
  - App names must match i3pm app registry (see: i3pm apps list)
  - Modes are mutually exclusive (only one flag allowed)
  - Force launch bypasses all state detection
`);
  Deno.exit(0);
}

/**
 * Run application with smart state detection
 */
async function runApp(
  args: (string | number)[],
  options: RunCommandOptions,
): Promise<void> {
  const parsed = parseArgs(args.map(String), {
    boolean: ["summon", "hide", "nohide", "force", "json", "help"],
    alias: { h: "help" },
  });

  if (parsed.help) {
    showHelp();
  }

  const appName = parsed._[0] ? String(parsed._[0]) : undefined;

  if (!appName) {
    console.error(`${red("✗")} Error: Missing required argument: app_name`);
    console.error(`\nUsage: i3pm run <app_name> [OPTIONS]`);
    console.error(`Try 'i3pm run --help' for more information`);
    Deno.exit(1);
  }

  // Validate mutually exclusive flags
  const modeFlags = [parsed.summon, parsed.hide, parsed.nohide].filter(Boolean);
  if (modeFlags.length > 1) {
    console.error(
      `${red("✗")} Error: --summon, --hide, and --nohide are mutually exclusive`,
    );
    Deno.exit(1);
  }

  // Determine mode (default: summon)
  let mode = "summon";
  if (parsed.hide) {
    mode = "hide";
  } else if (parsed.nohide) {
    mode = "nohide";
  }

  const forceLaunch = parsed.force || false;

  const client = createClient();

  try {
    const result = await client.request("app.run", {
      app_name: appName,
      mode: mode,
      force_launch: forceLaunch,
    });

    if (parsed.json) {
      console.log(JSON.stringify(result, null, 2));
    } else {
      // Human-readable output based on action
      const action = result.action;
      const windowId = result.window_id;
      const focused = result.focused;
      const message = result.message;

      switch (action) {
        case "launched":
          console.log(`${green("✓")} Launched ${cyan(appName)}`);
          if (options.verbose) {
            console.log(`  ${dim("Action:")} New instance created`);
          }
          break;

        case "focused":
          console.log(`${green("✓")} Focused ${cyan(appName)}`);
          if (options.verbose && windowId) {
            console.log(`  ${dim("Window ID:")} ${windowId}`);
            console.log(`  ${dim("Action:")} ${message}`);
          }
          break;

        case "moved":
          console.log(`${green("✓")} Summoned ${cyan(appName)} to current workspace`);
          if (options.verbose && windowId) {
            console.log(`  ${dim("Window ID:")} ${windowId}`);
          }
          break;

        case "hidden":
          console.log(`${yellow("●")} Hidden ${cyan(appName)}`);
          if (options.verbose && windowId) {
            console.log(`  ${dim("Window ID:")} ${windowId}`);
            console.log(`  ${dim("Action:")} Moved to scratchpad`);
          }
          break;

        case "shown":
          console.log(`${green("✓")} Shown ${cyan(appName)} from scratchpad`);
          if (options.verbose && windowId) {
            console.log(`  ${dim("Window ID:")} ${windowId}`);
          }
          break;

        case "none":
          if (options.verbose) {
            console.log(`${gray("●")} ${message}`);
          }
          break;

        default:
          console.log(`${gray("●")} ${message}`);
      }
    }
  } catch (error) {
    if (parsed.json) {
      console.error(JSON.stringify({ error: String(error) }, null, 2));
    } else {
      // Enhanced error messages
      const errorMsg = error.message || String(error);

      if (errorMsg.includes("not found") || errorMsg.includes("NOT_FOUND")) {
        console.error(`${red("✗")} Application '${appName}' not found in registry`);
        console.error(`\nTry: ${dim("i3pm apps list")} to see available apps`);
      } else if (
        errorMsg.includes("daemon") || errorMsg.includes("connection")
      ) {
        console.error(`${red("✗")} Could not connect to i3pm daemon`);
        console.error(`\nCheck status: ${dim("systemctl --user status i3-project-event-listener")}`);
      } else if (errorMsg.includes("timeout")) {
        console.error(`${red("✗")} Launch timeout for '${appName}'`);
        console.error(`\nThe application may be slow to start or failed to launch`);
      } else {
        console.error(`${red("✗")} Error running ${appName}: ${errorMsg}`);
      }

      if (options.debug) {
        console.error(`\n${dim("Debug info:")}`);
        console.error(error);
      }
    }
    Deno.exit(1);
  }
}

/**
 * Main command router
 */
export async function runCommand(
  args: (string | number)[],
  options: RunCommandOptions = {},
): Promise<void> {
  const parsed = parseArgs(args.map(String), {
    boolean: ["help"],
    alias: { h: "help" },
  });

  if (parsed.help || args.length === 0) {
    showHelp();
  }

  // Direct invocation: i3pm run <app_name> [flags]
  await runApp(args, options);
}
