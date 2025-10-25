/**
 * Application Registry Commands
 *
 * Manages the unified application launcher registry, providing CLI access
 * to list, launch, and inspect applications with project context support.
 *
 * Feature: 034-create-a-feature (Unified Application Launcher)
 */

import { parseArgs } from "@std/cli/parse-args";
import { createClient } from "../client.ts";
import type { Project } from "../models.ts";
import { ProjectSchema, validateResponse } from "../validation.ts";
import { bold, cyan, dim, gray, green, red, yellow } from "../ui/ansi.ts";
import { Table } from "@cliffy/table";

interface AppsCommandOptions {
  verbose?: boolean;
  debug?: boolean;
}

interface ApplicationEntry {
  name: string;
  display_name: string;
  command: string;
  parameters?: string;
  scope?: "scoped" | "global";
  expected_class?: string;
  preferred_workspace?: number;
  icon?: string;
  nix_package?: string;
  multi_instance?: boolean;
  fallback_behavior?: "skip" | "use_home" | "error";
  description?: string;
}

interface ApplicationRegistry {
  version: string;
  applications: ApplicationEntry[];
}

/**
 * Show apps command help
 */
function showHelp(): void {
  console.log(`
i3pm apps - Application registry management

USAGE:
  i3pm apps <SUBCOMMAND> [OPTIONS]

SUBCOMMANDS:
  list              List all registered applications
  launch <name>     Launch an application with project context
  info <name>       Show detailed information about an application
  edit              Open registry file in $EDITOR
  validate          Validate registry file
  add               Add a new application to the registry
  remove <name>     Remove an application from the registry

OPTIONS:
  -h, --help        Show this help message

EXAMPLES:
  i3pm apps list                           List all applications
  i3pm apps list --scope=scoped            List only scoped applications
  i3pm apps list --workspace=1             List applications for workspace 1
  i3pm apps list --json                    Output as JSON
  i3pm apps launch vscode                  Launch VS Code with project context
  i3pm apps launch vscode --dry-run        Preview launch command
  i3pm apps launch vscode --project=nixos  Override project context
  i3pm apps info vscode                    Show VS Code details
  i3pm apps edit                           Edit registry in $EDITOR
  i3pm apps validate                       Check registry for errors
  i3pm apps add                            Add application interactively
  i3pm apps add --non-interactive ...      Add application non-interactively
  i3pm apps remove firefox                 Remove application with confirmation
  i3pm apps remove firefox --force         Remove without confirmation
`);
  Deno.exit(0);
}

/**
 * Load application registry from file
 */
async function loadRegistry(): Promise<ApplicationRegistry> {
  const homeDir = Deno.env.get("HOME");
  if (!homeDir) {
    throw new Error("HOME environment variable not set");
  }

  const registryPath = `${homeDir}/.config/i3/application-registry.json`;

  try {
    const content = await Deno.readTextFile(registryPath);
    return JSON.parse(content);
  } catch (error) {
    if (error instanceof Deno.errors.NotFound) {
      throw new Error(
        `Registry file not found: ${registryPath}\n` +
        `Run 'sudo nixos-rebuild switch' to generate the registry.`
      );
    }
    throw new Error(`Failed to load registry: ${error instanceof Error ? error.message : String(error)}`);
  }
}

/**
 * List applications
 */
async function listApps(args: (string | number)[], options: AppsCommandOptions): Promise<void> {
  const parsed = parseArgs(args.map(String), {
    boolean: ["json"],
    string: ["scope", "workspace"],
  });

  const registry = await loadRegistry();
  let apps = registry.applications;

  // Apply filters
  if (parsed.scope) {
    const scope = parsed.scope as "scoped" | "global";
    apps = apps.filter((app) => app.scope === scope);
  }

  if (parsed.workspace) {
    const workspace = parseInt(parsed.workspace, 10);
    apps = apps.filter((app) => app.preferred_workspace === workspace);
  }

  // Output format
  if (parsed.json) {
    console.log(JSON.stringify(apps, null, 2));
    return;
  }

  // Table format
  console.log(bold(`\nApplication Registry (${apps.length} applications)\n`));

  const table = new Table()
    .header(["Name", "Display Name", "Scope", "Workspace", "Command"])
    .body(
      apps.map((app) => {
        const scopeColor = app.scope === "scoped" ? cyan : gray;
        return [
          yellow(app.name),
          app.display_name,
          scopeColor(app.scope || "global"),
          app.preferred_workspace?.toString() || "-",
          dim(app.command),
        ];
      })
    );

  table.render();
  console.log();
}

