/**
 * Project command - Manage projects
 * Feature 035: User Story 2 - Project Management Commands
 * Feature 058: Updated to use daemon ProjectService via JSON-RPC
 * Feature 101: Most commands deprecated in favor of worktree commands
 */

import { parseArgs } from "@std/cli/parse-args";
import { DaemonClient } from "../services/daemon-client.ts";

export async function projectCommand(args: string[], flags: Record<string, unknown>): Promise<number> {
  // Parse command-specific flags
  const parsed = parseArgs(args, {
    boolean: ["json", "verbose", "debug"],
    string: ["directory", "dir", "display-name", "display", "icon"],
    alias: {
      d: "directory",
    },
    "--": true,
  });

  // Merge parsed flags with global flags
  const allFlags = { ...flags, ...parsed };
  const subcommand = String(parsed._[0] || "");

  try {
    switch (subcommand) {
      case "create":
        // Feature 101: Redirect to worktree create
        console.error("Note: 'i3pm project create' is deprecated. Use 'i3pm worktree create <branch>' instead.");
        return 1;
      case "list":
        // Feature 101: Redirect to worktree list
        console.error("Note: 'i3pm project list' is deprecated. Use 'i3pm worktree list' instead.");
        return 1;
      case "show":
        return await showProject(String(parsed._[1] || ""), allFlags);
      case "current":
        return await currentProject(allFlags);
      case "update":
        console.error("Note: 'i3pm project update' is deprecated. Projects are now managed via git worktrees.");
        return 1;
      case "delete":
        // Feature 101: Redirect to worktree remove
        console.error("Note: 'i3pm project delete' is deprecated. Use 'i3pm worktree remove <branch>' instead.");
        return 1;
      case "switch":
        // Feature 101: Redirect to worktree switch
        const name = String(parsed._[1] || "");
        if (!name) {
          console.error("Error: Missing project name");
          console.error("Usage: i3pm worktree switch <account/repo:branch>");
          return 1;
        }
        console.error(`Note: 'i3pm project switch' is deprecated. Use 'i3pm worktree switch ${name}' instead.`);
        // Still execute via daemon for backwards compatibility
        return await switchProject(name, allFlags);
      case "clear":
        return await clearProject(allFlags);
      case "refresh":
        return await refreshProject(String(parsed._[1] || ""), allFlags);
      case "discover":
        return await discoverProjects(parsed._.slice(1).map(String), allFlags);
      default:
        console.error("Usage: i3pm project <switch|clear|current|discover|refresh>");
        console.error("");
        console.error("Note: Most project commands are deprecated. Use 'i3pm worktree' instead:");
        console.error("  i3pm worktree list              List all worktrees");
        console.error("  i3pm worktree switch <name>     Switch to worktree");
        console.error("  i3pm worktree create <branch>   Create new worktree");
        console.error("  i3pm worktree remove <branch>   Remove worktree");
        return 1;
    }
  } catch (error) {
    console.error(`Error: ${error instanceof Error ? error.message : String(error)}`);
    return 1;
  }
}

async function createProject(args: string[], flags: Record<string, unknown>): Promise<number> {
  const name = args[0];
  if (!name) {
    console.error("Error: Missing project name");
    console.error("Usage: i3pm project create <name> --directory <dir> --display-name <name>");
    return 1;
  }

  const directory = flags.directory || flags.dir;
  const displayName = flags["display-name"] || flags.display || name;
  const icon = flags.icon;

  if (!directory) {
    console.error("Error: Missing --directory flag");
    return 1;
  }

  // Feature 058: Use daemon ProjectService via JSON-RPC
  const client = new DaemonClient();
  try {
    const project = await client.request<{
      name: string;
      directory: string;
      display_name: string;
      icon: string;
      created_at: string;
      updated_at: string;
    }>("project_create", {
      name,
      display_name: String(displayName),
      directory: String(directory),
      icon: icon ? String(icon) : "📁",
    });

    if (flags.json) {
      console.log(JSON.stringify(project, null, 2));
    } else {
      console.log(`\n✓ Project '${name}' created successfully`);
      console.log(`  Location: ~/.config/i3/projects/${name}.json\n`);
      console.log(`To switch to this project:`);
      console.log(`  i3pm worktree switch ${name}\n`);
    }

    return 0;
  } finally {
    client.disconnect();
  }
}

