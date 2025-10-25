/**
 * Interactive Monitor Dashboard
 *
 * Multi-pane TUI showing live daemon status, event stream, and window state.
 * Provides holistic real-time monitoring for debugging i3pm system.
 */

import type { DaemonClient } from "../client.ts";
import type { DaemonStatus, EventNotification, Output } from "../models.ts";
import { renderTree } from "./tree.ts";
import * as ansi from "./ansi.ts";

/**
 * Pane focus modes
 */
type FocusPane = "status" | "events" | "windows";

/**
 * Dashboard state
 */
interface DashboardState {
  focusPane: FocusPane;
  daemonStatus: DaemonStatus | null;
  events: EventNotification[];
  outputs: Output[];
  running: boolean;
  lastRefresh: number;
  error: string | null;
}

/**
 * Keyboard codes
 */
const KEYS = {
  TAB: "\t",
  CTRL_C: "\x03",
  LOWER_Q: "q",
  UPPER_Q: "Q",
  LOWER_S: "s",
  UPPER_S: "S",
  LOWER_E: "e",
  UPPER_E: "E",
  LOWER_W: "w",
  UPPER_W: "W",
} as const;

/**
 * Monitor Dashboard Class
 */
export class MonitorDashboard {
  private client: DaemonClient;
  private state: DashboardState;
  private encoder: TextEncoder;
  private decoder: TextDecoder;
  private lastCtrlC = 0;
  private maxEvents = 20; // Keep last 20 events

  constructor(client: DaemonClient) {
    this.client = client;
    this.encoder = new TextEncoder();
    this.decoder = new TextDecoder();

    this.state = {
      focusPane: "status",
      daemonStatus: null,
      events: [],
      outputs: [],
      running: false,
      lastRefresh: 0,
      error: null,
    };
  }

  /**
   * Run the dashboard
   */
  async run(): Promise<void> {
    // Setup signal handlers
    this.setupSignalHandlers();

    // Enter alternate screen and hide cursor
    await this.writeToStdout(ansi.ALTERNATE_SCREEN_ENTER);
    await this.writeToStdout(ansi.CURSOR_HIDE);

    // Set raw mode for keyboard input
    Deno.stdin.setRaw(true);

    this.state.running = true;

    try {
      // Initial refresh
      await this.refresh();

      // Start background tasks
      const eventTask = this.subscribeToEvents();
      const keyboardTask = this.handleKeyboard();
      const refreshTask = this.refreshLoop();

      // Wait for exit
      await Promise.race([eventTask, keyboardTask, refreshTask]);
    } finally {
      await this.cleanup();
    }
  }

  /**
   * Setup signal handlers
   */
  private setupSignalHandlers(): void {
    // Handle Ctrl+C gracefully
    Deno.addSignalListener("SIGINT", () => {
      const now = Date.now();
      if (now - this.lastCtrlC < 1000) {
        // Double Ctrl+C - immediate exit
        this.state.running = false;
      } else {
        // First Ctrl+C - mark time
        this.lastCtrlC = now;
      }
    });

    // Handle terminal resize
    Deno.addSignalListener("SIGWINCH", () => {
      if (this.state.running) {
        this.render().catch((err) => {
          this.state.error = `Resize error: ${err.message}`;
        });
      }
    });
  }

  /**
   * Subscribe to daemon events
   */
  private async subscribeToEvents(): Promise<void> {
    try {
      await this.client.subscribe(
        ["window", "workspace", "output", "tick"],
        async (notification) => {
          if (!this.state.running) return;

          // Parse event from notification
          const params = notification.params as {
            event?: EventNotification;
            type?: string;
            event_type?: string;
          };

          if (params.event) {
            // Full event notification
            this.addEvent(params.event);
          } else {
            // Simple notification - create basic event
            const eventType = params.type || params.event_type || "unknown";
            const basicEvent: EventNotification = {
              event_id: Date.now(),
              event_type: eventType as any,
              change: notification.method || "unknown",
              container: null,
              timestamp: Date.now(),
            };
            this.addEvent(basicEvent);
          }

          // Trigger refresh on relevant events
          await this.throttledRefresh();
        },
      );
    } catch (err) {
      if (this.state.running && err instanceof Error) {
        this.state.error = `Event subscription failed: ${err.message}`;
      }
    }
  }

  /**
   * Add event to history (keeping max size)
   */
  private addEvent(event: EventNotification): void {
    this.state.events.unshift(event); // Add to front
    if (this.state.events.length > this.maxEvents) {
      this.state.events.pop(); // Remove oldest
    }
  }