/**
 * Get current project from daemon
 */
async function getCurrentProject(options: AppsCommandOptions): Promise<Project | null> {
  const client = createClient();
  try {
    const result = await client.call("get_current_project", {});

    if (result === null) {
      return null;
    }

    const validated = validateResponse(result, ProjectSchema, "get_current_project");
    return validated;
  } catch (error) {
    if (options.verbose) {
      console.error(dim("Warning: Failed to get project context:"), error instanceof Error ? error.message : String(error));
    }
    return null;
  } finally {
    client.close();
  }
}

/**
 * Launch application
 */
async function launchApp(args: (string | number)[], options: AppsCommandOptions): Promise<void> {
  const parsed = parseArgs(args.map(String), {
    boolean: ["dry-run", "help"],
    string: ["project"],
    alias: { n: "dry-run" },
  });

  if (parsed.help || parsed._.length === 0) {
    console.log(`
Usage: i3pm apps launch <name> [OPTIONS]

Launch an application with project context.

OPTIONS:
  --dry-run, -n     Show resolved command without executing
  --project=<name>  Override project context (for testing)
  -h, --help        Show this help message

EXAMPLES:
  i3pm apps launch vscode
  i3pm apps launch vscode --dry-run
  i3pm apps launch vscode --project=nixos
`);
    Deno.exit(0);
  }

  const appName = String(parsed._[0]);
  const registry = await loadRegistry();
  const app = registry.applications.find((a) => a.name === appName);

  if (!app) {
    console.error(red(`Error: Application '${appName}' not found in registry`));
    console.error(dim("\nAvailable applications:"));
    for (const a of registry.applications) {
      console.error(dim(`  - ${a.name}`));
    }
    Deno.exit(1);
  }

  // Get wrapper script path
  const homeDir = Deno.env.get("HOME");
  if (!homeDir) {
    throw new Error("HOME environment variable not set");
  }
  const wrapperScript = `${homeDir}/.local/bin/app-launcher-wrapper.sh`;

  // Check wrapper exists
  try {
    await Deno.stat(wrapperScript);
  } catch {
    console.error(red(`Error: Wrapper script not found: ${wrapperScript}`));
    console.error(dim("Run 'sudo nixos-rebuild switch' to install the wrapper script."));
    Deno.exit(1);
  }

  // Build command
  const cmd = [wrapperScript, appName];

  if (parsed["dry-run"]) {
    // Set DRY_RUN environment variable
    const dryRunCmd = new Deno.Command("bash", {
      args: ["-c", `DRY_RUN=1 ${wrapperScript} ${appName}`],
      stdout: "inherit",
      stderr: "inherit",
    });

    const status = await dryRunCmd.output();
    Deno.exit(status.code);
  } else {
    // Execute wrapper script
    const launchCmd = new Deno.Command(wrapperScript, {
      args: [appName],
      stdout: "inherit",
      stderr: "inherit",
      stdin: "null",
    });

    const status = await launchCmd.output();
    if (status.code !== 0) {
      console.error(red(`\nError: Application launch failed (exit code ${status.code})`));
      Deno.exit(status.code);
    }
  }
}

/**
 * Show application info
 */
