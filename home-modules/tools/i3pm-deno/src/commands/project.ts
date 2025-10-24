/**
 * Project Management Commands
 *
 * Handles project context switching, listing, creation, and configuration.
 */

import { parseArgs } from "@std/cli/parse-args";
import { createClient } from "../client.ts";
import type {
  ClearProjectResult,
  CreateProjectParams,
  Project,
  SwitchProjectResult,
} from "../models.ts";
import {
  ClearProjectResultSchema,
  ProjectSchema,
  SwitchProjectResultSchema,
  validateResponse,
} from "../validation.ts";
import { bold, cyan, dim, gray, green, yellow } from "../ui/ansi.ts";
import {
  formatDirectoryNotAccessibleError,
  formatDirectoryNotFoundError,
  formatInvalidDirectoryError,
  formatInvalidProjectNameError,
  formatProjectNotFoundError,
} from "../utils/errors.ts";
import { Spinner } from "@cli-ux";

interface ProjectCommandOptions {
  verbose?: boolean;
  debug?: boolean;
}

/**
 * Show project command help
 */
function showHelp(): void {
  console.log(`
i3pm project - Project management commands

USAGE:
  i3pm project <SUBCOMMAND> [OPTIONS]

SUBCOMMANDS:
  list              List all configured projects
  current           Show currently active project
  switch <name>     Switch to a project
  clear             Clear active project (enter global mode)
  create            Create a new project
  show <name>       Show project details
  validate          Validate all project configurations
  delete <name>     Delete a project

OPTIONS:
  -h, --help        Show this help message

EXAMPLES:
  i3pm project list
  i3pm project current
  i3pm project switch nixos
  i3pm project clear
  i3pm project create --name myproject --dir /path/to/project
  i3pm project show nixos
  i3pm project validate
  i3pm project delete oldproject
`);
  Deno.exit(0);
}

/**
 * List all projects
 */
async function listProjects(args: (string | number)[], options: ProjectCommandOptions): Promise<void> {
  const parsed = parseArgs(args.map(String), {
    boolean: ["json"],
  });

  const client = createClient();

  try {
    const projects = await client.request<Project[]>("list_projects");
    const validated = projects.map((p) => validateResponse(ProjectSchema, p));

    if (parsed.json) {
      // JSON output
      console.log(JSON.stringify(validated, null, 2));
      return;
    }

    // Human-readable output
    if (validated.length === 0) {
      console.log("No projects configured.");
      console.log("");
      console.log("Create a project with:");
      console.log("  i3pm project create --name myproject --dir /path/to/project");
      return;
    }

    console.log(bold("Projects:"));
    console.log("");

    for (const project of validated) {
      console.log(
        `  ${project.icon} ${cyan(project.name)} ${dim("(" + project.display_name + ")")}`,
      );
      console.log(`    ${gray("Directory:")} ${project.directory}`);
      console.log(
        `    ${gray("Classes:")} ${project.scoped_classes.join(", ") || dim("none")}`,
      );
      console.log("");
    }

    console.log(`Total: ${validated.length} project${validated.length !== 1 ? "s" : ""}`);
  } catch (err) {
    console.error(err instanceof Error ? err.message : String(err));
    Deno.exit(1);
  } finally {
    await client.close();
    // Force exit to avoid event loop blocking from pending read operations
    // See: https://github.com/denoland/deno/issues/4284
    Deno.exit(0);
  }
}

/**
 * Show current project
 */
async function currentProject(args: (string | number)[], options: ProjectCommandOptions): Promise<void> {
  const parsed = parseArgs(args.map(String), {
    boolean: ["json"],
  });

  const client = createClient();

  try {
    const result = await client.request<{
      name: string | null;
      display_name: string | null;
      icon: string | null;
      directory: string | null;
    }>("get_current_project");

    if (parsed.json) {
      // JSON output for scripting (app launcher wrapper script expects this)
      console.log(JSON.stringify(result, null, 2));
      return;
    }

    if (result.name === null) {
      // Output plain text when piped, colored when interactive
      if (Deno.stdout.isTerminal()) {
        console.log(dim("Global") + " " + gray("(no active project)"));
      } else {
        console.log("");  // Empty string for "no project" when piped
      }
    } else {
      // Output plain text when piped, colored when interactive
      if (Deno.stdout.isTerminal()) {
        console.log(cyan(result.name));
      } else {
        console.log(result.name);  // Plain text for scripting
      }
    }
  } catch (err) {
    console.error(err instanceof Error ? err.message : String(err));
    Deno.exit(1);
  } finally {
    await client.close();
    // Force exit to avoid event loop blocking from pending read operations
    // See: https://github.com/denoland/deno/issues/4284
    Deno.exit(0);
  }
}

/**
 * Switch to a project
 */
