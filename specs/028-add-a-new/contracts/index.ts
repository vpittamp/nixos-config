/**
 * CLI User Experience Enhancement Library
 *
 * Provides modern CLI UX patterns including progress indicators, semantic
 * color coding, interactive prompts, table rendering, and event streaming.
 *
 * @module cli-ux
 * @version 1.0.0
 */

// Terminal capabilities detection
export {
  ColorLevel,
  detectColorSupport,
  detectTerminalCapabilities,
  getTerminalSize,
  onTerminalResize,
  supportsUnicode,
  type TerminalCapabilities,
} from "./terminal-capabilities.ts";

// Output formatting and colors
export {
  createAsciiSymbols,
  createDarkTheme,
  createLightTheme,
  createPlainTheme,
  createUnicodeSymbols,
  OutputFormatter,
  type ColorTheme,
  type SymbolSet,
} from "./output-formatter.ts";

// Progress indicators
export {
  createProgress,
  ProgressBar,
  Spinner,
  withProgress,
  type ProgressOptions,
} from "./progress-indicator.ts";

// Interactive prompts
export {
  canPrompt,
  promptConfirm,
  promptInput,
  promptMultipleSelect,
  promptSecret,
  promptSelect,
  type MenuItem,
  type MultiSelectOptions,
  type SelectOptions,
} from "./interactive-prompts.ts";

// Table rendering
export {
  calculateTableLayout,
  formatCell,
  renderTable,
  sortTableData,
  TableRenderer,
  truncateText,
  type Alignment,
  type TableColumn,
  type TableLayout,
  type TableOptions,
} from "./table-renderer.ts";

// Event streaming
export {
  aggregateEvents,
  createEventBuffer,
  EventStream,
  formatEvent,
  streamEventsLive,
  type Event,
  type EventStreamOptions,
} from "./event-stream.ts";

/**
 * Package version
 */
export const VERSION = "1.0.0";

/**
 * Quick setup helper that creates commonly-used instances.
 *
 * @returns {object} Configured instances ready to use
 *
 * @example
 * ```typescript
 * import { setup } from "@cli-ux";
 *
 * const { formatter, capabilities } = setup();
 *
 * console.log(formatter.success("Ready!"));
 * console.log(`Terminal: ${capabilities.width}x${capabilities.height}`);
 * ```
 */
export function setup(): {
  capabilities: TerminalCapabilities;
  formatter: OutputFormatter;
};
