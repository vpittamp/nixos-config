/**
 * Event Stream API
 *
 * Provides real-time event streaming with buffering, <100ms latency, and
 * graceful Ctrl+C handling.
 *
 * @module event-stream
 */

import type { TerminalCapabilities } from "./terminal-capabilities.ts";
import { OutputFormatter } from "./output-formatter.ts";

/** Generic event structure */
export interface Event<T = unknown> {
  /** Event timestamp (milliseconds since epoch) */
  timestamp: number;
  /** Event type identifier */
  type: string;
  /** Event payload data */
  payload: T;
}

/** Event stream configuration options */
export interface EventStreamOptions {
  /** Maximum buffer size (default: 500) */
  bufferSize?: number;
  /** Flush interval in milliseconds (default: 100ms for <100ms latency) */
  flushInterval?: number;
  /** Enable event aggregation to combine duplicates (default: true) */
  aggregate?: boolean;
  /** Optional filter function to exclude events */
  filter?: (event: Event) => boolean;
  /** Terminal capabilities for formatting */
  capabilities?: TerminalCapabilities;
}

/** Event handler callback type */
type EventHandler<T> = (events: Event<T>[]) => void;

/** Error handler callback type */
type ErrorHandler = (error: Error) => void;

/**
 * Event stream with circular buffer and automatic flushing.
 *
 * Buffers incoming events and flushes them periodically to prevent terminal
 * flooding while maintaining <100ms latency.
 */
export class EventStream<T = unknown> {
  #buffer: Event<T>[] = [];
  #maxSize: number;
  #flushInterval: number;
  #aggregate: boolean;
  #filter?: (event: Event<T>) => boolean;
  #intervalId: number | null = null;
  #totalEvents = 0;
  #flushHandlers: Set<EventHandler<T>> = new Set();
  #errorHandlers: Set<ErrorHandler> = new Set();

  constructor(options: EventStreamOptions = {}) {
    this.#maxSize = options.bufferSize ?? 500;
    this.#flushInterval = options.flushInterval ?? 100;
    this.#aggregate = options.aggregate ?? true;
    this.#filter = options.filter;

    // Start auto-flush timer
    this.#intervalId = setInterval(() => {
      if (this.#buffer.length > 0) {
        this.flush();
      }
    }, this.#flushInterval);
  }

  /** Get maximum buffer size */
  get bufferSize(): number {
    return this.#maxSize;
  }

  /** Get current number of buffered events */
  get eventCount(): number {
    return this.#buffer.length;
  }

  /** Get total number of events processed */
  get totalEvents(): number {
    return this.#totalEvents;
  }

  /**
   * Push an event into the stream.
   * Automatically flushes if buffer is full.
   *
   * @param event - Event to add to the stream
   */
  push(event: Event<T>): void {
    // Apply filter if provided
    if (this.#filter && !this.#filter(event)) {
      return;
    }

    this.#totalEvents++;

    // Add to circular buffer
    this.#buffer.push(event);
    if (this.#buffer.length > this.#maxSize) {
      this.#buffer.shift(); // Remove oldest
    }

    // Flush immediately if buffer full
    if (this.#buffer.length >= this.#maxSize) {
      this.flush();
    }
  }

  /**
   * Flush all buffered events to registered handlers.
   * Applies aggregation if enabled.
   */
  flush(): void {
    if (this.#buffer.length === 0) return;

    const events = this.#aggregate
      ? this.#aggregateEvents([...this.#buffer])
      : [...this.#buffer];

    this.#buffer = []; // Clear buffer

    // Notify handlers
    this.#flushHandlers.forEach((handler) => {
      try {
        handler(events);
      } catch (error) {
        this.#errorHandlers.forEach((eh) => eh(error as Error));
      }
    });
  }

  /**
   * Clear all buffered events without flushing.
   */
  clear(): void {
    this.#buffer = [];
  }

  /**
   * Stop the stream and perform final flush.
   */
  stop(): void {
    if (this.#intervalId !== null) {
      clearInterval(this.#intervalId);
      this.#intervalId = null;
    }
    this.flush(); // Final flush
  }

  /**
   * Register event handlers.
   *
   * @param event - Event type ("flush" or "error")
   * @param handler - Handler function
   */
  on(event: "flush", handler: EventHandler<T>): void;
  on(event: "error", handler: ErrorHandler): void;
  on(event: string, handler: unknown): void {
    if (event === "flush") {
      this.#flushHandlers.add(handler as EventHandler<T>);
    } else if (event === "error") {
      this.#errorHandlers.add(handler as ErrorHandler);
    }
  }

  /**
   * Unregister event handlers.
   *
   * @param event - Event type ("flush" or "error")
   * @param handler - Handler function to remove
   */
  off(event: "flush" | "error", handler: (data: unknown) => void): void {
    if (event === "flush") {
      this.#flushHandlers.delete(handler as EventHandler<T>);
    } else if (event === "error") {
      this.#errorHandlers.delete(handler as ErrorHandler);
    }
  }

  /**
   * Aggregate sequential events of the same type within 200ms.
   * Reduces duplicate events in rapid succession.
   *
   * @param events - Events to aggregate
   * @returns Aggregated event list
   */
  #aggregateEvents(events: Event<T>[]): Event<T>[] {
    const aggregated: Event<T>[] = [];
    let current: Event<T> | null = null;

    for (const event of events) {
      if (
        current &&
        current.type === event.type &&
        event.timestamp - current.timestamp < 200
      ) {
        // Skip duplicate - already represented by current
      } else {
        if (current) aggregated.push(current);
        current = event;
      }
    }

    if (current) aggregated.push(current);
    return aggregated;
  }
}

