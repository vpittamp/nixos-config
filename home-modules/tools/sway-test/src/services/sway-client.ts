/**
 * Sway Client Service
 *
 * Wraps `swaymsg` subprocess calls for interacting with Sway window manager.
 */

import type { StateSnapshot } from "../models/state-snapshot.ts";
import { SyncManager } from "./sync-manager.ts";
import type { SyncResult, SyncStats, SyncConfig } from "../models/sync-marker.ts";

/**
 * Sway IPC client for test framework
 */
export class SwayClient {
  private syncManager: SyncManager;

  constructor(syncConfig?: Partial<SyncConfig>) {
    this.syncManager = new SyncManager(syncConfig);
  }

  /**
   * Get complete window tree state from Sway
   */
  async getTree(): Promise<StateSnapshot> {
    const startTime = performance.now();

    const command = new Deno.Command("swaymsg", {
      args: ["-t", "get_tree"],
      stdout: "piped",
      stderr: "piped",
    });

    const { code, stdout, stderr } = await command.output();

    if (code !== 0) {
      const error = new TextDecoder().decode(stderr);
      throw new Error(`swaymsg failed: ${error}`);
    }

    const output = new TextDecoder().decode(stdout);
    const tree = JSON.parse(output) as StateSnapshot;

    const endTime = performance.now();

    // Add framework metadata
    tree.capturedAt = new Date().toISOString();
    tree.captureLatency = Math.round(endTime - startTime);

    return tree;
  }

  /**
   * Capture current state (alias for getTree for semantic clarity in tests)
   */
  async captureState(): Promise<StateSnapshot> {
    return await this.getTree();
  }

  /**
   * Send IPC command to Sway
   */
  async sendCommand(ipcCommand: string): Promise<{ success: boolean; error?: string }> {
    const command = new Deno.Command("swaymsg", {
      args: [ipcCommand],
      stdout: "piped",
      stderr: "piped",
    });

    const { code, stdout, stderr } = await command.output();

    if (code !== 0) {
      const error = new TextDecoder().decode(stderr);
      return { success: false, error };
    }

    const output = new TextDecoder().decode(stdout);
    const result = JSON.parse(output);

    // swaymsg returns array of command results
    if (Array.isArray(result)) {
      const failures = result.filter((r) => !r.success);
      if (failures.length > 0) {
        return { success: false, error: failures[0].error || "Command failed" };
      }
    }

    return { success: true };
  }

  /**
   * Get Sway version
   */
  async getVersion(): Promise<string> {
    const command = new Deno.Command("swaymsg", {
      args: ["-t", "get_version"],
      stdout: "piped",
      stderr: "piped",
    });

    const { code, stdout } = await command.output();

    if (code !== 0) {
      return "unknown";
    }

    const output = new TextDecoder().decode(stdout);
    const version = JSON.parse(output);

    return version.human_readable || version.version || "unknown";
  }

  /**
   * Check if Sway is running and accessible
   */
  async isAvailable(): Promise<boolean> {
    try {
      await this.getVersion();
      return true;
    } catch {
      return false;
    }
  }

  /**
   * Get current workspaces
   */
  async getWorkspaces(): Promise<unknown[]> {
    const command = new Deno.Command("swaymsg", {
      args: ["-t", "get_workspaces"],
      stdout: "piped",
      stderr: "piped",
    });

    const { code, stdout } = await command.output();

    if (code !== 0) {
      throw new Error("Failed to get workspaces");
    }

    const output = new TextDecoder().decode(stdout);
    return JSON.parse(output);
  }

  /**
   * Get outputs (displays)
   */
  async getOutputs(): Promise<unknown[]> {
    const command = new Deno.Command("swaymsg", {
      args: ["-t", "get_outputs"],
      stdout: "piped",
      stderr: "piped",
    });

    const { code, stdout } = await command.output();

    if (code !== 0) {
      throw new Error("Failed to get outputs");
    }

    const output = new TextDecoder().decode(stdout);
    return JSON.parse(output);
  }

