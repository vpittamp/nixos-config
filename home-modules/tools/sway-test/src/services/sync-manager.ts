/**
 * Synchronization manager for Sway IPC state consistency.
 * Feature 069: Synchronization-Based Test Framework
 *
 * @module sync-manager
 */

import {
  DEFAULT_SYNC_CONFIG,
  type SyncConfig,
  type SyncResult,
  type SyncStats,
  generateSyncMarker,
} from "../models/sync-marker.ts";

/**
 * Manages synchronization operations and performance statistics.
 *
 * This class handles:
 * - Executing sync operations via Sway IPC mark/unmark commands
 * - Tracking sync latency statistics (p95, p99, average)
 * - Configuration management (timeouts, logging, stats tracking)
 */
export class SyncManager {
  private config: SyncConfig;
  private stats: SyncStats;

  constructor(config: Partial<SyncConfig> = {}) {
    this.config = { ...DEFAULT_SYNC_CONFIG, ...config };
    this.stats = {
      totalSyncs: 0,
      successfulSyncs: 0,
      failedSyncs: 0,
      averageLatencyMs: 0,
      p95LatencyMs: 0,
      p99LatencyMs: 0,
      maxLatencyMs: 0,
      latencies: [],
    };
  }

  /**
   * Execute synchronization operation using Sway IPC mark/unmark commands.
   *
   * @param sendCommand - Function to send IPC commands (injected for testability)
   * @param timeout - Optional timeout override (milliseconds)
   * @param testId - Optional test ID for marker correlation
   * @returns SyncResult with success status and latency metrics
   *
   * @example
   * const result = await syncManager.sync(
   *   (cmd) => swayClient.sendCommand(cmd),
   *   5000,
   *   "test-firefox-launch"
   * );
   */
  async sync(
    sendCommand: (cmd: string) => Promise<{ success: boolean; error?: string }>,
    timeout?: number,
    testId?: string,
  ): Promise<SyncResult> {
    const marker = generateSyncMarker(testId);
    const startTime = performance.now();
    const timeoutMs = timeout ?? this.config.defaultTimeout;

    try {
      // Step 1: Send mark command
      const markResult = await this.sendWithTimeout(
        () => sendCommand(`mark --add ${marker.marker}`),
        timeoutMs,
      );

      if (!markResult.success) {
        throw new Error(`Mark command failed: ${markResult.error}`);
      }

      // Step 2: Send unmark command
      const unmarkResult = await this.sendWithTimeout(
        () => sendCommand(`unmark ${marker.marker}`),
        timeoutMs,
      );

      if (!unmarkResult.success) {
        throw new Error(`Unmark command failed: ${unmarkResult.error}`);
      }

      // Step 3: Success
      const endTime = performance.now();
      const latencyMs = Math.round(endTime - startTime);

      const result: SyncResult = {
        success: true,
        marker,
        latencyMs,
        startTime,
        endTime,
      };

      // Track statistics
      if (this.config.trackStats) {
        this.recordSuccess(latencyMs);
      }

      // Log if needed
      if (
        this.config.logAllSyncs ||
        latencyMs > this.config.warnThresholdMs
      ) {
        console.log(
          `Sync completed in ${latencyMs}ms (marker: ${marker.marker})`,
        );
      }

      return result;
    } catch (error) {
      const endTime = performance.now();
      const latencyMs = Math.round(endTime - startTime);

      const result: SyncResult = {
        success: false,
        marker,
        latencyMs,
        error: error instanceof Error ? error.message : String(error),
        startTime,
        endTime,
      };

      // Track failure
      if (this.config.trackStats) {
        this.recordFailure();
      }

      return result;
    }
  }

  /**
   * Get current sync statistics.
   * @returns SyncStats or null if tracking disabled
   */
  getSyncStats(): SyncStats | null {
    if (!this.config.trackStats) {
      return null;
    }
    return { ...this.stats };
  }

  /**
   * Reset sync statistics.
   * Useful for per-test benchmarking.
   */
  resetSyncStats(): void {
    this.stats = {
      totalSyncs: 0,
      successfulSyncs: 0,
      failedSyncs: 0,
      averageLatencyMs: 0,
      p95LatencyMs: 0,
      p99LatencyMs: 0,
      maxLatencyMs: 0,
      latencies: [],
    };
  }

  /**
   * Send command with timeout.
   * @param fn - Function to execute
   * @param timeout - Timeout in milliseconds
   * @returns Command result
   */
  private async sendWithTimeout<T>(
    fn: () => Promise<T>,
    timeout: number,
  ): Promise<T> {
    let timeoutId: number | undefined;
    const timeoutPromise = new Promise<never>((_, reject) => {
      timeoutId = setTimeout(
        () => reject(new Error(`Command timeout after ${timeout}ms`)),
        timeout,
      );
    });

    try {
      const result = await Promise.race([fn(), timeoutPromise]);
      if (timeoutId !== undefined) {
        clearTimeout(timeoutId);
      }
      return result;
    } catch (error) {
      if (timeoutId !== undefined) {
        clearTimeout(timeoutId);
      }
      throw error;
    }
  }

  /**
   * Record successful sync operation.
   * @param latencyMs - Sync latency in milliseconds
   */
  private recordSuccess(latencyMs: number): void {
    this.stats.totalSyncs++;
    this.stats.successfulSyncs++;
    this.stats.latencies.push(latencyMs);

    // Maintain ring buffer (max maxLatencyHistory entries)
    if (this.stats.latencies.length > this.config.maxLatencyHistory) {
      this.stats.latencies.shift();
    }

    // Update statistics
    this.updateStatistics();
  }

  /**
   * Record failed sync operation.
   */
  private recordFailure(): void {
    this.stats.totalSyncs++;
    this.stats.failedSyncs++;
  }

  /**
   * Update statistical metrics (average, p95, p99, max).
   */
  private updateStatistics(): void {
    const latencies = this.stats.latencies;
    if (latencies.length === 0) return;

    // Average
    const sum = latencies.reduce((acc, val) => acc + val, 0);
    this.stats.averageLatencyMs = Math.round(sum / latencies.length);

    // Max
    this.stats.maxLatencyMs = Math.max(...latencies);

    // Percentiles (sort ascending)
    const sorted = [...latencies].sort((a, b) => a - b);
    const p95Index = Math.floor(sorted.length * 0.95);
    const p99Index = Math.floor(sorted.length * 0.99);

    this.stats.p95LatencyMs = sorted[p95Index] ?? sorted[sorted.length - 1];
    this.stats.p99LatencyMs = sorted[p99Index] ?? sorted[sorted.length - 1];
  }
}
