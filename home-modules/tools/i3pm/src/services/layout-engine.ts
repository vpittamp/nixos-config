/**
 * Layout engine service
 * Feature 035: User Story 4 - Layout capture and restore with instance ID matching
 *
 * Captures window positions and restores them with deterministic window matching
 * using I3PM_APP_ID from /proc environment.
 */

import { Layout, WindowSnapshot } from "../models/layout.ts";
import { RegistryService } from "./registry.ts";
import { DaemonClient } from "./daemon-client.ts";
import * as path from "@std/path";

export class LayoutError extends Error {
  constructor(message: string, public override cause?: Error) {
    super(message);
    this.name = "LayoutError";
  }
}

/**
 * Window data from i3 tree
 */
interface I3Window {
  id: number;
  window: number; // X11 window ID
  window_class?: string;
  name?: string; // title
  rect: {
    x: number;
    y: number;
    width: number;
    height: number;
  };
  floating: string; // "auto_on", "user_on", "auto_off", "user_off"
  focused: boolean;
  workspace?: number;
}

/**
 * Layout engine for capturing and restoring layouts
 */
export class LayoutEngine {
  private layoutsDir: string;

  constructor(configDir?: string) {
    const home = Deno.env.get("HOME") || "/home/user";
    const baseDir = configDir || path.join(home, ".config/i3");
    this.layoutsDir = path.join(baseDir, "layouts");
  }

  /**
   * Ensure layouts directory exists
   */
  private async ensureLayoutsDir(): Promise<void> {
    await Deno.mkdir(this.layoutsDir, { recursive: true });
  }

  /**
   * Get layout file path
   */
  private getLayoutPath(projectName: string, layoutName?: string): string {
    const name = layoutName || projectName;
    return path.join(this.layoutsDir, `${name}.json`);
  }

  /**
   * Get window PID using xprop
   */
  private async getWindowPid(windowId: number): Promise<number | null> {
    try {
      const cmd = new Deno.Command("xprop", {
        args: ["-id", String(windowId), "_NET_WM_PID"],
        stdout: "piped",
        stderr: "piped",
      });

      const { success, stdout, stderr } = await cmd.output();
      if (!success) {
        console.warn(`xprop failed for window ${windowId}:`, new TextDecoder().decode(stderr));
        return null;
      }

      const output = new TextDecoder().decode(stdout).trim();
      // Parse: "_NET_WM_PID(CARDINAL) = 12345"
      const match = output.match(/=\s+(\d+)/);
      if (match) {
        return parseInt(match[1], 10);
      }

      return null;
    } catch (error) {
      console.warn(`Failed to get PID for window ${windowId}:`, error);
      return null;
    }
  }

  /**
   * Read I3PM environment variables from /proc
   */
  private async readProcEnvironment(pid: number): Promise<Record<string, string>> {
    try {
      const envPath = `/proc/${pid}/environ`;
      const data = await Deno.readFile(envPath);

      const env: Record<string, string> = {};
      const pairs = new TextDecoder().decode(data).split("\0");

      for (const pair of pairs) {
        if (pair.includes("=")) {
          const [key, value] = pair.split("=", 2);
          env[key] = value;
        }
      }

      return env;
    } catch (error) {
      // Permission denied or process doesn't exist
      return {};
    }
  }

  /**
   * Get i3 window tree via i3-msg
   */
  private async getWindowTree(): Promise<any> {
    const cmd = new Deno.Command("i3-msg", {
      args: ["-t", "get_tree"],
      stdout: "piped",
    });

    const { success, stdout } = await cmd.output();
    if (!success) {
      throw new LayoutError("Failed to get i3 window tree");
    }

    return JSON.parse(new TextDecoder().decode(stdout));
  }

  /**
   * Extract leaf windows from i3 tree
   */
  private extractWindows(node: any, workspace?: number): I3Window[] {
    const windows: I3Window[] = [];

    if (node.window && node.window > 0) {
      // This is a window leaf
      windows.push({
        id: node.id,
        window: node.window,
        window_class: node.window_properties?.class,
        name: node.name,
        rect: node.rect,
        floating: node.floating,
        focused: node.focused,
        workspace: workspace || node.workspace,
      });
    }

    // Track workspace number as we descend
    const currentWorkspace = node.type === "workspace" ? node.num : workspace;

    // Recursively process children
    if (node.nodes) {
      for (const child of node.nodes) {
        windows.push(...this.extractWindows(child, currentWorkspace));
      }
    }
    if (node.floating_nodes) {
      for (const child of node.floating_nodes) {
        windows.push(...this.extractWindows(child, currentWorkspace));
      }
    }

    return windows;
  }

