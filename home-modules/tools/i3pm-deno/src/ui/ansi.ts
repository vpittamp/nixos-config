/**
 * ANSI Formatting Utilities
 *
 * Provides ANSI escape codes for terminal formatting and control.
 * Wraps Deno's TextEncoder/TextDecoder for byte-level operations.
 */

const encoder = new TextEncoder();
const decoder = new TextDecoder();

// ============================================================================
// ANSI Escape Sequences
// ============================================================================

// Cursor Control
export const CURSOR_UP = (n: number) => `\x1b[${n}A`;
export const CURSOR_DOWN = (n: number) => `\x1b[${n}B`;
export const CURSOR_FORWARD = (n: number) => `\x1b[${n}C`;
export const CURSOR_BACK = (n: number) => `\x1b[${n}D`;
export const CURSOR_POSITION = (row: number, col: number) => `\x1b[${row};${col}H`;
export const CURSOR_HOME = "\x1b[H";

// Cursor Visibility
export const CURSOR_HIDE = "\x1b[?25l";
export const CURSOR_SHOW = "\x1b[?25h";

// Screen Management
export const CLEAR_SCREEN = "\x1b[2J";
export const CLEAR_LINE = "\x1b[2K";
export const CLEAR_TO_END = "\x1b[J";
export const CLEAR_TO_START = "\x1b[1J";

// Alternate Screen Buffer
export const ALTERNATE_SCREEN_ENTER = "\x1b[?1049h";
export const ALTERNATE_SCREEN_EXIT = "\x1b[?1049l";

// Reset
export const RESET = "\x1b[0m";

// ============================================================================
// Text Styles
// ============================================================================

export const BOLD = "\x1b[1m";
export const DIM = "\x1b[2m";
export const ITALIC = "\x1b[3m";
export const UNDERLINE = "\x1b[4m";
export const BLINK = "\x1b[5m";
export const REVERSE = "\x1b[7m";
export const HIDDEN = "\x1b[8m";
export const STRIKETHROUGH = "\x1b[9m";

// ============================================================================
// Foreground Colors
// ============================================================================

export const BLACK = "\x1b[30m";
export const RED = "\x1b[31m";
export const GREEN = "\x1b[32m";
export const YELLOW = "\x1b[33m";
export const BLUE = "\x1b[34m";
export const MAGENTA = "\x1b[35m";
export const CYAN = "\x1b[36m";
export const WHITE = "\x1b[37m";
export const GRAY = "\x1b[90m";

// Bright Colors
export const BRIGHT_RED = "\x1b[91m";
export const BRIGHT_GREEN = "\x1b[92m";
export const BRIGHT_YELLOW = "\x1b[93m";
export const BRIGHT_BLUE = "\x1b[94m";
export const BRIGHT_MAGENTA = "\x1b[95m";
export const BRIGHT_CYAN = "\x1b[96m";
export const BRIGHT_WHITE = "\x1b[97m";

// ============================================================================
// Background Colors
// ============================================================================

export const BG_BLACK = "\x1b[40m";
export const BG_RED = "\x1b[41m";
export const BG_GREEN = "\x1b[42m";
export const BG_YELLOW = "\x1b[43m";
export const BG_BLUE = "\x1b[44m";
export const BG_MAGENTA = "\x1b[45m";
export const BG_CYAN = "\x1b[46m";
export const BG_WHITE = "\x1b[47m";

// ============================================================================
// Helper Functions
// ============================================================================

/**
 * Write ANSI escape sequence to stdout
 */
export function writeAnsi(sequence: string): void {
  Deno.stdout.writeSync(encoder.encode(sequence));
}

/**
 * Apply style to text
 */
export function styled(text: string, ...styles: string[]): string {
  return styles.join("") + text + RESET;
}

/**
 * Bold text
 */
export function bold(text: string): string {
  return styled(text, BOLD);
}

/**
 * Dimmed text
 */
export function dim(text: string): string {
  return styled(text, DIM);
}

/**
 * Underlined text
 */
export function underline(text: string): string {
  return styled(text, UNDERLINE);
}

/**
 * Red text
 */
export function red(text: string): string {
  return styled(text, RED);
}

/**
 * Green text
 */
export function green(text: string): string {
  return styled(text, GREEN);
}

/**
 * Yellow text
 */
export function yellow(text: string): string {
  return styled(text, YELLOW);
}

/**
 * Blue text
 */
export function blue(text: string): string {
  return styled(text, BLUE);
}

/**
 * Magenta text
 */
export function magenta(text: string): string {
  return styled(text, MAGENTA);
}

/**
 * Cyan text
 */
export function cyan(text: string): string {
  return styled(text, CYAN);
}

/**
 * Gray text
 */
export function gray(text: string): string {
  return styled(text, GRAY);
}

/**
 * Move cursor up and clear lines
 */
export function clearPreviousLines(count: number): void {
  if (count > 0) {
    writeAnsi(CURSOR_UP(count));
    writeAnsi(CLEAR_TO_END);
  }
}

/**
 * Clear screen and move cursor to home
 */
export function clearScreen(): void {
  writeAnsi(CLEAR_SCREEN);
  writeAnsi(CURSOR_HOME);
}

/**
 * Hide cursor
 */
export function hideCursor(): void {
  writeAnsi(CURSOR_HIDE);
}

/**
 * Show cursor
 */
export function showCursor(): void {
  writeAnsi(CURSOR_SHOW);
}

/**
 * Enter alternate screen buffer
 */
export function enterAlternateScreen(): void {
  writeAnsi(ALTERNATE_SCREEN_ENTER);
}

/**
 * Exit alternate screen buffer
 */
export function exitAlternateScreen(): void {
  writeAnsi(ALTERNATE_SCREEN_EXIT);
}

/**
 * Check if color output is disabled
 */
export function isColorDisabled(): boolean {
  return Deno.noColor;
}

/**
 * Strip ANSI escape codes from text
 */
export function stripAnsi(text: string): string {
  // eslint-disable-next-line no-control-regex
  return text.replace(/\x1b\[[0-9;]*m/g, "");
}
