/**
 * Tree Monitor RPC Client
 *
 * JSON-RPC 2.0 client for communicating with sway-tree-monitor daemon over Unix sockets.
 * Based on Feature 065 research.md and contracts/rpc-protocol.json.
 */

import type {
  Event,
  GetEventParams,
  QueryEventsParams,
  RPCErrorResponse,
  RPCRequest,
  RPCResponse,
  RPCSuccessResponse,
  Stats,
} from "../models/tree-monitor.ts";

/**
 * Tree Monitor Client for daemon communication
 */
export class TreeMonitorClient {
  private conn: Deno.UnixConn | null = null;
  private socketPath: string;
  private requestId = 0;

  constructor(socketPath?: string) {
    const xdgRuntimeDir = Deno.env.get("XDG_RUNTIME_DIR");
    if (!xdgRuntimeDir && !socketPath) {
      throw new Error("XDG_RUNTIME_DIR not set and no socket path provided");
    }
    this.socketPath = socketPath || `${xdgRuntimeDir}/sway-tree-monitor.sock`;
  }

  /**
   * Connect to daemon Unix socket
   * Handles ENOENT, ECONNREFUSED, ETIMEDOUT errors
   */
  async connect(): Promise<void> {
    try {
      this.conn = await Deno.connect({
        transport: "unix",
        path: this.socketPath,
      }) as Deno.UnixConn;
    } catch (err) {
      if (err instanceof Deno.errors.NotFound) {
        throw new Error(
          `Cannot connect to daemon: socket not found at ${this.socketPath}\n\n` +
            `Start daemon with: systemctl --user start sway-tree-monitor`,
        );
      } else if (err instanceof Deno.errors.ConnectionRefused) {
        throw new Error(
          `Cannot connect to daemon: connection refused at ${this.socketPath}\n\n` +
            `Verify daemon is running: systemctl --user status sway-tree-monitor`,
        );
      } else if (err instanceof Deno.errors.PermissionDenied) {
        throw new Error(
          `Permission denied accessing socket at ${this.socketPath}\n\n` +
            `Socket should have permissions 0600 (owner read/write only)`,
        );
      } else {
        throw new Error(`Failed to connect to daemon: ${err}`);
      }
    }
  }

  /**
   * Send JSON-RPC 2.0 request and wait for response
   * Includes 5-second timeout per edge case requirement
   */
  async sendRequest(
    method: string,
    params?: Record<string, unknown>,
  ): Promise<RPCResponse> {
    if (!this.conn) {
      throw new Error("Not connected - call connect() first");
    }

    // Generate request
    const request: RPCRequest = {
      jsonrpc: "2.0",
      method,
      params,
      id: ++this.requestId,
    };

    // Encode and send (newline-delimited)
    const encoder = new TextEncoder();
    const requestData = encoder.encode(JSON.stringify(request) + "\n");

    try {
      await this.conn.write(requestData);
    } catch (err) {
      throw new Error(`Failed to send request: ${err}`);
    }

    // Read response with 5-second timeout
    const decoder = new TextDecoder();
    const buffer = new Uint8Array(65536); // 64KB buffer

    const timeoutPromise = new Promise<never>((_, reject) => {
      setTimeout(() => reject(new Error("Request timeout after 5 seconds")), 5000);
    });

    const readPromise = (async () => {
      let accumulated = "";

      while (true) {
        const n = await this.conn!.read(buffer);
        if (n === null) {
          throw new Error("Connection closed by daemon");
        }

        accumulated += decoder.decode(buffer.subarray(0, n));

        // Look for newline (response complete)
        const newlineIndex = accumulated.indexOf("\n");
        if (newlineIndex >= 0) {
          const responseLine = accumulated.substring(0, newlineIndex);

          try {
            const response = JSON.parse(responseLine) as RPCResponse;
            return response;
          } catch (err) {
            throw new Error(
              `Malformed JSON from daemon:\n${responseLine}\n\nParse error: ${err}`,
            );
          }
        }
      }
    })();

    return await Promise.race([readPromise, timeoutPromise]);
  }

  /**
   * Close connection to daemon
   */
  close(): void {
    if (this.conn) {
      this.conn.close();
      this.conn = null;
    }
  }

  /**
   * Ping daemon for health check
   */
  async ping(): Promise<{ status: string; timestamp: number }> {
    const response = await this.sendRequest("ping");

    if ("error" in response) {
      throw new Error(`Ping failed: ${response.error.message}`);
    }

    return response.result as { status: string; timestamp: number };
  }

