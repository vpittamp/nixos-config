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
} from "./src/terminal-capabilities.ts";

// Progress indicators
export {
  createProgress,
  ProgressBar,
  Spinner,
  withProgress,
  type ProgressOptions,
} from "./src/progress-indicator.ts";

// Output formatting
export {
  createAsciiSymbols,
  createDarkTheme,
  createLightTheme,
  createPlainTheme,
  createUnicodeSymbols,
  OutputFormatter,
  type ColorTheme,
  type SymbolSet,
} from "./src/output-formatter.ts";

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
} from "./src/interactive-prompts.ts";

// Event streaming
export {
  aggregateEvents,
  createEventBuffer,
  EventStream,
  formatEvent,
  streamEventsLive,
  type Event,
  type EventStreamOptions,
} from "./src/event-stream.ts";

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
} from "./src/table-renderer.ts";

// Import for internal use
import { detectTerminalCapabilities } from "./src/terminal-capabilities.ts";
import { OutputFormatter } from "./src/output-formatter.ts";

export const VERSION = "1.0.0";

/**
 * Convenience setup function that detects terminal capabilities
 * and returns ready-to-use instances.
 *
 * @returns Object with capabilities and formatter
 *
 * @example
 * ```typescript
 * import { setup } from "@cli-ux";
 *
 * const { capabilities, formatter } = setup();
 * console.log(formatter.success("Ready!"));
 * ```
 */
export function setup() {
  const capabilities = detectTerminalCapabilities();
  const formatter = new OutputFormatter(capabilities);

  return {
    capabilities,
    formatter,
  };
}