async function showInfo(args: (string | number)[], options: AppsCommandOptions): Promise<void> {
  const parsed = parseArgs(args.map(String), {
    boolean: ["resolve", "help"],
  });

  if (parsed.help || parsed._.length === 0) {
    console.log(`
Usage: i3pm apps info <name> [OPTIONS]

Show detailed information about an application.

OPTIONS:
  --resolve         Show resolved command with current project context
  -h, --help        Show this help message

EXAMPLES:
  i3pm apps info vscode
  i3pm apps info vscode --resolve
`);
    Deno.exit(0);
  }

  const appName = String(parsed._[0]);
  const registry = await loadRegistry();
  const app = registry.applications.find((a) => a.name === appName);

  if (!app) {
    console.error(red(`Error: Application '${appName}' not found in registry`));
    Deno.exit(1);
  }

  // Display application details
  console.log(bold(`\nApplication: ${app.display_name}\n`));

  console.log(`${bold("Name:")}           ${yellow(app.name)}`);
  console.log(`${bold("Display Name:")}   ${app.display_name}`);
  console.log(`${bold("Command:")}        ${cyan(app.command)}`);
  console.log(`${bold("Parameters:")}     ${app.parameters || dim("(none)")}`);
  console.log(`${bold("Scope:")}          ${app.scope === "scoped" ? cyan("scoped") : gray("global")}`);
  console.log(`${bold("Workspace:")}      ${app.preferred_workspace || dim("(not set)")}`);
  console.log(`${bold("Icon:")}           ${app.icon || dim("(default)")}`);
  console.log(`${bold("Nix Package:")}    ${app.nix_package || dim("(not specified)")}`);
  console.log(`${bold("Multi-Instance:")} ${app.multi_instance ? green("yes") : dim("no")}`);
  console.log(`${bold("Fallback:")}       ${app.fallback_behavior || "skip"}`);
  console.log(`${bold("Description:")}    ${app.description || dim("(none)")}`);

  if (parsed.resolve) {
    console.log(bold("\nResolved Command:"));

    // Get current project
    let project: Project | null = null;
    try {
      const client = createClient();
      const result = await client.call("get_current_project", {});
      client.close();

      if (result !== null) {
        project = validateResponse(result, ProjectSchema, "get_current_project");
      }
    } catch (error) {
      console.log(dim("  (Could not get project context)"));
    }

    if (project) {
      console.log(`  ${dim("Project:")}     ${project.name} (${project.directory})`);

      // Simulate variable substitution
      let resolvedParams = app.parameters || "";
      resolvedParams = resolvedParams.replace(/\$PROJECT_DIR/g, project.directory);
      resolvedParams = resolvedParams.replace(/\$PROJECT_NAME/g, project.name);
      resolvedParams = resolvedParams.replace(/\$SESSION_NAME/g, project.name);
      resolvedParams = resolvedParams.replace(/\$WORKSPACE/g, String(app.preferred_workspace || ""));
      resolvedParams = resolvedParams.replace(/\$HOME/g, Deno.env.get("HOME") || "");

      console.log(`  ${dim("Resolved:")}    ${app.command} ${resolvedParams}`);
    } else {
      console.log(dim("  (No active project - would use fallback behavior)"));
    }
  }

  console.log();
}

/**
 * Edit registry file
 */
async function editRegistry(args: (string | number)[], options: AppsCommandOptions): Promise<void> {
  const homeDir = Deno.env.get("HOME");
  if (!homeDir) {
    throw new Error("HOME environment variable not set");
  }

  const registryPath = `${homeDir}/.config/i3/application-registry.json`;
  const editor = Deno.env.get("EDITOR") || "vi";

  console.log(dim(`Opening ${registryPath} in ${editor}...`));

  const cmd = new Deno.Command(editor, {
    args: [registryPath],
    stdin: "inherit",
    stdout: "inherit",
    stderr: "inherit",
  });

  const status = await cmd.output();
  Deno.exit(status.code);
}

/**
 * Ensure registry file is writable (copy from Nix store if needed)
 */
async function ensureWritableRegistry(registryPath: string): Promise<void> {
  try {
    // Check if file is a symlink (from Nix store)
    const fileInfo = await Deno.lstat(registryPath);
    if (fileInfo.isSymlink) {
      // Read the symlink content
      const content = await Deno.readTextFile(registryPath);

      // Remove symlink
      await Deno.remove(registryPath);

      // Write as regular file
      await Deno.writeTextFile(registryPath, content);

      console.log(yellow("⚠ Copied registry from Nix store to make it writable"));
      console.log(dim("  Changes will be overwritten on next 'nixos-rebuild'"));
      console.log(dim("  To persist changes, edit: home-modules/desktop/app-registry.nix\n"));
    }
  } catch (error) {
    // File might not exist yet, that's okay
    if (!(error instanceof Deno.errors.NotFound)) {
      throw error;
    }
  }
}

