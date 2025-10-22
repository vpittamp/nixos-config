/**
 * Progress Indicator API
 *
 * Provides progress bars and spinners for long-running operations with
 * automatic visibility control and update rate management.
 *
 * @module progress-indicator
 */

import type { TerminalCapabilities } from "./terminal-capabilities.ts";

/** Options for creating a progress indicator */
export interface ProgressOptions {
  /** Description of the operation */
  message: string;
  /** Total expected value (omit for unknown duration) */
  total?: number;
  /** Minimum elapsed time before showing indicator (ms, default: 3000) */
  showAfter?: number;
  /** Update interval in milliseconds (default: 500, min: 250 for 2Hz) */
  updateInterval?: number;
  /** Whether to clear indicator after completion (default: false) */
  clear?: boolean;
  /** Terminal capabilities (auto-detected if omitted) */
  capabilities?: TerminalCapabilities;
}

/** Progress indicator for operations with known duration */
export class ProgressBar {
  /**
   * Creates a new progress bar.
   *
   * @param {ProgressOptions} options - Progress bar configuration
   *
   * @example
   * ```typescript
   * const progress = new ProgressBar({
   *   message: "Downloading file",
   *   total: 100,
   * });
   *
   * progress.start();
   *
   * for (let i = 0; i <= 100; i++) {
   *   progress.update(i);
   *   await delay(50);
   * }
   *
   * progress.finish("Download complete");
   * ```
   */
  constructor(options: ProgressOptions);

  /** Current progress value */
  current: number;

  /** Total expected value */
  readonly total: number;

  /** Operation message/description */
  message: string;

  /** Elapsed time in milliseconds */
  readonly elapsed: number;

  /** Percentage complete (0-100) */
  readonly percentage: number;

  /** Whether indicator is currently visible */
  readonly isVisible: boolean;

  /**
   * Starts the progress indicator.
   *
   * Indicator will auto-hide until elapsed time exceeds showAfter threshold.
   */
  start(): void;

  /**
   * Updates the current progress value.
   *
   * @param {number} value - New progress value (0 to total)
   *
   * @example
   * ```typescript
   * progress.update(50); // 50% complete
   * ```
   */
  update(value: number): void;

  /**
   * Increments progress by delta.
   *
   * @param {number} delta - Amount to increment (default: 1)
   *
   * @example
   * ```typescript
   * progress.increment(); // +1
   * progress.increment(5); // +5
   * ```
   */
  increment(delta?: number): void;

  /**
   * Finishes the progress indicator with optional completion message.
   *
   * @param {string} message - Completion message (optional)
   *
   * @example
   * ```typescript
   * progress.finish("✓ Build completed successfully");
   * ```
   */
  finish(message?: string): void;

  /**
   * Stops the progress indicator without completion message.
   */
  stop(): void;
}

/** Spinner for operations with unknown duration */
export class Spinner {
  /**
   * Creates a new spinner.
   *
   * @param {ProgressOptions} options - Spinner configuration
   *
   * @example
   * ```typescript
   * const spinner = new Spinner({
   *   message: "Connecting to server...",
   * });
   *
   * spinner.start();
   *
   * // ... do work ...
   *
   * spinner.finish("✓ Connected");
   * ```
   */
  constructor(options: Omit<ProgressOptions, "total">);

  /** Operation message/description */
  message: string;

  /** Elapsed time in milliseconds */
  readonly elapsed: number;

  /** Whether spinner is currently visible */
  readonly isVisible: boolean;

  /**
   * Starts the spinner.
   *
   * Spinner will auto-hide until elapsed time exceeds showAfter threshold.
   */
  start(): void;

  /**
   * Updates the spinner message while running.
   *
   * @param {string} message - New message text
   *
   * @example
   * ```typescript
   * spinner.updateMessage("Processing file 3 of 10...");
   * ```
   */
  updateMessage(message: string): void;

  /**
   * Finishes the spinner with optional completion message.
   *
   * @param {string} message - Completion message (optional)
   *
   * @example
   * ```typescript
   * spinner.finish("✓ Processing complete");
   * ```
   */
  finish(message?: string): void;

  /**
   * Stops the spinner without completion message.
   */
  stop(): void;
}

/**
 * Creates and manages a progress indicator for an async operation.
 *
 * Automatically determines whether to use a spinner or progress bar based
 * on whether total is provided.
 *
 * @param {ProgressOptions} options - Progress configuration
 * @returns {ProgressBar | Spinner} Progress indicator instance
 *
 * @example
 * ```typescript
 * const progress = createProgress({
 *   message: "Building project",
 *   total: 100,
 * });
 *
 * progress.start();
 * // ... update progress ...
 * progress.finish();
 * ```
 */
export function createProgress(
  options: ProgressOptions,
): ProgressBar | Spinner;

/**
 * Wraps an async function with automatic progress indication.
 *
 * @param {function} fn - Async function to execute
 * @param {ProgressOptions} options - Progress configuration
 * @returns {Promise<T>} Result of the wrapped function
 *
 * @example
 * ```typescript
 * const result = await withProgress(
 *   async () => {
 *     // Long-running operation
 *     return await buildProject();
 *   },
 *   { message: "Building project" }
 * );
 * ```
 */
export function withProgress<T>(
  fn: (progress: ProgressBar | Spinner) => Promise<T>,
  options: ProgressOptions,
): Promise<T>;