  /**
   * Handle keyboard input
   */
  private async handleKeyboard(): Promise<void> {
    const buffer = new Uint8Array(4);

    while (this.state.running) {
      try {
        const n = await Deno.stdin.read(buffer);
        if (n === null) break;

        const key = this.decoder.decode(buffer.slice(0, n));

        switch (key) {
          case KEYS.TAB:
            // Cycle through panes
            this.cycleFocusPane();
            await this.render();
            break;

          case KEYS.LOWER_S:
          case KEYS.UPPER_S:
            // Focus status pane
            this.state.focusPane = "status";
            await this.render();
            break;

          case KEYS.LOWER_E:
          case KEYS.UPPER_E:
            // Focus events pane
            this.state.focusPane = "events";
            await this.render();
            break;

          case KEYS.LOWER_W:
          case KEYS.UPPER_W:
            // Focus windows pane
            this.state.focusPane = "windows";
            await this.render();
            break;

          case KEYS.LOWER_Q:
          case KEYS.UPPER_Q:
          case KEYS.CTRL_C:
            // Exit
            this.state.running = false;
            break;
        }
      } catch (err) {
        if (this.state.running && err instanceof Error) {
          this.state.error = `Keyboard error: ${err.message}`;
        }
        break;
      }
    }
  }

  /**
   * Cycle focus pane
   */
  private cycleFocusPane(): void {
    const panes: FocusPane[] = ["status", "events", "windows"];
    const current = panes.indexOf(this.state.focusPane);
    this.state.focusPane = panes[(current + 1) % panes.length];
  }

  /**
   * Refresh loop (every 1 second)
   */
  private async refreshLoop(): Promise<void> {
    while (this.state.running) {
      await new Promise((resolve) => setTimeout(resolve, 1000));
      if (this.state.running) {
        await this.refresh();
      }
    }
  }

  /**
   * Throttled refresh (rate limited to 250ms)
   */
  private async throttledRefresh(): Promise<void> {
    const now = Date.now();
    if (now - this.state.lastRefresh > 250) {
      await this.refresh();
    }
  }

  /**
   * Refresh all data from daemon
   */
  private async refresh(): Promise<void> {
    try {
      // Fetch daemon status
      const status = await this.client.request<DaemonStatus>("get_status");
      this.state.daemonStatus = status;

      // Fetch window state
      const outputs = await this.client.request<Output[]>("get_windows");
      this.state.outputs = outputs;

      this.state.lastRefresh = Date.now();
      this.state.error = null;

      // Render
      await this.render();
    } catch (err) {
      if (err instanceof Error) {
        this.state.error = `Refresh failed: ${err.message}`;
        await this.render();
      }
    }
  }

  /**
   * Render entire dashboard
   */
  private async render(): Promise<void> {
    // Clear screen
    await this.writeToStdout(ansi.CLEAR_SCREEN);
    await this.writeToStdout(ansi.CURSOR_HOME);

    // Render header
    await this.writeToStdout(this.renderHeader());

    // Get terminal size
    const { rows } = Deno.consoleSize();
    const availableRows = rows - 5; // Reserve for header/footer

    // Split screen into three panes (status, events, windows)
    const statusRows = Math.floor(availableRows * 0.3);
    const eventsRows = Math.floor(availableRows * 0.3);
    const windowsRows = availableRows - statusRows - eventsRows;

    // Render panes
    await this.writeToStdout(
      this.renderStatusPane(statusRows),
    );
    await this.writeToStdout(
      this.renderEventsPane(eventsRows),
    );
    await this.writeToStdout(
      this.renderWindowsPane(windowsRows),
    );

    // Render footer
    await this.writeToStdout(this.renderFooter());

    // Show error if present
    if (this.state.error) {
      await this.writeToStdout(
        `\n${ansi.RED}${ansi.BOLD}Error: ${this.state.error}${ansi.RESET}`,
      );
    }
  }

  /**
   * Render dashboard header
   */
  private renderHeader(): string {
    const title = `${ansi.BOLD}${ansi.CYAN}i3pm monitor${ansi.RESET}`;
    const timestamp = new Date().toLocaleTimeString();
    return `${title} | ${ansi.DIM}${timestamp}${ansi.RESET}\n`;
  }

