/**
 * JSON-RPC 2.0 Client for Daemon Communication
 *
 * Handles all communication with the i3-project-daemon via Unix socket.
 * Supports both request-response and notification (event subscription) patterns.
 */

import type {
  JsonRpcNotification,
  JsonRpcRequest,
  JsonRpcResponse,
} from "./models.ts";
import { connectWithRetry, getSocketPath } from "./utils/socket.ts";
import { parseDaemonConnectionError } from "./utils/errors.ts";
import * as logger from "./utils/logger.ts";

/**
 * Pending request tracking
 */
interface PendingRequest<T = unknown> {
  resolve: (value: T) => void;
  reject: (error: Error) => void;
  timeout: number;
}

/**
 * Notification handler type
 */
export type NotificationHandler = (notification: JsonRpcNotification) => void | Promise<void>;

/**
 * JSON-RPC 2.0 Client
 */
export class DaemonClient {
  private socketPath: string;
  private conn: Deno.UnixConn | null = null;
  private requestId = 0;
  private pendingRequests = new Map<number, PendingRequest<unknown>>();
  private notificationHandlers: NotificationHandler[] = [];
  private encoder = new TextEncoder();
  private decoder = new TextDecoder();
  private readLoopActive = false;
  private readLoopPromise: Promise<void> | null = null;

  constructor(socketPath?: string) {
    this.socketPath = socketPath || getSocketPath();
  }

  /**
   * Connect to daemon socket
   */
  async connect(): Promise<void> {
    if (this.conn) {
      logger.verbose("Already connected to daemon");
      return; // Already connected
    }

    logger.debugSocket("Connecting to daemon", this.socketPath);

    try {
      this.conn = await connectWithRetry(this.socketPath);

      // Unref the connection so it doesn't block process exit
      // This allows quick commands to exit immediately without waiting
      // for the 5-second Deno default timeout
      this.conn.unref();

      logger.verbose(`Connected to daemon at ${this.socketPath}`);
    } catch (err) {
      logger.debugSocket("Connection failed", this.socketPath);
      const friendlyError = parseDaemonConnectionError(
        err instanceof Error ? err : new Error(String(err)),
      );
      throw new Error(friendlyError);
    }
  }

  /**
   * Check if connected
   */
  isConnected(): boolean {
    return this.conn !== null;
  }

  /**
   * Send JSON-RPC request and wait for response
   */
  async request<T = unknown>(method: string, params?: unknown): Promise<T> {
    if (!this.conn) {
      await this.connect();
    }

    // Start read loop if not already running
    if (!this.readLoopActive) {
      this.startReadLoop();
    }

    const id = ++this.requestId;
    const request: JsonRpcRequest = {
      jsonrpc: "2.0",
      method,
      params,
      id,
    };

    // Log request
    logger.debugRpcRequest(method, params);

    // Send request
    const requestData = JSON.stringify(request) + "\n";
    await this.conn!.write(this.encoder.encode(requestData));
    logger.verbose(`Sent RPC request: ${method}`);

    // Wait for response
    return new Promise<T>((resolve, reject) => {
      const timeout = setTimeout(() => {
        this.pendingRequests.delete(id);
        logger.debugRpcResponse(method, "TIMEOUT");
        reject(
          new Error(
            `Request timeout for method: ${method}\n` +
              "The daemon did not respond within 5 seconds.\n" +
              "Try restarting the daemon:\n" +
              "  systemctl --user restart i3-project-event-listener",
          ),
        );
      }, 5000);

      this.pendingRequests.set(id, {
        resolve: resolve as (value: unknown) => void,
        reject,
        timeout,
      });
    });
  }

  /**
   * Subscribe to event notifications
   */
  async subscribe(
    eventTypes: string[],
    handler: NotificationHandler,
  ): Promise<void> {
    if (!this.conn) {
      await this.connect();
    }

    // Add handler to list
    this.notificationHandlers.push(handler);

    // Subscribe to events via RPC
    await this.request("subscribe_events", { event_types: eventTypes });

    // Start read loop if not already running
    if (!this.readLoopActive) {
      this.startReadLoop();
    }
  }

  /**
   * Start background read loop for notifications
   */
  private startReadLoop(): void {
    if (this.readLoopActive || !this.conn) {
      return;
    }

    this.readLoopActive = true;
    this.readLoopPromise = this.runReadLoop();
  }

  /**
   * Run the read loop
   */
  private async runReadLoop(): Promise<void> {
    const buffer = new Uint8Array(8192);
    let partial = "";

    while (this.conn && this.readLoopActive) {
      try {
        const n = await this.conn.read(buffer);
        if (n === null) {
          // Connection closed
          break;
        }

        partial += this.decoder.decode(buffer.subarray(0, n));
        const lines = partial.split("\n");
        partial = lines.pop() || "";

        for (const line of lines) {
          if (!line.trim()) continue;

          try {
            const msg = JSON.parse(line);
            this.handleMessage(msg);
          } catch (err) {
            console.error("Failed to parse JSON-RPC message:", line);
            console.error(err);
          }
        }
      } catch (err) {
        if (this.readLoopActive) {
          console.error("Error in read loop:", err);
        }
        break;
      }
    }

    this.readLoopActive = false;
  }

  /**
   * Handle incoming JSON-RPC message
   */
  private handleMessage(msg: unknown): void {
    if (!msg || typeof msg !== "object") {
      return;
    }

    const obj = msg as Record<string, unknown>;

    if ("id" in obj && typeof obj.id === "number") {
      // This is a response to a request
      this.handleResponse(obj as unknown as JsonRpcResponse);
    } else if ("method" in obj && typeof obj.method === "string") {
      // This is a notification
      this.handleNotification(obj as unknown as JsonRpcNotification);
    }
  }

  /**
   * Handle JSON-RPC response
   */
  private handleResponse(response: JsonRpcResponse): void {
    const pending = this.pendingRequests.get(response.id);
    if (!pending) {
      logger.debug(`Received response for unknown request ID: ${response.id}`);
      return;
    }

    this.pendingRequests.delete(response.id);
    clearTimeout(pending.timeout);

    if (response.error) {
      logger.debugRpcResponse(`request-${response.id}`, response.error);
      pending.reject(
        new Error(
          `RPC Error (${response.error.code}): ${response.error.message}`,
        ),
      );
    } else {
      logger.debugRpcResponse(`request-${response.id}`, response.result);
      logger.verbose(`Received RPC response for request ID ${response.id}`);
      pending.resolve(response.result);
    }
  }

  /**
   * Handle JSON-RPC notification
   */
  private async handleNotification(
    notification: JsonRpcNotification,
  ): Promise<void> {
    for (const handler of this.notificationHandlers) {
      try {
        await handler(notification);
      } catch (err) {
        console.error("Error in notification handler:", err);
      }
    }
  }

  /**
   * Close connection and clean up
   */
  close(): void {
    this.readLoopActive = false;

    // Reject all pending requests
    for (const [id, pending] of this.pendingRequests.entries()) {
      clearTimeout(pending.timeout);
      pending.reject(new Error("Connection closed"));
      this.pendingRequests.delete(id);
    }

    // Close connection
    if (this.conn) {
      try {
        this.conn.close();
      } catch {
        // Ignore close errors
      }
      this.conn = null;
    }
  }

  /**
   * Wait for read loop to finish
   */
  async waitForReadLoop(): Promise<void> {
    if (this.readLoopPromise) {
      await this.readLoopPromise;
    }
  }
}

/**
 * Create a new daemon client instance
 */
export function createClient(socketPath?: string): DaemonClient {
  return new DaemonClient(socketPath);
}
