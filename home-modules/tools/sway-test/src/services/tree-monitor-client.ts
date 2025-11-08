/**
 * Tree Monitor Client Service
 *
 * JSON-RPC client for communicating with sway-tree-monitor daemon over Unix socket.
 */

import type { TreeMonitorEvent } from "../models/test-result.ts";

/**
 * JSON-RPC request
 */
interface RPCRequest {
  jsonrpc: "2.0";
  method: string;
  params?: unknown;
  id: number;
}

/**
 * JSON-RPC response
 */
interface RPCResponse {
  jsonrpc: "2.0";
  result?: unknown;
  error?: {
    code: number;
    message: string;
    data?: unknown;
  };
  id: number;
}

/**
 * Tree-monitor daemon client
 */
export class TreeMonitorClient {
  private socketPath: string;
  private requestId = 0;
  private availableMethods: Set<string> | null = null;
  private introspectionWarningShown = false;

  constructor(socketPath = "/run/user/1000/sway-tree-monitor.sock") {
    this.socketPath = socketPath;
  }

  /**
   * Send JSON-RPC request to daemon
   */
  private async sendRequest(method: string, params?: unknown): Promise<unknown> {
    this.requestId++;

    const request: RPCRequest = {
      jsonrpc: "2.0",
      method,
      params,
      id: this.requestId,
    };

    // Connect to Unix socket
    const conn = await Deno.connect({ path: this.socketPath, transport: "unix" });

    try {
      // Send request
      const encoder = new TextEncoder();
      const requestData = encoder.encode(JSON.stringify(request) + "\n");
      await conn.write(requestData);

      // Read response
      const decoder = new TextDecoder();
      const buffer = new Uint8Array(65536); // 64KB buffer
      const bytesRead = await conn.read(buffer);

      if (!bytesRead) {
        throw new Error("No response from daemon");
      }

      const responseText = decoder.decode(buffer.subarray(0, bytesRead));
      const response: RPCResponse = JSON.parse(responseText.trim());

      if (response.error) {
        throw new Error(`RPC error: ${response.error.message}`);
      }

      return response.result;
    } finally {
      conn.close();
    }
  }

  /**
   * Check if an RPC method is available on tree-monitor daemon
   *
   * Uses system.listMethods introspection with session-level caching.
   *
   * @param methodName - Method name to check (e.g., "sendSyncMarker")
   * @returns true if method available, false otherwise
   */
  async checkMethodAvailability(methodName: string): Promise<boolean> {
    // Lazy load available methods on first call
    if (this.availableMethods === null) {
      try {
        const methods = await this.sendRequest("system.listMethods", {}) as string[];
        this.availableMethods = new Set(methods);
      } catch (error) {
        // Log warning once on first introspection failure
        if (!this.introspectionWarningShown) {
          console.warn(
            "RPC introspection unavailable, disabling auto-sync features.\n" +
            `Error: ${error.message}`
          );
          this.introspectionWarningShown = true;
        }
        this.availableMethods = new Set(); // Empty set = no methods available
      }
    }

    return this.availableMethods.has(methodName);
  }

  /**
   * Send sync marker to daemon with graceful fallback
   *
   * Checks method availability first. If unavailable, returns null
   * and caller should fall back to timeout-based synchronization.
   *
   * @returns Sync marker ID if successful, null if method unavailable
   */
  async sendSyncMarkerSafe(): Promise<string | null> {
    // Check if method available
    if (!(await this.checkMethodAvailability("sendSyncMarker"))) {
      // Log warning once
      if (!this.introspectionWarningShown) {
        console.warn(
          "Auto-sync unavailable (daemon not running or method missing), " +
          "using timeout-based synchronization"
        );
        this.introspectionWarningShown = true;
      }
      return null;
    }

    try {
      return await this.sendSyncMarker();
    } catch (error) {
      console.warn(`send Sync marker failed: ${error.message}, falling back to timeout`);
      return null;
    }
  }

  /**
   * Ping daemon to check connectivity (T012)
   */
  async ping(): Promise<boolean> {
    try {
      const result = await this.sendRequest("ping", {});
      return result === "pong" || (typeof result === "object" && result !== null);
    } catch {
      return false;
    }
  }

  /**
   * Check if daemon is available
   */
  async isAvailable(): Promise<boolean> {
    try {
      await Deno.stat(this.socketPath);
      return await this.ping();
    } catch {
      return false;
    }
  }