/**
 * Stream events live to the console with graceful Ctrl+C handling.
 *
 * @param source - AsyncIterable source of events
 * @param options - Streaming options
 */
export async function streamEventsLive<T>(
  source: AsyncIterable<Event<T>>,
  options: {
    formatter?: (event: Event<T>) => string;
    filter?: (event: Event<T>) => boolean;
    capabilities?: TerminalCapabilities;
  } = {},
): Promise<void> {
  const fmt = new OutputFormatter(options.capabilities);

  // Setup Ctrl+C handler for graceful exit
  let running = true;
  const abortController = new AbortController();

  const signalHandler = () => {
    running = false;
    abortController.abort();
  };

  Deno.addSignalListener("SIGINT", signalHandler);

  try {
    for await (const event of source) {
      if (!running) break;

      // Apply filter
      if (options.filter && !options.filter(event)) {
        continue;
      }

      // Format and display
      const output = options.formatter
        ? options.formatter(event)
        : formatEvent(event);

      console.log(output);
    }
  } finally {
    Deno.removeSignalListener("SIGINT", signalHandler);
    console.log(fmt.dim("\n--- Stream ended ---"));
  }
}

/**
 * Format an event for display.
 *
 * @param event - Event to format
 * @param options - Formatting options
 * @returns Formatted event string
 */
export function formatEvent<T>(
  event: Event<T>,
  options: {
    showTimestamp?: boolean;
    showType?: boolean;
    capabilities?: TerminalCapabilities;
  } = {},
): string {
  const showTimestamp = options.showTimestamp ?? true;
  const showType = options.showType ?? true;
  const fmt = new OutputFormatter(options.capabilities);

  const parts: string[] = [];

  if (showTimestamp) {
    const date = new Date(event.timestamp);
    const time = date.toLocaleTimeString();
    parts.push(fmt.dim(`[${time}]`));
  }

  if (showType) {
    parts.push(fmt.bold(`[${event.type}]`));
  }

  parts.push(String(event.payload));

  return parts.join(" ");
}

/**
 * Aggregate events by combining duplicates within a time window.
 *
 * @param events - Events to aggregate
 * @returns Aggregated events
 */
export function aggregateEvents<T>(
  events: Event<T>[],
): Event<T>[] {
  // Use EventStream for consistent aggregation logic
  const stream = new EventStream<T>({ aggregate: true });
  const result: Event<T>[] = [];

  stream.on("flush", (flushed) => result.push(...flushed));

  events.forEach((e) => stream.push(e));
  stream.flush();
  stream.stop();

  return result;
}

/**
 * Create a circular event buffer with fixed capacity.
 *
 * @param maxSize - Maximum number of events to store
 * @returns Event buffer object
 */
export function createEventBuffer<T>(maxSize: number) {
  const buffer: Event<T>[] = [];

  return {
    /**
     * Add an event to the buffer.
     * Removes oldest event if buffer is full.
     */
    push(event: Event<T>): void {
      buffer.push(event);
      if (buffer.length > maxSize) {
        buffer.shift();
      }
    },

    /**
     * Get events from the buffer.
     * @param count - Number of recent events to retrieve (default: all)
     * @returns Array of events
     */
    get(count?: number): Event<T>[] {
      if (count === undefined) return [...buffer];
      return buffer.slice(-count);
    },

    /**
     * Clear all events from the buffer.
     */
    clear(): void {
      buffer.length = 0;
    },

    /**
     * Get current buffer size.
     */
    get size(): number {
      return buffer.length;
    },
  };
}
