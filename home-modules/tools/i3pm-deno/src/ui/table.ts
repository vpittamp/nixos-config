/**
 * Table View Formatter for Window State
 *
 * Renders window state as sortable table with all properties.
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
  { header: "Class", width: 20, align: "left" },
  { header: "Title", width: 40, align: "left" },
  { header: "WS", width: 4, align: "left" },
  { header: "Output", width: 12, align: "left" },
  { header: "Project", width: 12, align: "left" },
  { header: "Status", width: 10, align: "left" },
];

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
 * Format window as table row
 */
function formatRow(window: WindowState): string {
  const project = getProjectFromMarks(window.marks) || "-";
  const status = getStatusIndicators(window);

  const cells = [
    padString(window.id.toString(), COLUMNS[0].width, COLUMNS[0].align),
    padString(window.class, COLUMNS[1].width, COLUMNS[1].align),
    padString(window.title, COLUMNS[2].width, COLUMNS[2].align),
    padString(window.workspace, COLUMNS[3].width, COLUMNS[3].align),
    padString(window.output, COLUMNS[4].width, COLUMNS[4].align),
    padString(project, COLUMNS[5].width, COLUMNS[5].align),
    padString(status, COLUMNS[6].width, COLUMNS[6].align),
  ];

  return cells.join(" | ");
}

/**
 * Render outputs as table view
 */
export function renderTable(
  outputs: Output[],
  options: { showHidden?: boolean } = {},
): string {
  const { showHidden = false } = options;

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
    lines.push(formatRow(window));
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
  ${STATUS_ICONS.focused} Focused window
  ${STATUS_ICONS.scoped} Scoped to project
  ${STATUS_ICONS.hidden} Hidden (inactive project)
  ${STATUS_ICONS.floating} Floating window
`;
}
