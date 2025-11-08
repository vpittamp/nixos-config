/**
 * Structured Logger Service (T077)
 *
 * Provides JSON Lines format logging for machine-readable test diagnostics.
 * Captures IPC operations, action execution, state captures, and test events.
 */

/**
 * Log level enumeration
 */
export enum LogLevel {
  DEBUG = "debug",
  INFO = "info",
  WARN = "warn",
  ERROR = "error",
}

/**
 * Log event type
 */
export enum LogEventType {
  TEST_START = "test_start",
  TEST_END = "test_end",
  ACTION_START = "action_start",
  ACTION_END = "action_end",
  IPC_COMMAND = "ipc_command",
  STATE_CAPTURE = "state_capture",
  STATE_COMPARISON = "state_comparison",
  FIXTURE_SETUP = "fixture_setup",
  FIXTURE_TEARDOWN = "fixture_teardown",
  ERROR = "error",
  DEBUG = "debug",
}

/**
 * Base log entry structure
 */
export interface LogEntry {
  timestamp: string; // ISO 8601 format
  level: LogLevel;
  event_type: LogEventType;
  message: string;
  context?: Record<string, unknown>;
  duration_ms?: number;
  error?: {
    message: string;
    stack?: string;
  };
}

/**
 * Logger configuration options
 */
export interface LoggerOptions {
  /** Minimum log level to output */
  level?: LogLevel;
  /** Output file path (default: stdout) */
  outputFile?: string;
  /** Pretty print JSON (default: false for JSON Lines) */
  pretty?: boolean;
}

/**
 * Structured Logger Service
 */
export class Logger {
  private level: LogLevel;
  private outputFile?: string;
  private pretty: boolean;
  private buffer: string[] = [];
  private fileHandle?: Deno.FsFile;

  constructor(options: LoggerOptions = {}) {
    this.level = options.level || LogLevel.INFO;
    this.outputFile = options.outputFile;
    this.pretty = options.pretty || false;
  }

  /**
   * Initialize logger (open file handle if needed)
   */
  async init(): Promise<void> {
    if (this.outputFile) {
      this.fileHandle = await Deno.open(this.outputFile, {
        write: true,
        create: true,
        append: true,
      });
    }
  }

  /**
   * Close logger (flush buffer, close file handle)
   */
  async close(): Promise<void> {
    await this.flush();
    if (this.fileHandle) {
      this.fileHandle.close();
      this.fileHandle = undefined;
    }
  }

  /**
   * Flush buffered log entries
   */
  async flush(): Promise<void> {
    if (this.buffer.length === 0) {
      return;
    }

    const output = this.buffer.join("\n") + "\n";
    this.buffer = [];

    if (this.fileHandle) {
      const encoder = new TextEncoder();
      await this.fileHandle.write(encoder.encode(output));
    } else {
      Deno.stdout.writeSync(new TextEncoder().encode(output));
    }
  }

  /**
   * Log entry with specified level
   */
  private log(
    level: LogLevel,
    eventType: LogEventType,
    message: string,
    context?: Record<string, unknown>,
    duration?: number,
    error?: Error,
  ): void {
    // Filter by log level
    if (!this.shouldLog(level)) {
      return;
    }

    const entry: LogEntry = {
      timestamp: new Date().toISOString(),
      level,
      event_type: eventType,
      message,
    };

    if (context) {
      entry.context = context;
    }

    if (duration !== undefined) {
      entry.duration_ms = duration;
    }

    if (error) {
      entry.error = {
        message: error.message,
        stack: error.stack,
      };
    }

    // Serialize to JSON Lines format
    const serialized = this.pretty
      ? JSON.stringify(entry, null, 2)
      : JSON.stringify(entry);

    this.buffer.push(serialized);

    // Auto-flush on error or if buffer is large
    if (level === LogLevel.ERROR || this.buffer.length >= 100) {
      this.flush().catch((err) => {
        console.error("Failed to flush log buffer:", err);
      });
    }
  }

  /**
   * Check if log level should be output
   */
  private shouldLog(level: LogLevel): boolean {
    const levels = [LogLevel.DEBUG, LogLevel.INFO, LogLevel.WARN, LogLevel.ERROR];
    const minIndex = levels.indexOf(this.level);
    const currentIndex = levels.indexOf(level);
    return currentIndex >= minIndex;
  }

