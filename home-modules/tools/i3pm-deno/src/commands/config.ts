/**
 * Discovery Configuration Commands
 *
 * Feature 097: Git-Based Project Discovery and Management
 * Tasks T063-T067: CLI commands for managing discovery configuration.
 */

import { parseArgs } from "@std/cli/parse-args";
import { DaemonClient } from "../client.ts";
import { z } from "zod";
import { setup } from "@cli-ux";

// Initialize CLI-UX formatter for semantic colors
const { formatter } = setup();

// Validation schemas for discovery config
const DiscoveryConfigSchema = z.object({
  scan_paths: z.array(z.string()),
  exclude_patterns: z.array(z.string()),
  auto_discover_on_startup: z.boolean(),
  max_depth: z.number(),
});

type DiscoveryConfig = z.infer<typeof DiscoveryConfigSchema>;

function showHelp(): void {
  console.log(`
i3pm config - Discovery configuration management

USAGE:
  i3pm config <SUBCOMMAND> [OPTIONS]

SUBCOMMANDS:
  discovery           Show discovery configuration
  discovery show      Show current discovery configuration
  discovery add-path  Add a scan path
  discovery remove-path  Remove a scan path
  discovery set       Set configuration options

OPTIONS:
  -h, --help          Show this help message

DISCOVERY SHOW OPTIONS:
  --json              Output as JSON

DISCOVERY ADD-PATH:
  i3pm config discovery add-path <PATH>

DISCOVERY REMOVE-PATH:
  i3pm config discovery remove-path <PATH>

DISCOVERY SET OPTIONS:
  --auto-discover <true|false>    Enable/disable auto-discovery on daemon startup
  --max-depth <N>                 Set maximum scan depth (1-10)

EXAMPLES:
  i3pm config discovery               Show current config
  i3pm config discovery show          Show current config
  i3pm config discovery add-path ~/work   Add ~/work to scan paths
  i3pm config discovery remove-path ~/old Remove ~/old from scan paths
  i3pm config discovery set --auto-discover true   Enable auto-discovery
  i3pm config discovery set --max-depth 4          Set max scan depth to 4
`);
}

async function showDiscoveryConfig(args: string[]): Promise<void> {
  const parsedArgs = parseArgs(args, {
    boolean: ["json", "help"],
    alias: { h: "help" },
  });

  if (parsedArgs.help) {
    showHelp();
    return;
  }

  const client = new DaemonClient();

  try {
    await client.connect();
    const response = await client.request("get_discovery_config", {});
    const config = DiscoveryConfigSchema.parse(response);

    if (parsedArgs.json) {
      console.log(JSON.stringify(config, null, 2));
    } else {
      console.log(formatter.info("\nDiscovery Configuration\n"));
      console.log(formatter.dim("─".repeat(40)));

      console.log(`\n${formatter.info("Scan Paths:")}`);
      if (config.scan_paths.length === 0) {
        console.log(formatter.dim("  (none configured)"));
      } else {
        for (const path of config.scan_paths) {
          console.log(`  ${formatter.success("●")} ${path}`);
        }
      }

      console.log(`\n${formatter.info("Exclude Patterns:")}`);
      if (config.exclude_patterns.length === 0) {
        console.log(formatter.dim("  (none)"));
      } else {
        for (const pattern of config.exclude_patterns) {
          console.log(`  ${formatter.dim("○")} ${pattern}`);
        }
      }

      console.log(`\n${formatter.info("Settings:")}`);
      console.log(
        `  Auto-discover on startup: ${
          config.auto_discover_on_startup
            ? formatter.success("enabled")
            : formatter.dim("disabled")
        }`
      );
      console.log(`  Max scan depth: ${config.max_depth}`);
      console.log();
    }
  } catch (error) {
    console.error(formatter.error(`Failed to get config: ${error}`));
    Deno.exit(1);
  } finally {
    client.close();
  }
}

async function addScanPath(args: string[]): Promise<void> {
  const parsedArgs = parseArgs(args, {
    boolean: ["help"],
    alias: { h: "help" },
  });

  if (parsedArgs.help || parsedArgs._.length === 0) {
    console.log(`
Add a directory to the discovery scan paths.

USAGE:
  i3pm config discovery add-path <PATH>

ARGUMENTS:
  PATH    Directory path to add (e.g., ~/projects, /opt/repos)

EXAMPLES:
  i3pm config discovery add-path ~/projects
  i3pm config discovery add-path /opt/work
`);
    return;
  }

  const path = String(parsedArgs._[0]);
  const client = new DaemonClient();

  try {
    await client.connect();
    const response = await client.request("update_discovery_config", {
      add_path: path,
    });

    if (response.success) {
      console.log(formatter.success(`Added scan path: ${path}`));
      console.log(
        formatter.dim(
          `Total scan paths: ${response.config.scan_paths.length}`
        )
      );
    } else {
      console.error(formatter.error("Failed to add path"));
      Deno.exit(1);
    }
  } catch (error) {
    console.error(formatter.error(`Failed to add path: ${error}`));
    Deno.exit(1);
  } finally {
    client.close();
  }
}