  /**
   * Query historical events with optional filters
   */
  /**
   * Transform daemon event format to our TypeScript interface
   */
  // deno-lint-ignore no-explicit-any
  private transformEvent(daemonEvent: any): Event {
    return {
      id: String(daemonEvent.event_id ?? daemonEvent.id ?? "unknown"),
      timestamp: daemonEvent.timestamp_ms ?? daemonEvent.timestamp ?? 0,
      type: daemonEvent.event_type ?? daemonEvent.type ?? "unknown",
      change_count: daemonEvent.diff?.total_changes ?? daemonEvent.change_count ?? 0,
      significance: daemonEvent.diff?.significance_score ?? daemonEvent.significance ?? 0,
      correlation: daemonEvent.correlations?.[0] ? {
        action_type: daemonEvent.correlations[0].action_type,
        binding_command: daemonEvent.correlations[0].binding_command,
        time_delta_ms: daemonEvent.correlations[0].time_delta_ms,
        confidence: daemonEvent.correlations[0].confidence,
        reasoning: daemonEvent.correlations[0].reasoning,
      } : undefined,
      diff: daemonEvent.diff?.changes || undefined,
      enrichment: daemonEvent.enrichment || undefined,
    };
  }

  async queryEvents(params: QueryEventsParams = {}): Promise<Event[]> {
    const response = await this.sendRequest("query_events", params);

    if ("error" in response) {
      const err = response as RPCErrorResponse;
      if (err.error.code === -32602) {
        throw new Error(`Invalid query parameters: ${err.error.message}`);
      }
      throw new Error(`Query failed: ${err.error.message}`);
    }

    const result = (response as RPCSuccessResponse).result;

    // Handle different possible response formats
    // deno-lint-ignore no-explicit-any
    let daemonEvents: any[] = [];
    if (Array.isArray(result)) {
      daemonEvents = result;
      // deno-lint-ignore no-explicit-any
    } else if (result && typeof result === "object" && "events" in result) {
      // deno-lint-ignore no-explicit-any
      daemonEvents = (result as { events: any[] }).events || [];
    }

    // Transform daemon format to our interface
    return daemonEvents.map((e) => this.transformEvent(e));
  }

  /**
   * Get detailed event information by ID
   */
  async getEvent(eventId: string): Promise<Event> {
    const params: GetEventParams = { event_id: eventId };
    const response = await this.sendRequest("get_event", params);

    if ("error" in response) {
      const err = response as RPCErrorResponse;
      if (err.error.code === -32000) {
        throw new Error(`Event not found: ${eventId}`);
      }
      throw new Error(`Get event failed: ${err.error.message}`);
    }

    const result = (response as RPCSuccessResponse).result;

    // If result is already an event object (not wrapped), transform it directly
    // If wrapped in {event: ...}, unwrap first
    // deno-lint-ignore no-explicit-any
    const daemonEvent = (result as any).event || result;
    return this.transformEvent(daemonEvent);
  }

  /**
   * Transform daemon statistics format to our TypeScript interface
   */
  // deno-lint-ignore no-explicit-any
  private transformStats(daemonStats: any): Stats {
    return {
      memory_mb: daemonStats.buffer?.memory_estimate_mb || 0,
      cpu_percent: 0, // Not provided by daemon
      buffer: {
        current_size: daemonStats.buffer?.size || 0,
        max_size: daemonStats.buffer?.max_size || 500,
        utilization: (daemonStats.buffer?.size || 0) / (daemonStats.buffer?.max_size || 500),
      },
      event_distribution: daemonStats.event_type_distribution || {},
      diff_stats: {
        avg_compute_time_ms: daemonStats.performance?.avg_diff_computation_ms || 0,
        max_compute_time_ms: daemonStats.performance?.max_diff_computation_ms || 0,
        total_diffs_computed: daemonStats.buffer?.size || 0,
      },
      uptime_seconds: daemonStats.buffer?.time_range?.span_seconds || 0,
      timestamp: Date.now(),
    };
  }

  /**
   * Get daemon performance statistics
   */
  async getStatistics(): Promise<Stats> {
    const response = await this.sendRequest("get_statistics");

    if ("error" in response) {
      throw new Error(`Get statistics failed: ${response.error.message}`);
    }

    const result = (response as RPCSuccessResponse).result;
    return this.transformStats(result);
  }

  /**
   * Get daemon health and buffer state
   */
  async getDaemonStatus(): Promise<{
    running: boolean;
    buffer_size: number;
    uptime_seconds: number;
  }> {
    const response = await this.sendRequest("get_daemon_status");

    if ("error" in response) {
      throw new Error(`Get daemon status failed: ${response.error.message}`);
    }

    const result = (response as RPCSuccessResponse).result as {
      status: {
        running: boolean;
        buffer_size: number;
        uptime_seconds: number;
      };
    };
    return result.status;
  }
}

/**
 * Helper to check if response is an error
 */
export function isRPCError(response: RPCResponse): response is RPCErrorResponse {
  return "error" in response;
}