/**
 * Add application to registry
 */
async function addApp(args: (string | number)[], options: AppsCommandOptions): Promise<void> {
  const parsed = parseArgs(args.map(String), {
    boolean: ["help", "non-interactive"],
    string: ["name", "display-name", "command", "parameters", "scope", "workspace", "icon", "nix-package", "description"],
    alias: { h: "help" },
  });

  if (parsed.help) {
    console.log(`
Usage: i3pm apps add [OPTIONS]

Add a new application to the registry.

OPTIONS:
  --non-interactive           Use only CLI flags (no prompts)
  --name=<name>              Application identifier (lowercase, no spaces)
  --display-name=<name>      Human-readable display name
  --command=<cmd>            Command to execute
  --parameters=<params>      Command parameters (supports variables)
  --scope=<scoped|global>    Application scope (default: global)
  --workspace=<1-9>          Preferred workspace number
  --icon=<icon>              Icon name or path
  --nix-package=<pkg>        Nix package name
  --description=<desc>       Application description
  -h, --help                 Show this help message

EXAMPLES:
  i3pm apps add --non-interactive --name=firefox --display-name="Firefox" --command=firefox
  i3pm apps add  # Interactive mode with prompts

NOTE:
  This command modifies the local registry file. Changes will be overwritten on
  the next NixOS rebuild. To persist changes, edit: home-modules/desktop/app-registry.nix
`);
    Deno.exit(0);
  }

  const homeDir = Deno.env.get("HOME");
  if (!homeDir) {
    throw new Error("HOME environment variable not set");
  }

  const registryPath = `${homeDir}/.config/i3/application-registry.json`;

  // Ensure registry is writable
  await ensureWritableRegistry(registryPath);

  const registry = await loadRegistry();

  let newApp: Partial<ApplicationEntry> = {};

  if (parsed["non-interactive"]) {
    // Non-interactive mode: Use CLI flags only
    if (!parsed.name || !parsed["display-name"] || !parsed.command) {
      console.error(red("Error: --name, --display-name, and --command are required in non-interactive mode"));
      Deno.exit(1);
    }

    newApp = {
      name: parsed.name,
      display_name: parsed["display-name"],
      command: parsed.command,
      parameters: parsed.parameters,
      scope: (parsed.scope as "scoped" | "global") || "global",
      preferred_workspace: parsed.workspace ? parseInt(parsed.workspace, 10) : undefined,
      icon: parsed.icon,
      nix_package: parsed["nix-package"],
      description: parsed.description,
    };
  } else {
    // Interactive mode: Prompt for values
    console.log(bold("\nAdd New Application\n"));

    // Prompt helper using Deno's built-in prompt()
    const promptUser = (message: string, defaultValue?: string): string => {
      const defaultText = defaultValue ? dim(` [${defaultValue}]`) : "";
      const input = prompt(`${message}${defaultText}: `);
      return input?.trim() || defaultValue || "";
    };

    const name = promptUser("Application name (identifier)", parsed.name);
    if (!name) {
      console.error(red("Error: Application name is required"));
      Deno.exit(1);
    }

    // Check for duplicate
    if (registry.applications.some((app) => app.name === name)) {
      console.error(red(`Error: Application '${name}' already exists in registry`));
      console.error(dim("Use 'i3pm apps edit' to modify existing applications"));
      Deno.exit(1);
    }

    const displayName = promptUser("Display name", parsed["display-name"] || name);
    const command = promptUser("Command", parsed.command);
    if (!command) {
      console.error(red("Error: Command is required"));
      Deno.exit(1);
    }

    const parameters = promptUser("Parameters (supports $PROJECT_DIR, $SESSION_NAME, etc.)", parsed.parameters);
    const scope = promptUser("Scope (scoped/global)", parsed.scope || "global");
    const workspace = promptUser("Preferred workspace (1-9, leave empty for none)", parsed.workspace);
    const icon = promptUser("Icon name", parsed.icon);
    const nixPackage = promptUser("Nix package name", parsed["nix-package"]);
    const description = promptUser("Description", parsed.description);

    newApp = {
      name,
      display_name: displayName || name,
      command,
      parameters: parameters || undefined,
      scope: (scope === "scoped" ? "scoped" : "global"),
      preferred_workspace: workspace ? parseInt(workspace, 10) : undefined,
      icon: icon || undefined,
      nix_package: nixPackage || undefined,
      description: description || undefined,
    };
  }

  // Validate new application
  if (registry.applications.some((app) => app.name === newApp.name)) {
    console.error(red(`Error: Application '${newApp.name}' already exists in registry`));
    Deno.exit(1);
  }

  if (newApp.preferred_workspace && (newApp.preferred_workspace < 1 || newApp.preferred_workspace > 9)) {
    console.error(red(`Error: Workspace must be between 1 and 9, got ${newApp.preferred_workspace}`));
    Deno.exit(1);
  }

  // Add to registry
  registry.applications.push(newApp as ApplicationEntry);

  // Sort by name
  registry.applications.sort((a, b) => a.name.localeCompare(b.name));

  // Write back to file
  const content = JSON.stringify(registry, null, 2);
  await Deno.writeTextFile(registryPath, content);

  console.log(green(`\n✓ Added application '${newApp.name}' to registry`));
  console.log(dim(`\nRegistry location: ${registryPath}`));
  console.log(dim("Note: Changes only affect manual edits. To update system config, edit home-modules/desktop/app-registry.nix"));
}

