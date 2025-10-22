/**
 * Output Formatting API
 *
 * Provides functions for semantic color coding, symbol selection, and
 * formatted output with automatic terminal capability adaptation.
 *
 * @module output-formatter
 */

import type { TerminalCapabilities } from "./terminal-capabilities.ts";

/** Color theme for semantic output */
export interface ColorTheme {
  /** ANSI code for error messages (red) */
  error: string;
  /** ANSI code for warnings (yellow/amber) */
  warning: string;
  /** ANSI code for success messages (green) */
  success: string;
  /** ANSI code for informational text (gray) */
  info: string;
  /** ANSI code for dimmed/de-emphasized text */
  dim: string;
  /** ANSI code for bold text */
  bold: string;
  /** ANSI code to reset all formatting */
  reset: string;
}

/** Symbol set for status indicators */
export interface SymbolSet {
  /** Success indicator (✓ or [OK]) */
  success: string;
  /** Error indicator (✗ or [X]) */
  error: string;
  /** Warning indicator (⚠ or [!]) */
  warning: string;
  /** Info indicator (ℹ or [i]) */
  info: string;
  /** Spinner animation frames */
  spinner: string[];
}

/** Output formatter with terminal capability adaptation */
export class OutputFormatter {
  /**
   * Creates an output formatter with detected terminal capabilities.
   *
   * @param {TerminalCapabilities} capabilities - Terminal capabilities (optional, auto-detected if omitted)
   *
   * @example
   * ```typescript
   * const formatter = new OutputFormatter();
   * console.log(formatter.success("Build completed!"));
   * ```
   */
  constructor(capabilities?: TerminalCapabilities);

  /** Current terminal capabilities */
  readonly capabilities: TerminalCapabilities;

  /** Current color theme */
  readonly colors: ColorTheme;

  /** Current symbol set */
  readonly symbols: SymbolSet;

  /**
   * Formats an error message with red color and error symbol.
   *
   * @param {string} message - Error message text
   * @returns {string} Formatted message with colors and symbol
   *
   * @example
   * ```typescript
   * console.log(formatter.error("Connection failed"));
   * // Output (with colors): ✗ Connection failed
   * ```
   */
  error(message: string): string;

  /**
   * Formats a warning message with yellow color and warning symbol.
   *
   * @param {string} message - Warning message text
   * @returns {string} Formatted message with colors and symbol
   *
   * @example
   * ```typescript
   * console.log(formatter.warning("Deprecation notice"));
   * // Output (with colors): ⚠ Deprecation notice
   * ```
   */
  warning(message: string): string;

  /**
   * Formats a success message with green color and success symbol.
   *
   * @param {string} message - Success message text
   * @returns {string} Formatted message with colors and symbol
   *
   * @example
   * ```typescript
   * console.log(formatter.success("Tests passed"));
   * // Output (with colors): ✓ Tests passed
   * ```
   */
  success(message: string): string;

  /**
   * Formats an informational message with default color and info symbol.
   *
   * @param {string} message - Info message text
   * @returns {string} Formatted message with colors and symbol
   *
   * @example
   * ```typescript
   * console.log(formatter.info("Starting process..."));
   * // Output (with colors): ℹ Starting process...
   * ```
   */
  info(message: string): string;

  /**
   * Formats text with dimmed/de-emphasized styling.
   *
   * @param {string} text - Text to dim
   * @returns {string} Dimmed text
   *
   * @example
   * ```typescript
   * console.log(`Main text ${formatter.dim("(optional detail)")}`);
   * ```
   */
  dim(text: string): string;

  /**
   * Formats text with bold styling.
   *
   * @param {string} text - Text to bold
   * @returns {string} Bolded text
   *
   * @example
   * ```typescript
   * console.log(formatter.bold("Important:") + " Details here");
   * ```
   */
  bold(text: string): string;

  /**
   * Strips all ANSI escape codes from text.
   *
   * Useful for calculating actual text length or producing plain output.
   *
   * @param {string} text - Text with ANSI codes
   * @returns {string} Plain text without codes
   *
   * @example
   * ```typescript
   * const colored = formatter.success("Done");
   * const plain = formatter.stripAnsi(colored);
   * console.log(plain.length); // Actual character count
   * ```
   */
  stripAnsi(text: string): string;
}

/**
 * Creates a color theme for dark terminal backgrounds.
 *
 * Colors meet WCAG AA contrast requirements (4.5:1 minimum).
 *
 * @returns {ColorTheme} Dark theme color codes
 */
export function createDarkTheme(): ColorTheme;

/**
 * Creates a color theme for light terminal backgrounds.
 *
 * Colors meet WCAG AA contrast requirements (4.5:1 minimum).
 *
 * @returns {ColorTheme} Light theme color codes
 */
export function createLightTheme(): ColorTheme;

/**
 * Creates a theme with no colors (empty strings).
 *
 * Used when color support is disabled or output is non-TTY.
 *
 * @returns {ColorTheme} Plain theme with no ANSI codes
 */
export function createPlainTheme(): ColorTheme;

/**
 * Creates Unicode symbol set.
 *
 * @returns {SymbolSet} Unicode symbols
 */
export function createUnicodeSymbols(): SymbolSet;

/**
 * Creates ASCII symbol set for terminals without Unicode support.
 *
 * @returns {SymbolSet} ASCII-safe symbols
 */
export function createAsciiSymbols(): SymbolSet;