  /**
   * Log test start event
   */
  testStart(testName: string, context?: Record<string, unknown>): void {
    this.log(LogLevel.INFO, LogEventType.TEST_START, `Test started: ${testName}`, context);
  }

  /**
   * Log test end event
   */
  testEnd(testName: string, passed: boolean, duration: number): void {
    this.log(
      passed ? LogLevel.INFO : LogLevel.WARN,
      LogEventType.TEST_END,
      `Test ${passed ? "passed" : "failed"}: ${testName}`,
      { passed },
      duration,
    );
  }

  /**
   * Log action start event
   */
  actionStart(actionType: string, params: Record<string, unknown>): void {
    this.log(
      LogLevel.DEBUG,
      LogEventType.ACTION_START,
      `Action started: ${actionType}`,
      { action_type: actionType, params },
    );
  }

  /**
   * Log action end event
   */
  actionEnd(actionType: string, success: boolean, duration: number, error?: Error): void {
    this.log(
      success ? LogLevel.DEBUG : LogLevel.ERROR,
      LogEventType.ACTION_END,
      `Action ${success ? "completed" : "failed"}: ${actionType}`,
      { action_type: actionType, success },
      duration,
      error,
    );
  }

  /**
   * Log IPC command
   */
  ipcCommand(command: string, context?: Record<string, unknown>): void {
    this.log(
      LogLevel.DEBUG,
      LogEventType.IPC_COMMAND,
      `IPC command: ${command}`,
      { ...context, command },
    );
  }

  /**
   * Log state capture event
   */
  stateCapture(context?: Record<string, unknown>): void {
    this.log(
      LogLevel.DEBUG,
      LogEventType.STATE_CAPTURE,
      "State captured from Sway",
      context,
    );
  }

  /**
   * Log state comparison event
   */
  stateComparison(matches: boolean, differences: number, context?: Record<string, unknown>): void {
    this.log(
      matches ? LogLevel.INFO : LogLevel.WARN,
      LogEventType.STATE_COMPARISON,
      `State comparison: ${matches ? "match" : `mismatch (${differences} differences)`}`,
      { ...context, matches, differences },
    );
  }

  /**
   * Log fixture setup event
   */
  fixtureSetup(fixtureName: string, duration: number): void {
    this.log(
      LogLevel.DEBUG,
      LogEventType.FIXTURE_SETUP,
      `Fixture setup: ${fixtureName}`,
      { fixture: fixtureName },
      duration,
    );
  }

  /**
   * Log fixture teardown event
   */
  fixtureTeardown(fixtureName: string, duration: number): void {
    this.log(
      LogLevel.DEBUG,
      LogEventType.FIXTURE_TEARDOWN,
      `Fixture teardown: ${fixtureName}`,
      { fixture: fixtureName },
      duration,
    );
  }

  /**
   * Log error event
   */
  error(message: string, error?: Error, context?: Record<string, unknown>): void {
    this.log(LogLevel.ERROR, LogEventType.ERROR, message, context, undefined, error);
  }

  /**
   * Log debug message
   */
  debug(message: string, context?: Record<string, unknown>): void {
    this.log(LogLevel.DEBUG, LogEventType.DEBUG, message, context);
  }

  /**
   * Log info message
   */
  info(message: string, context?: Record<string, unknown>): void {
    this.log(LogLevel.INFO, LogEventType.DEBUG, message, context);
  }

  /**
   * Log warning message
   */
  warn(message: string, context?: Record<string, unknown>): void {
    this.log(LogLevel.WARN, LogEventType.DEBUG, message, context);
  }
}

/**
 * Global logger instance (singleton pattern)
 */
let globalLogger: Logger | null = null;

/**
 * Get or create global logger instance
 */
export function getLogger(options?: LoggerOptions): Logger {
  if (!globalLogger) {
    globalLogger = new Logger(options);
  }
  return globalLogger;
}

/**
 * Reset global logger (useful for testing)
 */
export function resetLogger(): void {
  if (globalLogger) {
    globalLogger.close().catch(() => {}); // Ignore errors on close
    globalLogger = null;
  }
}
