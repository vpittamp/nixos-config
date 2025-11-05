/**
 * Tree View Formatter for Window State
 *
 * Renders hierarchical window state: outputs → workspaces → windows
 * with visual indicators and project tags.
 */

import type { Output, Workspace, WindowState } from "../models.ts";

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
 * Handles multiple mark formats:
 * - "project:name" or "project:name:id" (scratchpad windows)
 * - "scoped:name:id" (scoped visible windows)
 * - "global:name:id" (global visible windows, but we ignore these)
 */
function getProjectFromMarks(marks: string[]): string | null {
  for (const mark of marks) {
    if (mark.startsWith("project:")) {
      // Format: "project:name" or "project:name:id"
      const parts = mark.split(":");
      return parts[1] || null;
    } else if (mark.startsWith("scoped:")) {
      // Format: "scoped:name:id"
      const parts = mark.split(":");
      return parts[1] || null;
    }
    // Skip "global:" marks - those are truly global windows
  }
  return null;
}

/**
 * Format window as tree node (output/workspace hierarchy)
 */
function formatWindow(window: WindowState, indent: string): string {
  const indicators: string[] = [];

  // Focus indicator
  if (window.focused) {
    indicators.push(STATUS_ICONS.focused);
  }

  // Scoped indicator (has project mark)
  const project = getProjectFromMarks(window.marks);
  if (project) {
    indicators.push(STATUS_ICONS.scoped);
  }

  // Hidden indicator
  if (window.hidden) {
    indicators.push(STATUS_ICONS.hidden);
  }

  // Floating indicator
  if (window.floating) {
    indicators.push(STATUS_ICONS.floating);
  }

  // Build status string
  const status = indicators.length > 0 ? ` ${indicators.join("")}` : "";

  // Build project tag
  const projectTag = project ? ` [${project}]` : "";

  // Build PID tag
  const pidTag = window.pid ? ` (PID: ${window.pid})` : "";

  // Truncate long titles
  const maxTitleLength = 60;
  let title = window.title;
  if (title.length > maxTitleLength) {
    title = title.substring(0, maxTitleLength - 3) + "...";
  }

  return `${indent}${window.class} - ${title}${pidTag}${projectTag}${status}`;
}

/**
 * Format window for project-centric view (shows location as attributes)
 */
function formatWindowByProject(window: WindowState, indent: string): string {
  const indicators: string[] = [];

  // Focus indicator
  if (window.focused) {
    indicators.push(STATUS_ICONS.focused);
  }

  // Hidden indicator
  if (window.hidden) {
    indicators.push(STATUS_ICONS.hidden);
  }

  // Floating indicator
  if (window.floating) {
    indicators.push(STATUS_ICONS.floating);
  }

  // Build status string
  const status = indicators.length > 0 ? ` ${indicators.join("")}` : "";

  // Build location info (workspace and output)
  const location = `${window.workspace} @ ${window.output}`;

  // Build PID tag
  const pidTag = window.pid ? ` (PID: ${window.pid})` : "";

  // Truncate long titles
  const maxTitleLength = 50;
  let title = window.title;
  if (title.length > maxTitleLength) {
    title = title.substring(0, maxTitleLength - 3) + "...";
  }

  return `${indent}${window.class} - ${title}${pidTag} | ${location}${status}`;
}

/**
 * Format workspace as tree node
 */
function formatWorkspace(
  workspace: Workspace,
  indent: string,
  showHidden: boolean,
): string[] {
  const lines: string[] = [];

  // Workspace header
  const focusMarker = workspace.focused ? " (focused)" : "";
  const visibleMarker = workspace.visible ? " (visible)" : "";
  lines.push(`${indent}Workspace ${workspace.name}${focusMarker}${visibleMarker}`);

  // Filter windows if not showing hidden
  const windows = showHidden
    ? workspace.windows
    : workspace.windows.filter((w) => !w.hidden);

  // Render windows
  if (windows.length === 0) {
    lines.push(`${indent}  (no windows)`);
  } else {
    for (const window of windows) {
      lines.push(formatWindow(window, `${indent}  `));
    }
  }

  return lines;
}

/**
 * Format output (monitor) as tree node
 */