/**
 * Remove application from registry
 */
async function removeApp(args: (string | number)[], options: AppsCommandOptions): Promise<void> {
  const parsed = parseArgs(args.map(String), {
    boolean: ["help", "force"],
    alias: { h: "help", f: "force" },
  });

  if (parsed.help || parsed._.length === 0) {
    console.log(`
Usage: i3pm apps remove <name> [OPTIONS]

Remove an application from the registry.

OPTIONS:
  --force, -f    Skip confirmation prompt
  -h, --help     Show this help message

EXAMPLES:
  i3pm apps remove firefox
  i3pm apps remove firefox --force

NOTE:
  This command modifies the local registry file. Changes will be overwritten on
  the next NixOS rebuild. To persist changes, edit: home-modules/desktop/app-registry.nix
`);
    Deno.exit(0);
  }

  const appName = String(parsed._[0]);
  const homeDir = Deno.env.get("HOME");
  if (!homeDir) {
    throw new Error("HOME environment variable not set");
  }

  const registryPath = `${homeDir}/.config/i3/application-registry.json`;

  // Ensure registry is writable
  await ensureWritableRegistry(registryPath);

  const registry = await loadRegistry();

  // Find application
  const appIndex = registry.applications.findIndex((app) => app.name === appName);
  if (appIndex === -1) {
    console.error(red(`Error: Application '${appName}' not found in registry`));
    console.error(dim("\nAvailable applications:"));
    for (const a of registry.applications) {
      console.error(dim(`  - ${a.name}`));
    }
    Deno.exit(1);
  }

  const app = registry.applications[appIndex];

  // Confirmation prompt
  if (!parsed.force) {
    console.log(yellow(`\nAre you sure you want to remove '${app.display_name}' (${app.name})?`));
    console.log(dim(`Command: ${app.command}`));
    const confirm = prompt("Type 'yes' to confirm: ");

    if (confirm?.toLowerCase() !== "yes") {
      console.log(dim("\nCancelled - no changes made"));
      Deno.exit(0);
    }
  }

  // Remove from registry
  registry.applications.splice(appIndex, 1);

  // Write back to file
  const content = JSON.stringify(registry, null, 2);
  await Deno.writeTextFile(registryPath, content);

  console.log(green(`\n✓ Removed application '${appName}' from registry`));
  console.log(dim(`\nRegistry location: ${registryPath}`));
  console.log(dim("Note: Changes only affect manual edits. To update system config, edit home-modules/desktop/app-registry.nix"));
}

