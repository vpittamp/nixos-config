/**
 * Logger Utility
 *
 * Provides verbose and debug logging capabilities across the CLI.
 */

import * as ansi from "../ui/ansi.ts";

/**
 * Global logging configuration
 */
let verboseEnabled = false;
let debugEnabled = false;

/**
 * Enable verbose logging
 */
export function enableVerbose(): void {
  verboseEnabled = true;
}

/**
 * Enable debug logging (includes verbose)
 */
export function enableDebug(): void {
  debugEnabled = true;
  verboseEnabled = true; // Debug implies verbose
}

/**
 * Check if verbose logging is enabled
 */
export function isVerbose(): boolean {
  return verboseEnabled;
}

/**
 * Check if debug logging is enabled
 */
export function isDebug(): boolean {
  return debugEnabled;
}

/**
 * Log verbose message
 */
export function verbose(message: string, ...args: unknown[]): void {
  if (verboseEnabled) {
    console.error(`${ansi.DIM}[VERBOSE]${ansi.RESET} ${message}`, ...args);
  }
}

/**
 * Log debug message
 */
export function debug(message: string, ...args: unknown[]): void {
  if (debugEnabled) {
    console.error(`${ansi.CYAN}[DEBUG]${ansi.RESET} ${message}`, ...args);
  }
}

/**
 * Log error message (always shown)
 */
export function error(message: string, ...args: unknown[]): void {
  console.error(`${ansi.RED}[ERROR]${ansi.RESET} ${message}`, ...args);
}

/**
 * Log warning message (always shown)
 */
export function warn(message: string, ...args: unknown[]): void {
  console.error(`${ansi.YELLOW}[WARN]${ansi.RESET} ${message}`, ...args);
}

/**
 * Log info message (always shown)
 */
export function info(message: string, ...args: unknown[]): void {
  console.error(`${ansi.GREEN}[INFO]${ansi.RESET} ${message}`, ...args);
}

/**
 * Log JSON object for debugging
 */
export function debugJson(label: string, obj: unknown): void {
  if (debugEnabled) {
    console.error(`${ansi.CYAN}[DEBUG]${ansi.RESET} ${label}:`);
    console.error(JSON.stringify(obj, null, 2));
  }
}

/**
 * Log RPC request for debugging
 */
export function debugRpcRequest(method: string, params?: unknown): void {
  if (debugEnabled) {
    console.error(`${ansi.CYAN}[DEBUG]${ansi.RESET} RPC Request: ${method}`);
    if (params) {
      console.error(`  Params: ${JSON.stringify(params)}`);
    }
  }
}

/**
 * Log RPC response for debugging
 */
export function debugRpcResponse(method: string, result: unknown): void {
  if (debugEnabled) {
    console.error(`${ansi.CYAN}[DEBUG]${ansi.RESET} RPC Response: ${method}`);
    console.error(`  Result: ${JSON.stringify(result, null, 2)}`);
  }
}

/**
 * Log socket connection details
 */
export function debugSocket(message: string, path?: string): void {
  if (debugEnabled) {
    console.error(`${ansi.CYAN}[DEBUG]${ansi.RESET} Socket: ${message}`);
    if (path) {
      console.error(`  Path: ${path}`);
    }
  }
}

/**
 * Log terminal state changes
 */
export function debugTerminal(message: string): void {
  if (debugEnabled) {
    console.error(`${ansi.CYAN}[DEBUG]${ansi.RESET} Terminal: ${message}`);
  }
}

/**
 * Log signal handling events
 */
export function debugSignal(signal: string, action: string): void {
  if (debugEnabled) {
    console.error(`${ansi.CYAN}[DEBUG]${ansi.RESET} Signal: ${signal} -> ${action}`);
  }
}

/**
 * Log validation details
 */
export function debugValidation(message: string, details?: unknown): void {
  if (debugEnabled) {
    console.error(`${ansi.CYAN}[DEBUG]${ansi.RESET} Validation: ${message}`);
    if (details) {
      console.error(`  Details: ${JSON.stringify(details, null, 2)}`);
    }
  }
}