  /**
   * Extract PID from window by searching Sway tree
   *
   * Recursively walks the container tree to find a window matching the criteria
   * and extracts its PID from container.pid field.
   *
   * @param criteria - Window criteria (app_id, class, or title)
   * @returns PID if found, null otherwise
   */
  async extractWindowPid(criteria: {
    app_id?: string;
    class?: string;
    title?: string;
  }): Promise<number | null> {
    const tree = await this.getTree();

    // Recursive tree walker
    const findWindow = (node: any): number | null => {
      // Check if this node is a window (type: "con" with app_id or class)
      if (node.type === "con" && node.pid) {
        // Match criteria
        const matchesAppId = !criteria.app_id || node.app_id === criteria.app_id;
        const matchesClass = !criteria.class ||
                            node.window_properties?.class === criteria.class;
        const matchesTitle = !criteria.title ||
                            (node.name && node.name.includes(criteria.title));

        if (matchesAppId && matchesClass && matchesTitle) {
          return node.pid;
        }
      }

      // Recursively search children
      if (node.nodes && Array.isArray(node.nodes)) {
        for (const child of node.nodes) {
          const pid = findWindow(child);
          if (pid !== null) return pid;
        }
      }

      // Also search floating_nodes
      if (node.floating_nodes && Array.isArray(node.floating_nodes)) {
        for (const child of node.floating_nodes) {
          const pid = findWindow(child);
          if (pid !== null) return pid;
        }
      }

      return null;
    };

    return findWindow(tree);
  }

  /**
   * Find window container by criteria
   *
   * Returns full window container object matching the criteria.
   *
   * @param criteria - Window criteria (app_id, class, or title)
   * @returns Window container if found, null otherwise
   */
  async findWindow(criteria: {
    app_id?: string;
    class?: string;
    title?: string;
  }): Promise<any | null> {
    const tree = await this.getTree();

    // Recursive tree walker
    const findWindowNode = (node: any): any | null => {
      // Check if this node is a window
      if (node.type === "con" && (node.app_id || node.window_properties)) {
        // Match criteria
        const matchesAppId = !criteria.app_id || node.app_id === criteria.app_id;
        const matchesClass = !criteria.class ||
                            node.window_properties?.class === criteria.class;
        const matchesTitle = !criteria.title ||
                            (node.name && node.name.includes(criteria.title));

        if (matchesAppId && matchesClass && matchesTitle) {
          return node;
        }
      }

      // Recursively search children
      if (node.nodes && Array.isArray(node.nodes)) {
        for (const child of node.nodes) {
          const found = findWindowNode(child);
          if (found !== null) return found;
        }
      }

      // Also search floating_nodes
      if (node.floating_nodes && Array.isArray(node.floating_nodes)) {
        for (const child of node.floating_nodes) {
          const found = findWindowNode(child);
          if (found !== null) return found;
        }
      }

      return null;
    };

    return findWindowNode(tree);
  }

  /**
   * Synchronize with Sway IPC state.
   * Guarantees all prior IPC commands have been processed by X11.
   *
   * @param timeout - Optional timeout in milliseconds (default: 5000)
   * @param testId - Optional test ID for marker correlation
   * @returns SyncResult with latency metrics
   * @throws Error if sync times out
   *
   * @example
   * await swayClient.sendCommand("workspace 3");
   * await swayClient.sync(); // Wait for workspace switch to complete
   * const tree = await swayClient.getTree(); // Tree reflects workspace 3
   */
  async sync(timeout?: number, testId?: string): Promise<SyncResult> {
    return await this.syncManager.sync(
      (cmd) => this.sendCommand(cmd),
      timeout,
      testId,
    );
  }

  /**
   * Get tree with automatic sync before capture.
   * Convenience method for common pattern.
   *
   * @returns StateSnapshot with guaranteed fresh state
   *
   * @example
   * const tree = await swayClient.getTreeSynced();
   * // tree reflects latest Sway state (no race condition)
   */
  async getTreeSynced(): Promise<StateSnapshot> {
    const syncResult = await this.sync();
    if (!syncResult.success) {
      throw new Error(`Sync failed: ${syncResult.error}`);
    }
    return await this.getTree();
  }

  /**
   * Send command and sync automatically.
   * Convenience method for common pattern.
   *
   * @param command - Sway IPC command string
   * @returns Result with sync completion
   *
   * @example
   * await swayClient.sendCommandSync("workspace 5");
   * // Workspace switch is complete (X11 processed)
   */
  async sendCommandSync(
    command: string,
  ): Promise<{ success: boolean; error?: string }> {
    const result = await this.sendCommand(command);
    if (!result.success) {
      return result;
    }

    const syncResult = await this.sync();
    if (!syncResult.success) {
      return { success: false, error: syncResult.error };
    }

    return { success: true };
  }

  /**
   * Get current sync statistics.
   * For performance monitoring and diagnostics.
   *
   * @returns SyncStats or null if tracking disabled
   */
  getSyncStats(): SyncStats | null {
    return this.syncManager.getSyncStats();
  }

  /**
   * Reset sync statistics.
   * Useful for per-test benchmarking.
   */
  resetSyncStats(): void {
    this.syncManager.resetSyncStats();
  }
}
