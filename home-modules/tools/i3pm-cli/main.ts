#!/usr/bin/env -S deno run --allow-read --allow-write --allow-env
// Feature 087: Remote Project Environment Support
// i3pm CLI - Command-line interface for remote project management
// Created: 2025-11-22

/**
 * i3pm CLI - Project management commands for i3pm
 *
 * Commands:
 *   project create-remote <name>  Create a new remote project with SSH configuration
 */

import { parseArgs } from "https://deno.land/std@0.208.0/cli/parse_args.ts";
import { createRemote } from "./src/commands/project/create-remote.ts";

async function main(): Promise<number> {
  const args = Deno.args;

  if (args.length === 0 || args[0] === "--help" || args[0] === "-h") {
    printHelp();
    return 0;
  }

  const command = args[0];
  const subcommand = args[1];

  if (command === "project") {
    if (subcommand === "create-remote") {
      return await createRemote(args.slice(2));
    } else {
      console.error(`Unknown project subcommand: ${subcommand}`);
      console.error("Available subcommands: create-remote");
      return 1;
    }
  } else {
    console.error(`Unknown command: ${command}`);
    printHelp();
    return 1;
  }
}

function printHelp(): void {
  console.log(`i3pm CLI - Project management for i3pm

Usage: i3pm <command> [options]

Commands:
  project create-remote <name>    Create a new remote project with SSH configuration
                                   Flags:
                                     --local-dir <path>      Local project directory (required)
                                     --remote-host <host>    SSH hostname or IP (required)
                                     --remote-user <user>    SSH username (required)
                                     --remote-dir <path>     Remote working directory (required, absolute path)
                                     --port <number>         SSH port (default: 22)
                                     --display-name <name>   Display name (default: project name)
                                     --icon <emoji>          Project icon (default: 🌐)

Options:
  -h, --help    Show this help message

Examples:
  # Create a remote project for Hetzner Cloud development
  i3pm project create-remote hetzner-dev \\
    --local-dir ~/projects/hetzner-dev \\
    --remote-host hetzner-sway.tailnet \\
    --remote-user vpittamp \\
    --remote-dir /home/vpittamp/dev/my-app

  # Create a remote project with custom port
  i3pm project create-remote staging \\
    --local-dir ~/projects/staging \\
    --remote-host 192.168.1.100 \\
    --remote-user deploy \\
    --remote-dir /opt/applications/staging \\
    --port 2222
`);
}

// Run main and exit with status code
if (import.meta.main) {
  const exitCode = await main();
  Deno.exit(exitCode);
}