  /**
   * Capture current window layout for a project
   */
  async capture(
    projectName: string,
    layoutName?: string,
  ): Promise<{ layout: Layout; warnings: string[] }> {
    await this.ensureLayoutsDir();

    const tree = await this.getWindowTree();
    const allWindows = this.extractWindows(tree);
    const registry = RegistryService.getInstance();
    await registry.load();

    const snapshots: WindowSnapshot[] = [];
    const warnings: string[] = [];

    console.log(`Capturing ${allWindows.length} windows...`);

    for (const window of allWindows) {
      // Get PID
      const pid = await this.getWindowPid(window.window);
      if (!pid) {
        warnings.push(`Could not get PID for window ${window.window} (${window.window_class})`);
        continue;
      }

      // Read environment
      const env = await this.readProcEnvironment(pid);
      const appId = env.I3PM_APP_ID;
      const appName = env.I3PM_APP_NAME;

      if (!appId || !appName) {
        // Window has no I3PM environment - skip (likely global app or non-registry app)
        console.log(`Skipping window ${window.window} (${window.window_class}) - no I3PM environment`);
        continue;
      }

      // Verify app exists in registry
      const app = await registry.findByName(appName);
      if (!app) {
        warnings.push(`Application '${appName}' not found in registry (window ${window.window})`);
        continue;
      }

      // Create snapshot
      const snapshot: WindowSnapshot = {
        registry_app_id: appName,
        app_instance_id: appId,
        workspace: window.workspace || 1,
        x: window.rect.x,
        y: window.rect.y,
        width: window.rect.width,
        height: window.rect.height,
        floating: window.floating !== "auto_off" && window.floating !== "user_off",
        focused: window.focused,
        captured_class: window.window_class,
        captured_title: window.name,
        captured_pid: pid,
      };

      snapshots.push(snapshot);
      console.log(`✓ Captured ${appName} (${appId}) on workspace ${snapshot.workspace}`);
    }

    if (snapshots.length === 0) {
      throw new LayoutError("No windows with I3PM environment found to capture");
    }

    // Get i3 version
    const versionCmd = new Deno.Command("i3", {
      args: ["--version"],
      stdout: "piped",
    });
    const versionOutput = await versionCmd.output();
    const versionStr = new TextDecoder().decode(versionOutput.stdout);
    const versionMatch = versionStr.match(/(\d+\.\d+)/);
    const i3Version = versionMatch ? versionMatch[1] : "unknown";

    const layout: Layout = {
      project_name: projectName,
      layout_name: layoutName || projectName,
      windows: snapshots,
      captured_at: new Date().toISOString(),
      i3_version: i3Version,
    };

    return { layout, warnings };
  }

  /**
   * Save layout to disk
   */
  async save(layout: Layout, overwrite: boolean = false): Promise<void> {
    const layoutPath = this.getLayoutPath(layout.project_name, layout.layout_name);

    // Check if exists
    try {
      await Deno.stat(layoutPath);
      if (!overwrite) {
        throw new LayoutError(
          `Layout '${layout.layout_name}' already exists. Use --overwrite to replace it.`,
        );
      }
    } catch (error) {
      if (!(error instanceof Deno.errors.NotFound)) {
        throw error;
      }
    }

    await Deno.writeTextFile(layoutPath, JSON.stringify(layout, null, 2));
  }

  /**
   * Load layout from disk
   */
  async load(projectName: string, layoutName?: string): Promise<Layout> {
    const layoutPath = this.getLayoutPath(projectName, layoutName);

    try {
      const content = await Deno.readTextFile(layoutPath);
      return JSON.parse(content);
    } catch (error) {
      if (error instanceof Deno.errors.NotFound) {
        throw new LayoutError(`Layout '${layoutName || projectName}' not found`);
      }
      throw new LayoutError(
        `Failed to load layout: ${error instanceof Error ? error.message : String(error)}`,
        error instanceof Error ? error : undefined,
      );
    }
  }

  /**
   * Delete layout
   */
  async delete(projectName: string, layoutName?: string): Promise<void> {
    const layoutPath = this.getLayoutPath(projectName, layoutName);

    try {
      await Deno.remove(layoutPath);
    } catch (error) {
      if (error instanceof Deno.errors.NotFound) {
        throw new LayoutError(`Layout '${layoutName || projectName}' not found`);
      }
      throw error;
    }
  }

