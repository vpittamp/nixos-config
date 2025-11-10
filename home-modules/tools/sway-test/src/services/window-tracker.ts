/**
 * Window Tracker Service for Sway Test Framework
 *
 * Feature 070 - User Story 2: Graceful Cleanup Commands
 * Task: T019
 *
 * Tracks window markers and closes windows via Sway IPC commands.
 */

import { WindowCleanupEntry } from "../models/cleanup-report.ts";

/**
 * Window Tracker - tracks and closes windows via Sway IPC
 */
export class WindowTracker {
  /** Set of tracked window markers */
  private windowMarkers: Set<string> = new Set();

  /**
   * Register a window marker for tracking
   * @param marker - Window marker to track (e.g., "sway-test-window-1")
   */
  registerWindow(marker: string): void {
    this.windowMarkers.add(marker);
  }

  /**
   * Unregister a window marker
   * @param marker - Window marker to stop tracking
   */
  unregisterWindow(marker: string): void {
    this.windowMarkers.delete(marker);
  }

  /**
   * Get all tracked window markers
   * @returns Set of tracked markers
   */
  getTrackedWindows(): Set<string> {
    return new Set(this.windowMarkers);
  }

  /**
   * Find window ID by marker using swaymsg
   * @param marker - Window marker to find
   * @returns Window container ID or null if not found
   */
  private async findWindowByMarker(marker: string): Promise<number | null> {
    try {
      const process = Deno.run({
        cmd: ["swaymsg", "-t", "get_tree"],
        stdout: "piped",
        stderr: "null",
      });

      const output = await process.output();
      const tree = JSON.parse(new TextDecoder().decode(output));
      process.close();

      // Recursively search tree for window with matching mark
      const findMarked = (node: any): number | null => {
        if (node.marks && node.marks.includes(marker)) {
          return node.id;
        }

        if (node.nodes) {
          for (const child of node.nodes) {
            const found = findMarked(child);
            if (found !== null) return found;
          }
        }

        if (node.floating_nodes) {
          for (const child of node.floating_nodes) {
            const found = findMarked(child);
            if (found !== null) return found;
          }
        }

        return null;
      };

      return findMarked(tree);
    } catch {
      return null;
    }
  }

  /**
   * Close a single window by marker using Sway IPC
   * @param marker - Window marker to close
   * @returns Cleanup entry describing the closure
   */
  async closeWindow(marker: string): Promise<WindowCleanupEntry> {
    const startTime = Date.now();

    try {
      // Find window ID by marker
      const windowId = await this.findWindowByMarker(marker);

      if (windowId === null) {
        return {
          marker,
          success: false,
          error: "Window not found by marker",
          duration_ms: Date.now() - startTime,
        };
      }

      // Close window using swaymsg with marker criteria
      const process = Deno.run({
        cmd: ["swaymsg", `[con_mark="${marker}"]`, "kill"],
        stdout: "null",
        stderr: "piped",
      });

      const status = await process.status();
      const stderr = await process.stderrOutput();
      process.close();

      if (!status.success) {
        const errorMsg = new TextDecoder().decode(stderr);
        return {
          marker,
          window_id: windowId,
          success: false,
          error: `swaymsg kill failed: ${errorMsg}`,
          duration_ms: Date.now() - startTime,
        };
      }

      this.unregisterWindow(marker);
      return {
        marker,
        window_id: windowId,
        success: true,
        duration_ms: Date.now() - startTime,
      };
    } catch (error) {
      return {
        marker,
        success: false,
        error: error instanceof Error ? error.message : String(error),
        duration_ms: Date.now() - startTime,
      };
    }
  }

  /**
   * Close all tracked windows
   * @returns Array of cleanup entries for all windows
   */
  async closeAll(): Promise<WindowCleanupEntry[]> {
    const entries: WindowCleanupEntry[] = [];

    // Close all windows concurrently
    const promises = Array.from(this.windowMarkers).map(marker =>
      this.closeWindow(marker)
    );

    const results = await Promise.all(promises);
    entries.push(...results);

    return entries;
  }

  /**
   * Clear all tracked windows without closing them
   * Useful for testing or when windows are already closed
   */
  clear(): void {
    this.windowMarkers.clear();
  }

  /**
   * Get count of tracked windows
   */
  getCount(): number {
    return this.windowMarkers.size;
  }
}
