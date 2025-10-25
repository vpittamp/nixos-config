/**
 * Live TUI for Window State Monitoring
 *
 * Interactive terminal UI with real-time updates via event subscriptions.
 */

import type { DaemonClient } from "../client.ts";
import type { Output } from "../models.ts";
import { renderTree } from "./tree.ts";
import { renderTable, ChangeTracker } from "./table.ts";

/**
 * View modes for live TUI
 */
type ViewMode = "tree" | "table";

/**
 * Live TUI state
 */
interface TUIState {
  viewMode: ViewMode;
  showHidden: boolean;
  outputs: Output[];
  running: boolean;
  lastRefresh: number;
}

/**
 * ANSI escape codes
 */
const ANSI = {
  // Screen management
  CLEAR_SCREEN: "\x1b[2J",
  HOME: "\x1b[H",
  ALTERNATE_SCREEN_ENTER: "\x1b[?1049h",
  ALTERNATE_SCREEN_LEAVE: "\x1b[?1049l",

  // Cursor control
  HIDE_CURSOR: "\x1b[?25l",
  SHOW_CURSOR: "\x1b[?25h",

  // Colors
  RESET: "\x1b[0m",
  BOLD: "\x1b[1m",
  DIM: "\x1b[2m",
  CYAN: "\x1b[36m",
  YELLOW: "\x1b[33m",
  GREEN: "\x1b[32m",
} as const;

/**
 * Keyboard codes
 */
const KEYS = {
  TAB: "\t",
  CTRL_C: "\x03",
  LOWER_H: "h",
  UPPER_H: "H",
  LOWER_Q: "q",
  UPPER_Q: "Q",
} as const;

/**
 * Live TUI class
 */
export class LiveTUI {
  private client: DaemonClient;
  private state: TUIState;
  private encoder: TextEncoder;
  private decoder: TextDecoder;
  private refreshTimer: number | null = null;
  private changeTracker: ChangeTracker;

  constructor(client: DaemonClient) {
    this.client = client;
    this.encoder = new TextEncoder();
    this.decoder = new TextDecoder();
    this.changeTracker = new ChangeTracker(3000); // 3 second expiry

    this.state = {
      viewMode: "tree",
      showHidden: false,
      outputs: [],
      running: false,
      lastRefresh: 0,
    };
  }

  /**
   * Run the live TUI
   */
  async run(): Promise<void> {
    // Setup signal handlers
    this.setupSignalHandlers();

    // Enter alternate screen and hide cursor
    await this.writeToStdout(ANSI.ALTERNATE_SCREEN_ENTER);
    await this.writeToStdout(ANSI.HIDE_CURSOR);

    // Set raw mode for keyboard input
    Deno.stdin.setRaw(true);

    this.state.running = true;

    try {
      // Initial render
      await this.refresh();

      // Start background tasks
      const eventTask = this.subscribeToEvents();
      const keyboardTask = this.handleKeyboard();

      // Wait for exit
      await Promise.race([eventTask, keyboardTask]);
    } finally {
      await this.cleanup();
    }
  }

  /**
   * Setup signal handlers
   */
  private setupSignalHandlers(): void {
    // Note: Ctrl+C is handled directly in raw mode keyboard handler (handleKeyboard)
    // Using Deno.addSignalListener("SIGINT") conflicts with raw mode input

    // Handle terminal resize
    Deno.addSignalListener("SIGWINCH", () => {
      if (this.state.running) {
        this.refresh().catch((err) => {
          console.error("Error during resize refresh:", err);
        });
      }
    });
  }

  /**
   * Subscribe to daemon events
   */
  private async subscribeToEvents(): Promise<void> {
    try {
      await this.client.subscribe(["window", "workspace", "output"], async (notification) => {
        if (!this.state.running) return;

        // Check if event type is relevant
        // Daemon sends "event_type" field with format like "window::focus", "workspace::focus"
        const params = notification.params as { type?: string; event_type?: string };
        const eventType = params.event_type || params.type;

        if (
          eventType?.startsWith("window") ||
          eventType?.startsWith("workspace") ||
          eventType?.startsWith("output")
        ) {
          // Throttle refreshes to avoid excessive redraws (50ms = 20fps max)
          const now = Date.now();
          if (now - this.state.lastRefresh > 50) {
            await this.refresh();
          }
        }
      });
    } catch (err) {
      if (this.state.running && err instanceof Error) {
        await this.showError(`Event subscription failed: ${err.message}`);
      }
    }
  }

