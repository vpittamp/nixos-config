/**
 * Signal Handling Utilities
 *
 * Manages graceful shutdown and terminal resize handling.
 */

/**
 * Cleanup function type
 */
export type CleanupFunction = () => void | Promise<void>;

/**
 * Signal handler configuration
 */
interface SignalHandlers {
  onSigInt?: CleanupFunction;
  onSigTerm?: CleanupFunction;
  onSigWinch?: () => void | Promise<void>;
}

/**
 * Register signal handlers
 */
export function setupSignalHandlers(handlers: SignalHandlers): void {
  // Handle Ctrl+C (SIGINT)
  if (handlers.onSigInt) {
    Deno.addSignalListener("SIGINT", async () => {
      await handlers.onSigInt?.();
      Deno.exit(130); // Standard exit code for SIGINT
    });
  }

  // Handle SIGTERM
  if (handlers.onSigTerm) {
    Deno.addSignalListener("SIGTERM", async () => {
      await handlers.onSigTerm?.();
      Deno.exit(143); // Standard exit code for SIGTERM
    });
  }

  // Handle terminal resize (SIGWINCH)
  if (handlers.onSigWinch) {
    Deno.addSignalListener("SIGWINCH", handlers.onSigWinch);
  }
}

/**
 * Remove all signal handlers
 */
export function removeSignalHandlers(): void {
  try {
    Deno.removeSignalListener("SIGINT", () => {});
    Deno.removeSignalListener("SIGTERM", () => {});
    Deno.removeSignalListener("SIGWINCH", () => {});
  } catch {
    // Ignore errors when removing handlers
  }
}

/**
 * Double Ctrl+C detection for immediate exit
 */
export class DoubleCtrlCDetector {
  private lastSigIntTime = 0;
  private readonly doublePressThresholdMs: number;
  private cleanupFn?: CleanupFunction;

  constructor(thresholdMs = 1000, cleanupFn?: CleanupFunction) {
    this.doublePressThresholdMs = thresholdMs;
    this.cleanupFn = cleanupFn;
  }

  /**
   * Handle SIGINT and detect double press
   * @returns true if immediate exit should occur
   */
  async handleSigInt(): Promise<boolean> {
    const now = Date.now();
    const timeSinceLastPress = now - this.lastSigIntTime;

    if (timeSinceLastPress < this.doublePressThresholdMs) {
      // Double press detected - immediate exit
      if (this.cleanupFn) {
        await this.cleanupFn();
      }
      return true;
    }

    this.lastSigIntTime = now;
    return false;
  }

  /**
   * Register double Ctrl+C handler
   */
  register(): void {
    Deno.addSignalListener("SIGINT", async () => {
      const shouldExit = await this.handleSigInt();
      if (shouldExit) {
        Deno.exit(130);
      } else {
        console.log("\nPress Ctrl+C again to exit immediately");
      }
    });
  }
}

/**
 * Terminal state restoration on exit
 */
export class TerminalStateManager {
  private rawModeEnabled = false;
  private cursorHidden = false;
  private alternateScreenActive = false;
  private encoder = new TextEncoder();

  /**
   * Enter raw mode for keyboard input
   */
  enterRawMode(): void {
    if (!this.rawModeEnabled) {
      Deno.stdin.setRaw(true);
      this.rawModeEnabled = true;
    }
  }

  /**
   * Leave raw mode
   */
  leaveRawMode(): void {
    if (this.rawModeEnabled) {
      Deno.stdin.setRaw(false);
      this.rawModeEnabled = false;
    }
  }

  /**
   * Hide cursor
   */
  hideCursor(): void {
    if (!this.cursorHidden) {
      Deno.stdout.writeSync(this.encoder.encode("\x1b[?25l"));
      this.cursorHidden = true;
    }
  }

  /**
   * Show cursor
   */
  showCursor(): void {
    if (this.cursorHidden) {
      Deno.stdout.writeSync(this.encoder.encode("\x1b[?25h"));
      this.cursorHidden = false;
    }
  }

  /**
   * Enter alternate screen buffer
   */
  enterAlternateScreen(): void {
    if (!this.alternateScreenActive) {
      Deno.stdout.writeSync(this.encoder.encode("\x1b[?1049h"));
      this.alternateScreenActive = true;
    }
  }

  /**
   * Leave alternate screen buffer
   */
  leaveAlternateScreen(): void {
    if (this.alternateScreenActive) {
      Deno.stdout.writeSync(this.encoder.encode("\x1b[?1049l"));
      this.alternateScreenActive = false;
    }
  }

  /**
   * Clear screen
   */
  clearScreen(): void {
    Deno.stdout.writeSync(this.encoder.encode("\x1b[2J\x1b[H"));
  }

  /**
   * Restore terminal to normal state
   */
  restore(): void {
    this.leaveAlternateScreen();
    this.showCursor();
    this.leaveRawMode();
  }

  /**
   * Setup automatic cleanup on exit
   */
  setupAutoCleanup(): void {
    setupSignalHandlers({
      onSigInt: () => this.restore(),
      onSigTerm: () => this.restore(),
    });
  }
}
