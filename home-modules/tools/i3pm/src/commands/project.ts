/**
 * Project command - Manage projects
 * Feature 035: User Story 2 - Project Management Commands
 * Feature 058: Updated to use daemon ProjectService via JSON-RPC
 */

import { DaemonClient } from "../services/daemon-client.ts";

export async function projectCommand(args: string[], flags: Record<string, unknown>): Promise<number> {
  const [subcommand] = args;

  try {
    switch (subcommand) {
      case "create":
        return await createProject(args.slice(1), flags);
      case "list":
        return await listProjects(flags);
      case "show":
        return await showProject(args[1], flags);
      case "current":
        return await currentProject(flags);
      case "update":
        return await updateProject(args.slice(1), flags);
      case "delete":
        return await deleteProject(args[1], flags);
      case "switch":
        return await switchProject(args[1], flags);
      case "clear":
        return await clearProject(flags);
      default:
        console.error("Usage: i3pm project <create|list|show|current|update|delete|switch|clear>");
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
      console.log(`  i3pm project switch ${name}\n`);
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
  // Feature 058: Use daemon ProjectService via JSON-RPC
  const client = new DaemonClient();
  try {
    const activeResult = await client.request<{ name: string | null }>("project_get_active", {});
    const activeName = activeResult.name;

    if (!activeName) {
      if (flags.json) {
        console.log(JSON.stringify({ project_name: null, message: "No active project" }, null, 2));
      } else {
        console.log("No active project. Use 'i3pm project switch <name>' to activate a project.");
      }
      return 0;
    }

    // Get full project details
    const project = await client.request<{
      name: string;
      directory: string;
      display_name: string;
      icon: string;
      created_at: string;
      updated_at: string;
    }>("project_get", { name: activeName });

    if (flags.json) {
      console.log(JSON.stringify(project, null, 2));
      return 0;
    }

    console.log(`\nCurrent Project: ${project.display_name}`);
    console.log(`  Name:       ${project.name}`);
    console.log(`  Directory:  ${project.directory}\n`);

    return 0;
  } finally {
    client.disconnect();
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
    console.error("Usage: i3pm project switch <name>");
    return 1;
  }

  // Feature 058: Use daemon ProjectService via JSON-RPC
  // project_set_active automatically triggers window filtering
  const client = new DaemonClient();
  try {
    const result = await client.request<{
      previous: string | null;
      current: string | null;
      filtering_applied: boolean;
    }>("project_set_active", { name });

    if (flags.json) {
      console.log(JSON.stringify({ status: "success", ...result }, null, 2));
    } else {
      console.log(`\n✓ Switched to project '${name}'`);
      if (result.filtering_applied) {
        console.log(`  Window filtering applied\n`);
      } else {
        console.log();
      }
    }

    return 0;
  } finally {
    client.disconnect();
  }
}

async function clearProject(flags: Record<string, unknown>): Promise<number> {
  // Feature 058: Use daemon ProjectService via JSON-RPC
  // project_set_active with null clears active project and triggers window filtering
  const client = new DaemonClient();
  try {
    const result = await client.request<{
      previous: string | null;
      current: string | null;
      filtering_applied: boolean;
    }>("project_set_active", { name: null });

    if (flags.json) {
      console.log(JSON.stringify({ status: "success", ...result }, null, 2));
    } else {
      console.log("\n✓ Cleared active project (returned to global mode)");
      if (result.filtering_applied) {
        console.log(`  Window filtering applied\n`);
      } else {
        console.log();
      }
    }

    return 0;
  } finally {
    client.disconnect();
  }
}