  /**
   * Render status pane
   */
  private renderStatusPane(maxRows: number): string {
    const focused = this.state.focusPane === "status";
    const border = focused ? "━" : "─";
    const indicator = focused ? `${ansi.GREEN}●${ansi.RESET}` : " ";

    let lines = [
      `${indicator} ${ansi.BOLD}Daemon Status${ansi.RESET} ${ansi.DIM}${border.repeat(60)}${ansi.RESET}`,
    ];

    if (this.state.daemonStatus) {
      const status = this.state.daemonStatus;
      const statusColor = status.status === "running" ? ansi.GREEN : ansi.RED;

      lines.push(`  Status: ${statusColor}${status.status}${ansi.RESET}`);
      lines.push(
        `  Connected: ${status.connected ? ansi.GREEN + "yes" : ansi.RED + "no"}${ansi.RESET}`,
      );
      lines.push(`  Uptime: ${this.formatUptime(status.uptime)}`);
      lines.push(
        `  Active Project: ${status.active_project || ansi.DIM + "Global" + ansi.RESET}`,
      );
      lines.push(`  Windows: ${status.window_count}`);
      lines.push(`  Workspaces: ${status.workspace_count}`);
      lines.push(`  Events: ${status.event_count}`);
      lines.push(`  Errors: ${status.error_count > 0 ? ansi.YELLOW : ""}${status.error_count}${ansi.RESET}`);
      lines.push(`  Version: ${ansi.DIM}${status.version}${ansi.RESET}`);
    } else {
      lines.push(`  ${ansi.DIM}Loading...${ansi.RESET}`);
    }

    // Truncate to maxRows
    lines = lines.slice(0, maxRows);

    return lines.join("\n") + "\n";
  }

  /**
   * Render events pane
   */
  private renderEventsPane(maxRows: number): string {
    const focused = this.state.focusPane === "events";
    const border = focused ? "━" : "─";
    const indicator = focused ? `${ansi.GREEN}●${ansi.RESET}` : " ";

    let lines = [
      `${indicator} ${ansi.BOLD}Event Stream${ansi.RESET} ${ansi.DIM}${border.repeat(60)}${ansi.RESET}`,
    ];

    if (this.state.events.length === 0) {
      lines.push(`  ${ansi.DIM}No events yet...${ansi.RESET}`);
    } else {
      // Show most recent events (already ordered newest first)
      const eventsToShow = this.state.events.slice(0, maxRows - 2);

      for (const event of eventsToShow) {
        const time = new Date(event.timestamp).toLocaleTimeString();
        const typeColor = this.getEventTypeColor(event.event_type);
        const line = `  ${ansi.DIM}${time}${ansi.RESET} ${typeColor}${event.event_type}${ansi.RESET}:${event.change}`;
        lines.push(line);
      }
    }

    // Truncate to maxRows
    lines = lines.slice(0, maxRows);

    return lines.join("\n") + "\n";
  }

  /**
   * Render windows pane
   */
  private renderWindowsPane(maxRows: number): string {
    const focused = this.state.focusPane === "windows";
    const border = focused ? "━" : "─";
    const indicator = focused ? `${ansi.GREEN}●${ansi.RESET}` : " ";

    let lines = [
      `${indicator} ${ansi.BOLD}Window State${ansi.RESET} ${ansi.DIM}${border.repeat(60)}${ansi.RESET}`,
    ];

    if (this.state.outputs.length === 0) {
      lines.push(`  ${ansi.DIM}No windows${ansi.RESET}`);
    } else {
      // Render tree view (compact)
      const tree = renderTree(this.state.outputs, { showHidden: false });
      const treeLines = tree.split("\n").slice(0, maxRows - 2);
      lines.push(...treeLines.map((line) => `  ${line}`));
    }

    // Truncate to maxRows
    lines = lines.slice(0, maxRows);

    return lines.join("\n") + "\n";
  }

  /**
   * Render footer
   */
  private renderFooter(): string {
    return `${ansi.DIM}${"─".repeat(80)}${ansi.RESET}\n` +
      `${ansi.GREEN}[Tab]${ansi.RESET} Cycle Panes  ` +
      `${ansi.GREEN}[S]${ansi.RESET} Status  ` +
      `${ansi.GREEN}[E]${ansi.RESET} Events  ` +
      `${ansi.GREEN}[W]${ansi.RESET} Windows  ` +
      `${ansi.GREEN}[Q]${ansi.RESET} Quit\n`;
  }

  /**
   * Get color for event type
   */
  private getEventTypeColor(eventType: string): string {
    switch (eventType) {
      case "window":
        return ansi.CYAN;
      case "workspace":
        return ansi.YELLOW;
      case "output":
        return ansi.MAGENTA;
      case "tick":
        return ansi.GREEN;
      default:
        return ansi.GRAY;
    }
  }

  /**
   * Format uptime in human-readable format
   */
  private formatUptime(seconds: number): string {
    const hours = Math.floor(seconds / 3600);
    const minutes = Math.floor((seconds % 3600) / 60);
    const secs = Math.floor(seconds % 60);

    if (hours > 0) {
      return `${hours}h ${minutes}m ${secs}s`;
    } else if (minutes > 0) {
      return `${minutes}m ${secs}s`;
    } else {
      return `${secs}s`;
    }
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
    // Restore terminal state
    await this.writeToStdout(ansi.CURSOR_SHOW);
    await this.writeToStdout(ansi.ALTERNATE_SCREEN_EXIT);

    // Restore normal mode
    try {
      Deno.stdin.setRaw(false);
    } catch {
      // Ignore errors during cleanup
    }
  }
}