  /**
   * Handle keyboard input
   */
  private async handleKeyboard(): Promise<void> {
    const buffer = new Uint8Array(16);

    while (this.state.running) {
      try {
        const n = await Deno.stdin.read(buffer);
        if (n === null) break;

        // Check for Ctrl+C BEFORE decoding (best practice)
        if (buffer[0] === 0x03) {
          this.state.running = false;
          break;
        }

        const key = this.decoder.decode(buffer.slice(0, n));

        switch (key) {
          case KEYS.TAB:
            // Toggle view mode
            this.state.viewMode = this.state.viewMode === "tree" ? "table" : "tree";
            await this.refresh();
            break;

          case KEYS.LOWER_H:
          case KEYS.UPPER_H:
            // Toggle hidden windows
            this.state.showHidden = !this.state.showHidden;
            await this.refresh();
            break;

          case KEYS.LOWER_Q:
          case KEYS.UPPER_Q:
            // Exit
            this.state.running = false;
            break;
        }
      } catch (err) {
        if (this.state.running && err instanceof Error) {
          await this.showError(`Keyboard error: ${err.message}`);
        }
        break;
      }
    }
  }

  /**
   * Refresh display
   */
  private async refresh(): Promise<void> {
    try {
      // Fetch fresh state from daemon
      const response = await this.client.request<Output[]>("get_windows");
      this.state.outputs = response;
      this.state.lastRefresh = Date.now();

      // Render screen
      await this.render();
    } catch (err) {
      if (err instanceof Error) {
        await this.showError(`Failed to refresh: ${err.message}`);
      }
    }
  }

  /**
   * Render screen
   */
  private async render(): Promise<void> {
    // Clear screen and move to home
    await this.writeToStdout(ANSI.CLEAR_SCREEN);
    await this.writeToStdout(ANSI.HOME);

    // Render header
    const header = this.renderHeader();
    await this.writeToStdout(header);

    // Render content based on view mode
    const content = this.state.viewMode === "tree"
      ? renderTree(this.state.outputs, { showHidden: this.state.showHidden })
      : renderTable(this.state.outputs, {
          showHidden: this.state.showHidden,
          changeTracker: this.changeTracker
        });

    await this.writeToStdout(content);

    // Render footer
    const footer = this.renderFooter();
    await this.writeToStdout(footer);
  }

  /**
   * Render header
   */
  private renderHeader(): string {
    const viewMode = this.state.viewMode.toUpperCase();
    const hiddenStatus = this.state.showHidden ? "SHOWING HIDDEN" : "HIDING HIDDEN";

    return `${ANSI.BOLD}${ANSI.CYAN}i3pm windows --live${ANSI.RESET} | ` +
      `View: ${ANSI.BOLD}${viewMode}${ANSI.RESET} | ` +
      `${hiddenStatus}\n` +
      `${ANSI.DIM}${"=".repeat(80)}${ANSI.RESET}\n\n`;
  }

  /**
   * Render footer
   */
  private renderFooter(): string {
    return `\n${ANSI.DIM}${"=".repeat(80)}${ANSI.RESET}\n` +
      `${ANSI.GREEN}[Tab]${ANSI.RESET} Switch View  ` +
      `${ANSI.GREEN}[H]${ANSI.RESET} Toggle Hidden  ` +
      `${ANSI.GREEN}[Q]${ANSI.RESET} or ${ANSI.GREEN}[Ctrl+C]${ANSI.RESET} Exit\n`;
  }

  /**
   * Show error message
   */
  private async showError(message: string): Promise<void> {
    await this.writeToStdout(`\n${ANSI.YELLOW}Error: ${message}${ANSI.RESET}\n`);
  }

  /**
   * Write to stdout
   */
  private async writeToStdout(text: string): Promise<void> {
    await Deno.stdout.write(this.encoder.encode(text));
  }

  /**
   * Cleanup and restore terminal state
   */
  private async cleanup(): Promise<void> {
    // Clear refresh timer
    if (this.refreshTimer !== null) {
      clearTimeout(this.refreshTimer);
      this.refreshTimer = null;
    }

    // Restore terminal state
    await this.writeToStdout(ANSI.SHOW_CURSOR);
    await this.writeToStdout(ANSI.ALTERNATE_SCREEN_LEAVE);

    // Restore normal mode
    try {
      Deno.stdin.setRaw(false);
    } catch {
      // Ignore errors during cleanup
    }
  }
}