async function listProjects(flags: Record<string, unknown>): Promise<number> {
  // Feature 058: Use daemon ProjectService via JSON-RPC
  const client = new DaemonClient();
  try {
    const projectsResult = await client.request<{
      projects: Array<{
        name: string;
        directory: string;
        display_name: string;
        icon: string;
        created_at: string;
        updated_at: string;
      }>;
    }>("project_list", {});

    const activeResult = await client.request<{ name: string | null }>("project_get_active", {});

    const projects = projectsResult.projects;
    const activeName = activeResult.name;

    if (flags.json) {
      console.log(JSON.stringify({ projects, active: { project_name: activeName } }, null, 2));
      return 0;
    }

    console.log("\nProjects:\n");
    console.log("NAME".padEnd(20), "DISPLAY NAME".padEnd(30), "ACTIVE");
    console.log("─".repeat(60));

    for (const project of projects) {
      const isActive = activeName === project.name ? "●" : "";
      console.log(
        project.name.padEnd(20),
        project.display_name.padEnd(30),
        isActive
      );
    }

    console.log(`\nTotal: ${projects.length} projects\n`);
    return 0;
  } finally {
    client.disconnect();
  }
}

async function showProject(name: string | undefined, flags: Record<string, unknown>): Promise<number> {
  // If no name provided, show current project
  if (!name) {
    return await currentProject(flags);
  }

  // Feature 058: Use daemon ProjectService via JSON-RPC
  const client = new DaemonClient();
  try {
    const project = await client.request<{
      name: string;
      directory: string;
      display_name: string;
      icon: string;
      created_at: string;
      updated_at: string;
    }>("project_get", { name });

    const activeResult = await client.request<{ name: string | null }>("project_get_active", {});
    const isActive = activeResult.name === name;

    if (flags.json) {
      console.log(JSON.stringify({ ...project, is_active: isActive }, null, 2));
      return 0;
    }

    console.log(`\nProject: ${project.display_name}`);
    console.log("─".repeat(60));
    console.log(`Name:           ${project.name}`);
    console.log(`Directory:      ${project.directory}`);
    console.log(`Icon:           ${project.icon || "none"}`);
    console.log(`Active:         ${isActive ? "yes" : "no"}`);
    console.log(`Created:        ${project.created_at}`);
    console.log(`Updated:        ${project.updated_at}`);
    console.log();

    return 0;
  } finally {
    client.disconnect();
  }
}

async function currentProject(flags: Record<string, unknown>): Promise<number> {
  // Feature 101: Read from active-worktree.json (single source of truth)
  const homeDir = Deno.env.get("HOME") || "";
  const worktreeFile = `${homeDir}/.config/i3/active-worktree.json`;

  try {
    const content = await Deno.readTextFile(worktreeFile);
    const worktree = JSON.parse(content) as {
      qualified_name: string;
      repo_qualified_name: string;
      branch: string;
      directory: string;
      account: string;
      repo_name: string;
    };

    if (!worktree.qualified_name) {
      if (flags.json) {
        console.log(JSON.stringify({ project_name: null, message: "No active project" }, null, 2));
      } else {
        console.log("No active project. Use 'i3pm worktree switch <name>' to activate a project.");
      }
      return 0;
    }

    if (flags.json) {
      console.log(JSON.stringify({
        name: worktree.qualified_name,
        directory: worktree.directory,
        display_name: worktree.repo_name,
        branch: worktree.branch,
        account: worktree.account,
        repo_name: worktree.repo_name,
      }, null, 2));
      return 0;
    }

    // Extract branch number if present
    const branchMatch = worktree.branch.match(/^(\d+)-/);
    const branchNumber = branchMatch ? branchMatch[1] : null;
    const displayName = branchNumber ? `${branchNumber} - ${worktree.repo_name}` : worktree.repo_name;

    console.log(`\nCurrent Project: ${displayName}`);
    console.log(`  Qualified Name: ${worktree.qualified_name}`);
    console.log(`  Branch:         ${worktree.branch}`);
    console.log(`  Directory:      ${worktree.directory}\n`);

    return 0;
  } catch (error) {
    if (error instanceof Deno.errors.NotFound) {
      if (flags.json) {
        console.log(JSON.stringify({ project_name: null, message: "No active project" }, null, 2));
      } else {
        console.log("No active project. Use 'i3pm worktree switch <name>' to activate a project.");
      }
      return 0;
    }
    throw error;
  }
}

async function updateProject(args: string[], flags: Record<string, unknown>): Promise<number> {
  const name = args[0];
  if (!name) {
    console.error("Error: Missing project name");
    console.error("Usage: i3pm project update <name> [--directory <dir>] [--display-name <name>] [--icon <icon>]");
    return 1;
  }

  const params: Record<string, unknown> = { name };

  if (flags.directory || flags.dir) params.directory = String(flags.directory || flags.dir);
  if (flags["display-name"] || flags.display) params.display_name = String(flags["display-name"] || flags.display);
  if (flags.icon) params.icon = String(flags.icon);

  if (Object.keys(params).length === 1) { // Only 'name' key
    console.error("Error: No updates provided");
    console.error("Specify at least one of: --directory, --display-name, --icon");
    return 1;
  }

  // Feature 058: Use daemon ProjectService via JSON-RPC
  const client = new DaemonClient();
  try {
    const project = await client.request<{
      name: string;
      directory: string;
      display_name: string;
      icon: string;
      created_at: string;
      updated_at: string;
    }>("project_update", params);

    if (flags.json) {
      console.log(JSON.stringify(project, null, 2));
    } else {
      console.log(`\n✓ Project '${name}' updated successfully\n`);
    }

    return 0;
  } finally {
    client.disconnect();
  }
}

