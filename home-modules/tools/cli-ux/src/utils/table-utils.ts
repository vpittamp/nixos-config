/**
 * Table utility functions
 *
 * Provides cell formatting, text truncation, and sorting utilities for tables.
 *
 * @module utils/table-utils
 */

/** Alignment options for table cells */
export type Alignment = "left" | "right" | "center";

/**
 * Calculate the display width of a string (handles multi-byte Unicode).
 *
 * For simplicity, this treats most characters as width 1.
 * In production, you'd use a library that handles East Asian Width properly.
 *
 * @param text - Text to measure
 * @returns Display width
 */
function stringWidth(text: string): number {
  // Simple implementation - counts characters
  // In production, use a library like string-width or @std/cli/unicode-width
  return text.length;
}

/**
 * Format a cell with padding to match the specified width and alignment.
 *
 * @param value - Cell value to format
 * @param width - Target width
 * @param alignment - Text alignment (default: "left")
 * @returns Formatted cell string
 */
export function formatCell(
  value: string,
  width: number,
  alignment: Alignment = "left",
): string {
  const actualWidth = stringWidth(value);

  if (actualWidth >= width) {
    return truncateText(value, width);
  }

  const padding = width - actualWidth;

  switch (alignment) {
    case "right":
      return " ".repeat(padding) + value;
    case "center": {
      const leftPad = Math.floor(padding / 2);
      const rightPad = padding - leftPad;
      return " ".repeat(leftPad) + value + " ".repeat(rightPad);
    }
    default: // left
      return value + " ".repeat(padding);
  }
}

/**
 * Truncate text to fit within a maximum width using ellipsis.
 *
 * Preserves the beginning and end of the text when possible.
 *
 * @param text - Text to truncate
 * @param maxWidth - Maximum width
 * @returns Truncated text
 */
export function truncateText(text: string, maxWidth: number): string {
  const width = stringWidth(text);
  if (width <= maxWidth) {
    return text;
  }

  if (maxWidth < 4) {
    return text.substring(0, maxWidth);
  }

  // Preserve first and last characters when possible
  const ellipsis = "…";
  const availableWidth = maxWidth - stringWidth(ellipsis);
  const leftChars = Math.ceil(availableWidth / 2);
  const rightChars = Math.floor(availableWidth / 2);

  if (leftChars + rightChars < text.length) {
    return text.substring(0, leftChars) + ellipsis +
      text.substring(text.length - rightChars);
  }

  return text.substring(0, maxWidth - 1) + ellipsis;
}

/**
 * Sort table data by a specific column.
 *
 * @param data - Array of row objects
 * @param sortBy - Key to sort by
 * @param direction - Sort direction ("asc" or "desc")
 * @returns Sorted array (new array, does not mutate original)
 */
export function sortTableData(
  data: Record<string, unknown>[],
  sortBy: string,
  direction: "asc" | "desc",
): Record<string, unknown>[] {
  return [...data].sort((a, b) => {
    const aVal = a[sortBy];
    const bVal = b[sortBy];

    let comparison = 0;

    // Handle null/undefined
    if (aVal == null && bVal == null) return 0;
    if (aVal == null) return 1;
    if (bVal == null) return -1;

    // Compare as strings for safety with unknown types
    const aStr = String(aVal);
    const bStr = String(bVal);

    if (aStr < bStr) comparison = -1;
    else if (aStr > bStr) comparison = 1;

    return direction === "asc" ? comparison : -comparison;
  });
}