  /**
   * Restore layout (launch applications and position windows)
   *
   * NOTE: This is a complex operation that requires:
   * 1. Closing existing project windows
   * 2. Launching each application with expected I3PM_APP_ID
   * 3. Waiting for windows to appear
   * 4. Verifying I3PM_APP_ID matches
   * 5. Positioning windows
   *
   * This implementation provides the framework but requires integration with
   * the app-launcher-wrapper.sh to launch with specific APP_ID.
   */
  async restore(
    layout: Layout,
    dryRun: boolean = false,
  ): Promise<{ launched: number; positioned: number; failed: string[] }> {
    const registry = RegistryService.getInstance();
    await registry.load();

    const failed: string[] = [];
    let launched = 0;
    let positioned = 0;

    // Validate all apps exist in registry
    for (const window of layout.windows) {
      const app = await registry.findByName(window.registry_app_id);
      if (!app) {
        failed.push(`Application '${window.registry_app_id}' not found in registry`);
      }
    }

    if (failed.length > 0 && !dryRun) {
      console.warn("\nWarnings:");
      for (const warning of failed) {
        console.warn(`  ⚠ ${warning}`);
      }
      console.warn("\nContinuing with available applications...\n");
    }

    if (dryRun) {
      console.log("\nDry Run - Would restore:");
      for (const window of layout.windows) {
        console.log(`  ${window.registry_app_id} (${window.app_instance_id}) → WS ${window.workspace}`);
      }
      return { launched: 0, positioned: 0, failed };
    }

    // Close existing project windows via daemon
    const client = new DaemonClient();
    await client.connect();
    const closedCount = await client.closeProjectWindows(layout.project_name);
    console.log(`Closed ${closedCount} existing windows`);
    client.disconnect();

    // Launch applications with specific I3PM_APP_ID for deterministic matching
    console.log("\nLaunching applications with layout-specific instance IDs...\n");

    for (const window of layout.windows) {
      const app = await registry.findByName(window.registry_app_id);
      if (!app) {
        failed.push(`Application '${window.registry_app_id}' not found in registry`);
        continue;
      }

      try {
        // Launch via app-launcher with I3PM_APP_ID_OVERRIDE environment variable
        // The wrapper script will use this ID instead of generating a new one
        const launchCmd = new Deno.Command("app-launcher", {
          args: [window.registry_app_id],
          env: {
            ...Deno.env.toObject(),
            I3PM_APP_ID_OVERRIDE: window.app_instance_id,
          },
          stdout: "piped",
          stderr: "piped",
        });

        console.log(`Launching ${window.registry_app_id} with ID ${window.app_instance_id}...`);
        const process = launchCmd.spawn();
        launched++;

        // TODO: Implement window waiting and verification
        // 1. Subscribe to i3 window::new events via daemon
        // 2. Wait for window with matching I3PM_APP_ID (read from /proc)
        // 3. Once matched, position window using i3-msg
        // 4. Timeout after 5 seconds if no match

        // For now, just wait a bit for window to appear
        await new Promise((resolve) => setTimeout(resolve, 500));

        // Position window (simplified - assumes window appeared)
        const moveCmd = new Deno.Command("i3-msg", {
          args: [
            `[class="${window.captured_class}"]`,
            `move to workspace number ${window.workspace},`,
            `resize set ${window.width} px ${window.height} px,`,
            `move position ${window.x} px ${window.y} px`,
          ],
        });

        const moveResult = await moveCmd.output();
        if (moveResult.success) {
          positioned++;
          console.log(`✓ Positioned ${window.registry_app_id} on workspace ${window.workspace}`);
        } else {
          failed.push(`Failed to position ${window.registry_app_id}: ${new TextDecoder().decode(moveResult.stderr)}`);
        }

        // Cleanup process
        await process.status;
      } catch (error) {
        failed.push(`Failed to launch ${window.registry_app_id}: ${error instanceof Error ? error.message : String(error)}`);
      }
    }

    // Focus the window that was focused in the layout
    const focusedWindow = layout.windows.find((w) => w.focused);
    if (focusedWindow) {
      const focusCmd = new Deno.Command("i3-msg", {
        args: [`[class="${focusedWindow.captured_class}"]`, "focus"],
      });
      await focusCmd.output();
    }

    return { launched, positioned, failed };
  }
}
