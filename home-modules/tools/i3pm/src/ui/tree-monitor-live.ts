/**
 * Live Event Streaming TUI
 *
 * Full-screen terminal interface for real-time event monitoring.
 * Displays events as they arrive from the daemon with <100ms latency.
 *
 * Based on Feature 065 spec.md User Story 1 and quickstart.md.
 */

import type { Event } from "../models/tree-monitor.ts";
import { TreeMonitorClient } from "../services/tree-monitor-client.ts";
import { formatTimestamp } from "../utils/time-parser.ts";
import {
  formatChanges,
  formatConfidence,
  formatEventType,
  formatTriggeredBy,
  truncate,
  pad,
} from "../utils/formatters.ts";

/**
 * Live TUI state
 */
interface LiveState {
  events: Event[];
  selectedIndex: number;
  scrollOffset: number;
  running: boolean;
  error?: string;
}

/**
 * Terminal dimensions
 */
interface TerminalSize {
  rows: number;
  cols: number;
}

/**
 * Get terminal size
 */
function getTerminalSize(): TerminalSize {
  const { rows, columns } = Deno.consoleSize();
  return { rows: rows || 24, cols: columns || 80 };
}

/**
 * ANSI escape codes
 */
const ANSI = {
  CLEAR_SCREEN: "\x1b[2J",
  CLEAR_LINE: "\x1b[2K",
  CURSOR_HOME: "\x1b[H",
  CURSOR_HIDE: "\x1b[?25l",
  CURSOR_SHOW: "\x1b[?25h",
  RESET: "\x1b[0m",
  BOLD: "\x1b[1m",
  DIM: "\x1b[2m",
  REVERSE: "\x1b[7m",
  SAVE_SCREEN: "\x1b[?1049h",
  RESTORE_SCREEN: "\x1b[?1049l",
};

/**
 * Clear screen and move cursor to home
 */
function clearScreen(): void {
  Deno.stdout.writeSync(new TextEncoder().encode(ANSI.CLEAR_SCREEN + ANSI.CURSOR_HOME));
}

/**
 * Hide cursor
 */
function hideCursor(): void {
  Deno.stdout.writeSync(new TextEncoder().encode(ANSI.CURSOR_HIDE));
}

/**
 * Show cursor
 */
function showCursor(): void {
  Deno.stdout.writeSync(new TextEncoder().encode(ANSI.CURSOR_SHOW));
}

/**
 * Enable alternate screen buffer
 */
function enableAltScreen(): void {
  Deno.stdout.writeSync(new TextEncoder().encode(ANSI.SAVE_SCREEN));
}

/**
 * Disable alternate screen buffer
 */
function disableAltScreen(): void {
  Deno.stdout.writeSync(new TextEncoder().encode(ANSI.RESTORE_SCREEN));
}

/**
 * Render header
 */
function renderHeader(state: LiveState, size: TerminalSize): string {
  const title = `${ANSI.BOLD}i3pm tree-monitor live${ANSI.RESET}`;
  const count = `Events: ${state.events.length}`;
  const help = `q=quit ↑↓=navigate r=refresh Enter=inspect`;

  const padding = " ".repeat(Math.max(0, size.cols - title.length - count.length));
  const header = `${title}${padding}${count}\n`;
  const helpLine = `${ANSI.DIM}${help}${ANSI.RESET}\n`;
  const separator = "─".repeat(size.cols) + "\n";

  return header + helpLine + separator;
}

/**
 * Render event row
 */
function renderEventRow(
  event: Event,
  selected: boolean,
  size: TerminalSize,
): string {
  const timeWidth = 12; // HH:MM:SS.mmm
  const typeWidth = 25;
  const changesWidth = 20;
  const triggeredWidth = 30;
  const confWidth = 3;

  // Format fields
  const time = pad(formatTimestamp(event.timestamp, "time"), timeWidth);
  const type = pad(truncate(event.type, typeWidth), typeWidth);
  const changes = pad(formatChanges(event), changesWidth);
  const triggered = pad(truncate(formatTriggeredBy(event), triggeredWidth), triggeredWidth);
  const confidence = pad(formatConfidence(event), confWidth);

  // Build row
  let row = `${time} ${formatEventType(type)} ${changes} ${triggered} ${confidence}`;

  // Truncate to terminal width
  row = truncate(row, size.cols);

  // Apply selection highlight
  if (selected) {
    row = `${ANSI.REVERSE}${row}${ANSI.RESET}`;
  }

  return row + "\n";
}

/**
 * Render event list
 */
function renderEventList(state: LiveState, size: TerminalSize): string {
  const headerHeight = 3; // title + help + separator
  const footerHeight = 1;
  const availableRows = size.rows - headerHeight - footerHeight;

  if (state.events.length === 0) {
    return `${ANSI.DIM}No events yet... waiting for daemon${ANSI.RESET}\n`;
  }

  // Adjust scroll offset to keep selection in view
  const { selectedIndex, scrollOffset } = state;
  let newScrollOffset = scrollOffset;

  if (selectedIndex < scrollOffset) {
    newScrollOffset = selectedIndex;
  } else if (selectedIndex >= scrollOffset + availableRows) {
    newScrollOffset = selectedIndex - availableRows + 1;
  }

  state.scrollOffset = newScrollOffset;

  // Render visible rows
  let output = "";
  const visibleEvents = state.events.slice(
    newScrollOffset,
    newScrollOffset + availableRows,
  );

  for (let i = 0; i < visibleEvents.length; i++) {
    const event = visibleEvents[i];
    const globalIndex = newScrollOffset + i;
    const selected = globalIndex === selectedIndex;
    output += renderEventRow(event, selected, size);
  }

  return output;
}

/**
 * Render footer
 */