function formatOutput(output: Output, showHidden: boolean): string[] {
  const lines: string[] = [];

  // Output header with icon
  const primaryMarker = output.primary ? ", primary" : "";
  const activeMarker = output.active ? "" : " (inactive)";
  lines.push(
    `📺 ${output.name} (${output.geometry.width}x${output.geometry.height}${primaryMarker})${activeMarker}`,
  );

  // Render workspaces
  for (const workspace of output.workspaces) {
    const workspaceLines = formatWorkspace(workspace, "  ", showHidden);
    lines.push(...workspaceLines);
  }

  return lines;
}

/**
 * Render outputs as tree view
 */
export function renderTree(
  outputs: Output[],
  options: { showHidden?: boolean } = {},
): string {
  const { showHidden = true } = options; // Changed default to true: always show all windows including scratchpad

  if (outputs.length === 0) {
    return "No outputs found";
  }

  const lines: string[] = [];

  // Count total windows
  let totalWindows = 0;
  let visibleWindows = 0;
  for (const output of outputs) {
    for (const workspace of output.workspaces) {
      totalWindows += workspace.windows.length;
      visibleWindows += workspace.windows.filter((w) => !w.hidden).length;
    }
  }

  // Render each output
  for (const output of outputs) {
    lines.push(...formatOutput(output, showHidden));
    lines.push(""); // Blank line between outputs
  }

  // Add summary footer
  const hiddenCount = totalWindows - visibleWindows;
  const summary = showHidden
    ? (hiddenCount > 0
      ? `Total: ${totalWindows} windows (${visibleWindows} visible, ${hiddenCount} in scratchpad)`
      : `Total: ${totalWindows} windows (all visible)`)
    : `Total: ${visibleWindows} windows visible (${hiddenCount} in scratchpad, use --hidden to show)`;
  lines.push(summary);

  return lines.join("\n");
}

/**
 * Render outputs as project-centric tree view
 * Groups windows by project instead of by output/workspace
 */
export function renderTreeByProject(
  outputs: Output[],
  options: { showHidden?: boolean } = {},
): string {
  const { showHidden = true } = options;

  if (outputs.length === 0) {
    return "No outputs found";
  }

  const lines: string[] = [];

  // Collect all windows from all outputs/workspaces
  const allWindows: WindowState[] = [];
  for (const output of outputs) {
    for (const workspace of output.workspaces) {
      const windows = showHidden
        ? workspace.windows
        : workspace.windows.filter((w) => !w.hidden);
      allWindows.push(...windows);
    }
  }

  // Group windows by project
  const projectGroups = new Map<string, WindowState[]>();
  const globalWindows: WindowState[] = [];

  for (const window of allWindows) {
    const project = getProjectFromMarks(window.marks);
    if (project) {
      if (!projectGroups.has(project)) {
        projectGroups.set(project, []);
      }
      projectGroups.get(project)!.push(window);
    } else {
      globalWindows.push(window);
    }
  }

  // Count totals
  let totalWindows = allWindows.length;
  let visibleWindows = allWindows.filter((w) => !w.hidden).length;

  // Render project groups (sorted alphabetically)
  const sortedProjects = Array.from(projectGroups.keys()).sort();

  for (const projectName of sortedProjects) {
    const windows = projectGroups.get(projectName)!;
    const visibleCount = windows.filter(w => !w.hidden).length;
    const hiddenCount = windows.filter(w => w.hidden).length;

    const countStr = hiddenCount > 0
      ? ` (${visibleCount} visible, ${hiddenCount} hidden)`
      : ` (${windows.length} windows)`;

    lines.push(`📦 ${projectName}${countStr}`);

    for (const window of windows) {
      lines.push(formatWindowByProject(window, "  "));
    }
    lines.push(""); // Blank line between projects
  }

  // Render global/unassigned windows
  if (globalWindows.length > 0) {
    lines.push(`🌐 Global (${globalWindows.length} windows)`);
    for (const window of globalWindows) {
      lines.push(formatWindowByProject(window, "  "));
    }
    lines.push("");
  }

  // Add summary footer
  const hiddenCount = totalWindows - visibleWindows;
  const summary = hiddenCount > 0
    ? `Total: ${totalWindows} windows (${visibleWindows} visible, ${hiddenCount} in scratchpad)`
    : `Total: ${totalWindows} windows (all visible)`;
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
  [project] Project name
`;
}
