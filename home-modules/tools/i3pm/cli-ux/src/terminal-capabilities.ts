/**
 * Terminal Capabilities Detection
 *
 * Provides functions to detect terminal capabilities including TTY status,
 * color support, Unicode support, and terminal dimensions.
 *
 * @module terminal-capabilities
 */

/** Color support levels for terminal output */
export enum ColorLevel {
  /** No color support (TERM=dumb or NO_COLOR set) */
  None = 0,
  /** 16-color support (basic ANSI colors) */
  Basic = 16,
  /** 256-color support (extended palette) */
  Extended = 256,
  /** 24-bit true color (16.7M colors) */
  TrueColor = 16777216,
}

/** Terminal capability detection result */
export interface TerminalCapabilities {
  /** Whether output is connected to a TTY (vs pipe/redirect) */
  isTTY: boolean;
  /** Detected level of color support */
  colorSupport: ColorLevel;
  /** Whether terminal supports Unicode characters */
  supportsUnicode: boolean;
  /** Current terminal width in columns */
  width: number;
  /** Current terminal height in rows */
  height: number;
}

/**
 * Detects color support level for the current terminal.
 *
 * Checks in priority order:
 * 1. FORCE_COLOR env var (explicit override)
 * 2. NO_COLOR env var (explicit disable)
 * 3. Deno.noColor flag
 * 4. TERM environment variable patterns
 * 5. COLORTERM environment variable
 *
 * @returns {ColorLevel} Detected color support level
 */
export function detectColorSupport(): ColorLevel {
  // Check FORCE_COLOR env var (explicit override)
  const forceColor = Deno.env.get("FORCE_COLOR");
  if (forceColor !== undefined) {
    return forceColor === "0" ? ColorLevel.None : ColorLevel.Extended;
  }

  // Check NO_COLOR env var (explicit disable)
  if (Deno.env.get("NO_COLOR") !== undefined) {
    return ColorLevel.None;
  }

  // Check Deno.noColor flag
  if (Deno.noColor) {
    return ColorLevel.None;
  }

  // Check TERM environment variable
  const term = Deno.env.get("TERM") || "";
  if (term === "dumb") return ColorLevel.None;
  if (term.includes("256color")) return ColorLevel.Extended;
  if (term.startsWith("xterm")) return ColorLevel.Basic;

  // Check COLORTERM for truecolor support
  const colorTerm = Deno.env.get("COLORTERM") || "";
  if (colorTerm === "truecolor" || colorTerm === "24bit") {
    return ColorLevel.TrueColor;
  }

  // Default: assume basic colors if TTY
  return Deno.stdout.isTerminal() ? ColorLevel.Basic : ColorLevel.None;
}

/**
 * Detects Unicode support for the current terminal.
 *
 * Checks:
 * - LANG environment variable for UTF-8 encoding
 * - TERM environment variable (e.g., "linux" has limited support)
 * - TTY status (non-TTY assumes no Unicode)
 *
 * @returns {boolean} True if Unicode is supported
 */
export function supportsUnicode(): boolean {
  const lang = Deno.env.get("LANG") || "";
  if (lang.includes("UTF-8") || lang.includes("utf8")) return true;

  const term = Deno.env.get("TERM") || "";
  if (term === "linux") return false; // Linux console has limited Unicode

  return Deno.stdout.isTerminal();
}

/**
 * Gets current terminal dimensions with fallback.
 *
 * @returns {object} Terminal dimensions
 * @returns {number} return.columns - Terminal width (min: 40, default: 80)
 * @returns {number} return.rows - Terminal height (min: 10, default: 24)
 */
export function getTerminalSize(): { columns: number; rows: number } {
  try {
    const size = Deno.consoleSize();
    return {
      columns: Math.max(40, size.columns), // Minimum 40 columns
      rows: Math.max(10, size.rows),       // Minimum 10 rows
    };
  } catch {
    return { columns: 80, rows: 24 }; // Default fallback
  }
}

/**
 * Detects terminal capabilities for the current environment.
 *
 * Detection logic:
 * 1. TTY: Deno.stdout.isTerminal()
 * 2. Color: FORCE_COLOR, NO_COLOR, Deno.noColor, TERM env vars
 * 3. Unicode: LANG env var, TERM value, TTY status
 * 4. Dimensions: Deno.consoleSize() with fallback to 80x24
 *
 * @returns {TerminalCapabilities} Detected capabilities
 */
export function detectTerminalCapabilities(): TerminalCapabilities {
  const isTTY = Deno.stdout.isTerminal();
  const { columns, rows } = getTerminalSize();

  return {
    isTTY,
    colorSupport: isTTY ? detectColorSupport() : ColorLevel.None,
    supportsUnicode: supportsUnicode(),
    width: columns,
    height: rows,
  };
}

/**
 * Listens for terminal resize events (SIGWINCH).
 *
 * @param {function} callback - Function called when terminal is resized
 * @returns {function} Cleanup function to remove listener
 */
export function onTerminalResize(
  callback: (size: { columns: number; rows: number }) => void,
): () => void {
  const handler = () => callback(getTerminalSize());

  // Listen for SIGWINCH (terminal resize signal)
  Deno.addSignalListener("SIGWINCH", handler);

  // Return cleanup function
  return () => Deno.removeSignalListener("SIGWINCH", handler);
}
