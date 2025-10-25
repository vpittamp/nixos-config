/**
 * Layout command - Save and restore window layouts
 * Feature 035: User Story 4 - Layout Management
 */

import { LayoutEngine } from "../services/layout-engine.ts";
import { ProjectManager } from "../services/project-manager.ts";

export async function layoutCommand(args: string[], flags: Record<string, unknown>): Promise<number> {
  const [subcommand] = args;

  try {
    switch (subcommand) {
      case "save":
        return await saveLayout(args.slice(1), flags);
      case "restore":
        return await restoreLayout(args.slice(1), flags);
      case "delete":
        return await deleteLayout(args.slice(1), flags);
      case "list":
        return await listLayouts(flags);
      default:
        console.error("Usage: i3pm layout <save|restore|delete|list>");
        return 1;
    }
  } catch (error) {
    console.error(`Error: ${error instanceof Error ? error.message : String(error)}`);
    return 1;
  }
}

async function saveLayout(args: string[], flags: Record<string, unknown>): Promise<number> {
  const projectName = args[0];
  const layoutName = args[1] as string | undefined;

  if (!projectName) {
    console.error("Error: Missing project name");
    console.error("Usage: i3pm layout save <project> [layout-name] [--overwrite]");
    return 1;
  }

  // Verify project exists
  const projectManager = new ProjectManager();
  await projectManager.load(projectName); // Just verify it exists

  const engine = new LayoutEngine();
  console.log(`\nCapturing layout for project '${projectName}'...\n`);

  const { layout, warnings } = await engine.capture(projectName, layoutName);

  // Show warnings
  if (warnings.length > 0) {
    console.log("\nWarnings:");
    for (const warning of warnings) {
      console.log(`  ⚠ ${warning}`);
    }
    console.log();
  }

  // Save layout
  const overwrite = flags.overwrite || flags.force;
  await engine.save(layout, Boolean(overwrite));

  // Update project's saved_layout field
  await projectManager.update(projectName, {
    saved_layout: layout.layout_name,
  });

  if (flags.json) {
    console.log(JSON.stringify(layout, null, 2));
  } else {
    console.log(`\n✓ Layout '${layout.layout_name}' saved successfully`);
    console.log(`  Windows: ${layout.windows.length}`);
    console.log(`  Location: ~/.config/i3/layouts/${layout.layout_name}.json\n`);
  }

  return 0;
}

async function restoreLayout(args: string[], flags: Record<string, unknown>): Promise<number> {
  const projectName = args[0];
  const layoutName = args[1] as string | undefined;

  if (!projectName) {
    console.error("Error: Missing project name");
    console.error("Usage: i3pm layout restore <project> [layout-name] [--dry-run]");
    return 1;
  }

  // Load project to get saved layout if no layout name provided
  const projectManager = new ProjectManager();
  const project = await projectManager.load(projectName);

  const finalLayoutName = layoutName || project.saved_layout;
  if (!finalLayoutName) {
    console.error(`Error: No layout specified and project has no saved layout`);
    console.error(`Save a layout first: i3pm layout save ${projectName}`);
    return 1;
  }

  const engine = new LayoutEngine();
  const layout = await engine.load(projectName, finalLayoutName);

  const dryRun = flags["dry-run"] || flags.n;

  console.log(`\nRestoring layout '${finalLayoutName}' for project '${projectName}'...\n`);

  const { launched, positioned, failed } = await engine.restore(layout, Boolean(dryRun));

  if (failed.length > 0) {
    console.log("\nFailed:");
    for (const error of failed) {
      console.log(`  ✗ ${error}`);
    }
  }

  if (!dryRun) {
    console.log(`\n✓ Layout restore initiated`);
    console.log(`  Launched: ${launched}`);
    console.log(`  Positioned: ${positioned}`);
    console.log(`  Failed: ${failed.length}\n`);
  }

  return 0;
}

async function deleteLayout(args: string[], flags: Record<string, unknown>): Promise<number> {
  const projectName = args[0];
  const layoutName = args[1] as string | undefined;

  if (!projectName) {
    console.error("Error: Missing project name");
    console.error("Usage: i3pm layout delete <project> [layout-name]");
    return 1;
  }

  // Confirmation prompt unless --yes flag
  if (!flags.yes && !flags.y) {
    const name = layoutName || projectName;
    console.log(`Delete layout '${name}'? (y/N)`);
    const buf = new Uint8Array(1024);
    const n = await Deno.stdin.read(buf);
    const response = new TextDecoder().decode(buf.subarray(0, n || 0)).trim().toLowerCase();

    if (response !== "y" && response !== "yes") {
      console.log("Cancelled");
      return 0;
    }
  }

  const engine = new LayoutEngine();
  await engine.delete(projectName, layoutName);

  // Clear project's saved_layout if it was the deleted one
  const projectManager = new ProjectManager();
  const project = await projectManager.load(projectName);
  if (project.saved_layout === (layoutName || projectName)) {
    await projectManager.update(projectName, { saved_layout: undefined });
  }

  console.log(`\n✓ Layout deleted\n`);
  return 0;
}

async function listLayouts(flags: Record<string, unknown>): Promise<number> {
  const layoutsDir = `${Deno.env.get("HOME")}/.config/i3/layouts`;

  const layouts: string[] = [];
  try {
    for await (const entry of Deno.readDir(layoutsDir)) {
      if (entry.isFile && entry.name.endsWith(".json")) {
        layouts.push(entry.name.replace(".json", ""));
      }
    }
  } catch (error) {
    if (error instanceof Deno.errors.NotFound) {
      console.log("\nNo layouts saved yet\n");
      return 0;
    }
    throw error;
  }

  if (flags.json) {
    console.log(JSON.stringify(layouts, null, 2));
    return 0;
  }

  console.log("\nSaved Layouts:\n");
  for (const layout of layouts.sort()) {
    console.log(`  ${layout}`);
  }
  console.log(`\nTotal: ${layouts.length} layouts\n`);

  return 0;
}