async function removeScanPath(args: string[]): Promise<void> {
  const parsedArgs = parseArgs(args, {
    boolean: ["help"],
    alias: { h: "help" },
  });

  if (parsedArgs.help || parsedArgs._.length === 0) {
    console.log(`
Remove a directory from the discovery scan paths.

USAGE:
  i3pm config discovery remove-path <PATH>

ARGUMENTS:
  PATH    Directory path to remove (must match exactly)

EXAMPLES:
  i3pm config discovery remove-path ~/projects
`);
    return;
  }

  const path = String(parsedArgs._[0]);
  const client = new DaemonClient();

  try {
    await client.connect();
    const response = await client.request("update_discovery_config", {
      remove_path: path,
    });

    if (response.success) {
      console.log(formatter.success(`Removed scan path: ${path}`));
      console.log(
        formatter.dim(
          `Remaining scan paths: ${response.config.scan_paths.length}`
        )
      );
    } else {
      console.error(formatter.error("Failed to remove path"));
      Deno.exit(1);
    }
  } catch (error) {
    console.error(formatter.error(`Failed to remove path: ${error}`));
    Deno.exit(1);
  } finally {
    client.close();
  }
}

async function setDiscoveryConfig(args: string[]): Promise<void> {
  const parsedArgs = parseArgs(args, {
    string: ["auto-discover", "max-depth"],
    boolean: ["help"],
    alias: { h: "help" },
  });

  if (parsedArgs.help) {
    console.log(`
Set discovery configuration options.

USAGE:
  i3pm config discovery set [OPTIONS]

OPTIONS:
  --auto-discover <true|false>   Enable/disable auto-discovery on daemon startup
  --max-depth <N>                Set maximum scan depth (1-10)

EXAMPLES:
  i3pm config discovery set --auto-discover true
  i3pm config discovery set --max-depth 4
  i3pm config discovery set --auto-discover true --max-depth 5
`);
    return;
  }

  const updates: Record<string, unknown> = {};

  if (parsedArgs["auto-discover"] !== undefined) {
    const value = parsedArgs["auto-discover"].toLowerCase();
    if (value !== "true" && value !== "false") {
      console.error(
        formatter.error("--auto-discover must be 'true' or 'false'")
      );
      Deno.exit(1);
    }
    updates.auto_discover_on_startup = value === "true";
  }

  if (parsedArgs["max-depth"] !== undefined) {
    const depth = parseInt(parsedArgs["max-depth"], 10);
    if (isNaN(depth) || depth < 1 || depth > 10) {
      console.error(
        formatter.error("--max-depth must be a number between 1 and 10")
      );
      Deno.exit(1);
    }
    updates.max_depth = depth;
  }

  if (Object.keys(updates).length === 0) {
    console.error(formatter.error("No options provided. Use --help for usage."));
    Deno.exit(1);
  }

  const client = new DaemonClient();

  try {
    await client.connect();
    const response = await client.request("update_discovery_config", updates);

    if (response.success) {
      console.log(formatter.success("Configuration updated:"));
      for (const [key, value] of Object.entries(updates)) {
        console.log(`  ${key}: ${value}`);
      }
    } else {
      console.error(formatter.error("Failed to update configuration"));
      Deno.exit(1);
    }
  } catch (error) {
    console.error(formatter.error(`Failed to update config: ${error}`));
    Deno.exit(1);
  } finally {
    client.close();
  }
}

async function handleDiscoverySubcommand(args: string[]): Promise<void> {
  const subcommand = args[0];

  switch (subcommand) {
    case "show":
    case undefined:
      await showDiscoveryConfig(args.slice(1));
      break;
    case "add-path":
      await addScanPath(args.slice(1));
      break;
    case "remove-path":
      await removeScanPath(args.slice(1));
      break;
    case "set":
      await setDiscoveryConfig(args.slice(1));
      break;
    default:
      console.error(formatter.error(`Unknown subcommand: ${subcommand}`));
      showHelp();
      Deno.exit(1);
  }
}

export async function configCommand(args: string[]): Promise<void> {
  const parsedArgs = parseArgs(args, {
    boolean: ["help"],
    alias: { h: "help" },
    stopEarly: true,
  });

  if (parsedArgs.help && parsedArgs._.length === 0) {
    showHelp();
    return;
  }

  const subcommand = String(parsedArgs._[0] || "");
  const subArgs = args.slice(args.indexOf(subcommand) + 1);

  switch (subcommand) {
    case "discovery":
      await handleDiscoverySubcommand(subArgs);
      break;
    case "":
      showHelp();
      break;
    default:
      console.error(formatter.error(`Unknown subcommand: ${subcommand}`));
      showHelp();
      Deno.exit(1);
  }
}
