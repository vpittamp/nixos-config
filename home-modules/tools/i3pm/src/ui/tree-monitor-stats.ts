/**
 * Performance Statistics Display
 *
 * Displays daemon health metrics:
 * - Memory usage (MB)
 * - CPU percentage
 * - Event buffer utilization
 * - Event distribution by type
 * - Diff computation performance
 *
 * Based on Feature 065 spec.md User Story 4 and quickstart.md.
 */

import type { Stats } from "../models/tree-monitor.ts";
import { formatTimeDelta } from "../utils/time-parser.ts";

/**
 * Render section header
 */
function renderSectionHeader(title: string): string {
  return `\n${"=".repeat(60)}\n${title}\n${"=".repeat(60)}`;
}

/**
 * Render system resources section
 */
function renderSystemResources(stats: Stats): string {
  let output = renderSectionHeader("System Resources");

  output += `\nMemory Usage:  ${stats.memory_mb.toFixed(2)} MB`;
  output += `\nCPU Usage:     ${stats.cpu_percent.toFixed(2)}%`;
  output += `\nUptime:        ${formatUptime(stats.uptime_seconds)}`;

  return output;
}

/**
 * Format uptime in human-readable format
 */
function formatUptime(seconds: number): string {
  const days = Math.floor(seconds / (24 * 3600));
  const hours = Math.floor((seconds % (24 * 3600)) / 3600);
  const minutes = Math.floor((seconds % 3600) / 60);
  const secs = Math.floor(seconds % 60);

  const parts: string[] = [];
  if (days > 0) parts.push(`${days}d`);
  if (hours > 0) parts.push(`${hours}h`);
  if (minutes > 0) parts.push(`${minutes}m`);
  if (secs > 0 || parts.length === 0) parts.push(`${secs}s`);

  return parts.join(" ");
}

/**
 * Render event buffer section
 */
function renderEventBuffer(stats: Stats): string {
  let output = renderSectionHeader("Event Buffer");

  const { current_size, max_size, utilization } = stats.buffer;

  output += `\nCurrent Size:  ${current_size} events`;
  output += `\nMax Size:      ${max_size} events`;
  output += `\nUtilization:   ${(utilization * 100).toFixed(1)}%`;

  // ASCII progress bar
  const barWidth = 40;
  const filledWidth = Math.round(utilization * barWidth);
  const emptyWidth = barWidth - filledWidth;
  const bar = "█".repeat(filledWidth) + "░".repeat(emptyWidth);

  output += `\n[${bar}]`;

  return output;
}

/**
 * Render event distribution section
 */
function renderEventDistribution(stats: Stats): string {
  let output = renderSectionHeader("Event Distribution by Type");

  const entries = Object.entries(stats.event_distribution).sort((a, b) => b[1] - a[1]);

  if (entries.length === 0) {
    output += `\n(No events recorded)`;
    return output;
  }

  const total = entries.reduce((sum, [, count]) => sum + count, 0);

  output += `\n`;
  for (const [eventType, count] of entries) {
    const percentage = ((count / total) * 100).toFixed(1);
    const barWidth = 30;
    const filledWidth = Math.round((count / total) * barWidth);
    const emptyWidth = barWidth - filledWidth;
    const bar = "█".repeat(filledWidth) + "░".repeat(emptyWidth);

    output += `\n${eventType.padEnd(25)} [${bar}] ${count} (${percentage}%)`;
  }

  output += `\n\nTotal Events: ${total}`;

  return output;
}

/**
 * Render diff computation stats section
 */
function renderDiffStats(stats: Stats): string {
  let output = renderSectionHeader("Diff Computation Performance");

  const { avg_compute_time_ms, max_compute_time_ms, total_diffs_computed } = stats.diff_stats;

  output += `\nTotal Diffs Computed:  ${total_diffs_computed}`;
  output += `\nAverage Compute Time:  ${formatTimeDelta(avg_compute_time_ms)}`;
  output += `\nMax Compute Time:      ${formatTimeDelta(max_compute_time_ms)}`;

  // Performance indicator
  let perfIndicator: string;
  let perfLabel: string;

  if (avg_compute_time_ms < 10) {
    perfIndicator = "🟢";
    perfLabel = "Excellent";
  } else if (avg_compute_time_ms < 50) {
    perfIndicator = "🟡";
    perfLabel = "Good";
  } else if (avg_compute_time_ms < 100) {
    perfIndicator = "🟠";
    perfLabel = "Fair";
  } else {
    perfIndicator = "🔴";
    perfLabel = "Slow";
  }

  output += `\n\nPerformance:           ${perfIndicator} ${perfLabel}`;

  return output;
}

/**
 * Render full statistics display
 */
export function renderStats(stats: Stats): string {
  let output = "";

  output += renderSystemResources(stats);
  output += "\n" + renderEventBuffer(stats);
  output += "\n" + renderEventDistribution(stats);
  output += "\n" + renderDiffStats(stats);

  output += "\n\n" + "=".repeat(60) + "\n";

  return output;
}

/**
 * Render statistics as JSON
 */
export function renderStatsJSON(stats: Stats): string {
  return JSON.stringify(stats, null, 2);
}

/**
 * Display statistics (text or JSON)
 */
export function displayStats(stats: Stats, json: boolean): void {
  if (json) {
    console.log(renderStatsJSON(stats));
  } else {
    console.log(renderStats(stats));
  }
}
