/**
 * Table Renderer API
 *
 * Provides structured table output with smart column alignment, priority-based
 * hiding, and terminal width adaptation.
 *
 * @module table-renderer
 */

import type { TerminalCapabilities } from "./terminal-capabilities.ts";
import { detectTerminalCapabilities } from "./terminal-capabilities.ts";
import {
  type Alignment,
  formatCell,
  sortTableData,
  truncateText,
} from "./utils/table-utils.ts";

// Re-export utilities for convenience
export { formatCell, sortTableData, truncateText, type Alignment };

/** Table column configuration */
export interface TableColumn<T = unknown> {
  /** Column key (matches data object keys) */
  key: string;
  /** Column header text */
  header: string;
  /** Text alignment (default: "left") */
  alignment?: Alignment;
  /** Column priority (1=always show, higher=hide first when space limited) */
  priority?: number;
  /** Minimum column width */
  minWidth?: number;
  /** Maximum column width (null = unlimited) */
  maxWidth?: number | null;
  /** Custom formatter function */
  formatter?: (value: T, row: Record<string, unknown>) => string;
}

/** Table rendering options */
export interface TableOptions {
  /** Column definitions */
  columns: TableColumn[];
  /** Column separator (default: " │ ") */
  separator?: string;
  /** Show header row (default: true) */
  showHeader?: boolean;
  /** Show table border (default: false) */
  showBorder?: boolean;
  /** Terminal capabilities */
  capabilities?: TerminalCapabilities;
  /** Sort by column key */
  sortBy?: string;
  /** Sort direction */
  sortDirection?: "asc" | "desc";
}

/** Calculated table layout */
export interface TableLayout {
  /** Columns that fit in available width */
  columns: TableColumn[];
  /** Calculated width for each column */
  columnWidths: number[];
  /** Total table width */
  totalWidth: number;
}

/**
 * Calculate which columns to display based on terminal width.
 *
 * Uses priority-based hiding: columns with higher priority values are
 * hidden first when space is limited.
 *
 * @param columns - All available columns
 * @param data - Table data (used to calculate required widths)
 * @param terminalWidth - Available terminal width
 * @returns Layout with columns that fit
 */
export function calculateTableLayout(
  columns: TableColumn[],
  data: Record<string, unknown>[],
  terminalWidth: number,
): TableLayout {
  // Sort columns by priority (lower = more important)
  const sortedCols = [...columns].sort((a, b) =>
    (a.priority ?? 999) - (b.priority ?? 999)
  );

  const separator = " │ ";
  const separatorWidth = separator.length;

  const selectedColumns: TableColumn[] = [];
  const columnWidths: number[] = [];
  let currentWidth = 0;

  for (const col of sortedCols) {
    // Calculate required width for this column
    let colWidth = col.header.length;

    // Check data for max width
    for (const row of data) {
      const value = String(row[col.key] ?? "");
      const valueWidth = value.length;
      colWidth = Math.max(colWidth, valueWidth);
    }

    // Apply min/max constraints
    const minWidth = col.minWidth ?? colWidth;
    const maxWidth = col.maxWidth ?? colWidth;
    colWidth = Math.max(minWidth, Math.min(maxWidth, colWidth));

    // Check if we have room
    const addedWidth = colWidth +
      (selectedColumns.length > 0 ? separatorWidth : 0);

    if (currentWidth + addedWidth <= terminalWidth - 2) {
      // -2 for margins
      selectedColumns.push(col);
      columnWidths.push(colWidth);
      currentWidth += addedWidth;
    } else {
      break; // No more room
    }
  }

  return {
    columns: selectedColumns,
    columnWidths,
    totalWidth: currentWidth,
  };
}

/**
 * Render a table to a string.
 *
 * @param data - Array of row objects
 * @param options - Table rendering options
 * @returns Rendered table as string
 */
export function renderTable(
  data: Record<string, unknown>[],
  options: TableOptions,
): string {
  const capabilities = options.capabilities ?? detectTerminalCapabilities();
  const separator = options.separator ?? " │ ";
  const showHeader = options.showHeader ?? true;

  // Sort data if requested
  let sortedData = data;
  if (options.sortBy) {
    sortedData = sortTableData(
      data,
      options.sortBy,
      options.sortDirection ?? "asc",
    );
  }

  // Calculate layout
  const layout = calculateTableLayout(
    options.columns,
    sortedData,
    capabilities.width,
  );

  const lines: string[] = [];

  // Render header
  if (showHeader) {
    const headerCells = layout.columns.map((col, i) =>
      formatCell(col.header, layout.columnWidths[i], col.alignment)
    );
    lines.push(headerCells.join(separator));

    // Optional separator line
    if (options.showBorder) {
      const borderCells = layout.columns.map((_, i) =>
        "─".repeat(layout.columnWidths[i])
      );
      lines.push(borderCells.join("─┼─"));
    }
  }

  // Render rows
  for (const row of sortedData) {
    const cells = layout.columns.map((col, i) => {
      const value = col.formatter
        ? col.formatter(row[col.key] as never, row)
        : String(row[col.key] ?? "");

      return formatCell(value, layout.columnWidths[i], col.alignment);
    });
    lines.push(cells.join(separator));
  }

  return lines.join("\n");
}

/**
 * Table renderer class with state management.
 *
 * Useful for rendering multiple tables with the same configuration.
 */
export class TableRenderer {
  #options: TableOptions;
  #layout: TableLayout | null = null;

  constructor(options: TableOptions) {
    this.#options = options;
  }

  /** Get current table options */
  get options(): TableOptions {
    return this.#options;
  }

  /** Get cached layout (if calculated) */
  get layout(): TableLayout | null {
    return this.#layout;
  }

  /**
   * Render table with current options.
   *
   * @param data - Table data
   * @returns Rendered table string
   */
  render(data: Record<string, unknown>[]): string {
    return renderTable(data, this.#options);
  }

  /**
   * Update table options.
   *
   * @param options - Partial options to update
   */
  updateOptions(options: Partial<TableOptions>): void {
    this.#options = { ...this.#options, ...options };
    this.#layout = null; // Invalidate layout
  }

  /**
   * Update terminal width and recalculate layout.
   *
   * @param terminalWidth - New terminal width
   */
  updateLayout(terminalWidth: number): void {
    const capabilities = this.#options.capabilities ??
      detectTerminalCapabilities();
    this.#options.capabilities = { ...capabilities, width: terminalWidth };
    this.#layout = null; // Invalidate layout
  }
}