async function deleteProject(name: string | undefined, flags: Record<string, unknown>): Promise<number> {
  if (!name) {
    console.error("Error: Missing project name");
    console.error("Usage: i3pm project delete <name>");
    return 1;
  }

  // Confirmation prompt unless --yes flag
  if (!flags.yes && !flags.y) {
    console.log(`Are you sure you want to delete project '${name}'? (y/N)`);
    const buf = new Uint8Array(1024);
    const n = await Deno.stdin.read(buf);
    const response = new TextDecoder().decode(buf.subarray(0, n || 0)).trim().toLowerCase();

    if (response !== "y" && response !== "yes") {
      console.log("Cancelled");
      return 0;
    }
  }

  // Feature 058: Use daemon ProjectService via JSON-RPC
  const client = new DaemonClient();
  try {
    await client.request<{ deleted: boolean; name: string }>("project_delete", { name });

    console.log(`\n✓ Project '${name}' deleted\n`);
    return 0;
  } finally {
    client.disconnect();
  }
}

async function switchProject(name: string | undefined, flags: Record<string, unknown>): Promise<number> {
  if (!name) {
    console.error("Error: Missing project name");
    console.error("Usage: i3pm project switch <qualified_name>");
    console.error("Example: i3pm project switch vpittamp/nixos-config:main");
    return 1;
  }

  // Feature 101: All project switching now goes through worktree.switch
  // This is the single source of truth for switching logic
  const client = new DaemonClient();
  try {
    const result = await client.request<{
      success: boolean;
      qualified_name: string;
      directory: string;
      branch: string;
      previous_project?: string;
      duration_ms?: number;
    }>("worktree.switch", { qualified_name: name });

    if (flags.json) {
      console.log(JSON.stringify({ status: "success", ...result }, null, 2));
    } else {
      console.log(`\n✓ Switched to project '${result.qualified_name}'`);
      console.log(`  Directory: ${result.directory}`);
      if (result.previous_project) {
        console.log(`  Previous: ${result.previous_project}`);
      }
      console.log();
    }

    return 0;
  } finally {
    client.disconnect();
  }
}

async function clearProject(flags: Record<string, unknown>): Promise<number> {
  // Feature 101: All project management now goes through worktree.* IPC methods
  const client = new DaemonClient();
  try {
    const result = await client.request<{
      success: boolean;
      previous_project: string | null;
      duration_ms?: number;
    }>("worktree.clear", {});

    if (flags.json) {
      console.log(JSON.stringify({ status: "success", ...result }, null, 2));
    } else {
      console.log("\n✓ Cleared active project (returned to global mode)");
      if (result.previous_project) {
        console.log(`  Previous: ${result.previous_project}`);
      }
      console.log();
    }

    return 0;
  } finally {
    client.disconnect();
  }
}

/**
 * Feature 098: Refresh git and branch metadata for a project
 */
async function refreshProject(name: string | undefined, flags: Record<string, unknown>): Promise<number> {
  if (!name) {
    console.error("Error: Missing project name");
    console.error("Usage: i3pm project refresh <name>");
    return 1;
  }

  const client = new DaemonClient();
  try {
    const result = await client.request<{
      success: boolean;
      project: {
        name: string;
        git_metadata?: {
          branch: string;
          commit: string;
          is_clean: boolean;
          ahead: number;
          behind: number;
        };
        branch_metadata?: {
          number: string | null;
          type: string | null;
          full_name: string;
        };
      };
      fields_updated: string[];
    }>("project.refresh", { name });

    if (flags.json) {
      console.log(JSON.stringify(result, null, 2));
      return 0;
    }

    console.log(`\n✓ Refreshed project '${name}'`);
    console.log(`  Fields updated: ${result.fields_updated.join(", ")}`);

    if (result.project.git_metadata) {
      const meta = result.project.git_metadata;
      const cleanStatus = meta.is_clean ? "✓ clean" : "* dirty";
      console.log(`  Branch: ${meta.branch} ${cleanStatus}`);
      console.log(`  Commit: ${meta.commit}`);
      if (meta.ahead > 0 || meta.behind > 0) {
        console.log(`  Sync: ↑${meta.ahead} ↓${meta.behind}`);
      }
    }

    if (result.project.branch_metadata) {
      const bm = result.project.branch_metadata;
      console.log(`  Branch Number: ${bm.number || "none"}`);
      console.log(`  Branch Type: ${bm.type || "none"}`);
    }

    console.log();
    return 0;
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    if (message.includes("not found") || message.includes("1001")) {
      console.error(`Error: Project '${name}' not found`);
    } else if (message.includes("-32001") || message.includes("does not exist")) {
      console.error(`Error: Cannot refresh project '${name}': directory does not exist`);
      console.error("\nEither restore the directory or delete the project with:");
      console.error(`  i3pm project delete ${name}`);
    } else {
      console.error(`Error: ${message}`);
    }
    return 1;
  } finally {
    client.disconnect();
  }
}