async function switchProject(projectName: string, options: ProjectCommandOptions): Promise<void> {
  const spinner = new Spinner({
    message: `Switching to ${projectName}...`,
    showAfter: 0
  });
  spinner.start();

  const client = createClient();

  try {
    const result = await client.request<SwitchProjectResult>("switch_project", {
      project_name: projectName,
    });
    const validated = validateResponse(SwitchProjectResultSchema, result);
    spinner.stop();

    console.log(green("✓") + ` Switched to project: ${cyan(validated.new_project)}`);
    console.log("");
    console.log(`  Hidden: ${validated.windows_hidden} window${validated.windows_hidden !== 1 ? "s" : ""}`);
    console.log(`  Shown: ${validated.windows_shown} window${validated.windows_shown !== 1 ? "s" : ""}`);

    if (validated.previous_project) {
      console.log("");
      console.log(gray(`Previous project: ${validated.previous_project}`));
    }
  } catch (err) {
    spinner.stop();
    const message = err instanceof Error ? err.message : String(err);

    // Check for project not found error
    if (message.includes("not found") || message.includes("does not exist")) {
      console.error(formatProjectNotFoundError(projectName));
    } else {
      console.error(message);
    }

    Deno.exit(1);
  } finally {
    await client.close();
    // Force exit to avoid event loop blocking from pending read operations
    // See: https://github.com/denoland/deno/issues/4284
    Deno.exit(0);
  }
}

/**
 * Clear active project (global mode)
 */
async function clearProject(options: ProjectCommandOptions): Promise<void> {
  const client = createClient();

  try {
    const result = await client.request<ClearProjectResult>("clear_project");
    const validated = validateResponse(ClearProjectResultSchema, result);

    console.log(green("✓") + " Cleared project context " + dim("(global mode)"));
    console.log("");
    console.log(`  Shown: ${validated.windows_shown} window${validated.windows_shown !== 1 ? "s" : ""}`);

    if (validated.previous_project) {
      console.log("");
      console.log(gray(`Previous project: ${validated.previous_project}`));
    }
  } catch (err) {
    console.error(err instanceof Error ? err.message : String(err));
    Deno.exit(1);
  } finally {
    await client.close();
    // Force exit to avoid event loop blocking from pending read operations
    // See: https://github.com/denoland/deno/issues/4284
    Deno.exit(0);
  }
}

/**
 * Create a new project
 */
async function createProject(args: string[], options: ProjectCommandOptions): Promise<void> {
  const parsed = parseArgs(args, {
    string: ["name", "dir", "icon", "display-name"],
    alias: {
      n: "name",
      d: "dir",
      i: "icon",
    },
  });

  // Validate required arguments
  if (!parsed.name || !parsed.dir) {
    console.error("Error: --name and --dir are required");
    console.error("");
    console.error("Usage: i3pm project create --name <name> --dir <directory> [--icon <emoji>] [--display-name <name>]");
    console.error("");
    console.error("Example: i3pm project create --name myproject --dir /home/user/projects/myproject --icon 🚀");
    Deno.exit(1);
  }

  const name = String(parsed.name);
  const directory = String(parsed.dir);
  const icon = parsed.icon ? String(parsed.icon) : "📁";
  const displayName = parsed["display-name"] ? String(parsed["display-name"]) : name;

  // Validate project name format
  if (!/^[a-z0-9-]+$/.test(name)) {
    console.error(formatInvalidProjectNameError(name));
    Deno.exit(1);
  }

  // Validate directory path format
  if (!directory.startsWith("/")) {
    console.error(formatInvalidDirectoryError(directory));
    Deno.exit(1);
  }

  // Check if directory exists (warning only)
  try {
    const stat = await Deno.stat(directory);
    if (!stat.isDirectory) {
      console.warn(yellow("⚠") + " Warning: Path exists but is not a directory");
    }
  } catch (err) {
    if (err instanceof Deno.errors.NotFound) {
      console.warn(yellow("⚠") + " " + formatDirectoryNotFoundError(directory));
    } else if (err instanceof Deno.errors.PermissionDenied) {
      console.warn(yellow("⚠") + " " + formatDirectoryNotAccessibleError(directory));
    }
  }

  const client = createClient();

  try {
    const params: CreateProjectParams = {
      name,
      directory,
      icon,
      display_name: displayName,
    };

    await client.request("create_project", params);

    console.log(green("✓") + ` Created project: ${cyan(name)}`);
    console.log("");
    console.log(`  Display Name: ${displayName}`);
    console.log(`  Icon: ${icon}`);
    console.log(`  Directory: ${directory}`);
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);

    // Check for duplicate project error
    if (message.includes("already exists")) {
      console.error(`Error: Project '${name}' already exists`);
      console.error("");
      console.error("Use a different name or delete the existing project:");
      console.error(`  i3pm project delete ${name}`);
    } else {
      console.error(message);
    }

    Deno.exit(1);
  } finally {
    await client.close();
    // Force exit to avoid event loop blocking from pending read operations
    // See: https://github.com/denoland/deno/issues/4284
    Deno.exit(0);
  }
}

/**
 * Show project details
 */
