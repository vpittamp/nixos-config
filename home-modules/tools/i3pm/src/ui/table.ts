/**
 * Table View Formatter for Window State
 *
 * Renders window state as sortable table with all properties.
 * Supports change tracking for real-time updates.
 */

import { unicodeWidth } from "@std/cli/unicode-width";
import type { Output, WindowState } from "../models.ts";

/**
 * Table column definitions
 */
interface Column {
  header: string;
  width: number;
  align: "left" | "right";
}

const COLUMNS: Column[] = [
  { header: "ID", width: 16, align: "right" },
  { header: "PID", width: 8, align: "right" },
  { header: "APP_ID", width: 25, align: "left" },
  { header: "Class", width: 18, align: "left" },
  { header: "Title", width: 35, align: "left" },
  { header: "WS", width: 4, align: "left" },
  { header: "Output", width: 12, align: "left" },
  { header: "Project", width: 12, align: "left" },
  { header: "Status", width: 10, align: "left" },
  { header: "Change", width: 7, align: "left" },
];

/**
 * Change types for windows
 */
export enum ChangeType {
  None = "none",
  New = "new",
  Modified = "modified",
  Removed = "removed",
}

/**
 * Window change tracking
 */
export interface WindowChange {
  id: number;
  changeType: ChangeType;
  timestamp: number;
  previousState?: Partial<WindowState>;
}

/**
 * Change tracker for table rendering
 */
export class ChangeTracker {
  private changes: Map<number, WindowChange> = new Map();
  private previousWindows: Map<number, WindowState> = new Map();
  private changeExpiryMs: number;

  constructor(changeExpiryMs: number = 3000) {
    this.changeExpiryMs = changeExpiryMs;
  }

  /**
   * Update with new window state and track changes
   */
  updateWindows(windows: WindowState[]): void {
    const now = Date.now();
    const currentIds = new Set(windows.map((w) => w.id));
    const previousIds = new Set(this.previousWindows.keys());

    // Track new windows
    for (const window of windows) {
      if (!previousIds.has(window.id)) {
        this.changes.set(window.id, {
          id: window.id,
          changeType: ChangeType.New,
          timestamp: now,
        });
      } else {
        // Check for modifications
        const prev = this.previousWindows.get(window.id)!;
        if (this.hasChanged(prev, window)) {
          this.changes.set(window.id, {
            id: window.id,
            changeType: ChangeType.Modified,
            timestamp: now,
            previousState: {
              title: prev.title,
              workspace: prev.workspace,
              output: prev.output,
              focused: prev.focused,
            },
          });
        }
      }
    }

    // Track removed windows (keep for a bit to show they were removed)
    for (const prevId of previousIds) {
      if (!currentIds.has(prevId)) {
        this.changes.set(prevId, {
          id: prevId,
          changeType: ChangeType.Removed,
          timestamp: now,
          previousState: this.previousWindows.get(prevId),
        });
      }
    }

    // Update previous state
    this.previousWindows.clear();
    for (const window of windows) {
      this.previousWindows.set(window.id, { ...window });
    }

    // Clean up expired changes
    this.cleanupExpiredChanges(now);
  }

  /**
   * Check if window has meaningfully changed
   */
  private hasChanged(prev: WindowState, current: WindowState): boolean {
    return (
      prev.title !== current.title ||
      prev.workspace !== current.workspace ||
      prev.output !== current.output ||
      prev.focused !== current.focused ||
      prev.floating !== current.floating ||
      JSON.stringify(prev.marks) !== JSON.stringify(current.marks)
    );
  }

  /**
   * Get change for a window ID
   */
  getChange(windowId: number): WindowChange | undefined {
    return this.changes.get(windowId);
  }

  /**
   * Clean up changes older than expiry time
   */
  private cleanupExpiredChanges(now: number): void {
    for (const [id, change] of this.changes.entries()) {
      if (now - change.timestamp > this.changeExpiryMs) {
        this.changes.delete(id);
      }
    }
  }

  /**
   * Clear all tracked changes
   */
  clear(): void {
    this.changes.clear();
    this.previousWindows.clear();
  }
}

/**
 * Status icons for windows
 */
const STATUS_ICONS = {
  focused: "●",
  scoped: "🔸",
  hidden: "🔒",
  floating: "⬜",
} as const;

/**
 * Change indicators with ANSI colors
 */
const CHANGE_INDICATORS = {
  [ChangeType.New]: { symbol: "NEW", color: "\x1b[32m" },      // Green
  [ChangeType.Modified]: { symbol: "MOD", color: "\x1b[33m" }, // Yellow
  [ChangeType.Removed]: { symbol: "DEL", color: "\x1b[31m" },  // Red
  [ChangeType.None]: { symbol: "", color: "" },
} as const;

/**
 * ANSI reset code
 */
const ANSI_RESET = "\x1b[0m";

/**
 * Extract project name from window marks
 */
function getProjectFromMarks(marks: string[]): string | null {
  for (const mark of marks) {
    if (mark.startsWith("project:")) {
      return mark.substring(8); // Remove "project:" prefix
    }
  }
  return null;
}

/**
 * Get status indicators for a window
 */
function getStatusIndicators(window: WindowState): string {
  const indicators: string[] = [];

  if (window.focused) indicators.push(STATUS_ICONS.focused);
  if (getProjectFromMarks(window.marks)) indicators.push(STATUS_ICONS.scoped);
  if (window.hidden) indicators.push(STATUS_ICONS.hidden);
  if (window.floating) indicators.push(STATUS_ICONS.floating);

  return indicators.join("");
}

/**
 * Pad string to target width (accounting for Unicode width)
 */
