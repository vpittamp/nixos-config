/**
 * Diff Renderer UI Component
 *
 * Renders state diffs in human-readable colored format for terminal output.
 */

import type { StateDiff, DiffEntry, TreeMonitorEvent } from "../models/test-result.ts";

/**
 * ANSI color codes for terminal output
 */
const COLORS = {
  reset: "\x1b[0m",
  red: "\x1b[31m",
  green: "\x1b[32m",
  yellow: "\x1b[33m",
  blue: "\x1b[34m",
  magenta: "\x1b[35m",
  cyan: "\x1b[36m",
  gray: "\x1b[90m",
  bold: "\x1b[1m",
};

/**
 * Diff Renderer for test framework
 */
export class DiffRenderer {
  private useColor: boolean;

  constructor(useColor = true) {
    this.useColor = useColor && Deno.stdout.isTerminal();
  }

  /**
   * Render diff to string
   */
  render(diff: StateDiff): string {
    if (diff.matches) {
      return this.color("✓ States match exactly", "green");
    }

    const lines: string[] = [];

    // Header
    lines.push(this.color("✗ States differ:", "red"));
    lines.push("");

    // Summary
    lines.push(this.renderSummary(diff));
    lines.push("");

    // Detailed differences
    lines.push(this.color("Differences:", "bold"));

    for (const entry of diff.differences) {
      lines.push(this.renderDiffEntry(entry));
    }

    return lines.join("\n");
  }

  /**
   * Render summary of changes
   */
  private renderSummary(diff: StateDiff): string {
    const { added, removed, modified } = diff.summary;
    const parts: string[] = [];

    if (added > 0) {
      parts.push(this.color(`+${added} added`, "green"));
    }
    if (removed > 0) {
      parts.push(this.color(`-${removed} removed`, "red"));
    }
    if (modified > 0) {
      parts.push(this.color(`~${modified} modified`, "yellow"));
    }

    return `Summary: ${parts.join(", ")}`;
  }

  /**
   * Render individual diff entry
   */
  private renderDiffEntry(entry: DiffEntry): string {
    const path = this.color(entry.path, "cyan");

    switch (entry.type) {
      case "added":
        return `  ${this.color("+", "green")} ${path}\n    ${
          this.color("Value:", "gray")
        } ${this.formatValue(entry.actual)}`;

      case "removed":
        return `  ${this.color("-", "red")} ${path}\n    ${
          this.color("Was:", "gray")
        } ${this.formatValue(entry.expected)}`;

      case "modified":
        return `  ${this.color("~", "yellow")} ${path}\n    ${
          this.color("Expected:", "gray")
        } ${this.formatValue(entry.expected)}\n    ${
          this.color("Actual:", "gray")
        }   ${this.formatValue(entry.actual)}`;

      default:
        return `  ${path}: ${entry.type}`;
    }
  }

  /**
   * Format value for display
   */
  private formatValue(value: unknown): string {
    if (value === null) {
      return this.color("null", "gray");
    }

    if (value === undefined) {
      return this.color("undefined", "gray");
    }

    if (typeof value === "string") {
      return this.color(`"${value}"`, "green");
    }

    if (typeof value === "number") {
      return this.color(String(value), "blue");
    }

    if (typeof value === "boolean") {
      return this.color(String(value), "magenta");
    }

    if (Array.isArray(value)) {
      if (value.length === 0) {
        return this.color("[]", "gray");
      }
      return this.color(`Array(${value.length})`, "cyan");
    }

    if (typeof value === "object") {
      const keys = Object.keys(value as Record<string, unknown>);
      if (keys.length === 0) {
        return this.color("{}", "gray");
      }
      return this.color(`Object{${keys.length} keys}`, "cyan");
    }

    return String(value);
  }

  /**
   * Apply color to text
   */
  private color(text: string, colorName: keyof typeof COLORS): string {
    if (!this.useColor) {
      return text;
    }

    const color = COLORS[colorName];
    const reset = COLORS.reset;

    return `${color}${text}${reset}`;
  }

  /**
   * Render compact diff (single line summary)
   */
  renderCompact(diff: StateDiff): string {
    if (diff.matches) {
      return this.color("✓ PASS", "green");
    }

    const { added, removed, modified } = diff.summary;
    const total = added + removed + modified;

    return this.color(
      `✗ FAIL (${total} differences: +${added} -${removed} ~${modified})`,
      "red",
    );
  }

  /**
   * Render tree-monitor event correlation (T029)
   * Shows events that may have caused the state differences
   */
  renderEventCorrelation(events: TreeMonitorEvent[]): string {
    if (!events || events.length === 0) {
      return "";
    }

    const lines: string[] = [];
    lines.push("");
    lines.push(this.color("📋 Tree Monitor Events (last 10):", "bold"));
    lines.push("");

    // Filter to show only significant events
    const significantEvents = events.filter(
      (e) => e.diff.significance_level !== "minimal"
    );

    const eventsToShow = significantEvents.length > 0 ? significantEvents : events.slice(0, 5);

    for (const event of eventsToShow) {
      lines.push(this.renderEvent(event));
    }

    if (significantEvents.length === 0 && events.length > 5) {
      lines.push(this.color(`  ... and ${events.length - 5} more events`, "gray"));
    }

    return lines.join("\n");
  }

  /**
   * Render single event
   */
  private renderEvent(event: TreeMonitorEvent): string {
    const lines: string[] = [];

    // Event header
    const eventType = this.color(event.event_type, "cyan");
    const significance = this.getSignificanceColor(event.diff.significance_level);
    const timestamp = new Date(event.timestamp_ms).toISOString().split("T")[1].split(".")[0];

    lines.push(
      `  ${this.color("▸", "blue")} ${eventType} ${this.color(`[${significance}]`, "gray")} ${
        this.color(`@${timestamp}`, "gray")
      }`
    );

    // Event details
    if (event.diff.total_changes > 0) {
      lines.push(
        `    ${this.color("Changes:", "gray")} ${event.diff.total_changes} fields modified`
      );
    }

    // Show field-level changes if available
    if (event.diff.field_changes && event.diff.field_changes.length > 0) {
      for (const change of event.diff.field_changes.slice(0, 3)) {
        lines.push(
          `      ${this.color("•", "yellow")} ${change.path}: ${
            this.formatValue(change.old_value)
          } → ${this.formatValue(change.new_value)}`
        );
      }

      if (event.diff.field_changes.length > 3) {
        lines.push(
          `      ${this.color(`... and ${event.diff.field_changes.length - 3} more changes`, "gray")}`
        );
      }
    }

    // Show user action correlation if available
    if (event.correlations && event.correlations.length > 0) {
      for (const correlation of event.correlations) {
        if (correlation.keybinding) {
          lines.push(
            `    ${this.color("Keybinding:", "gray")} ${this.color(correlation.keybinding, "magenta")}`
          );
        }
        if (correlation.command) {
          lines.push(`    ${this.color("Command:", "gray")} ${correlation.command}`);
        }
      }
    }

    return lines.join("\n");
  }

  /**
   * Get significance level display name
   */
  private getSignificanceColor(level: string): string {
    switch (level) {
      case "critical":
        return this.color("CRITICAL", "red");
      case "significant":
        return this.color("SIGNIFICANT", "yellow");
      case "moderate":
        return this.color("MODERATE", "blue");
      case "minimal":
        return this.color("minimal", "gray");
      default:
        return level;
    }
  }
}
