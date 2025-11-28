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
  DiscoverProjectsParams,
  DiscoverProjectsResult,
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

// Feature 097: Import new discover command
import { discoverCommand } from "./project/discover.ts";

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
                    --json         Output as JSON (T071)
                    --hierarchy    Tree view grouped by repo (T070)
  current           Show currently active project
  switch <name>     Switch to a project
  clear             Clear active project (enter global mode)
  create            Create a new project
  show <name>       Show project details
  validate          Validate all project configurations
  delete <name>     Delete a project
  discover          Discover git repositories and create projects (Feature 097)

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
  i3pm project discover                         # Discover repos in configured paths
  i3pm project discover --path ~/projects       # Discover in specific path
  i3pm project discover --dry-run               # Preview without creating projects
  i3pm project discover --github                # Include GitHub repos (requires gh CLI auth)
  i3pm project discover -g --dry-run            # Preview GitHub integration
`);
  Deno.exit(0);
}

/**
 * List all projects
 *
 * Feature 097 T070: --hierarchy flag shows tree format grouped by bare_repo_path
 * Feature 097 T071: --json output includes source_type, parent_project, bare_repo_path
 */
async function listProjects(args: (string | number)[], options: ProjectCommandOptions): Promise<void> {
  const parsed = parseArgs(args.map(String), {
    boolean: ["json", "hierarchy"],
    alias: { t: "hierarchy" },  // -t for tree
  });

  // Feature 097: Read directly from project JSON files for hierarchy support
  const projectsDir = Deno.env.get("HOME") + "/.config/i3/projects";
  const projects: Project[] = [];

  try {
    for await (const entry of Deno.readDir(projectsDir)) {
      if (entry.isFile && entry.name.endsWith(".json")) {
        try {
          const content = await Deno.readTextFile(`${projectsDir}/${entry.name}`);
          const project = JSON.parse(content) as Project;
          projects.push(project);
        } catch {
          // Skip invalid JSON files
        }
      }
    }
  } catch {
    // Directory doesn't exist yet
  }

  if (parsed.json) {
    // Feature 097 T071: JSON output with all fields
    console.log(JSON.stringify(projects, null, 2));
    Deno.exit(0);
  }

  if (projects.length === 0) {
    console.log("No projects configured.");
    console.log("");
    console.log("Create a project with:");
    console.log("  i3pm project create --name myproject --dir /path/to/project");
    console.log("Or discover git repositories:");
    console.log("  i3pm project discover --path ~/projects");
    Deno.exit(0);
  }

  if (parsed.hierarchy) {
    // Feature 097 T070: Tree output format
    await listProjectsHierarchy(projects);
  } else {
    // Default flat list
    console.log(bold("Projects:"));
    console.log("");

    for (const project of projects.sort((a, b) => a.name.localeCompare(b.name))) {
      const sourceType = (project as Record<string, unknown>).source_type as string | undefined;
      const typeLabel = sourceType === "repository" ? cyan("[repo]") :
                       sourceType === "worktree" ? yellow("[wt]") :
                       gray("[std]");
      console.log(
        `  ${project.icon} ${cyan(project.name)} ${typeLabel} ${dim("(" + project.display_name + ")")}`,
      );
      console.log(`    ${gray("Directory:")} ${project.directory}`);
      if (options.verbose) {
        const gitMeta = (project as Record<string, unknown>).git_metadata as { current_branch?: string; commit_hash?: string; is_clean?: boolean } | undefined;
        if (gitMeta?.current_branch) {
          console.log(`    ${gray("Branch:")} ${gitMeta.current_branch} @ ${gitMeta.commit_hash || "unknown"}`);
        }
        console.log(
          `    ${gray("Classes:")} ${project.scoped_classes.join(", ") || dim("none")}`,
        );
      }
      console.log("");
    }

    console.log(`Total: ${projects.length} project${projects.length !== 1 ? "s" : ""}`);
  }
  Deno.exit(0);
}

/**
 * Feature 097 T070: Display projects in tree hierarchy format
 * Groups by bare_repo_path: Repository → Worktrees
 */
async function listProjectsHierarchy(projects: Project[]): Promise<void> {
  // Group projects by type
  const repoMap = new Map<string, { repo: Project; worktrees: Project[] }>();
  const standalones: Project[] = [];
  const orphans: Project[] = [];

  for (const project of projects) {
    const sourceType = (project as Record<string, unknown>).source_type as string | undefined;
    const bareRepoPath = (project as Record<string, unknown>).bare_repo_path as string | undefined;
    const parentProject = (project as Record<string, unknown>).parent_project as string | undefined;

    if (sourceType === "repository" && bareRepoPath) {
      if (!repoMap.has(bareRepoPath)) {
        repoMap.set(bareRepoPath, { repo: project, worktrees: [] });
      } else {
        // Shouldn't happen, but handle gracefully
        const existing = repoMap.get(bareRepoPath)!;
        existing.repo = project;
      }
    } else if (sourceType === "worktree" && bareRepoPath) {
      if (repoMap.has(bareRepoPath)) {
        repoMap.get(bareRepoPath)!.worktrees.push(project);
      } else {
        // Check if parent exists, otherwise orphan
        const parentExists = projects.some(p => p.name === parentProject);
        if (parentExists) {
          // Parent hasn't been processed yet, create placeholder
          repoMap.set(bareRepoPath, { repo: null as unknown as Project, worktrees: [project] });
        } else {
          orphans.push(project);
        }
      }
    } else {
      standalones.push(project);
    }
  }

  // Fill in repos for worktrees added before repo
  for (const project of projects) {
    const sourceType = (project as Record<string, unknown>).source_type as string | undefined;
    const bareRepoPath = (project as Record<string, unknown>).bare_repo_path as string | undefined;
    if (sourceType === "repository" && bareRepoPath && repoMap.has(bareRepoPath)) {
      const entry = repoMap.get(bareRepoPath)!;
      if (!entry.repo) {
        entry.repo = project;
      }
    }
  }

  console.log(bold("Projects (Hierarchy View):"));
  console.log("");

  // Print Repository groups
  const sortedRepos = Array.from(repoMap.values())
    .filter(v => v.repo)
    .sort((a, b) => a.repo.name.localeCompare(b.repo.name));

  for (const { repo, worktrees } of sortedRepos) {
    const gitMeta = (repo as Record<string, unknown>).git_metadata as { current_branch?: string; is_clean?: boolean } | undefined;
    const cleanIndicator = gitMeta?.is_clean === false ? yellow("●") : green("✓");
    console.log(`${repo.icon} ${cyan(repo.name)} ${cleanIndicator} ${dim("(repository)")}`);
    console.log(`  ${gray("└─")} ${repo.directory}`);
    if (gitMeta?.current_branch) {
      console.log(`  ${gray("   branch:")} ${gitMeta.current_branch}`);
    }

    // Print worktrees
    const sortedWorktrees = worktrees.sort((a, b) => a.name.localeCompare(b.name));
    for (let i = 0; i < sortedWorktrees.length; i++) {
      const wt = sortedWorktrees[i];
      const isLast = i === sortedWorktrees.length - 1;
      const wtMeta = (wt as Record<string, unknown>).git_metadata as { current_branch?: string; is_clean?: boolean } | undefined;
      const wtClean = wtMeta?.is_clean === false ? yellow("●") : green("✓");
      const connector = isLast ? "└─" : "├─";
      console.log(`  ${gray(connector)} 🌿 ${cyan(wt.name)} ${wtClean} ${dim("(" + (wtMeta?.current_branch || "unknown") + ")")}`);
    }
    console.log("");
  }

  // Print standalones
  if (standalones.length > 0) {
    console.log(dim("Standalone Projects:"));
    for (const project of standalones.sort((a, b) => a.name.localeCompare(b.name))) {
      console.log(`  ${project.icon} ${cyan(project.name)} ${dim("(standalone)")}`);
    }
    console.log("");
  }

  // Print orphans
  if (orphans.length > 0) {
    console.log(yellow("⚠ Orphaned Worktrees:"));
    for (const project of orphans.sort((a, b) => a.name.localeCompare(b.name))) {
      console.log(`  ${project.icon} ${yellow(project.name)} ${dim("(no parent)")}`);
    }
    console.log("");
  }

  // Summary
  const repoCount = sortedRepos.length;
  const wtCount = sortedRepos.reduce((sum, r) => sum + r.worktrees.length, 0);
  console.log(`Total: ${repoCount} repositories, ${wtCount} worktrees, ${standalones.length} standalone, ${orphans.length} orphaned`);
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
 * Discover git repositories and create projects (Feature 097)
 */
async function discoverProjects(args: string[], options: ProjectCommandOptions): Promise<void> {
  const parsed = parseArgs(args, {
    string: ["path", "exclude", "max-depth"],
    boolean: ["dry-run", "json", "verbose", "github"],
    collect: ["path", "exclude"],
    alias: {
      p: "path",
      e: "exclude",
      d: "max-depth",
      n: "dry-run",
      g: "github",
    },
  });

  const includeGitHub = parsed.github || false;

  const spinner = new Spinner({
    message: parsed["dry-run"]
      ? "Scanning for git repositories (dry run)..."
      : includeGitHub
        ? "Discovering git repositories and GitHub repos..."
        : "Discovering git repositories...",
    showAfter: 0,
  });
  spinner.start();

  const client = createClient();

  try {
    // Build request parameters
    const params: DiscoverProjectsParams = {};

    // Handle path collection
    if (parsed.path && Array.isArray(parsed.path) && parsed.path.length > 0) {
      params.paths = parsed.path.map((p) => {
        // Expand ~ to home directory
        if (p.startsWith("~/")) {
          return Deno.env.get("HOME") + p.slice(1);
        }
        // Convert relative to absolute path
        if (!p.startsWith("/")) {
          return Deno.cwd() + "/" + p;
        }
        return p;
      });
    }

    // Handle exclude patterns
    if (parsed.exclude && Array.isArray(parsed.exclude) && parsed.exclude.length > 0) {
      params.exclude_patterns = parsed.exclude;
    }

    // Handle max depth
    if (parsed["max-depth"]) {
      params.max_depth = parseInt(parsed["max-depth"], 10);
      if (isNaN(params.max_depth) || params.max_depth < 1) {
        spinner.stop();
        console.error("Error: --max-depth must be a positive integer");
        Deno.exit(1);
      }
    }

    // Handle dry run
    if (parsed["dry-run"]) {
      params.dry_run = true;
    }

    // T045: Handle GitHub integration
    if (includeGitHub) {
      (params as Record<string, unknown>).include_github = true;
    }

    const result = await client.request<DiscoverProjectsResult>("discover_projects", params);
    spinner.stop();

    if (parsed.json) {
      // JSON output for scripting
      console.log(JSON.stringify(result, null, 2));
      return;
    }

    // Human-readable output
    const totalRepos = result.repositories.length;
    const totalWorktrees = result.worktrees.length;

    if (result.dry_run) {
      console.log(yellow("DRY RUN") + " - No projects were created or modified\n");
    }

    // Summary header
    console.log(bold("Discovery Results:"));
    console.log(`  Found ${cyan(String(totalRepos))} repositories and ${cyan(String(totalWorktrees))} worktrees`);
    console.log(`  Duration: ${dim(result.duration_ms.toFixed(1) + "ms")}`);
    console.log("");

    // Repositories section
    if (totalRepos > 0) {
      console.log(bold("Repositories:"));
      for (const repo of result.repositories) {
        const meta = repo.git_metadata;
        const branch = meta ? meta.current_branch : "unknown";
        const cleanStatus = meta?.is_clean ? green("✓") : yellow("*");
        console.log(`  ${repo.inferred_icon} ${cyan(repo.name)} ${dim("(" + branch + ")")} ${cleanStatus}`);
        if (parsed.verbose) {
          console.log(`    ${gray("Path:")} ${repo.path}`);
          if (meta) {
            console.log(`    ${gray("Commit:")} ${meta.commit_hash}`);
            if (meta.remote_url) {
              console.log(`    ${gray("Remote:")} ${meta.remote_url}`);
            }
          }
        }
      }
      console.log("");
    }

    // Worktrees section
    if (totalWorktrees > 0) {
      console.log(bold("Worktrees:"));
      for (const wt of result.worktrees) {
        console.log(`  ${wt.inferred_icon} ${cyan(wt.name)} ${dim("(" + wt.branch + ")")}`);
        if (parsed.verbose) {
          console.log(`    ${gray("Path:")} ${wt.path}`);
          console.log(`    ${gray("Parent:")} ${wt.parent_path}`);
        }
      }
      console.log("");
    }

    // Created/Updated section (only if not dry run)
    if (!result.dry_run) {
      if (result.created > 0) {
        console.log(green("✓") + ` Created ${result.created} project${result.created !== 1 ? "s" : ""}:`);
        for (const name of result.created_projects) {
          console.log(`    + ${cyan(name)}`);
        }
        console.log("");
      }

      if (result.updated > 0) {
        console.log(green("✓") + ` Updated ${result.updated} project${result.updated !== 1 ? "s" : ""}:`);
        for (const name of result.updated_projects) {
          console.log(`    ~ ${cyan(name)}`);
        }
        console.log("");
      }

      if (result.marked_missing.length > 0) {
        console.log(yellow("⚠") + ` Marked ${result.marked_missing.length} project${result.marked_missing.length !== 1 ? "s" : ""} as missing:`);
        for (const name of result.marked_missing) {
          console.log(`    - ${dim(name)}`);
        }
        console.log("");
      }

      if (result.created === 0 && result.updated === 0) {
        console.log(dim("No new projects created or updated."));
      }
    }

    // Errors section
    if (result.errors.length > 0) {
      console.log(yellow("⚠") + ` Encountered ${result.errors.length} error${result.errors.length !== 1 ? "s" : ""}:`);
      for (const err of result.errors) {
        console.log(`    ${err.path}: ${err.message}`);
      }
      console.log("");
    }

    // Skipped section (only in verbose mode)
    if (parsed.verbose && result.skipped.length > 0) {
      console.log(dim(`Skipped ${result.skipped.length} path${result.skipped.length !== 1 ? "s" : ""} (non-git directories)`));
    }

  } catch (err) {
    spinner.stop();
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
 * Refresh git metadata for a project or all projects.
 *
 * Feature 097 T068: Refresh git status without full re-discovery.
 */
async function refreshGitMetadata(
  args: string[],
  options: ProjectCommandOptions
): Promise<void> {
  const parsed = parseArgs(args, {
    boolean: ["all", "json", "help"],
    alias: { h: "help", a: "all" },
  });

  if (parsed.help) {
    console.log(`
