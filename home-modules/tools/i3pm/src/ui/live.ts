/**
 * Live TUI for Window State Monitoring
 *
 * Interactive terminal UI with real-time updates via event subscriptions.
 */

import type { DaemonClient } from "../client.ts";
import type { Output } from "../models.ts";
import { renderTree } from "./tree.ts";
import { renderTable, ChangeTracker, ChangeType } from "./table.ts";

/**
 * View modes for live TUI
 */
type ViewMode = "tree" | "table" | "inspect";

/**
 * Live TUI state
 */
interface TUIState {
  viewMode: ViewMode;
  showHidden: boolean;
  outputs: Output[];
  running: boolean;
  lastRefresh: number;
  selectedWindowId: number | null; // Window ID currently selected in table view
  inspectWindowId: number | null; // Window ID being inspected
  inspectData: unknown | null; // Raw Sway tree data for inspected window
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
  LOWER_I: "i",
  UPPER_I: "I",
  ESC: "\x1b",
  LOWER_B: "b",
  UPPER_B: "B",
  ENTER: "\r",
  ARROW_UP: "\x1b[A",
  ARROW_DOWN: "\x1b[B",
  PAGE_UP: "\x1b[5~",
  PAGE_DOWN: "\x1b[6~",
  HOME: "\x1b[H",
  END: "\x1b[F",
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
    this.changeTracker = new ChangeTracker(5000); // 5 second expiry for change indicators

