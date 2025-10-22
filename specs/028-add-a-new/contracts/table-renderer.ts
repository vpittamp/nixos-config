/**
 * Table Rendering API
 *
 * Provides structured table output with smart column alignment, width
 * adaptation, priority-based column hiding, and terminal width awareness.
 *
 * @module table-renderer
 */

import type { TerminalCapabilities } from "./terminal-capabilities.ts";

/** Column alignment options */
export type Alignment = "left" | "right" | "center";

/** Table column definition */
export interface TableColumn<T = unknown> {
  /** Column identifier (data field key) */
  key: string;
  /** Display header text */
  header: string;
  /** Text alignment (default: "left") */
  alignment?: Alignment;
  /** Visibility priority (1=always show, higher=hide first in narrow terminals) */
  priority?: number;
  /** Minimum column width (default: header.length) */
  minWidth?: number;
  /** Maximum column width (null = unlimited, default: null) */
  maxWidth?: number | null;
  /** Custom formatter function for cell values */
  formatter?: (value: T, row: Record<string, unknown>) => string;
}

/** Table rendering options */
export interface TableOptions {
  /** Column definitions */
  columns: TableColumn[];
  /** Column separator (default: " │ ") */
  separator?: string;
  /** Whether to show header row (default: true) */
  showHeader?: boolean;
  /** Whether to show border lines (default: false) */
  showBorder?: boolean;
  /** Terminal capabilities (auto-detected if omitted) */
  capabilities?: TerminalCapabilities;
  /** Sort column key (optional) */
  sortBy?: string;
  /** Sort direction (default: "asc") */
  sortDirection?: "asc" | "desc";
}

/** Computed table layout after width adaptation */
export interface TableLayout {
  /** Active columns (some may be hidden based on terminal width) */
  columns: TableColumn[];
  /** Computed width for each active column */
  columnWidths: number[];
  /** Total table width including separators */
  totalWidth: number;
}

/**
 * Renders data as a formatted table.
 *
 * Features:
 * - Smart column alignment (left/right/center)
 * - Priority-based column hiding for narrow terminals
 * - Text truncation with ellipsis
 * - Unicode-aware width calculation
 * - Optional sorting
 *
 * @param {unknown[]} data - Array of data objects to display
 * @param {TableOptions} options - Table configuration
 * @returns {string} Formatted table output
 *
 * @example
 * ```typescript
 * const data = [
 *   { name: "Alice", age: 30, city: "New York" },
 *   { name: "Bob", age: 25, city: "San Francisco" },
 * ];
 *
 * const table = renderTable(data, {
 *   columns: [
 *     { key: "name", header: "Name", priority: 1 },
 *     { key: "age", header: "Age", alignment: "right", priority: 2 },
 *     { key: "city", header: "City", priority: 3 },
 *   ],
 * });
 *
 * console.log(table);
 * // Output:
 * // Name  │ Age │ City
 * // Alice │  30 │ New York
 * // Bob   │  25 │ San Francisco
 * ```
 */
export function renderTable(
  data: Record<string, unknown>[],
  options: TableOptions,
): string;

/**
 * Calculates table layout for given data and terminal width.
 *
 * Determines which columns to show based on priority and available width.
 *
 * @param {TableColumn[]} columns - Column definitions
 * @param {unknown[]} data - Data to measure
 * @param {number} terminalWidth - Available terminal width
 * @returns {TableLayout} Computed layout with visible columns and widths
 *
 * @example
 * ```typescript
 * const layout = calculateTableLayout(columns, data, 80);
 * console.log(`Showing ${layout.columns.length} of ${columns.length} columns`);
 * ```
 */
export function calculateTableLayout(
  columns: TableColumn[],
  data: Record<string, unknown>[],
  terminalWidth: number,
): TableLayout;

/**
 * Formats a single cell value with padding and alignment.
 *
 * @param {string} value - Cell value
 * @param {number} width - Target width
 * @param {Alignment} alignment - Text alignment (default: "left")
 * @returns {string} Formatted cell with padding
 *
 * @example
 * ```typescript
 * formatCell("Hello", 10, "right"); // "     Hello"
 * formatCell("World", 10, "center"); // "  World   "
 * ```
 */
export function formatCell(
  value: string,
  width: number,
  alignment?: Alignment,
): string;

/**
 * Truncates text to fit width with ellipsis.
 *
 * Preserves first and last characters when possible for context.
 *
 * @param {string} text - Text to truncate
 * @param {number} maxWidth - Maximum width
 * @returns {string} Truncated text with ellipsis if needed
 *
 * @example
 * ```typescript
 * truncateText("very-long-window-title", 15); // "very…ow-title"
 * truncateText("short", 15);                   // "short"
 * ```
 */
export function truncateText(text: string, maxWidth: number): string;

/**
 * Sorts table data by column key.
 *
 * @param {unknown[]} data - Data to sort
 * @param {string} sortBy - Column key to sort by
 * @param {string} direction - Sort direction ("asc" or "desc")
 * @returns {unknown[]} Sorted data array
 *
 * @example
 * ```typescript
 * const sorted = sortTableData(data, "age", "desc");
 * ```
 */
export function sortTableData(
  data: Record<string, unknown>[],
  sortBy: string,
  direction: "asc" | "desc",
): Record<string, unknown>[];

/**
 * Table renderer class with state management.
 *
 * Useful for rendering multiple tables with consistent configuration
 * or updating tables in real-time (live views).
 */
export class TableRenderer {
  /**
   * Creates a table renderer with configuration.
   *
   * @param {TableOptions} options - Table configuration
   *
   * @example
   * ```typescript
   * const renderer = new TableRenderer({
   *   columns: [
   *     { key: "name", header: "Name" },
   *     { key: "status", header: "Status", alignment: "center" },
   *   ],
   * });
   *
   * console.log(renderer.render(data));
   * ```
   */
  constructor(options: TableOptions);

  /** Current table options */
  readonly options: TableOptions;

  /** Current computed layout */
  readonly layout: TableLayout | null;

  /**
   * Renders data with current configuration.
   *
   * @param {unknown[]} data - Data to render
   * @returns {string} Formatted table
   */
  render(data: Record<string, unknown>[]): string;

  /**
   * Updates table configuration.
   *
   * @param {Partial<TableOptions>} options - Options to update
   */
  updateOptions(options: Partial<TableOptions>): void;

  /**
   * Recalculates layout for new terminal width.
   *
   * Call this when terminal is resized (SIGWINCH).
   *
   * @param {number} terminalWidth - New terminal width
   */
  updateLayout(terminalWidth: number): void;
}
