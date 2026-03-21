/**
 * Apps command - Registry inspection and runtime overlay management.
 */

import { RegistryService } from "../services/registry.ts";
import {
  applyWorkingCopy,
  diffWorkingCopy,
  renderEffectiveRegistry,
  resetWorkingCopy,
  resolveRegistryRuntimePaths,
  validateRegistryRuntime,
} from "../services/app-registry-runtime.ts";

export async function appsCommand(args: string[], flags: Record<string, unknown>): Promise<number> {
  const [subcommand] = args;

  try {
    switch (subcommand || "list") {
      case "list":
        return await listApps(flags);
      case "show":
        return await showApp(args[1], flags);
      case "render-live":
        return await renderLive(flags);
      case "diff":
        return await diffApps(flags);
      case "apply":
        return await applyApps(flags);
      case "reset-working-copy":
        return await resetApps(flags);
      case "validate":
        return await validateApps(flags);
      default:
        printUsage();
        return 1;
    }
  } catch (error) {
    console.error(`Error: ${error instanceof Error ? error.message : String(error)}`);
    return 1;
  }
}

function printUsage(): void {
  console.error("Usage: i3pm apps <list|show|render-live|diff|apply|reset-working-copy|validate>");
  console.error("");
  console.error("Subcommands:");
  console.error("  list                 List effective applications from the runtime registry");
  console.error("  show <name>          Show a specific effective application");
  console.error("  render-live          Merge base + declarative overlay + working copy");
  console.error("  diff                 Show declarative overlay vs working-copy differences");
  console.error("  apply                Persist the working copy back to the declarative overlay");
  console.error("  reset-working-copy   Replace the working copy with the declarative overlay");
  console.error("  validate             Validate the base registry and overlay files");
}

async function listApps(flags: Record<string, unknown>): Promise<number> {
  const registry = RegistryService.getInstance();
  const apps = await registry.list();

  const scope = flags.scope as string | undefined;
  const filtered = scope
    ? apps.filter((app) => app.scope === scope)
    : apps;

  const workspace = flags.workspace as number | undefined;
  const workspaceFiltered = workspace
    ? filtered.filter((app) => app.preferred_workspace === workspace)
    : filtered;

  if (flags.json) {
    console.log(JSON.stringify(workspaceFiltered, null, 2));
    return 0;
  }

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
      multi,
    );
  }

  console.log(`\nTotal: ${workspaceFiltered.length} applications\n`);
  return 0;
}

async function showApp(name: string | undefined, flags: Record<string, unknown>): Promise<number> {
  if (!name) {
    console.error("Error: Missing application name");
    console.error("Usage: i3pm apps show <name>");
    return 1;
  }

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
  if (app.preferred_monitor_role) {
    console.log(`Monitor Role:      ${app.preferred_monitor_role}`);
  }
  console.log(`Workspace:         ${app.preferred_workspace || "dynamic"}`);
  console.log(`Multi-Instance:    ${app.multi_instance ? "yes" : "no"}`);
  console.log(`Fallback:          ${app.fallback_behavior}`);
  console.log(`Terminal:          ${app.terminal ? "yes" : "no"}`);
  console.log(`Icon:              ${app.icon}`);
  if (app.aliases?.length) {
    console.log(`Aliases:           ${app.aliases.join(", ")}`);
  }
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

async function renderLive(flags: Record<string, unknown>): Promise<number> {
  const registry = await renderEffectiveRegistry();
  const paths = resolveRegistryRuntimePaths();

  if (flags.json) {
    console.log(JSON.stringify({
      ok: true,
      effective_path: paths.effectivePath,
      applications: registry.applications.length,
    }, null, 2));
    return 0;
  }

  console.log(`Rendered ${registry.applications.length} applications to ${paths.effectivePath}`);
  return 0;
}

async function diffApps(flags: Record<string, unknown>): Promise<number> {
  const diff = await diffWorkingCopy();
  if (flags.json) {
    console.log(JSON.stringify(diff, null, 2));
    return 0;
  }

  if (!diff.length) {
    console.log("Working copy matches the declarative overlay.");
    return 0;
  }

  console.log("\nWorking Copy Diff:\n");
  for (const entry of diff) {
    console.log(`${entry.name}`);
    console.log(`  declarative: ${JSON.stringify(entry.before)}`);
    console.log(`  working:     ${JSON.stringify(entry.after)}`);
  }
  console.log();
  return 0;
}

async function applyApps(flags: Record<string, unknown>): Promise<number> {
  const result = await applyWorkingCopy();

  if (flags.json) {
    console.log(JSON.stringify({
      ok: true,
      changed_applications: result.changedApplications,
      repo_override_path: result.repoOverridePath,
      working_copy_path: result.workingCopyPath,
      effective_path: result.effectivePath,
    }, null, 2));
    return 0;
  }

  console.log(`Applied ${result.changedApplications.length} override(s) to ${result.repoOverridePath}`);
  console.log(`Effective registry refreshed at ${result.effectivePath}`);
  return 0;
}

async function resetApps(flags: Record<string, unknown>): Promise<number> {
  const workingCopy = await resetWorkingCopy();
  const paths = resolveRegistryRuntimePaths();

  if (flags.json) {
    console.log(JSON.stringify({
      ok: true,
      applications: Object.keys(workingCopy.applications).sort(),
      working_copy_path: paths.workingCopyPath,
      effective_path: paths.effectivePath,
    }, null, 2));
    return 0;
  }

  console.log(`Reset working copy at ${paths.workingCopyPath}`);
  console.log(`Effective registry refreshed at ${paths.effectivePath}`);
  return 0;
}

async function validateApps(flags: Record<string, unknown>): Promise<number> {
  const paths = await validateRegistryRuntime();

  if (flags.json) {
    console.log(JSON.stringify({
      ok: true,
      paths,
    }, null, 2));
    return 0;
  }

  console.log("Registry runtime files are valid:");
  console.log(`  base: ${paths.basePath}`);
  console.log(`  declarative overlay: ${paths.declarativePath}`);
  console.log(`  repo overlay: ${paths.repoOverridePath}`);
  console.log(`  working copy: ${paths.workingCopyPath}`);
  console.log(`  effective: ${paths.effectivePath}`);
  return 0;
}