/**
 * Validate registry file
 */
async function validateRegistry(args: (string | number)[], options: AppsCommandOptions): Promise<void> {
  console.log(dim("Validating application registry...\n"));

  try {
    const registry = await loadRegistry();

    // Check version
    if (!registry.version) {
      console.error(red("✗ Missing version field"));
      Deno.exit(1);
    }
    console.log(green(`✓ Version: ${registry.version}`));

    // Check applications array
    if (!Array.isArray(registry.applications)) {
      console.error(red("✗ Applications field must be an array"));
      Deno.exit(1);
    }
    console.log(green(`✓ Applications: ${registry.applications.length} entries`));

    // Validate each application
    const errors: string[] = [];
    const names = new Set<string>();

    for (const app of registry.applications) {
      // Check required fields
      if (!app.name) {
        errors.push("Missing 'name' field in application");
      }
      if (!app.display_name) {
        errors.push(`Application '${app.name}': missing 'display_name'`);
      }
      if (!app.command) {
        errors.push(`Application '${app.name}': missing 'command'`);
      }

      // Check for duplicates
      if (names.has(app.name)) {
        errors.push(`Duplicate application name: '${app.name}'`);
      }
      names.add(app.name);

      // Check workspace range
      if (app.preferred_workspace !== undefined) {
        if (app.preferred_workspace < 1 || app.preferred_workspace > 9) {
          errors.push(`Application '${app.name}': workspace must be 1-9, got ${app.preferred_workspace}`);
        }
      }

      // Check scope
      if (app.scope && app.scope !== "scoped" && app.scope !== "global") {
        errors.push(`Application '${app.name}': invalid scope '${app.scope}' (must be 'scoped' or 'global')`);
      }

      // Check fallback_behavior
      if (app.fallback_behavior) {
        const validFallbacks = ["skip", "use_home", "error"];
        if (!validFallbacks.includes(app.fallback_behavior)) {
          errors.push(
            `Application '${app.name}': invalid fallback_behavior '${app.fallback_behavior}' ` +
            `(must be one of: ${validFallbacks.join(", ")})`
          );
        }
      }
    }

    if (errors.length > 0) {
      console.error(red("\n✗ Validation failed:\n"));
      for (const error of errors) {
        console.error(red(`  - ${error}`));
      }
      Deno.exit(1);
    }

    console.log(green("\n✓ Registry validation passed"));
    console.log(dim(`\nRegistry location: ${Deno.env.get("HOME")}/.config/i3/application-registry.json`));
  } catch (error) {
    console.error(red(`✗ Validation failed: ${error instanceof Error ? error.message : String(error)}`));
    Deno.exit(1);
  }
}

/**
 * Apps command router
 */
export async function appsCommand(
  args: (string | number)[],
  options: AppsCommandOptions
): Promise<void> {
  const parsed = parseArgs(args.map(String), {
    boolean: ["help"],
    alias: { h: "help" },
    stopEarly: true,
  });

  if (parsed.help || parsed._.length === 0) {
    showHelp();
  }

  const subcommand = String(parsed._[0]);
  const subcommandArgs = parsed._.slice(1);

  switch (subcommand) {
    case "list":
      await listApps(subcommandArgs, options);
      break;

    case "launch":
      await launchApp(subcommandArgs, options);
      break;

    case "info":
      await showInfo(subcommandArgs, options);
      break;

    case "edit":
      await editRegistry(subcommandArgs, options);
      break;

    case "validate":
      await validateRegistry(subcommandArgs, options);
      break;

    case "add":
      await addApp(subcommandArgs, options);
      break;

    case "remove":
      await removeApp(subcommandArgs, options);
      break;

    default:
      console.error(red(`Error: Unknown subcommand '${subcommand}'`));
      console.error(dim("\nRun 'i3pm apps --help' to see available subcommands"));
      Deno.exit(1);
  }
}
