/**
 * Event Stream API
 *
 * Provides real-time event streaming with buffering, aggregation, and
 * live display capabilities for monitoring daemon events and i3 IPC.
 *
 * @module event-stream
 */

import type { TerminalCapabilities } from "./terminal-capabilities.ts";

/** Generic event structure */
export interface Event<T = unknown> {
  /** Event timestamp (milliseconds since epoch) */
  timestamp: number;
  /** Event type identifier */
  type: string;
  /** Event payload data */
  payload: T;
}

/** Event stream configuration */
export interface EventStreamOptions {
  /** Maximum buffer size (default: 500) */
  bufferSize?: number;
  /** Flush interval in milliseconds (default: 100) */
  flushInterval?: number;
  /** Whether to aggregate duplicate events (default: true) */
  aggregate?: boolean;
  /** Event filter function (return false to skip event) */
  filter?: (event: Event) => boolean;
  /** Terminal capabilities (auto-detected if omitted) */
  capabilities?: TerminalCapabilities;
}

/** Event stream state for live monitoring */
export class EventStream<T = unknown> {
  /**
   * Creates an event stream with buffering and aggregation.
   *
   * @param {EventStreamOptions} options - Stream configuration
   *
   * @example
   * ```typescript
   * const stream = new EventStream({
   *   bufferSize: 500,
   *   flushInterval: 100,
   *   filter: (event) => event.type !== "noise",
   * });
   *
   * stream.on("flush", (events) => {
   *   events.forEach(e => console.log(`[${e.type}] ${e.payload}`));
   * });
   *
   * stream.push({ timestamp: Date.now(), type: "window", payload: data });
   * ```
   */
  constructor(options?: EventStreamOptions);

  /** Current buffer size */
  readonly bufferSize: number;

  /** Number of events in buffer */
  readonly eventCount: number;

  /** Total events received since start */
  readonly totalEvents: number;

  /**
   * Adds an event to the stream.
   *
   * Event will be buffered and flushed according to flushInterval or when
   * buffer reaches capacity.
   *
   * @param {Event<T>} event - Event to add
   */
  push(event: Event<T>): void;

  /**
   * Manually flushes buffered events.
   *
   * Triggers "flush" event with current buffer contents.
   */
  flush(): void;

  /**
   * Clears all buffered events without flushing.
   */
  clear(): void;

  /**
   * Stops the stream and cleans up resources.
   */
  stop(): void;

  /**
   * Registers an event handler.
   *
   * @param {"flush" | "error"} event - Event name
   * @param {function} handler - Event handler function
   *
   * @example
   * ```typescript
   * stream.on("flush", (events) => {
   *   console.log(`Flushing ${events.length} events`);
   * });
   *
   * stream.on("error", (error) => {
   *   console.error("Stream error:", error);
   * });
   * ```
   */
  on(event: "flush", handler: (events: Event<T>[]) => void): void;
  on(event: "error", handler: (error: Error) => void): void;

  /**
   * Removes an event handler.
   *
   * @param {"flush" | "error"} event - Event name
   * @param {function} handler - Handler to remove
   */
  off(event: "flush" | "error", handler: (data: unknown) => void): void;
}

/**
 * Streams events with live display in terminal.
 *
 * Displays events as they arrive with timestamps, types, and formatted payloads.
 *
 * @param {AsyncIterable<Event>} source - Event source (async iterator)
 * @param {object} options - Display options
 * @param {function} [options.formatter] - Custom event formatter
 * @param {function} [options.filter] - Event filter predicate
 * @param {TerminalCapabilities} [options.capabilities] - Terminal capabilities
 * @returns {Promise<void>} Resolves when stream ends or is interrupted
 *
 * @example
 * ```typescript
 * async function* eventGenerator() {
 *   for (let i = 0; i < 100; i++) {
 *     yield { timestamp: Date.now(), type: "test", payload: i };
 *     await delay(100);
 *   }
 * }
 *
 * await streamEventsLive(eventGenerator(), {
 *   formatter: (e) => `Event #${e.payload}: ${e.type}`,
 *   filter: (e) => e.payload % 2 === 0, // Only even numbers
 * });
 * ```
 */
export function streamEventsLive<T>(
  source: AsyncIterable<Event<T>>,
  options?: {
    formatter?: (event: Event<T>) => string;
    filter?: (event: Event<T>) => boolean;
    capabilities?: TerminalCapabilities;
  },
): Promise<void>;

/**
 * Formats an event for display with timestamp and type.
 *
 * @param {Event} event - Event to format
 * @param {object} options - Format options
 * @param {boolean} [options.showTimestamp] - Include timestamp (default: true)
 * @param {boolean} [options.showType] - Include event type (default: true)
 * @param {TerminalCapabilities} [options.capabilities] - Terminal capabilities
 * @returns {string} Formatted event string
 *
 * @example
 * ```typescript
 * const event = { timestamp: Date.now(), type: "window", payload: "focus" };
 * console.log(formatEvent(event));
 * // Output: [12:34:56] [window] focus
 * ```
 */
export function formatEvent<T>(
  event: Event<T>,
  options?: {
    showTimestamp?: boolean;
    showType?: boolean;
    capabilities?: TerminalCapabilities;
  },
): string;

/**
 * Aggregates duplicate events within a time window.
 *
 * Combines sequential events of the same type within windowMs into a single
 * event with aggregated payload.
 *
 * @param {Event[]} events - Events to aggregate
 * @param {number} windowMs - Time window for aggregation (milliseconds)
 * @returns {Event[]} Aggregated events
 *
 * @example
 * ```typescript
 * const events = [
 *   { timestamp: 1000, type: "click", payload: 1 },
 *   { timestamp: 1050, type: "click", payload: 1 },
 *   { timestamp: 1100, type: "click", payload: 1 },
 * ];
 *
 * const aggregated = aggregateEvents(events, 200);
 * // Result: [{ timestamp: 1000, type: "click", payload: 3 }]
 * ```
 */
export function aggregateEvents<T>(
  events: Event<T>[],
  windowMs: number,
): Event<T>[];

/**
 * Creates a circular buffer for event history.
 *
 * Maintains a fixed-size buffer of recent events with automatic overflow handling.
 *
 * @param {number} maxSize - Maximum buffer size
 * @returns {object} Buffer with push/get/clear methods
 *
 * @example
 * ```typescript
 * const buffer = createEventBuffer(100);
 *
 * buffer.push(event1);
 * buffer.push(event2);
 *
 * const recent = buffer.get(10); // Get last 10 events
 * buffer.clear(); // Clear all events
 * ```
 */
export function createEventBuffer<T>(maxSize: number): {
  push(event: Event<T>): void;
  get(count?: number): Event<T>[];
  clear(): void;
  readonly size: number;
};
