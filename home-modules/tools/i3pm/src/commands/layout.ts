/**
 * Layout command - Save and restore window layouts
 * Feature 058: Python Backend Consolidation - User Story 2
 *
 * Uses daemon for all layout operations (capture, restore, list, delete).
 */

import { DaemonClient } from "../services/daemon-client.ts";

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
        return await listLayouts(args.slice(1), flags);
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
    console.error("Usage: i3pm layout save <project> [layout-name]");
    return 1;
  }

  const daemon = new DaemonClient();

  try {
    await daemon.connect();

    console.log(`\nCapturing layout for project '${projectName}'...\n`);

    // Call daemon to save layout
    const result = await daemon.request("layout.save", {
      project: projectName,
      name: layoutName,
    }) as {
      success: boolean;
      layout_path: string;
      workspace_count: number;
      window_count: number;
      focused_workspace: number;
    };

    if (flags.json) {
      console.log(JSON.stringify(result, null, 2));
    } else {
      console.log(`\n✓ Layout '${layoutName || "default"}' saved successfully`);
      console.log(`  Windows captured: ${result.window_count}`);
      console.log(`  Workspaces: ${result.workspace_count}`);
      console.log(`  Focused workspace: ${result.focused_workspace}`);
      console.log(`  Location: ${result.layout_path}\n`);
    }

    return 0;
  } catch (error) {
    console.error(`Failed to save layout: ${error instanceof Error ? error.message : String(error)}`);
    return 1;
  } finally {
    daemon.disconnect();
  }
}

async function restoreLayout(args: string[], flags: Record<string, unknown>): Promise<number> {
  const projectName = args[0];
  const layoutName = args[1] as string | undefined;

  if (!projectName) {
    console.error("Error: Missing project name");
    console.error("Usage: i3pm layout restore <project> [layout-name]");
    return 1;
  }

  const daemon = new DaemonClient();

  try {
    await daemon.connect();

    console.log(`\nRestoring layout for project '${projectName}'...\n`);

    // Call daemon to restore layout
    const result = await daemon.request("layout.restore", {
      project: projectName,
      name: layoutName,
    }) as {
      success: boolean;
      windows_launched: number;
      windows_matched: number;
      windows_timeout: number;
      windows_failed: number;
      elapsed_seconds: number;
      correlations: Array<{
        restoration_mark: string;
        window_class: string;
        status: string;
        window_id: number;
        correlation_time: number;
      }>;
    };

    if (flags.json) {
      console.log(JSON.stringify(result, null, 2));
    } else {
      console.log(`\n✓ Layout restored successfully`);
      console.log(`  Windows launched: ${result.windows_launched}`);
      console.log(`  Windows matched: ${result.windows_matched}`);

      if (result.windows_timeout > 0) {
        console.log(`  ⚠ Windows timeout: ${result.windows_timeout}`);
      }
      if (result.windows_failed > 0) {
        console.log(`  ✗ Windows failed: ${result.windows_failed}`);
      }

      console.log(`  Elapsed time: ${result.elapsed_seconds.toFixed(1)}s`);
      console.log();
    }

    return 0;
  } catch (error) {
    console.error(`Failed to restore layout: ${error instanceof Error ? error.message : String(error)}`);
    return 1;
  } finally {
    daemon.disconnect();
  }
}

async function deleteLayout(args: string[], flags: Record<string, unknown>): Promise<number> {
  const projectName = args[0];
  const layoutName = args[1];

  if (!projectName || !layoutName) {
    console.error("Error: Missing required arguments");
    console.error("Usage: i3pm layout delete <project> <layout-name>");
    return 1;
  }

  // Confirmation prompt unless --yes flag
  if (!flags.yes && !flags.y) {
    console.log(`Delete layout '${layoutName}' for project '${projectName}'? (y/N)`);
    const buf = new Uint8Array(1024);
    const n = await Deno.stdin.read(buf);
    const response = new TextDecoder().decode(buf.subarray(0, n || 0)).trim().toLowerCase();

    if (response !== "y" && response !== "yes") {
      console.log("Cancelled");
      return 0;
    }
  }

  const daemon = new DaemonClient();

  try {
    await daemon.connect();

    // Call daemon to delete layout
    const result = await daemon.request("layout.delete", {
      project_name: projectName,
      layout_name: layoutName,
    }) as {
      deleted: boolean;
      layout_name: string;
    };

    if (flags.json) {
      console.log(JSON.stringify(result, null, 2));
    } else {
      console.log(`\n✓ Layout '${result.layout_name}' deleted successfully\n`);
    }

    return 0;
  } catch (error) {
    console.error(`Failed to delete layout: ${error instanceof Error ? error.message : String(error)}`);
    return 1;
  } finally {
    daemon.disconnect();
  }
}

async function listLayouts(args: string[], flags: Record<string, unknown>): Promise<number> {
  const projectName = args[0];

  if (!projectName) {
    console.error("Error: Missing project name");
    console.error("Usage: i3pm layout list <project>");
    return 1;
  }

  const daemon = new DaemonClient();

  try {
    await daemon.connect();

    // Call daemon to list layouts
    const result = await daemon.request("layout.list", {
      project_name: projectName,
    }) as {
      project: string;
      layouts: Array<{
        layout_name: string;
        timestamp: string;
        windows_count: number;
        file_path: string;
      }>;
    };

    if (result.layouts.length === 0) {
      console.log(`\nNo layouts saved for project '${projectName}'\n`);
      return 0;
    }

    if (flags.json) {
      console.log(JSON.stringify(result, null, 2));
      return 0;
    }

    console.log(`\nSaved Layouts for project '${result.project}':\n`);
    for (const layout of result.layouts) {
      const date = new Date(layout.timestamp).toLocaleString();
      console.log(`  ${layout.layout_name}`);
      console.log(`    Windows: ${layout.windows_count}`);
      console.log(`    Saved: ${date}`);
      console.log(`    Path: ${layout.file_path}`);
      console.log();
    }
    console.log(`Total: ${result.layouts.length} layout(s)\n`);

    return 0;
  } catch (error) {
    console.error(`Failed to list layouts: ${error instanceof Error ? error.message : String(error)}`);
    return 1;
  } finally {
    daemon.disconnect();
  }
}
