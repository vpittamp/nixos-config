/**
 * Event Detail Inspection View
 *
 * Displays detailed information for a specific event including:
 * - Event metadata (ID, timestamp, type, significance)
 * - User action correlation (if available)
 * - Field-level changes (diff)
 * - I3PM enrichment (PID, environment variables, marks)
 *
 * Based on Feature 065 spec.md User Story 3 and quickstart.md.
 */

import type { Event } from "../models/tree-monitor.ts";
import { formatTimestamp, formatTimeDelta } from "../utils/time-parser.ts";
import {
  formatSignificance,
  formatConfidenceWithPercentage,
  formatDiffChange,
  formatEventType,
  RESET_COLOR,
} from "../utils/formatters.ts";

/**
 * Render section header
 */
function renderSectionHeader(title: string): string {
  return `\n${"=".repeat(60)}\n${title}\n${"=".repeat(60)}`;
}

/**
 * Render event metadata section
 */
function renderMetadata(event: Event): string {
  let output = renderSectionHeader("Event Metadata");

  output += `\nID:           ${event.id}`;
  output += `\nTimestamp:    ${formatTimestamp(event.timestamp, "time")} (${formatTimestamp(event.timestamp, "relative")})`;
  output += `\nType:         ${formatEventType(event.type)}${RESET_COLOR}`;
  output += `\nChanges:      ${event.change_count}`;
  output += `\nSignificance: ${formatSignificance(event.significance)}`;

  return output;
}

/**
 * Render correlation section
 */
function renderCorrelation(event: Event): string {
  if (!event.correlation) {
    return renderSectionHeader("User Action Correlation") +
      `\n(No correlation available)`;
  }

  const { action_type, binding_command, time_delta_ms, confidence, reasoning } = event.correlation;

  let output = renderSectionHeader("User Action Correlation");

  output += `\nAction Type:     ${action_type}`;

  if (binding_command) {
    output += `\nBinding Command: ${binding_command}`;
  }

  output += `\nTime Delta:      ${formatTimeDelta(time_delta_ms)}`;
  output += `\nConfidence:      ${formatConfidenceWithPercentage(confidence)}`;
  output += `\nReasoning:       ${reasoning}`;

  return output;
}

/**
 * Render diff section
 */
function renderDiff(event: Event): string {
  if (!event.diff || event.diff.length === 0) {
    return renderSectionHeader("Field-Level Changes (Diff)") +
      `\n(No diff available)`;
  }

  let output = renderSectionHeader("Field-Level Changes (Diff)");

  // Flatten field_changes from all node_changes and group by change type
  const allFieldChanges = event.diff.flatMap((node: any) =>
    node.field_changes.map((fc: any) => ({
      ...fc,
      node_path: node.node_path,
      node_type: node.node_type
    }))
  );

  const modified = allFieldChanges.filter((d: any) => d.change_type === "MODIFIED" || d.change_type === "modified");
  const added = allFieldChanges.filter((d: any) => d.change_type === "ADDED" || d.change_type === "added");
  const removed = allFieldChanges.filter((d: any) => d.change_type === "REMOVED" || d.change_type === "removed");

  // Render modified fields
  if (modified.length > 0) {
    output += `\n\nModified Fields (${modified.length}):`;
    for (const fc of modified) {
      output += `\n  ${fc.field_path}:`;
      output += `\n    ${formatDiffChange(fc.old_value, fc.new_value, fc.change_type)}`;
      output += `\n    Significance: ${fc.significance_score.toFixed(2)}`;
    }
  }

  // Render added fields
  if (added.length > 0) {
    output += `\n\nAdded Fields (${added.length}):`;
    for (const fc of added) {
      output += `\n  ${fc.field_path}:`;
      output += `\n    ${formatDiffChange(fc.old_value, fc.new_value, fc.change_type)}`;
      output += `\n    Significance: ${fc.significance_score.toFixed(2)}`;
    }
  }

  // Render removed fields
  if (removed.length > 0) {
    output += `\n\nRemoved Fields (${removed.length}):`;
    for (const fc of removed) {
      output += `\n  ${fc.field_path}:`;
      output += `\n    ${formatDiffChange(fc.old_value, fc.new_value, fc.change_type)}`;
      output += `\n    Significance: ${fc.significance_score.toFixed(2)}`;
    }
  }

  return output;
}

/**
 * Render enrichment section
 */
function renderEnrichment(event: Event): string {
  if (!event.enrichment) {
    return renderSectionHeader("I3PM Enrichment") +
      `\n(No enrichment available)`;
  }

  const { pid, i3pm_vars, marks, launch_context } = event.enrichment;

  let output = renderSectionHeader("I3PM Enrichment");

  output += `\nProcess ID: ${pid}`;

  if (i3pm_vars) {
    output += `\n\nEnvironment Variables:`;
    if (i3pm_vars.APP_ID) output += `\n  I3PM_APP_ID:       ${i3pm_vars.APP_ID}`;
    if (i3pm_vars.APP_NAME) output += `\n  I3PM_APP_NAME:     ${i3pm_vars.APP_NAME}`;
    if (i3pm_vars.PROJECT_NAME) output += `\n  I3PM_PROJECT_NAME: ${i3pm_vars.PROJECT_NAME}`;
    if (i3pm_vars.SCOPE) output += `\n  I3PM_SCOPE:        ${i3pm_vars.SCOPE}`;
    if (i3pm_vars.LAUNCH_CONTEXT) output += `\n  I3PM_LAUNCH_CONTEXT: ${i3pm_vars.LAUNCH_CONTEXT}`;
  }

  if (marks && marks.length > 0) {
    output += `\n\nWindow Marks: ${marks.join(", ")}`;
  }

  if (launch_context) {
    output += `\n\nLaunch Context:`;
    output += `\n  Method:    ${launch_context.method}`;
    output += `\n  Timestamp: ${formatTimestamp(launch_context.timestamp, "time")}`;
  }

  return output;
}

/**
 * Render full event detail
 */
export function renderEventDetail(event: Event): string {
  let output = "";

  output += renderMetadata(event);
  output += "\n" + renderCorrelation(event);
  output += "\n" + renderDiff(event);
  output += "\n" + renderEnrichment(event);

  output += "\n\n" + "=".repeat(60) + "\n";

  return output;
}

/**
 * Render event detail as JSON
 */
export function renderEventDetailJSON(event: Event): string {
  return JSON.stringify(event, null, 2);
}

/**
 * Display event detail (text or JSON)
 */
export function displayEventDetail(event: Event, json: boolean): void {
  if (json) {
    console.log(renderEventDetailJSON(event));
  } else {
    console.log(renderEventDetail(event));
  }
}
