/**
 * Sway Client Service
 *
 * Wraps `swaymsg` subprocess calls for interacting with Sway window manager.
 */

import type { StateSnapshot } from "../models/state-snapshot.ts";

/**
 * Sway IPC client for test framework
 */
export class SwayClient {
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
}
