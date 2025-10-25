/**
 * Apps command - List and query registry applications
 * Feature 035: User Story 2 - App Management Commands
 */

import { RegistryService } from "../services/registry.ts";

export async function appsCommand(args: string[], flags: Record<string, unknown>): Promise<number> {
  const [subcommand] = args;

  if (!subcommand || subcommand === "list") {
    return await listApps(flags);
  } else if (subcommand === "show") {
    const appName = args[1];
    if (!appName) {
      console.error("Error: Missing application name");
      console.error("Usage: i3pm apps show <name>");
      return 1;
    }
    return await showApp(appName, flags);
  } else {
    console.error(`Unknown subcommand: ${subcommand}`);
    console.error("Usage: i3pm apps [list|show <name>]");
    return 1;
  }
}

/**
 * List all applications from registry
 */
async function listApps(flags: Record<string, unknown>): Promise<number> {
  const registry = RegistryService.getInstance();
  const apps = await registry.list();

  // Filter by scope if requested
  const scope = flags.scope as string | undefined;
  const filtered = scope
    ? apps.filter((app) => app.scope === scope)
    : apps;

  // Filter by workspace if requested
  const workspace = flags.workspace as number | undefined;
  const workspaceFiltered = workspace
    ? filtered.filter((app) => app.preferred_workspace === workspace)
    : filtered;

  if (flags.json) {
    console.log(JSON.stringify(workspaceFiltered, null, 2));
    return 0;
  }

  // Print table
  console.log("\nApplications Registry:\n");
  console.log("NAME".padEnd(20), "DISPLAY NAME".padEnd(25), "WS", "SCOPE", "MULTI");
  console.log("─".repeat(80));

  for (const app of workspaceFiltered) {
    const ws = app.preferred_workspace ? app.preferred_workspace.toString() : "-";
    const multi = app.multi_instance ? "✓" : "";
    console.log(
      app.name.padEnd(20),
      app.display_name.padEnd(25),
      ws.padEnd(3),
      app.scope.padEnd(7),
      multi
    );
  }

  console.log(`\nTotal: ${workspaceFiltered.length} applications\n`);
  return 0;
}

/**
 * Show detailed information about a specific application
 */
async function showApp(name: string, flags: Record<string, unknown>): Promise<number> {
  const registry = RegistryService.getInstance();
  const app = await registry.findByName(name);

  if (!app) {
    console.error(`Error: Application '${name}' not found in registry`);
    return 1;
  }

  if (flags.json) {
    console.log(JSON.stringify(app, null, 2));
    return 0;
  }

  // Print formatted details
  console.log(`\nApplication: ${app.display_name}`);
  console.log("─".repeat(60));
  console.log(`Name:              ${app.name}`);
  console.log(`Command:           ${app.command}`);
  console.log(`Parameters:        ${Array.isArray(app.parameters) ? app.parameters.join(" ") : app.parameters}`);
  console.log(`Scope:             ${app.scope}`);
  console.log(`Expected Class:    ${app.expected_class}`);
  if (app.expected_title_contains) {
    console.log(`Title Contains:    ${app.expected_title_contains}`);
  }
  console.log(`Workspace:         ${app.preferred_workspace || "dynamic"}`);
  console.log(`Multi-Instance:    ${app.multi_instance ? "yes" : "no"}`);
  console.log(`Fallback:          ${app.fallback_behavior}`);
  console.log(`Terminal:          ${app.terminal ? "yes" : "no"}`);
  console.log(`Icon:              ${app.icon}`);
  if (app.nix_package) {
    console.log(`Nix Package:       ${app.nix_package}`);
  }
  if (app.description) {
    console.log(`\nDescription:`);
    console.log(`  ${app.description}`);
  }
  console.log();

  return 0;
}
