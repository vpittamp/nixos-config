/**
 * Formatting Utilities
 *
 * Formatters for tree-monitor output: confidence indicators, significance labels, etc.
 * Based on Feature 065 data-model.md and quickstart.md.
 */

import type { Event } from "../models/tree-monitor.ts";
import { getConfidenceIndicator, getSignificanceLabel } from "../models/tree-monitor.ts";

/**
 * Format event changes summary
 *
 * @param event - Event object
 * @returns Formatted string (e.g., "3 changes (critical)")
 */
export function formatChanges(event: Event): string {
  const label = getSignificanceLabel(event.significance);
  return `${event.change_count} changes (${label})`;
}

/**
 * Format correlation trigger summary
 *
 * @param event - Event object
 * @returns Formatted string or "(no correlation)" if missing
 */
export function formatTriggeredBy(event: Event): string {
  if (!event.correlation) {
    return "(no correlation)";
  }

  const { action_type, binding_command } = event.correlation;

  if (action_type === "binding" && binding_command) {
    return `Binding: ${binding_command}`;
  } else if (action_type === "mouse_click") {
    return "Mouse Click";
  } else if (action_type === "external_command") {
    return "External Command";
  } else {
    return action_type;
  }
}

/**
 * Format confidence indicator
 *
 * @param event - Event object
 * @returns Emoji indicator or "—" if no correlation
 */
export function formatConfidence(event: Event): string {
  if (!event.correlation) {
    return "—";
  }

  return getConfidenceIndicator(event.correlation.confidence);
}

/**
 * Format confidence with percentage
 *
 * @param confidence - Confidence score (0.0-1.0)
 * @returns Formatted string (e.g., "🟢 95%")
 */
export function formatConfidenceWithPercentage(confidence: number): string {
  const indicator = getConfidenceIndicator(confidence);
  const percentage = Math.round(confidence * 100);
  return `${indicator} ${percentage}%`;
}

/**
 * Format significance score with label
 *
 * @param significance - Significance score (0.0-1.0)
 * @returns Formatted string (e.g., "critical (0.92)")
 */
export function formatSignificance(significance: number): string {
  const label = getSignificanceLabel(significance);
  return `${label} (${significance.toFixed(2)})`;
}

/**
 * Get ANSI color code for event type
 *
 * @param eventType - Event type string
 * @returns ANSI escape code for color
 */
export function getEventTypeColor(eventType: string): string {
  if (eventType.startsWith("window::new")) {
    return "\x1b[38;2;0;120;212m"; // Blue
  } else if (eventType.startsWith("window::focus")) {
    return "\x1b[38;2;0;188;212m"; // Cyan
  } else if (eventType.startsWith("workspace::focus")) {
    return "\x1b[38;2;156;39;176m"; // Purple
  } else {
    return "\x1b[0m"; // Default (white)
  }
}

/**
 * Reset ANSI colors
 */
export const RESET_COLOR = "\x1b[0m";

/**
 * Format event type with color
 *
 * @param eventType - Event type string
 * @returns Colored event type
 */
export function formatEventType(eventType: string): string {
  const color = getEventTypeColor(eventType);
  return `${color}${eventType}${RESET_COLOR}`;
}

/**
 * Format diff change (old → new)
 *
 * @param oldValue - Old value
 * @param newValue - New value
 * @param changeType - Type of change
 * @returns Formatted string
 */
export function formatDiffChange(
  // deno-lint-ignore no-explicit-any
  oldValue: any,
  // deno-lint-ignore no-explicit-any
  newValue: any,
  changeType: "modified" | "added" | "removed",
): string {
  if (changeType === "added") {
    return `(none) → ${formatValue(newValue)}`;
  } else if (changeType === "removed") {
    return `${formatValue(oldValue)} → (removed)`;
  } else {
    return `${formatValue(oldValue)} → ${formatValue(newValue)}`;
  }
}

/**
 * Format value for display
 * deno-lint-ignore no-explicit-any
 */
function formatValue(value: any): string {
  if (value === null || value === undefined) {
    return "(null)";
  } else if (typeof value === "object") {
    return JSON.stringify(value);
  } else {
    return String(value);
  }
}

/**
 * Truncate string to max length with ellipsis
 *
 * @param str - String to truncate
 * @param maxLength - Maximum length
 * @returns Truncated string
 */
export function truncate(str: string, maxLength: number): string {
  if (str.length <= maxLength) {
    return str;
  }
  return str.substring(0, maxLength - 3) + "...";
}

/**
 * Pad string to fixed width
 *
 * @param str - String to pad
 * @param width - Target width
 * @param align - Alignment ("left" | "right" | "center")
 * @returns Padded string
 */
export function pad(str: string, width: number, align: "left" | "right" | "center" = "left"): string {
  if (str.length >= width) {
    return str;
  }

  const padding = width - str.length;

  if (align === "right") {
    return " ".repeat(padding) + str;
  } else if (align === "center") {
    const leftPad = Math.floor(padding / 2);
    const rightPad = padding - leftPad;
    return " ".repeat(leftPad) + str + " ".repeat(rightPad);
  } else {
    return str + " ".repeat(padding);
  }
}
