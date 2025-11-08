/**
 * Event Subscriber Service
 *
 * Sway IPC event subscription via swaymsg subprocess.
 * Provides event-driven waiting with filtering.
 */

/**
 * Sway IPC event types
 */
export type SwayEventType = "window" | "workspace" | "binding" | "shutdown" | "tick";

/**
 * Event criteria for filtering
 */
export interface EventCriteria {
  app_id?: string;           // Match by app_id (partial match)
  window_class?: string;      // Match by X11 class (partial match)
  change?: string;            // Match by change type (exact match)
  workspace?: number;         // Match by workspace number (exact match)
  name?: string;              // Match by window title (partial match)
  payload?: string;           // Match by tick payload (exact match)
}

/**
 * Sway container (window) data
 */
export interface SwayContainer {
  id: number;
  pid?: number;
  app_id?: string;
  window_properties?: {
    class?: string;
    instance?: string;
  };
  name: string;
  type: string;
  workspace?: number;
}

/**
 * Sway workspace data
 */
export interface SwayWorkspace {
  num: number;
  name: string;
  focused: boolean;
  output: string;
}

/**
 * Sway binding data
 */
export interface SwayBinding {
  command: string;
  input_type: string;
  symbol: string;
  event_state_mask: string[];
}

/**
 * Sway IPC event
 */
export interface SwayEvent {
  change: string;
  container?: SwayContainer;
  current?: SwayWorkspace;
  binding?: SwayBinding;
  payload?: string;  // For tick events
}

/**
 * Event subscription handle
 */
export interface EventSubscription {
  id: string;
  unsubscribe: () => void;
}

// Global subscription counter
let subscriptionCounter = 0;

/**
 * Subscribe to Sway IPC events with filtering criteria
 *
 * @param eventTypes - Array of Sway event types to subscribe to
 * @param criteria - Optional filtering criteria
 * @param callback - Function called for each matching event
 * @returns EventSubscription object with unsubscribe() method
 */
export function subscribeToEvents(
  eventTypes: SwayEventType[],
  criteria: EventCriteria | undefined,
  callback: (event: SwayEvent) => void
): EventSubscription {
  if (eventTypes.length === 0) {
    throw new Error("eventTypes must not be empty");
  }

  const subscriptionId = `sub-${++subscriptionCounter}`;

  // Spawn swaymsg subprocess
  const command = new Deno.Command("swaymsg", {
    args: ["-t", "subscribe", "-m", JSON.stringify(eventTypes)],
    stdout: "piped",
    stderr: "piped",
  });

  const process = command.spawn();
  const abortController = new AbortController();

  // Read events from stdout
  (async () => {
    try {
      const decoder = new TextDecoder();
      let buffer = "";

      for await (const chunk of process.stdout) {
        if (abortController.signal.aborted) break;

        buffer += decoder.decode(chunk);
        const lines = buffer.split("\n");

        // Keep the last incomplete line in buffer
        buffer = lines.pop() || "";

        for (const line of lines) {
          if (!line.trim()) continue;

          try {
            const event = JSON.parse(line) as SwayEvent;

            // Check if event matches criteria
            if (!criteria || matchesEventCriteria(event, criteria)) {
              callback(event);
            }
          } catch (error) {
          }
        }
      }
    } catch (error) {
      if (!abortController.signal.aborted) {
      }
    }
  })();

  // Read errors from stderr
  (async () => {
    try {
      const decoder = new TextDecoder();
      for await (const chunk of process.stderr) {
        if (abortController.signal.aborted) break;
        const error = decoder.decode(chunk).trim();
        if (error) {
        }
      }
    } catch {
      // Ignore errors during cleanup
    }
  })();

  // Unsubscribe function
  const unsubscribe = () => {
    abortController.abort();
    try {
      process.kill("SIGTERM");
    } catch {
      // Process may already be terminated
    }
  };

  return {
    id: subscriptionId,
    unsubscribe,
  };
}

/**
 * Wait for a specific Sway IPC event with timeout
 *
 * @param eventType - Single Sway event type to wait for
 * @param criteria - Optional filtering criteria
 * @param timeoutMs - Timeout in milliseconds (default 10000, max 60000)
 * @returns Promise that resolves to the matching SwayEvent
 * @throws WaitEventTimeoutError if timeout expires before event arrives
 */
export async function waitForEvent(
  eventType: SwayEventType,
  criteria: EventCriteria | undefined,
  timeoutMs: number = 10000
): Promise<SwayEvent> {
  if (timeoutMs > 60000) {
    throw new Error("Timeout cannot exceed 60000ms (60 seconds)");
  }


  // Create abort controller for cleanup
  const abortController = new AbortController();

  // Promise that resolves when event arrives
  const eventPromise = new Promise<SwayEvent>((resolve) => {
    const subscription = subscribeToEvents([eventType], criteria, (event) => {
      resolve(event);
      abortController.abort();
    });

    // Cleanup on abort
    abortController.signal.addEventListener("abort", () => {
      subscription.unsubscribe();
    });
  });

  // Promise that rejects after timeout
  const timeoutPromise = new Promise<SwayEvent>((_, reject) => {
    setTimeout(() => {
      reject(new WaitEventTimeoutError(eventType, criteria, timeoutMs));
      abortController.abort();
    }, timeoutMs);
  });

  // Race between event arrival and timeout
  return Promise.race([eventPromise, timeoutPromise]);
}

/**
 * Check if event matches criteria
 */
function matchesEventCriteria(event: SwayEvent, criteria: EventCriteria): boolean {
  // Match change type (exact)
  if (criteria.change && event.change !== criteria.change) {
    return false;
  }

  // Match app_id (partial)
  if (criteria.app_id && event.container) {
    if (!event.container.app_id?.includes(criteria.app_id)) {
      return false;
    }
  }

  // Match window class (partial)
  if (criteria.window_class && event.container) {
    if (!event.container.window_properties?.class?.includes(criteria.window_class)) {
      return false;
    }
  }

  // Match workspace (exact)
  if (criteria.workspace !== undefined) {
    if (event.container?.workspace !== criteria.workspace &&
        event.current?.num !== criteria.workspace) {
      return false;
    }
  }

  // Match window title (partial)
  if (criteria.name && event.container) {
    if (!event.container.name?.includes(criteria.name)) {
      return false;
    }
  }

  // Match tick payload (exact)
  if (criteria.payload && event.payload !== criteria.payload) {
    return false;
  }

  return true;
}

/**
 * Error thrown when wait_event times out
 */
export class WaitEventTimeoutError extends Error {
  constructor(
    public eventType: string,
    public criteria: EventCriteria | undefined,
    public timeoutMs: number
  ) {
    super(
      `WaitEventTimeoutError: No matching event after ${timeoutMs}ms\n` +
      `Event type: ${eventType}\n` +
      `Criteria: ${JSON.stringify(criteria || {}, null, 2)}`
    );
    this.name = "WaitEventTimeoutError";
  }
}