Refresh git metadata for projects.

USAGE:
  i3pm project refresh [PROJECT_NAME] [OPTIONS]

ARGUMENTS:
  PROJECT_NAME    Name of project to refresh (optional, omit for all)

OPTIONS:
  -a, --all       Refresh all local/worktree projects
  --json          Output result as JSON
  -h, --help      Show this help message

EXAMPLES:
  i3pm project refresh nixos        Refresh git status for 'nixos' project
  i3pm project refresh --all        Refresh all local projects
  i3pm project refresh              Refresh all (same as --all)
`);
    return;
  }

  const client = new DaemonClient();

  try {
    await client.connect();

    const projectName = parsed._[0] ? String(parsed._[0]) : undefined;

    const response = await client.request("refresh_git_metadata", {
      project_name: projectName,
    });

    if (parsed.json) {
      console.log(JSON.stringify(response, null, 2));
    } else {
      console.log(`Refreshed git metadata for ${response.refreshed_count} project(s)`);
      console.log(`Duration: ${response.duration_ms.toFixed(1)}ms`);

      if (response.errors.length > 0) {
        console.log(`\nErrors (${response.errors.length}):`);
        for (const error of response.errors) {
          console.log(`  - ${error}`);
        }
      }
    }
  } catch (err) {
    console.error(err instanceof Error ? err.message : String(err));
    Deno.exit(1);
  } finally {
    await client.close();
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

    case "discover":
      // Feature 097: Use new git-centric discover command
      await discoverCommand(args.slice(1).map(String));
      break;

    case "refresh":
      await refreshGitMetadata(args.slice(1).map(String), options);
      break;

    default:
      console.error(`Error: Unknown subcommand '${subcommand}'`);
      console.error("");
      console.error("Run 'i3pm project --help' to see available subcommands");
      Deno.exit(1);
  }
}