    this.state = {
      viewMode: "table", // Default to table view for better readability
      showHidden: false,
      outputs: [],
      running: false,
      lastRefresh: 0,
      selectedWindowId: null,
      inspectWindowId: null,
      inspectData: null,
    };
  }

  /**
   * Run the live TUI
   */
  async run(): Promise<void> {
    // Check if running in a terminal
    if (!Deno.stdin.isTerminal()) {
      throw new Error(
        "Live mode requires a terminal (TTY).\n" +
        "Cannot run with redirected input/output or in non-interactive mode.\n" +
        "Run directly in a terminal without redirection."
      );
    }

    // Setup signal handlers
    this.setupSignalHandlers();

    // Enter alternate screen and hide cursor
    await this.writeToStdout(ANSI.ALTERNATE_SCREEN_ENTER);
    await this.writeToStdout(ANSI.HIDE_CURSOR);

    // Set raw mode for keyboard input
    try {
      Deno.stdin.setRaw(true);
    } catch (err) {
      await this.cleanup();
      throw new Error(
        `Failed to enable raw terminal mode: ${err instanceof Error ? err.message : String(err)}\n` +
        "Make sure you're running in a real terminal (not via SSH without PTY allocation)."
      );
    }

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

      // Keep the promise alive while the TUI is running
      // This ensures Promise.race doesn't exit immediately after subscription
      while (this.state.running) {
        await new Promise((resolve) => setTimeout(resolve, 100));
      }
    } catch (err) {
      if (this.state.running && err instanceof Error) {
        await this.showError(`Event subscription failed: ${err.message}`);
      }
    }
  }

  /**
   * Get all visible windows as a flat list
   */
  private getAllWindows(): Array<{ id: number; [key: string]: any }> {
    const windows = [];
    for (const output of this.state.outputs) {
      for (const workspace of output.workspaces) {
        for (const window of workspace.windows) {
          if (this.state.showHidden || !window.hidden) {
            windows.push(window);
          }
        }
      }
    }
    return windows;
  }

  /**
   * Select the next window in the list
   */
  private selectNextWindow(): void {
    const windows = this.getAllWindows();
    if (windows.length === 0) return;

    if (this.state.selectedWindowId === null) {
      // Select first window
      this.state.selectedWindowId = windows[0].id;
    } else {
      // Find current selection and move to next
      const currentIndex = windows.findIndex(w => w.id === this.state.selectedWindowId);
      if (currentIndex === -1 || currentIndex === windows.length - 1) {
        // Wrap to first
        this.state.selectedWindowId = windows[0].id;
      } else {
        this.state.selectedWindowId = windows[currentIndex + 1].id;
      }
    }
  }

  /**
   * Select the previous window in the list
   */
  private selectPreviousWindow(): void {
    const windows = this.getAllWindows();
    if (windows.length === 0) return;

    if (this.state.selectedWindowId === null) {
      // Select last window
      this.state.selectedWindowId = windows[windows.length - 1].id;
    } else {
      // Find current selection and move to previous
      const currentIndex = windows.findIndex(w => w.id === this.state.selectedWindowId);
      if (currentIndex === -1 || currentIndex === 0) {
        // Wrap to last
        this.state.selectedWindowId = windows[windows.length - 1].id;
      } else {
        this.state.selectedWindowId = windows[currentIndex - 1].id;
      }
    }
  }

  /**
   * Select first window in the list
   */
  private selectFirstWindow(): void {
    const windows = this.getAllWindows();
    if (windows.length > 0) {
      this.state.selectedWindowId = windows[0].id;
    }
  }

  /**
   * Select last window in the list
   */
  private selectLastWindow(): void {
    const windows = this.getAllWindows();
    if (windows.length > 0) {
      this.state.selectedWindowId = windows[windows.length - 1].id;
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

        // Debug: Log key presses to help troubleshoot
        // (This will write to alternate screen, so won't interfere with output)

        switch (key) {
          case KEYS.TAB:
            // Toggle view mode (only when not in inspect mode)
            if (this.state.viewMode !== "inspect") {
              this.state.viewMode = this.state.viewMode === "tree" ? "table" : "tree";
              await this.refresh();
            }
            break;

          case KEYS.LOWER_H:
          case KEYS.UPPER_H:
            // Toggle hidden windows (only when not in inspect mode)
            if (this.state.viewMode !== "inspect") {
              this.state.showHidden = !this.state.showHidden;
              await this.refresh();
            }
            break;

          case KEYS.ARROW_DOWN:
            // Navigate to next window in table (only when not in inspect mode)
            if (this.state.viewMode !== "inspect") {
              this.selectNextWindow();
              await this.render();
            }
            break;

          case KEYS.ARROW_UP:
            // Navigate to previous window in table (only when not in inspect mode)
            if (this.state.viewMode !== "inspect") {
              this.selectPreviousWindow();
              await this.render();
            }
            break;

          case KEYS.PAGE_DOWN:
            // Jump down 10 windows (only when not in inspect mode)
            if (this.state.viewMode !== "inspect") {
              for (let i = 0; i < 10; i++) {
                this.selectNextWindow();
              }
              await this.render();
            }
            break;

          case KEYS.PAGE_UP:
            // Jump up 10 windows (only when not in inspect mode)
            if (this.state.viewMode !== "inspect") {
              for (let i = 0; i < 10; i++) {
                this.selectPreviousWindow();
              }
              await this.render();
            }
            break;

          case KEYS.HOME:
            // Jump to first window (only when not in inspect mode)
            if (this.state.viewMode !== "inspect") {
              this.selectFirstWindow();
              await this.render();
            }
            break;

          case KEYS.END:
            // Jump to last window (only when not in inspect mode)
            if (this.state.viewMode !== "inspect") {
              this.selectLastWindow();
              await this.render();
            }
            break;

          case KEYS.ENTER:
          case KEYS.LOWER_I:
          case KEYS.UPPER_I:
            // Enter inspect mode for selected window (or focused if none selected)
            if (this.state.viewMode !== "inspect") {
              await this.enterInspectMode();
            }
            break;

          case KEYS.ESC:
          case KEYS.LOWER_B:
          case KEYS.UPPER_B:
            // Exit inspect mode back to previous view
            if (this.state.viewMode === "inspect") {
              this.state.viewMode = "table";
              this.state.inspectWindowId = null;
              this.state.inspectData = null;
              await this.refresh();
            }
            break;

          case KEYS.LOWER_Q:
          case KEYS.UPPER_Q:
            // Exit
            this.state.running = false;
            break;

          default:
            // Show hint for unrecognized keys
            if (key.length === 1 && key.charCodeAt(0) >= 32 && key.charCodeAt(0) <= 126) {
              // Visible character - show hint
              const hint = this.state.viewMode === "inspect"
                ? "Press B or Esc to go back, Q to quit."
                : "Press I to inspect focused window, Tab to switch view, H to toggle hidden, Q to quit.";
              await this.showError(`Key '${key}' not recognized. ${hint}`);
            }
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
   * Enter inspect mode for the selected window
   */
  private async enterInspectMode(): Promise<void> {
    try {
      const windows = this.getAllWindows();

      // If no window is selected, try to select the focused one or the first one
      if (this.state.selectedWindowId === null) {
        // Try to find focused window
        let focusedWindow = null;
        for (const output of this.state.outputs) {
          for (const workspace of output.workspaces) {
            for (const window of workspace.windows) {
              if (window.focused) {
                focusedWindow = window;
                break;
              }
            }
            if (focusedWindow) break;
          }
          if (focusedWindow) break;
        }

        if (focusedWindow) {
          this.state.selectedWindowId = focusedWindow.id;
        } else if (windows.length > 0) {
          // No focused window, select first visible window
          this.state.selectedWindowId = windows[0].id;
        } else {
          await this.showError("No windows available to inspect. Open some windows first.");
          return;
        }
      }

      // Find the selected window
      const selectedWindow = windows.find(w => w.id === this.state.selectedWindowId);

      if (!selectedWindow) {
        await this.showError("Selected window not found. It may have been closed.");
        this.state.selectedWindowId = null;
        return;
      }

      // Enter inspect mode with the selected window
      this.state.inspectWindowId = selectedWindow.id;
      this.state.inspectData = selectedWindow;
      this.state.viewMode = "inspect";

      await this.render();
    } catch (err) {
      await this.showError(`Failed to enter inspect mode: ${err instanceof Error ? err.message : String(err)}`);
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
    let content: string;
    if (this.state.viewMode === "inspect") {
      content = this.renderInspect();
    } else if (this.state.viewMode === "tree") {
      content = renderTree(this.state.outputs, { showHidden: this.state.showHidden });
    } else {
      content = await renderTable(this.state.outputs, {
        showHidden: this.state.showHidden,
        changeTracker: this.changeTracker,
        groupByProject: true,
        selectedWindowId: this.state.selectedWindowId,
      });
    }

    await this.writeToStdout(content);

    // Render footer
    const footer = this.renderFooter();
    await this.writeToStdout(footer);
  }

  /**
   * Colorize JSON for better readability
   */
  private colorizeJson(json: string): string {
    // ANSI color codes for JSON elements
    const CYAN = "\x1b[36m";      // Cyan for keys
    const GREEN = "\x1b[32m";     // Green for string values
    const YELLOW = "\x1b[33m";    // Yellow for numbers
    const MAGENTA = "\x1b[35m";   // Magenta for booleans
    const DIM = "\x1b[2m";        // Dim for null
    const GRAY = "\x1b[90m";      // Gray for structural elements
    const RESET = "\x1b[0m";

    const lines = json.split('\n');
    const coloredLines: string[] = [];

    for (const line of lines) {
      let colored = '';
      let i = 0;

      while (i < line.length) {
        const char = line[i];

        // Handle strings (could be keys or values)
        if (char === '"') {
          const stringStart = i;
          i++; // Skip opening quote

          // Find closing quote (handle escaped quotes)
          while (i < line.length) {
            if (line[i] === '\\' && i + 1 < line.length) {
              i += 2; // Skip escaped character
            } else if (line[i] === '"') {
              break;
            } else {
              i++;
            }
          }
          i++; // Include closing quote

          const stringContent = line.substring(stringStart, i);

          // Check if this is a key (followed by colon) or value
          let j = i;
          while (j < line.length && /\s/.test(line[j])) j++;

          if (j < line.length && line[j] === ':') {
            // It's a key
            colored += CYAN + stringContent + RESET;
          } else {
            // It's a string value
            colored += GREEN + stringContent + RESET;
          }
          continue;
        }

        // Handle numbers
        if (/[\d-]/.test(char) && (i === 0 || /[\s:,\[]/.test(line[i - 1]))) {
          const numStart = i;
          while (i < line.length && /[\d.\-eE+]/.test(line[i])) {
            i++;
          }
          colored += YELLOW + line.substring(numStart, i) + RESET;
          continue;
        }

        // Handle booleans
        if (line.substring(i, i + 4) === 'true') {
          colored += MAGENTA + 'true' + RESET;
          i += 4;
          continue;
        }
        if (line.substring(i, i + 5) === 'false') {
          colored += MAGENTA + 'false' + RESET;
          i += 5;
          continue;
        }

        // Handle null
        if (line.substring(i, i + 4) === 'null') {
          colored += DIM + 'null' + RESET;
          i += 4;
          continue;
        }

        // Handle structural characters
        if (/[{}\[\],:]/.test(char)) {
          colored += GRAY + char + RESET;
          i++;
          continue;
        }

        // Regular character (whitespace, etc.)
        colored += char;
        i++;
      }

      coloredLines.push(colored);
    }

    return coloredLines.join('\n');
  }

  /**
   * Render inspect view for detailed window information
   */
  private renderInspect(): string {
    if (!this.state.inspectData) {
      return "No window data available for inspection.";
    }

    const window = this.state.inspectData as any;
    const lines: string[] = [];

    // Title
    lines.push(`${ANSI.BOLD}${ANSI.CYAN}Window Inspector${ANSI.RESET}`);
    lines.push(`${ANSI.DIM}${"═".repeat(100)}${ANSI.RESET}\n`);

    // Basic Information
    lines.push(`${ANSI.BOLD}${ANSI.YELLOW}Basic Information:${ANSI.RESET}`);
    lines.push(`  ${ANSI.BOLD}Window ID:${ANSI.RESET}       ${window.id}`);
    lines.push(`  ${ANSI.BOLD}PID:${ANSI.RESET}             ${window.pid || "N/A"}`);
    lines.push(`  ${ANSI.BOLD}Title:${ANSI.RESET}           ${window.title}`);
    lines.push(`  ${ANSI.BOLD}App ID:${ANSI.RESET}          ${window.app_id || "N/A"}`);
    lines.push(`  ${ANSI.BOLD}Class:${ANSI.RESET}           ${window.class}`);
    lines.push(`  ${ANSI.BOLD}Instance:${ANSI.RESET}        ${window.instance || "N/A"}`);
    lines.push("");

    // Location
    lines.push(`${ANSI.BOLD}${ANSI.YELLOW}Location:${ANSI.RESET}`);
    lines.push(`  ${ANSI.BOLD}Workspace:${ANSI.RESET}       ${window.workspace}`);
    lines.push(`  ${ANSI.BOLD}Output:${ANSI.RESET}          ${window.output}`);
    lines.push(`  ${ANSI.BOLD}Geometry:${ANSI.RESET}        ${window.geometry?.x || 0}, ${window.geometry?.y || 0} @ ${window.geometry?.width || 0}x${window.geometry?.height || 0}`);
    lines.push("");

    // State
    lines.push(`${ANSI.BOLD}${ANSI.YELLOW}State:${ANSI.RESET}`);
    lines.push(`  ${ANSI.BOLD}Focused:${ANSI.RESET}         ${window.focused ? "✓ Yes" : "○ No"}`);
    lines.push(`  ${ANSI.BOLD}Floating:${ANSI.RESET}        ${window.floating ? "✓ Yes" : "○ No"}`);
    lines.push(`  ${ANSI.BOLD}Hidden:${ANSI.RESET}          ${window.hidden ? "✓ Yes" : "○ No"}`);
    lines.push(`  ${ANSI.BOLD}Fullscreen:${ANSI.RESET}      ${window.fullscreen_mode !== 0 ? "✓ Yes" : "○ No"}`);
    lines.push(`  ${ANSI.BOLD}Sticky:${ANSI.RESET}          ${window.sticky ? "✓ Yes" : "○ No"}`);
    lines.push("");

    // Marks
    if (window.marks && window.marks.length > 0) {
      lines.push(`${ANSI.BOLD}${ANSI.YELLOW}Marks:${ANSI.RESET}`);
      for (const mark of window.marks) {
        lines.push(`  • ${mark}`);
      }
      lines.push("");
    }

    // Window Type
    if (window.window_type) {
      lines.push(`${ANSI.BOLD}${ANSI.YELLOW}Window Type:${ANSI.RESET}`);
      lines.push(`  ${window.window_type}`);
      lines.push("");
    }

    // Raw JSON Data
    lines.push(`${ANSI.BOLD}${ANSI.YELLOW}Raw Window Data (JSON):${ANSI.RESET}`);
    const jsonStr = JSON.stringify(window, null, 2);
    const colorizedJson = this.colorizeJson(jsonStr);
    lines.push(colorizedJson);

    return lines.join("\n");
  }

  /**
   * Render header
   */
  private renderHeader(): string {
    const now = new Date();
    const timeStr = now.toLocaleTimeString();
    const viewMode = this.state.viewMode.toUpperCase();
    const hiddenStatus = this.state.showHidden ? "✓ Show Hidden" : "○ Hide Hidden";

    // Build header with timestamp and status
    const title = `${ANSI.BOLD}${ANSI.CYAN}╔═══ i3pm Live Window Monitor ═══╗${ANSI.RESET}`;
    const timestamp = `${ANSI.DIM}Last update: ${timeStr}${ANSI.RESET}`;
    const status = `View: ${ANSI.BOLD}${ANSI.YELLOW}${viewMode}${ANSI.RESET}  |  ${hiddenStatus}`;

    return `${title}\n${timestamp}  |  ${status}\n${ANSI.DIM}${"─".repeat(100)}${ANSI.RESET}\n\n`;
  }

  /**
   * Render footer
   */
  private renderFooter(): string {
    // Count windows with changes
    let newCount = 0;
    let modifiedCount = 0;

    // Get all windows from outputs
    for (const output of this.state.outputs) {
      for (const workspace of output.workspaces) {
        for (const window of workspace.windows) {
          const change = this.changeTracker.getChange(window.id);
          if (change) {
            if (change.changeType === ChangeType.New) newCount++;
            else if (change.changeType === ChangeType.Modified) modifiedCount++;
          }
        }
      }
    }

    // Build change indicator line
    const changeIndicators = [];
    if (newCount > 0) {
      changeIndicators.push(`${ANSI.GREEN}${ANSI.BOLD}+${newCount} NEW${ANSI.RESET}`);
    }
    if (modifiedCount > 0) {
      changeIndicators.push(`${ANSI.YELLOW}${ANSI.BOLD}~${modifiedCount} CHANGED${ANSI.RESET}`);
    }

    const changeStatus = changeIndicators.length > 0
      ? `  ${changeIndicators.join("  ")}  ${ANSI.DIM}(visible for 5s)${ANSI.RESET}`
      : "";

    // Different keybindings based on view mode
    let keybindings: string;
    if (this.state.viewMode === "inspect") {
      keybindings = `${ANSI.BOLD}Keybindings:${ANSI.RESET} ` +
        `${ANSI.GREEN}[B]${ANSI.RESET} Back  ` +
        `${ANSI.GREEN}[Esc]${ANSI.RESET} Back  ` +
        `${ANSI.GREEN}[Q]${ANSI.RESET} Exit`;
    } else {
      keybindings = `${ANSI.BOLD}Keybindings:${ANSI.RESET} ` +
        `${ANSI.GREEN}[↑/↓]${ANSI.RESET} Navigate  ` +
        `${ANSI.GREEN}[Enter/I]${ANSI.RESET} Inspect  ` +
        `${ANSI.GREEN}[Tab]${ANSI.RESET} View  ` +
        `${ANSI.GREEN}[H]${ANSI.RESET} Hidden  ` +
        `${ANSI.GREEN}[Q]${ANSI.RESET} Exit`;
    }

    return `\n${ANSI.DIM}${"─".repeat(100)}${ANSI.RESET}\n` +
      keybindings +
      `${changeStatus}\n`;
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
