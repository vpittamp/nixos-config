/**
 * Synchronization marker model for Sway IPC state consistency.
 * Feature 069: Synchronization-Based Test Framework
 *
 * @module sync-marker
 */

/**
 * Unique identifier for a synchronization operation.
 * Format: sync_<timestamp>_<random>
 * Example: sync_1699887123456_a7b3c9d
 */
export interface SyncMarker {
  /**
   * Full marker string used in Sway IPC commands.
   * Format: "sync_<timestamp>_<random>"
   */
  readonly marker: string;

  /**
   * Unix timestamp (milliseconds) when marker was generated.
   * Used for debugging and timeout tracking.
   */
  readonly timestamp: number;

  /**
   * Random component for uniqueness (base36, 7 characters).
   * Ensures parallel tests don't interfere with each other.
   */
  readonly randomId: string;

  /**
   * Optional test ID this marker is associated with.
   * Useful for diagnostic logging.
   */
  readonly testId?: string;
}

/**
 * Result of a sync operation with performance metrics.
 */
export interface SyncResult {
  /**
   * Whether sync completed successfully.
   * False indicates timeout or IPC error.
   */
  success: boolean;

  /**
   * Sync marker used for this operation.
   * Useful for debugging and log correlation.
   */
  marker: SyncMarker;

  /**
   * Sync operation latency (milliseconds).
   * Includes: IPC round-trip + X11 processing time.
   * Target: <10ms (95th percentile)
   */
  latencyMs: number;

  /**
   * Error message if sync failed.
   * Only present when success === false.
   */
  error?: string;

  /**
   * Timestamp when sync operation started.
   * For debugging and timeline reconstruction.
   */
  startTime: number;

  /**
   * Timestamp when sync operation completed.
   * For debugging and timeline reconstruction.
   */
  endTime: number;
}

/**
 * Configuration for sync operations.
 * Global defaults that can be overridden per-action.
 */
export interface SyncConfig {
  /**
   * Default timeout for sync operations (milliseconds).
   * Default: 5000 (5 seconds)
   * Range: 100-30000 (0.1s to 30s)
   */
  defaultTimeout: number;

  /**
   * Whether to log all sync operations.
   * Default: false (only log slow ops >10ms)
   */
  logAllSyncs: boolean;

  /**
   * Latency threshold for warning logs (milliseconds).
   * Default: 10 (log if sync >10ms)
   */
  warnThresholdMs: number;

  /**
   * Whether to track sync statistics.
   * Default: true (enabled for performance monitoring)
   */
  trackStats: boolean;

  /**
   * Maximum number of latencies to keep in stats.
   * Default: 100 (ring buffer)
   */
  maxLatencyHistory: number;

  /**
   * Custom marker prefix (for testing/debugging).
   * Default: "sync"
   * Example: "test_sync" → "test_sync_1699887123456_a7b3c9d"
   */
  markerPrefix?: string;
}

/**
 * Track sync latency distribution for performance monitoring.
 */
export interface SyncStats {
  totalSyncs: number;
  successfulSyncs: number;
  failedSyncs: number;
  averageLatencyMs: number;
  p95LatencyMs: number; // 95th percentile
  p99LatencyMs: number; // 99th percentile
  maxLatencyMs: number;
  latencies: number[]; // Ring buffer, max 100 entries
}

/**
 * Default sync configuration.
 */
export const DEFAULT_SYNC_CONFIG: SyncConfig = {
  defaultTimeout: 5000,
  logAllSyncs: false,
  warnThresholdMs: 10,
  trackStats: true,
  maxLatencyHistory: 100,
  markerPrefix: "sync",
};

/**
 * Generate a new SyncMarker with guaranteed uniqueness.
 *
 * @param testId - Optional test identifier for debugging
 * @returns New SyncMarker instance
 *
 * @example
 * const marker = generateSyncMarker("test-firefox-launch");
 * // marker.marker === "sync_1699887123456_a7b3c9d"
 */
export function generateSyncMarker(testId?: string): SyncMarker {
  const timestamp = Date.now();
  const randomId = Math.random().toString(36).substring(2, 9); // 7 chars

  return {
    marker: `sync_${timestamp}_${randomId}`,
    timestamp,
    randomId,
    testId,
  };
}

/**
 * Validate SyncMarker format.
 * @param marker - Marker string to validate
 * @returns true if valid, throws Error if invalid
 */
export function validateSyncMarker(marker: string): boolean {
  const regex = /^sync_\d+_[a-z0-9]{7}$/;
  if (!regex.test(marker)) {
    throw new Error(`Invalid sync marker format: ${marker}`);
  }
  return true;
}

/**
 * Validate SyncConfig values.
 * @param config - Config to validate
 * @returns true if valid, throws Error if invalid
 */
export function validateSyncConfig(config: Partial<SyncConfig>): boolean {
  if (config.defaultTimeout !== undefined) {
    if (config.defaultTimeout < 100 || config.defaultTimeout > 30000) {
      throw new Error(
        `defaultTimeout out of range (100-30000): ${config.defaultTimeout}`,
      );
    }
  }

  if (config.warnThresholdMs !== undefined) {
    if (config.warnThresholdMs < 1 || config.warnThresholdMs > 1000) {
      throw new Error(
        `warnThresholdMs out of range (1-1000): ${config.warnThresholdMs}`,
      );
    }
  }

  if (config.maxLatencyHistory !== undefined) {
    if (config.maxLatencyHistory < 10 || config.maxLatencyHistory > 1000) {
      throw new Error(
        `maxLatencyHistory out of range (10-1000): ${config.maxLatencyHistory}`,
      );
    }
  }

  return true;
}
