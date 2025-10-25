/**
 * Project command - Manage projects
 * Feature 035: User Story 2 - Project Management Commands
 */

import { ProjectManager } from "../services/project-manager.ts";

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

  const manager = new ProjectManager();
  const project = await manager.create({
    name,
    display_name: String(displayName),
    directory: String(directory),
    icon: icon ? String(icon) : undefined,
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
}

async function listProjects(flags: Record<string, unknown>): Promise<number> {
  const manager = new ProjectManager();
  const projects = await manager.list();
  const active = await manager.getActive();

  if (flags.json) {
    console.log(JSON.stringify({ projects, active }, null, 2));
    return 0;
  }

  console.log("\nProjects:\n");
  console.log("NAME".padEnd(20), "DISPLAY NAME".padEnd(30), "ACTIVE");
  console.log("─".repeat(60));

  for (const project of projects) {
    const isActive = active.project_name === project.name ? "●" : "";
    console.log(
      project.name.padEnd(20),
      project.display_name.padEnd(30),
      isActive
    );
  }

  console.log(`\nTotal: ${projects.length} projects\n`);
  return 0;
}

async function showProject(name: string | undefined, flags: Record<string, unknown>): Promise<number> {
  const manager = new ProjectManager();

  // If no name provided, show current project
  if (!name) {
    return await currentProject(flags);
  }

  const project = await manager.load(name);
  const active = await manager.getActive();
  const isActive = active.project_name === name;

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
  console.log(`Saved Layout:   ${project.saved_layout || "none"}`);
  console.log(`Created:        ${project.created_at}`);
  console.log(`Updated:        ${project.updated_at}`);
  console.log();

  return 0;
}

async function currentProject(flags: Record<string, unknown>): Promise<number> {
  const manager = new ProjectManager();
  const project = await manager.getCurrent();

  if (!project) {
    if (flags.json) {
      console.log(JSON.stringify({ project_name: null, message: "No active project" }, null, 2));
    } else {
      console.log("No active project. Use 'i3pm project switch <name>' to activate a project.");
    }
    return 0;
  }

  if (flags.json) {
    console.log(JSON.stringify(project, null, 2));
    return 0;
  }

  console.log(`\nCurrent Project: ${project.display_name}`);
  console.log(`  Name:       ${project.name}`);
  console.log(`  Directory:  ${project.directory}\n`);

  return 0;
}

async function updateProject(args: string[], flags: Record<string, unknown>): Promise<number> {
  const name = args[0];
  if (!name) {
    console.error("Error: Missing project name");
    console.error("Usage: i3pm project update <name> [--directory <dir>] [--display-name <name>] [--icon <icon>]");
    return 1;
  }

  const manager = new ProjectManager();
  const updates: Record<string, unknown> = {};

  if (flags.directory || flags.dir) updates.directory = String(flags.directory || flags.dir);
  if (flags["display-name"] || flags.display) updates.display_name = String(flags["display-name"] || flags.display);
  if (flags.icon) updates.icon = String(flags.icon);

  if (Object.keys(updates).length === 0) {
    console.error("Error: No updates provided");
    console.error("Specify at least one of: --directory, --display-name, --icon");
    return 1;
  }

  const project = await manager.update(name, updates);

  if (flags.json) {
    console.log(JSON.stringify(project, null, 2));
  } else {
    console.log(`\n✓ Project '${name}' updated successfully\n`);
  }

  return 0;
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

  const manager = new ProjectManager();
  await manager.delete(name);

  console.log(`\n✓ Project '${name}' deleted\n`);
  return 0;
}

async function switchProject(name: string | undefined, flags: Record<string, unknown>): Promise<number> {
  if (!name) {
    console.error("Error: Missing project name");
    console.error("Usage: i3pm project switch <name>");
    return 1;
  }

  const manager = new ProjectManager();
  await manager.setActive(name);

  // Notify daemon via i3-msg tick event (daemon will filter windows via /proc reading)
  const tickCmd = new Deno.Command("i3-msg", {
    args: ["-t", "send_tick", `project:switch:${name}`],
    stdout: "null",
    stderr: "null",
  });
  await tickCmd.output();

  if (flags.json) {
    console.log(JSON.stringify({ status: "success", project: name }, null, 2));
  } else {
    console.log(`\n✓ Switched to project '${name}'\n`);
  }

  return 0;
}

async function clearProject(flags: Record<string, unknown>): Promise<number> {
  const manager = new ProjectManager();
  await manager.clearActive();

  // Notify daemon to show all windows
  const tickCmd = new Deno.Command("i3-msg", {
    args: ["-t", "send_tick", "project:clear"],
    stdout: "null",
    stderr: "null",
  });
  await tickCmd.output();

  if (flags.json) {
    console.log(JSON.stringify({ status: "success", project: null }, null, 2));
  } else {
    console.log("\n✓ Cleared active project (returned to global mode)\n");
  }

  return 0;
}