function renderFooter(state: LiveState): string {
  if (state.error) {
    return `${ANSI.BOLD}\x1b[31mError: ${state.error}${ANSI.RESET}`;
  }

  const status = `${ANSI.DIM}Live monitoring... (${state.events.length} events)${ANSI.RESET}`;
  return status;
}

/**
 * Render full UI
 */
function render(state: LiveState): void {
  const size = getTerminalSize();

  clearScreen();

  let output = "";
  output += renderHeader(state, size);
  output += renderEventList(state, size);
  output += renderFooter(state);

  Deno.stdout.writeSync(new TextEncoder().encode(output));
}

/**
 * Handle keyboard input
 */
async function handleInput(client: TreeMonitorClient, state: LiveState): Promise<void> {
  const buf = new Uint8Array(8);

  // Set stdin to raw mode
  Deno.stdin.setRaw(true);

  while (state.running) {
    const n = await Deno.stdin.read(buf);
    if (n === null) break;

    const key = buf.subarray(0, n);

    // q - quit
    if (key[0] === 113) {
      state.running = false;
      break;
    }

    // r - refresh
    if (key[0] === 114) {
      render(state);
    }

    // Arrow up
    if (key[0] === 27 && key[1] === 91 && key[2] === 65) {
      if (state.selectedIndex > 0) {
        state.selectedIndex--;
        render(state);
      }
    }

    // Arrow down
    if (key[0] === 27 && key[1] === 91 && key[2] === 66) {
      if (state.selectedIndex < state.events.length - 1) {
        state.selectedIndex++;
        render(state);
      }
    }

    // Enter - inspect
    if (key[0] === 13) {
      if (state.selectedIndex >= 0 && state.selectedIndex < state.events.length) {
        const event = state.events[state.selectedIndex];

        try {
          // Show detail view (blocking)
          await showEventDetail(client, event.id);
        } catch (err) {
          // If detail view fails, show error briefly
          state.error = err instanceof Error ? err.message : String(err);
          render(state);
          await new Promise((resolve) => setTimeout(resolve, 2000));
          state.error = undefined;
        }

        // Resume live view
        render(state);
      }
    }
  }

  // Restore stdin to normal mode
  Deno.stdin.setRaw(false);
}

/**
 * Show event detail view
 */
async function showEventDetail(
  client: TreeMonitorClient,
  eventId: string,
): Promise<void> {
  // Import detail view renderer
  const { renderEventDetail } = await import("./tree-monitor-detail.ts");

  // Fetch event details
  const event = await client.getEvent(eventId);

  // Clear screen and render detail view
  clearScreen();
  Deno.stdout.writeSync(new TextEncoder().encode(renderEventDetail(event)));
  Deno.stdout.writeSync(new TextEncoder().encode("\n\nPress 'b' to return to live view, 'q' to quit...\n"));

  // Wait for 'b' or 'q' key
  await waitForExitKey();
}

/**
 * Wait for exit key ('b' or 'q')
 */
function waitForExitKey(): Promise<void> {
  return new Promise((resolve) => {
    const buf = new Uint8Array(8);

    const readKey = async () => {
      const n = await Deno.stdin.read(buf);
      if (n === null) {
        resolve();
        return;
      }

      const key = buf.subarray(0, n);
      // 'b' or 'q' key
      if (key[0] === 98 || key[0] === 113) {
        resolve();
      } else {
        // Continue waiting for valid key
        readKey();
      }
    };

    readKey();
  });
}

/**
 * Stream events from daemon
 */
async function streamEvents(
  client: TreeMonitorClient,
  state: LiveState,
): Promise<void> {
  let lastEventId: string | undefined;

  while (state.running) {
    try {
      // Query new events since last ID
      const params: Record<string, string | number> = { last: 100 };
      if (lastEventId) {
        params.since_id = lastEventId;
      }

      const response = await client.queryEvents(params);

      if (response && response.length > 0) {
        // Add new events
        for (const event of response) {
          state.events.push(event);
          lastEventId = event.id;
        }

        // Limit buffer to 500 events (match daemon buffer size)
        if (state.events.length > 500) {
          state.events = state.events.slice(-500);
          // Adjust selection if needed
          if (state.selectedIndex >= state.events.length) {
            state.selectedIndex = state.events.length - 1;
          }
        }

        // Re-render with new events
        render(state);
      }
    } catch (err) {
      state.error = err instanceof Error ? err.message : String(err);
      render(state);
    }

    // Poll every 100ms for <100ms latency requirement
    await new Promise((resolve) => setTimeout(resolve, 100));
  }
}

/**
 * Main live TUI entry point
 */
export async function runLiveTUI(socketPath: string): Promise<void> {
  const client = new TreeMonitorClient(socketPath);

  // Initialize state
  const state: LiveState = {
    events: [],
    selectedIndex: 0,
    scrollOffset: 0,
    running: true,
  };

  // Setup terminal
  enableAltScreen();
  hideCursor();

  // Cleanup on exit
  const cleanup = () => {
    showCursor();
    disableAltScreen();
    Deno.stdin.setRaw(false);
  };

  // Handle Ctrl+C
  const signalHandler = () => {
    state.running = false;
    cleanup();
    Deno.exit(0);
  };

  Deno.addSignalListener("SIGINT", signalHandler);

  try {
    // Connect to daemon
    await client.connect();

    // Test connection
    await client.ping();

    // Initial render
    render(state);

    // Start input handler and event stream
    await Promise.race([
      handleInput(client, state),
      streamEvents(client, state),
    ]);
  } catch (err) {
    cleanup();
    console.error(`Error: ${err instanceof Error ? err.message : String(err)}`);
    Deno.exit(1);
  } finally {
    cleanup();
    Deno.removeSignalListener("SIGINT", signalHandler);
  }
}
