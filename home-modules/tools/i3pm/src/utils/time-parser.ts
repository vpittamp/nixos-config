/**
 * Time Parser Utility
 *
 * Parses human-friendly time formats (5m, 1h, 30s, 2d) into Date objects.
 * Based on Feature 065 research.md requirements.
 */

/**
 * Time unit multipliers (milliseconds)
 */
const TIME_MULTIPLIERS: Record<string, number> = {
  s: 1000, // seconds
  m: 60 * 1000, // minutes
  h: 60 * 60 * 1000, // hours
  d: 24 * 60 * 60 * 1000, // days
};

/**
 * Parse human-friendly time filter into Date object
 *
 * Supports formats: 5m, 1h, 30s, 2d
 *
 * @param input - Time string (e.g., "5m", "1h", "30s", "2d")
 * @returns Date object representing the time in the past
 * @throws Error if format is invalid
 *
 * @example
 * parseTimeFilter("5m")  // 5 minutes ago
 * parseTimeFilter("1h")  // 1 hour ago
 * parseTimeFilter("30s") // 30 seconds ago
 * parseTimeFilter("2d")  // 2 days ago
 */
export function parseTimeFilter(input: string): Date {
  const match = input.match(/^(\d+)([smhd])$/);

  if (!match) {
    throw new Error(
      `Invalid time format: "${input}". ` +
        `Use format: <number><unit> where unit is s (seconds), m (minutes), h (hours), or d (days). ` +
        `Examples: 5m, 1h, 30s, 2d`,
    );
  }

  const value = parseInt(match[1]);
  const unit = match[2];

  if (isNaN(value) || value < 0) {
    throw new Error(`Invalid time value: "${match[1]}" must be a positive number`);
  }

  const multiplier = TIME_MULTIPLIERS[unit];
  const now = Date.now();
  const targetTime = now - (value * multiplier);

  return new Date(targetTime);
}

/**
 * Convert Date to ISO 8601 string for RPC params
 */
export function dateToISO(date: Date): string {
  return date.toISOString();
}

/**
 * Parse time filter and return ISO 8601 string
 *
 * @param input - Time string (e.g., "5m") or ISO 8601 string
 * @returns ISO 8601 string
 */
export function parseTimeToISO(input: string): string {
  // If already ISO 8601 format, return as-is
  if (/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}/.test(input)) {
    return input;
  }

  // Parse human format
  const date = parseTimeFilter(input);
  return dateToISO(date);
}

/**
 * Format timestamp (milliseconds) to human-readable string
 *
 * @param timestamp - Unix timestamp in milliseconds
 * @param format - Output format ("time" for HH:MM:SS.mmm, "relative" for "2s ago")
 * @returns Formatted string
 */
export function formatTimestamp(
  timestamp: number,
  format: "time" | "relative" = "time",
): string {
  const date = new Date(timestamp);

  if (format === "time") {
    // HH:MM:SS.mmm
    const hours = String(date.getHours()).padStart(2, "0");
    const minutes = String(date.getMinutes()).padStart(2, "0");
    const seconds = String(date.getSeconds()).padStart(2, "0");
    const millis = String(date.getMilliseconds()).padStart(3, "0");
    return `${hours}:${minutes}:${seconds}.${millis}`;
  } else {
    // Relative time (e.g., "2s ago", "5m ago")
    const now = Date.now();
    const deltaMs = now - timestamp;

    if (deltaMs < 1000) {
      return "just now";
    } else if (deltaMs < 60 * 1000) {
      return `${Math.floor(deltaMs / 1000)}s ago`;
    } else if (deltaMs < 60 * 60 * 1000) {
      return `${Math.floor(deltaMs / (60 * 1000))}m ago`;
    } else if (deltaMs < 24 * 60 * 60 * 1000) {
      return `${Math.floor(deltaMs / (60 * 60 * 1000))}h ago`;
    } else {
      return `${Math.floor(deltaMs / (24 * 60 * 60 * 1000))}d ago`;
    }
  }
}

/**
 * Format time delta in milliseconds to human-readable string
 *
 * @param deltaMs - Time delta in milliseconds
 * @returns Formatted string (e.g., "150ms", "2.5s", "1.2m")
 */
export function formatTimeDelta(deltaMs: number): string {
  if (deltaMs < 1000) {
    return `${deltaMs}ms`;
  } else if (deltaMs < 60 * 1000) {
    return `${(deltaMs / 1000).toFixed(1)}s`;
  } else if (deltaMs < 60 * 60 * 1000) {
    return `${(deltaMs / (60 * 1000)).toFixed(1)}m`;
  } else {
    return `${(deltaMs / (60 * 60 * 1000)).toFixed(1)}h`;
  }
}