/**
 * Feature 097: Discover git repositories and create projects
 */
async function discoverProjects(args: string[], flags: Record<string, unknown>): Promise<number> {
  // Parse discover-specific flags
  const parsed = parseArgs(args, {
    string: ["path", "exclude", "max-depth"],
    boolean: ["dry-run", "github"],
    collect: ["path", "exclude"],
    alias: {
      p: "path",
      e: "exclude",
      d: "max-depth",
      n: "dry-run",
      g: "github",
    },
  });

  const client = new DaemonClient();
  try {
    // Build request parameters
    const params: Record<string, unknown> = {};

    // Handle path collection
    if (parsed.path && Array.isArray(parsed.path) && parsed.path.length > 0) {
      params.paths = parsed.path.map((p: string) => {
        if (p.startsWith("~/")) {
          return Deno.env.get("HOME") + p.slice(1);
        }
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
      params.max_depth = parseInt(String(parsed["max-depth"]), 10);
    }

    // Handle dry run
    if (parsed["dry-run"]) {
      params.dry_run = true;
    }

    // Handle GitHub integration
    if (parsed.github) {
      params.include_github = true;
    }

    const result = await client.request<{
      repositories: Array<{
        name: string;
        path: string;
        inferred_icon: string;
        git_metadata?: {
          current_branch: string;
          commit_hash: string;
          is_clean: boolean;
          remote_url?: string;
        };
      }>;
      worktrees: Array<{
        name: string;
        path: string;
        branch: string;
        parent_path: string;
        inferred_icon: string;
      }>;
      created: number;
      updated: number;
      created_projects: string[];
      updated_projects: string[];
      marked_missing: string[];
      skipped: string[];
      errors: Array<{ path: string; message: string }>;
      dry_run: boolean;
      duration_ms: number;
    }>("discover_projects", params);

    if (flags.json) {
      console.log(JSON.stringify(result, null, 2));
      return 0;
    }

    // Human-readable output
    if (result.dry_run) {
      console.log("\n[DRY RUN] No projects were created or modified\n");
    }

    console.log(`\nDiscovery Results:`);
    console.log(`  Found ${result.repositories.length} repositories and ${result.worktrees.length} worktrees`);
    console.log(`  Duration: ${result.duration_ms.toFixed(1)}ms\n`);

    if (result.repositories.length > 0) {
      console.log("Repositories:");
      for (const repo of result.repositories) {
        const meta = repo.git_metadata;
        const branch = meta ? meta.current_branch : "unknown";
        const cleanStatus = meta?.is_clean ? "✓" : "*";
        console.log(`  ${repo.inferred_icon} ${repo.name} (${branch}) ${cleanStatus}`);
      }
      console.log();
    }

    if (result.worktrees.length > 0) {
      console.log("Worktrees:");
      for (const wt of result.worktrees) {
        console.log(`  ${wt.inferred_icon} ${wt.name} (${wt.branch})`);
      }
      console.log();
    }

    if (!result.dry_run) {
      if (result.created > 0) {
        console.log(`✓ Created ${result.created} projects: ${result.created_projects.join(", ")}`);
      }
      if (result.updated > 0) {
        console.log(`✓ Updated ${result.updated} projects: ${result.updated_projects.join(", ")}`);
      }
      if (result.marked_missing.length > 0) {
        console.log(`⚠ Marked ${result.marked_missing.length} projects as missing: ${result.marked_missing.join(", ")}`);
      }
      if (result.created === 0 && result.updated === 0) {
        console.log("No new projects created or updated.");
      }
    }

    if (result.errors.length > 0) {
      console.log(`\n⚠ Encountered ${result.errors.length} errors:`);
      for (const err of result.errors) {
        console.log(`  ${err.path}: ${err.message}`);
      }
    }

    console.log();
    return 0;
  } finally {
    client.disconnect();
  }
}