async function showProject(projectName: string, options: ProjectCommandOptions): Promise<void> {
  const client = createClient();

  try {
    const project = await client.request<Project>("get_project", {
      project_name: projectName,
    });
    const validated = validateResponse(ProjectSchema, project);

    console.log(bold(`Project: ${validated.name}`));
    console.log("");
    console.log(`  Display Name: ${validated.display_name}`);
    console.log(`  Icon: ${validated.icon}`);
    console.log(`  Directory: ${validated.directory}`);
    console.log(`  Scoped Classes: ${validated.scoped_classes.join(", ") || dim("none")}`);
    console.log("");
    console.log(gray(`  Created: ${new Date(validated.created_at * 1000).toLocaleString()}`));
    console.log(gray(`  Last Used: ${new Date(validated.last_used_at * 1000).toLocaleString()}`));
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);

    if (message.includes("not found") || message.includes("does not exist")) {
      console.error(formatProjectNotFoundError(projectName));
    } else {
      console.error(message);
    }

    Deno.exit(1);
  } finally {
    await client.close();
    // Force exit to avoid event loop blocking from pending read operations
    // See: https://github.com/denoland/deno/issues/4284
    Deno.exit(0);
  }
}

/**
 * Validate all projects
 */
async function validateProjects(options: ProjectCommandOptions): Promise<void> {
  const client = createClient();

  try {
    const projects = await client.request<Project[]>("list_projects");

    let errors = 0;
    const issues: string[] = [];

    for (const project of projects) {
      try {
        validateResponse(ProjectSchema, project);

        // Check directory existence
        try {
          const stat = await Deno.stat(project.directory);
          if (!stat.isDirectory) {
            issues.push(`${project.name}: Directory is not a directory: ${project.directory}`);
            errors++;
          }
        } catch (err) {
          if (err instanceof Deno.errors.NotFound) {
            issues.push(`${project.name}: Directory not found: ${project.directory}`);
            errors++;
          } else if (err instanceof Deno.errors.PermissionDenied) {
            issues.push(`${project.name}: Directory not accessible: ${project.directory}`);
            errors++;
          }
        }
      } catch (err) {
        issues.push(`${project.name}: Invalid configuration - ${err instanceof Error ? err.message : String(err)}`);
        errors++;
      }
    }

    if (errors === 0) {
      console.log(green("✓") + ` All projects valid (${projects.length} project${projects.length !== 1 ? "s" : ""} checked)`);
    } else {
      console.log(yellow("⚠") + ` Found ${errors} issue${errors !== 1 ? "s" : ""}:`);
      console.log("");
      for (const issue of issues) {
        console.log(`  - ${issue}`);
      }
      Deno.exit(1);
    }
  } catch (err) {
    console.error(err instanceof Error ? err.message : String(err));
    Deno.exit(1);
  } finally {
    await client.close();
    // Force exit to avoid event loop blocking from pending read operations
    // See: https://github.com/denoland/deno/issues/4284
    Deno.exit(0);
  }
}

/**
 * Delete a project
 */
async function deleteProject(projectName: string, options: ProjectCommandOptions): Promise<void> {
  const client = createClient();

  try {
    await client.request("delete_project", { project_name: projectName });

    console.log(green("✓") + ` Deleted project: ${cyan(projectName)}`);
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);

    if (message.includes("not found") || message.includes("does not exist")) {
      console.error(formatProjectNotFoundError(projectName));
    } else {
      console.error(message);
    }

    Deno.exit(1);
  } finally {
    await client.close();
    // Force exit to avoid event loop blocking from pending read operations
    // See: https://github.com/denoland/deno/issues/4284
    Deno.exit(0);
  }
}

/**
 * Project command router
 */
export async function projectCommand(
  args: (string | number)[],
  options: ProjectCommandOptions,
): Promise<void> {
  const parsed = parseArgs(args.map(String), {
    boolean: ["help", "json"],
    alias: { h: "help" },
    stopEarly: true,
  });

  if (parsed.help) {
    showHelp();
  }

  if (parsed._.length === 0) {
    showHelp();
  }

  const subcommand = String(parsed._[0]);
  const subcommandArgs = args.slice(1);  // Pass all remaining args to preserve flags

  switch (subcommand) {
    case "list":
      await listProjects(subcommandArgs, options);
      break;

    case "current":
      await currentProject(subcommandArgs, options);
      break;

    case "switch":
      if (subcommandArgs.length === 0) {
        console.error("Error: Project name required");
        console.error("");
        console.error("Usage: i3pm project switch <name>");
        Deno.exit(1);
      }
      await switchProject(subcommandArgs[0], options);
      break;

    case "clear":
      await clearProject(options);
      break;

    case "create":
      await createProject(args.slice(1).map(String), options);
      break;

    case "show":
      if (subcommandArgs.length === 0) {
        console.error("Error: Project name required");
        console.error("");
        console.error("Usage: i3pm project show <name>");
        Deno.exit(1);
      }
      await showProject(subcommandArgs[0], options);
      break;

    case "validate":
      await validateProjects(options);
      break;

    case "delete":
      if (subcommandArgs.length === 0) {
        console.error("Error: Project name required");
        console.error("");
        console.error("Usage: i3pm project delete <name>");
        Deno.exit(1);
      }
      await deleteProject(subcommandArgs[0], options);
      break;

    default:
      console.error(`Error: Unknown subcommand '${subcommand}'`);
      console.error("");
      console.error("Run 'i3pm project --help' to see available subcommands");
      Deno.exit(1);
  }
}