function padString(
  text: string,
  width: number,
  align: "left" | "right",
): string {
  const textWidth = unicodeWidth(text);

  if (textWidth >= width) {
    // Truncate if too long
    return truncateToWidth(text, width);
  }

  const padding = " ".repeat(width - textWidth);
  return align === "left" ? text + padding : padding + text;
}

/**
 * Truncate string to target display width
 */
function truncateToWidth(text: string, maxWidth: number): string {
  if (unicodeWidth(text) <= maxWidth) {
    return text;
  }

  // Binary search for truncation point
  let left = 0;
  let right = text.length;

  while (left < right) {
    const mid = Math.floor((left + right + 1) / 2);
    const substr = text.substring(0, mid);
    const width = unicodeWidth(substr);

    if (width <= maxWidth - 3) {
      // Reserve 3 chars for "..."
      left = mid;
    } else {
      right = mid - 1;
    }
  }

  return text.substring(0, left) + "...";
}

/**
 * Format table header
 */
function formatHeader(): string {
  const headers = COLUMNS.map((col) => padString(col.header, col.width, col.align));
  const separator = COLUMNS.map((col) => "-".repeat(col.width)).join("-+-");

  return [
    headers.join(" | "),
    separator,
  ].join("\n");
}

/**
 * Get change indicator for a window
 */
function getChangeIndicator(change?: WindowChange): string {
  if (!change || change.changeType === ChangeType.None) {
    return "";
  }

  const indicator = CHANGE_INDICATORS[change.changeType];
  return `${indicator.color}${indicator.symbol}${ANSI_RESET}`;
}

/**
 * Format window as table row
 */
function formatRow(window: WindowState, change?: WindowChange): string {
  const project = getProjectFromMarks(window.marks) || "-";
  const status = getStatusIndicators(window);
  const changeIndicator = getChangeIndicator(change);
  const pid = window.pid ? window.pid.toString() : "-";
  const appId = window.app_id || "-";

  const cells = [
    padString(window.id.toString(), COLUMNS[0].width, COLUMNS[0].align),
    padString(pid, COLUMNS[1].width, COLUMNS[1].align),
    padString(appId, COLUMNS[2].width, COLUMNS[2].align),
    padString(window.class, COLUMNS[3].width, COLUMNS[3].align),
    padString(window.title, COLUMNS[4].width, COLUMNS[4].align),
    padString(window.workspace, COLUMNS[5].width, COLUMNS[5].align),
    padString(window.output, COLUMNS[6].width, COLUMNS[6].align),
    padString(project, COLUMNS[7].width, COLUMNS[7].align),
    padString(status, COLUMNS[8].width, COLUMNS[8].align),
    padString(changeIndicator, COLUMNS[9].width, COLUMNS[9].align),
  ];

  return cells.join(" | ");
}

/**
 * Render outputs as table view
 */
export function renderTable(
  outputs: Output[],
  options: { showHidden?: boolean; changeTracker?: ChangeTracker } = {},
): string {
  const { showHidden = false, changeTracker } = options;

  if (outputs.length === 0) {
    return "No windows found";
  }

  // Collect all windows from all outputs/workspaces
  const allWindows: WindowState[] = [];
  for (const output of outputs) {
    for (const workspace of output.workspaces) {
      for (const window of workspace.windows) {
        if (showHidden || !window.hidden) {
          allWindows.push(window);
        }
      }
    }
  }

  // Update change tracker if provided
  if (changeTracker) {
    changeTracker.updateWindows(allWindows);
  }

  if (allWindows.length === 0) {
    return "No visible windows (use --hidden to show hidden windows)";
  }

  // Sort windows by output, then workspace, then focus
  allWindows.sort((a, b) => {
    if (a.output !== b.output) return a.output.localeCompare(b.output);
    if (a.workspace !== b.workspace) return a.workspace.localeCompare(b.workspace);
    if (a.focused !== b.focused) return a.focused ? -1 : 1;
    return 0;
  });

  // Build table
  const lines: string[] = [];
  lines.push(formatHeader());

  for (const window of allWindows) {
    const change = changeTracker?.getChange(window.id);
    lines.push(formatRow(window, change));
  }

  // Add summary
  const totalWindows = outputs.reduce((sum, output) =>
    sum + output.workspaces.reduce((wsSum, ws) => wsSum + ws.windows.length, 0), 0
  );
  const hiddenCount = totalWindows - allWindows.length;

  lines.push("");
  const summary = showHidden
    ? `Total: ${allWindows.length} windows (${hiddenCount} hidden)`
    : `Total: ${allWindows.length} windows visible (${hiddenCount} hidden, use --hidden to show)`;
  lines.push(summary);

  return lines.join("\n");
}

/**
 * Render legend for status indicators
 */
export function renderLegend(): string {
  return `
Legend:
  Status Indicators:
    ${STATUS_ICONS.focused} Focused window
    ${STATUS_ICONS.scoped} Scoped to project
    ${STATUS_ICONS.hidden} Hidden (inactive project)
    ${STATUS_ICONS.floating} Floating window

  Change Indicators (live mode only):
    ${CHANGE_INDICATORS[ChangeType.New].color}${CHANGE_INDICATORS[ChangeType.New].symbol}${ANSI_RESET} New window (recently opened)
    ${CHANGE_INDICATORS[ChangeType.Modified].color}${CHANGE_INDICATORS[ChangeType.Modified].symbol}${ANSI_RESET} Modified window (title/workspace/focus changed)
    ${CHANGE_INDICATORS[ChangeType.Removed].color}${CHANGE_INDICATORS[ChangeType.Removed].symbol}${ANSI_RESET} Removed window (recently closed)
`;
}
