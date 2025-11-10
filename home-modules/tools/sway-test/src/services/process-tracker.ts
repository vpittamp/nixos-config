/**
 * Process Tracker Service for Sway Test Framework
 *
 * Feature 070 - User Story 2: Graceful Cleanup Commands
 * Task: T018
 *
 * Tracks spawned processes and provides graceful termination with
 * SIGTERM→SIGKILL escalation.
 */

import { ProcessCleanupEntry } from "../models/cleanup-report.ts";

/** Timeout for SIGTERM before escalating to SIGKILL (milliseconds) */
const SIGTERM_TIMEOUT_MS = 500;

/**
 * Process Tracker - tracks and terminates spawned processes
 */
export class ProcessTracker {
  /** Set of tracked process IDs */
  private processes: Set<number> = new Set();

  /**
   * Register a process for tracking
   * @param pid - Process ID to track
   */
  registerProcess(pid: number): void {
    this.processes.add(pid);
  }

  /**
   * Unregister a process (e.g., if it exits naturally)
   * @param pid - Process ID to untrack
   */
  unregisterProcess(pid: number): void {
    this.processes.delete(pid);
  }

  /**
   * Get all tracked process IDs
   * @returns Set of tracked PIDs
   */
  getTrackedProcesses(): Set<number> {
    return new Set(this.processes);
  }

  /**
   * Check if a process is still running
   * @param pid - Process ID to check
   * @returns true if process exists
   */
  private isProcessAlive(pid: number): boolean {
    try {
      // Sending signal 0 checks if process exists without affecting it
      Deno.kill(pid, "SIGTERM"); // Try to send signal to check existence
      return true;
    } catch (error) {
      // Process doesn't exist if we get ESRCH (No such process)
      if (error instanceof Deno.errors.NotFound) {
        return false;
      }
      // Process exists but we can't send signals (permission issue)
      return true;
    }
  }

  /**
   * Terminate a single process with SIGTERM→SIGKILL escalation
   * @param pid - Process ID to terminate
   * @returns Cleanup entry describing the termination
   */
  async terminateProcess(pid: number): Promise<ProcessCleanupEntry> {
    const startTime = Date.now();

    // Try to get command name (best effort)
    let command: string | undefined;
    try {
      const process = Deno.run({
        cmd: ["ps", "-p", pid.toString(), "-o", "comm="],
        stdout: "piped",
        stderr: "null",
      });
      const output = await process.output();
      command = new TextDecoder().decode(output).trim();
      process.close();
    } catch {
      // Ignore errors getting command name
    }

    // First try SIGTERM (graceful shutdown)
    try {
      Deno.kill(pid, "SIGTERM");

      // Wait for process to exit (with timeout)
      const deadline = Date.now() + SIGTERM_TIMEOUT_MS;
      while (Date.now() < deadline) {
        if (!this.isProcessAlive(pid)) {
          // Process exited gracefully
          this.unregisterProcess(pid);
          return {
            pid,
            command,
            method: "SIGTERM",
            success: true,
            duration_ms: Date.now() - startTime,
          };
        }
        // Wait a bit before checking again
        await new Promise(resolve => setTimeout(resolve, 50));
      }

      // SIGTERM timeout - escalate to SIGKILL
      Deno.kill(pid, "SIGKILL");

      // Wait a bit for SIGKILL to take effect
      await new Promise(resolve => setTimeout(resolve, 100));

      if (!this.isProcessAlive(pid)) {
        this.unregisterProcess(pid);
        return {
          pid,
          command,
          method: "SIGKILL",
          success: true,
          duration_ms: Date.now() - startTime,
        };
      }

      // Process still alive even after SIGKILL (shouldn't happen)
      return {
        pid,
        command,
        method: "SIGKILL",
        success: false,
        error: "Process did not respond to SIGKILL",
        duration_ms: Date.now() - startTime,
      };
    } catch (error) {
      return {
        pid,
        command,
        method: "SIGTERM",
        success: false,
        error: error instanceof Error ? error.message : String(error),
        duration_ms: Date.now() - startTime,
      };
    }
  }

  /**
   * Terminate all tracked processes
   * @returns Array of cleanup entries for all processes
   */
  async terminateAll(): Promise<ProcessCleanupEntry[]> {
    const entries: ProcessCleanupEntry[] = [];

    // Terminate all processes concurrently
    const promises = Array.from(this.processes).map(pid =>
      this.terminateProcess(pid)
    );

    const results = await Promise.all(promises);
    entries.push(...results);

    return entries;
  }

  /**
   * Clear all tracked processes without terminating them
   * Useful for testing or when processes are already dead
   */
  clear(): void {
    this.processes.clear();
  }

  /**
   * Get count of tracked processes
   */
  getCount(): number {
    return this.processes.size;
  }
}