  /**
   * Query events from daemon
   * @param params Query parameters (last, since, filters)
   */
  async queryEvents(
    params: { last?: number; since?: string; filters?: unknown } = {},
  ): Promise<TreeMonitorEvent[]> {
    const result = await this.sendRequest("query_events", params);

    if (!result || typeof result !== "object") {
      return [];
    }

    // Handle different response formats
    const resultObj = result as { events?: unknown[] };
    const events = resultObj.events || (Array.isArray(result) ? result : []);

    return events as TreeMonitorEvent[];
  }

  /**
   * Get latest event from daemon
   */
  async getLatestEvent(): Promise<TreeMonitorEvent | null> {
    const events = await this.queryEvents({ last: 1 });
    return events.length > 0 ? events[0] : null;
  }

  /**
   * Get daemon status/stats
   */
  async getStats(): Promise<unknown> {
    return await this.sendRequest("get_stats", {});
  }

  /**
   * Send sync marker (for I3_SYNC-style synchronization)
   * Will be implemented in Phase 7 (T053)
   */
  async sendSyncMarker(markerId: string): Promise<void> {
    await this.sendRequest("send_sync_marker", { marker_id: markerId });
  }

  /**
   * Await sync marker completion
   * Will be implemented in Phase 7 (T053)
   */
  async awaitSyncMarker(markerId: string, timeoutMs = 5000): Promise<boolean> {
    const result = await this.sendRequest("await_sync_marker", {
      marker_id: markerId,
      timeout_ms: timeoutMs,
    });
    return result === true;
  }

  /**
   * Create test scope for event filtering
   * Will be implemented in Phase 7
   */
  async createTestScope(testId: string): Promise<void> {
    await this.sendRequest("create_test_scope", { test_id: testId });
  }

  /**
   * Destroy test scope
   * Will be implemented in Phase 7
   */
  async destroyTestScope(testId: string): Promise<void> {
    await this.sendRequest("destroy_test_scope", { test_id: testId });
  }

  /**
   * Get events for specific test
   * Will be implemented in Phase 7
   */
  async getTestEvents(testId: string, filters?: unknown): Promise<TreeMonitorEvent[]> {
    const result = await this.sendRequest("get_test_events", {
      test_id: testId,
      filters,
    });

    if (!result || typeof result !== "object") {
      return [];
    }

    const resultObj = result as { events?: unknown[] };
    const events = resultObj.events || (Array.isArray(result) ? result : []);

    return events as TreeMonitorEvent[];
  }

  /**
   * Send sync marker via daemon (T053 - User Story 4 - Synchronization)
   *
   * Sends SEND_TICK command through daemon to Sway for I3_SYNC-style synchronization.
   * Returns unique marker ID to be passed to awaitSyncMarker().
   *
   * @param markerId Optional custom marker ID (daemon generates UUID if not provided)
   * @returns Marker ID that was sent
   * @throws Error if daemon unavailable or send_tick fails
   */
  async sendSyncMarker(markerId?: string): Promise<string> {
    const result = await this.sendRequest("send_sync_marker", {
      marker_id: markerId,
    });

    if (!result || typeof result !== "object") {
      throw new Error("Invalid response from send_sync_marker");
    }

    const resultObj = result as { marker_id?: string; success?: boolean };

    if (!resultObj.success || !resultObj.marker_id) {
      throw new Error("send_sync_marker failed");
    }

    return resultObj.marker_id;
  }

  /**
   * Wait for sync marker tick event (T053 - User Story 4 - Synchronization)
   *
   * Waits for TICK event matching marker_id with timeout.
   * Provides I3_SYNC-style guarantee that all previous IPC operations completed.
   *
   * @param markerId Marker ID from sendSyncMarker() to wait for
   * @param timeoutMs Maximum wait time in milliseconds (default: 5000)
   * @returns True if marker received, false if timeout
   * @throws Error if daemon unavailable or subscription fails
   */
  async awaitSyncMarker(markerId: string, timeoutMs = 5000): Promise<boolean> {
    const result = await this.sendRequest("await_sync_marker", {
      marker_id: markerId,
      timeout_ms: timeoutMs,
    });

    if (!result || typeof result !== "object") {
      throw new Error("Invalid response from await_sync_marker");
    }

    const resultObj = result as { success?: boolean; timeout?: boolean; message?: string };

    // Timeout is not an error - return false
    if (resultObj.timeout) {
      return false;
    }

    if (!resultObj.success) {
      throw new Error(resultObj.message || "await_sync_marker failed");
    }

    return true;
  }
}
