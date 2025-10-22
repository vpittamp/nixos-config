/**
 * Terminal Capabilities Detection API
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
 * Detects terminal capabilities for the current environment.
 *
 * Detection logic:
 * 1. TTY: Deno.stdout.isTerminal()
 * 2. Color: FORCE_COLOR, NO_COLOR, Deno.noColor, TERM env vars
 * 3. Unicode: LANG env var, TERM value, TTY status
 * 4. Dimensions: Deno.consoleSize() with fallback to 80x24
 *
 * @returns {TerminalCapabilities} Detected capabilities
 *
 * @example
 * ```typescript
 * const caps = detectTerminalCapabilities();
 * if (caps.isTTY && caps.colorSupport >= ColorLevel.Basic) {
 *   console.log("\x1b[32mGreen text\x1b[0m");
 * }
 * ```
 */
export function detectTerminalCapabilities(): TerminalCapabilities;

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
 *
 * @example
 * ```typescript
 * const level = detectColorSupport();
 * if (level >= ColorLevel.Extended) {
 *   // Use 256-color palette
 * }
 * ```
 */
export function detectColorSupport(): ColorLevel;

/**
 * Detects Unicode support for the current terminal.
 *
 * Checks:
 * - LANG environment variable for UTF-8 encoding
 * - TERM environment variable (e.g., "linux" has limited support)
 * - TTY status (non-TTY assumes no Unicode)
 *
 * @returns {boolean} True if Unicode is supported
 *
 * @example
 * ```typescript
 * const icon = supportsUnicode() ? "✓" : "[OK]";
 * console.log(`Success ${icon}`);
 * ```
 */
export function supportsUnicode(): boolean;

/**
 * Gets current terminal dimensions with fallback.
 *
 * @returns {object} Terminal dimensions
 * @returns {number} return.columns - Terminal width (min: 40, default: 80)
 * @returns {number} return.rows - Terminal height (min: 10, default: 24)
 *
 * @example
 * ```typescript
 * const { columns, rows } = getTerminalSize();
 * if (columns < 80) {
 *   console.log("Terminal is narrow, using compact mode");
 * }
 * ```
 */
export function getTerminalSize(): { columns: number; rows: number };

/**
 * Listens for terminal resize events (SIGWINCH).
 *
 * @param {function} callback - Function called when terminal is resized
 * @returns {function} Cleanup function to remove listener
 *
 * @example
 * ```typescript
 * const cleanup = onTerminalResize(() => {
 *   const caps = detectTerminalCapabilities();
 *   console.log(`Terminal resized to ${caps.width}x${caps.height}`);
 * });
 *
 * // Later: cleanup();
 * ```
 */
export function onTerminalResize(
  callback: (size: { columns: number; rows: number }) => void,
): () => void;
