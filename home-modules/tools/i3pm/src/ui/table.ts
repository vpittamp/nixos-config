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
  flexible?: boolean; // Can shrink when terminal is narrow
}

const COLUMNS: Column[] = [
  { header: "ID", width: 6, align: "right" },
  { header: "PID", width: 7, align: "right" },
  { header: "App", width: 18, align: "left", flexible: true },
  { header: "Title", width: 30, align: "left", flexible: true },
  { header: "WS", width: 8, align: "left" },
  { header: "Output", width: 11, align: "left" },
  { header: "Project", width: 14, align: "left" },
  { header: "Status", width: 8, align: "left" },
  { header: "Change", width: 6, align: "left" },
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
 * Change indicators with ANSI colors and bold
 */
const CHANGE_INDICATORS = {
  [ChangeType.New]: { symbol: "+NEW", color: "\x1b[1m\x1b[32m" },      // Bold Green
  [ChangeType.Modified]: { symbol: "~MOD", color: "\x1b[1m\x1b[33m" }, // Bold Yellow
  [ChangeType.Removed]: { symbol: "✗DEL", color: "\x1b[1m\x1b[31m" },  // Bold Red
  [ChangeType.None]: { symbol: "", color: "" },
} as const;

/**
 * ANSI reset code
 */
const ANSI_RESET = "\x1b[0m";

/**
 * Project icon cache
 */
const projectIconCache = new Map<string, string>();

/**
 * Extract project name from window marks (just the name, no ID)
 */
function getProjectFromMarks(marks: string[]): string | null {
  for (const mark of marks) {
    if (mark.startsWith("project:")) {
      // Extract just the project name from "project:name:id" format
      const parts = mark.split(":");
      const projectName = parts[1] || null;
      return projectName === "none" ? null : projectName;
    }
    // Feature 062/063: Scratchpad terminals have marks like "scratchpad:projectname"
    if (mark.startsWith("scratchpad:")) {
      const projectName = mark.substring(11); // Remove "scratchpad:" prefix
      return projectName === "global" ? null : projectName;
    }
  }
  return null;
}

/**
 * Get project icon from cache or load it
 */
async function getProjectIcon(projectName: string): Promise<string> {
  if (projectIconCache.has(projectName)) {
    return projectIconCache.get(projectName)!;
  }

  try {
    const homeDir = Deno.env.get("HOME");
    if (!homeDir) return "";

    const projectPath = `${homeDir}/.config/i3/projects/${projectName}.json`;
    const content = await Deno.readTextFile(projectPath);
    const project = JSON.parse(content);
    const icon = project.icon || "";
    projectIconCache.set(projectName, icon);
    return icon;
  } catch {
    projectIconCache.set(projectName, "");
    return "";
  }
}

/**
 * Detect if window is a scratchpad
 */
function isScratchpadWindow(window: WindowState): boolean {
  return window.marks.some(m => m.startsWith("scratchpad:"));
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
async function formatRow(window: WindowState, change?: WindowChange, selected: boolean = false): Promise<string> {
  const projectName = getProjectFromMarks(window.marks);
  const projectIcon = projectName ? await getProjectIcon(projectName) : "";
  const projectDisplay = projectName
    ? `${projectIcon}${projectIcon ? " " : ""}${projectName}`
    : isScratchpadWindow(window) ? "📋 scratch" : "-";

  const status = getStatusIndicators(window);
  const changeIndicator = getChangeIndicator(change);
  const pid = window.pid ? window.pid.toString() : "-";
  const app = window.app_id || window.class;

  // Better workspace display: show full name or abbreviation
  let ws = window.workspace;
  if (ws.startsWith("__i3_scratch")) {
    ws = "scratch";
  } else if (ws.length > COLUMNS[4].width) {
    ws = ws.substring(0, COLUMNS[4].width - 1) + "…";
  }

  const cells = [
    padString(window.id.toString(), COLUMNS[0].width, COLUMNS[0].align),
    padString(pid, COLUMNS[1].width, COLUMNS[1].align),
    padString(app, COLUMNS[2].width, COLUMNS[2].align),
    padString(window.title, COLUMNS[3].width, COLUMNS[3].align),
    padString(ws, COLUMNS[4].width, COLUMNS[4].align),
    padString(window.output, COLUMNS[5].width, COLUMNS[5].align),
    padString(projectDisplay, COLUMNS[6].width, COLUMNS[6].align),
    padString(status, COLUMNS[7].width, COLUMNS[7].align),
    padString(changeIndicator, COLUMNS[8].width, COLUMNS[8].align),
  ];

  const row = cells.join(" | ");

  // Highlight selected row with background color and bold
  if (selected) {
    return `\x1b[7m\x1b[1m${row}\x1b[0m`; // Inverse video (highlighted) + bold
  }

  return row;
}

/**
 * Render outputs as table view
 */
export async function renderTable(
  outputs: Output[],
  options: { showHidden?: boolean; changeTracker?: ChangeTracker; groupByProject?: boolean; selectedWindowId?: number | null } = {},
): Promise<string> {
  const { showHidden = true, changeTracker, groupByProject = true, selectedWindowId = null } = options;

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

  // Build table
  const lines: string[] = [];

  if (groupByProject) {
    // Group windows by project
    const byProject = new Map<string, WindowState[]>();
    const scratchpadWindows: WindowState[] = [];
    const globalWindows: WindowState[] = [];

    for (const window of allWindows) {
      const projectName = getProjectFromMarks(window.marks);
      if (isScratchpadWindow(window)) {
        scratchpadWindows.push(window);
      } else if (projectName) {
        if (!byProject.has(projectName)) {
          byProject.set(projectName, []);
        }
        byProject.get(projectName)!.push(window);
      } else {
        globalWindows.push(window);
      }
    }

    // Sort projects alphabetically
    const sortedProjects = Array.from(byProject.keys()).sort();

    // Render each project group
    for (const projectName of sortedProjects) {
      const windows = byProject.get(projectName)!;
      const icon = await getProjectIcon(projectName);

      lines.push("");
      lines.push(`\x1b[1m\x1b[36m${icon}${icon ? " " : ""}${projectName}\x1b[0m (${windows.length} windows)`);
      lines.push(formatHeader());

      for (const window of windows) {
        const change = changeTracker?.getChange(window.id);
        const isSelected = selectedWindowId !== null && window.id === selectedWindowId;
        lines.push(await formatRow(window, change, isSelected));
      }
    }

    // Render scratchpad group
    if (scratchpadWindows.length > 0) {
      lines.push("");
      lines.push(`\x1b[1m\x1b[35m📋 Scratchpad\x1b[0m (${scratchpadWindows.length} windows)`);
      lines.push(formatHeader());

      for (const window of scratchpadWindows) {
        const change = changeTracker?.getChange(window.id);
        const isSelected = selectedWindowId !== null && window.id === selectedWindowId;
        lines.push(await formatRow(window, change, isSelected));
      }
    }

    // Render global windows
    if (globalWindows.length > 0) {
      lines.push("");
      lines.push(`\x1b[1m\x1b[90mGlobal\x1b[0m (${globalWindows.length} windows)`);
      lines.push(formatHeader());

      for (const window of globalWindows) {
        const change = changeTracker?.getChange(window.id);
        const isSelected = selectedWindowId !== null && window.id === selectedWindowId;
        lines.push(await formatRow(window, change, isSelected));
      }
    }
  } else {
    // Single table, sorted by output/workspace
    allWindows.sort((a, b) => {
      if (a.output !== b.output) return a.output.localeCompare(b.output);
      if (a.workspace !== b.workspace) return a.workspace.localeCompare(b.workspace);
      if (a.focused !== b.focused) return a.focused ? -1 : 1;
      return 0;
    });

    lines.push(formatHeader());

    for (const window of allWindows) {
      const change = changeTracker?.getChange(window.id);
      const isSelected = selectedWindowId !== null && window.id === selectedWindowId;
      lines.push(await formatRow(window, change, isSelected));
    }
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
