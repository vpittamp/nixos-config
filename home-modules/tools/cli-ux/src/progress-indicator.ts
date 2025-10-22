/**
 * Progress Indicator API
 *
 * Provides progress bars and spinners for long-running operations with
 * automatic visibility control and update rate management.
 *
 * @module progress-indicator
 */

import type { TerminalCapabilities } from "./terminal-capabilities.ts";
import { detectTerminalCapabilities } from "./terminal-capabilities.ts";

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
  #current = 0;
  #total: number;
  #message: string;
  #startTime: number;
  #options: Required<ProgressOptions>;
  #intervalId: number | null = null;
  #capabilities: TerminalCapabilities;

  constructor(options: ProgressOptions) {
    if (!options.total) {
      throw new Error("ProgressBar requires total option");
    }

    this.#total = options.total;
    this.#message = options.message;
    this.#startTime = Date.now();
    this.#capabilities = options.capabilities ?? detectTerminalCapabilities();

    this.#options = {
      message: options.message,
      total: options.total,
      showAfter: options.showAfter ?? 3000,
      updateInterval: options.updateInterval ?? 500,
      clear: options.clear ?? false,
      capabilities: this.#capabilities,
    };
  }

  get current(): number {
    return this.#current;
  }

  get total(): number {
    return this.#total;
  }

  get message(): string {
    return this.#message;
  }

  set message(value: string) {
    this.#message = value;
  }

  get elapsed(): number {
    return Date.now() - this.#startTime;
  }

  get percentage(): number {
    return (this.#current / this.#total) * 100;
  }

  get isVisible(): boolean {
    return this.elapsed >= this.#options.showAfter;
  }

  start(): void {
    if (this.#intervalId !== null) return; // Already started

    this.#intervalId = setInterval(() => {
      if (this.isVisible) {
        this.#render();
      }
    }, this.#options.updateInterval);
  }

  update(value: number): void {
    this.#current = Math.min(value, this.#total);
    if (this.isVisible) {
      this.#render();
    }
  }

  increment(delta = 1): void {
    this.update(this.#current + delta);
  }

  finish(message?: string): void {
    this.#current = this.#total;
    this.#render();
    this.stop();

    if (message) {
      console.log(message);
    }
  }

  stop(): void {
    if (this.#intervalId !== null) {
      clearInterval(this.#intervalId);
      this.#intervalId = null;
    }

    if (this.#options.clear) {
      // Clear the progress line
      Deno.stdout.writeSync(new TextEncoder().encode("\r\x1b[K"));
    } else {
      Deno.stdout.writeSync(new TextEncoder().encode("\n"));
    }
  }

  #render(): void {
    const percentage = Math.floor(this.percentage);
    const barLength = 30;
    const filled = Math.floor((percentage / 100) * barLength);
    const empty = barLength - filled;

    const bar = "█".repeat(filled) + "░".repeat(empty);
    const elapsedSec = Math.floor(this.elapsed / 1000);

    const output = `\r[${this.#formatTime(elapsedSec)}] [${bar}] ${percentage}% - ${this.#message}`;

    Deno.stdout.writeSync(new TextEncoder().encode(output));
  }

  #formatTime(seconds: number): string {
    const mins = Math.floor(seconds / 60);
    const secs = seconds % 60;
    return `${String(mins).padStart(2, "0")}:${String(secs).padStart(2, "0")}`;
  }
}

const SPINNER_FRAMES = ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"];

/** Spinner for operations with unknown duration */
export class Spinner {
  #message: string;
  #startTime: number;
  #options: Omit<Required<ProgressOptions>, "total">;
  #intervalId: number | null = null;
  #frameIndex = 0;
  #capabilities: TerminalCapabilities;

  constructor(options: Omit<ProgressOptions, "total">) {
    this.#message = options.message;
    this.#startTime = Date.now();
    this.#capabilities = options.capabilities ?? detectTerminalCapabilities();

    this.#options = {
      message: options.message,
      showAfter: options.showAfter ?? 3000,
      updateInterval: options.updateInterval ?? 80, // Faster for smooth animation
      clear: options.clear ?? false,
      capabilities: this.#capabilities,
    };
  }

  get message(): string {
    return this.#message;
  }

  get elapsed(): number {
    return Date.now() - this.#startTime;
  }

  get isVisible(): boolean {
    return this.elapsed >= this.#options.showAfter;
  }

  start(): void {
    if (this.#intervalId !== null) return;

    this.#intervalId = setInterval(() => {
      if (this.isVisible) {
        this.#render();
      }
    }, this.#options.updateInterval);
  }

  updateMessage(message: string): void {
    this.#message = message;
    if (this.isVisible) {
      this.#render();
    }
  }

  finish(message?: string): void {
    this.stop();
    if (message) {
      console.log(message);
    }
  }

  stop(): void {
    if (this.#intervalId !== null) {
      clearInterval(this.#intervalId);
      this.#intervalId = null;
    }

    if (this.#options.clear) {
      Deno.stdout.writeSync(new TextEncoder().encode("\r\x1b[K"));
    } else {
      Deno.stdout.writeSync(new TextEncoder().encode("\n"));
    }
  }

  #render(): void {
    const frame = SPINNER_FRAMES[this.#frameIndex];
    this.#frameIndex = (this.#frameIndex + 1) % SPINNER_FRAMES.length;

    const output = `\r${frame} ${this.#message}`;
    Deno.stdout.writeSync(new TextEncoder().encode(output));
  }
}

/**
 * Creates and manages a progress indicator for an async operation.
 *
 * Automatically determines whether to use a spinner or progress bar based
 * on whether total is provided.
 */
export function createProgress(
  options: ProgressOptions,
): ProgressBar | Spinner {
  if (options.total !== undefined) {
    return new ProgressBar(options);
  } else {
    return new Spinner(options);
  }
}

/**
 * Wraps an async function with automatic progress indication.
 */
export async function withProgress<T>(
  fn: (progress: ProgressBar | Spinner) => Promise<T>,
  options: ProgressOptions,
): Promise<T> {
  const progress = createProgress(options);
  progress.start();

  try {
    const result = await fn(progress);
    progress.finish();
    return result;
  } catch (error) {
    progress.stop();
    throw error;
  }
}
