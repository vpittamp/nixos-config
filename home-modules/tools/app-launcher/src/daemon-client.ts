/**
 * i3pm daemon IPC client
 *
 * Feature: 034-create-a-feature
 * Provides communication with the i3pm daemon for project context queries
 */

import type { DaemonProjectResponse } from "./models.ts";

/**
 * Daemon client error
 */
export class DaemonError extends Error {
  constructor(message: string, public readonly cause?: Error) {
    super(message);
    this.name = "DaemonError";
  }
}

/**
 * Get current project from daemon
 *
 * Queries the i3pm daemon via `i3pm project current --json` command.
 * This is simpler and more reliable than direct socket communication.
 *
 * @returns Project data or null if no project active
 * @throws DaemonError if daemon is not running or query fails
 */
export async function getCurrentProject(): Promise<DaemonProjectResponse | null> {
  try {
    // Execute i3pm project current --json
    const command = new Deno.Command("i3pm", {
      args: ["project", "current", "--json"],
      stdout: "piped",
      stderr: "piped",
    });

    const { code, stdout, stderr } = await command.output();

    // If exit code indicates no project (specific exit code pattern)
    if (code !== 0) {
      const errorMsg = new TextDecoder().decode(stderr);

      // Check if error is "no project active" (not a failure)
      if (errorMsg.includes("No project active") || errorMsg.includes("global mode")) {
        return null;
      }

      // Daemon not running or other error
      throw new DaemonError(
        `Failed to query daemon: ${errorMsg.trim()}`,
      );
    }

    // Parse JSON response
    const output = new TextDecoder().decode(stdout);
    const data = JSON.parse(output);

    // Validate response structure
    if (!data || typeof data !== "object") {
      throw new DaemonError("Invalid response from daemon");
    }

    return {
      name: data.name,
      directory: data.directory,
      display_name: data.display_name,
      icon: data.icon,
    };
  } catch (err) {
    if (err instanceof DaemonError) {
      throw err;
    }

    // Command not found
    if (err instanceof Deno.errors.NotFound) {
      throw new DaemonError(
        "i3pm command not found - ensure i3pm CLI is installed",
      );
    }

    throw new DaemonError(
      "Failed to communicate with daemon",
      err instanceof Error ? err : new Error(String(err)),
    );
  }
}

/**
 * Check if daemon is running
 *
 * @returns true if daemon is responding, false otherwise
 */
export async function isDaemonRunning(): Promise<boolean> {
  try {
    await getCurrentProject();
    return true;
  } catch (err) {
    // Daemon not running
    if (err instanceof DaemonError) {
      return false;
    }
    return false;
  }
}

/**
 * Get daemon status information
 *
 * @returns Status object with daemon state
 */
export async function getDaemonStatus(): Promise<{
  running: boolean;
  error?: string;
}> {
  try {
    await getCurrentProject();
    return { running: true };
  } catch (err) {
    return {
      running: false,
      error: err instanceof Error ? err.message : String(err),
    };
  }
}
