/**
 * Historical Query Table View
 *
 * Displays historical events in a tabular format.
 * Supports sorting, filtering, and JSON output.
 *
 * Based on Feature 065 spec.md User Story 2 and quickstart.md.
 */

import type { Event } from "../models/tree-monitor.ts";
import { formatTimestamp } from "../utils/time-parser.ts";
import {
  formatChanges,
  formatConfidence,
  formatEventType,
  formatTriggeredBy,
  truncate,
  pad,
  RESET_COLOR,
} from "../utils/formatters.ts";

/**
 * Table column widths
 */
const COLUMN_WIDTHS = {
  time: 12, // HH:MM:SS.mmm
  type: 25,
  changes: 20,
  triggered: 30,
  confidence: 3,
  id: 8, // First 8 chars of UUID
};

/**
 * Render table header
 */
function renderHeader(): string {
  const time = pad("Time", COLUMN_WIDTHS.time);
  const type = pad("Event Type", COLUMN_WIDTHS.type);
  const changes = pad("Changes", COLUMN_WIDTHS.changes);
  const triggered = pad("Triggered By", COLUMN_WIDTHS.triggered);
  const confidence = pad("Conf", COLUMN_WIDTHS.confidence);
  const id = pad("ID", COLUMN_WIDTHS.id);

  const header = `${time} ${type} ${changes} ${triggered} ${confidence} ${id}`;
  const separator = "─".repeat(header.length);

  return `${header}\n${separator}`;
}

/**
 * Render table row
 */
function renderRow(event: Event): string {
  const time = pad(formatTimestamp(event.timestamp, "time"), COLUMN_WIDTHS.time);
  const type = pad(truncate(event.type, COLUMN_WIDTHS.type), COLUMN_WIDTHS.type);
  const changes = pad(formatChanges(event), COLUMN_WIDTHS.changes);
  const triggered = pad(
    truncate(formatTriggeredBy(event), COLUMN_WIDTHS.triggered),
    COLUMN_WIDTHS.triggered,
  );
  const confidence = pad(formatConfidence(event), COLUMN_WIDTHS.confidence);
  const id = pad(event.id.substring(0, 8), COLUMN_WIDTHS.id);

  return `${time} ${formatEventType(type)}${RESET_COLOR} ${changes} ${triggered} ${confidence} ${id}`;
}

/**
 * Render table view
 */
export function renderTable(events: Event[]): string {
  if (events.length === 0) {
    return "No events found.\n";
  }

  let output = renderHeader() + "\n";

  for (const event of events) {
    output += renderRow(event) + "\n";
  }

  output += `\n${events.length} event${events.length === 1 ? "" : "s"} found.`;

  return output;
}

/**
 * Render JSON output
 */
export function renderJSON(events: Event[]): string {
  return JSON.stringify(events, null, 2);
}

/**
 * Display events (table or JSON)
 */
export function displayEvents(events: Event[], json: boolean): void {
  if (json) {
    console.log(renderJSON(events));
  } else {
    console.log(renderTable(events));
  }
}
