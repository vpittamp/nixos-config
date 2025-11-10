/**
 * Daemon client service
 * Feature 035: Registry-Centric Project & Workspace Management
 *
 * JSON-RPC 2.0 client for communicating with the Python i3pm daemon
 */

import * as path from "@std/path";

export class DaemonError extends Error {
  constructor(message: string, public code?: number, public override cause?: Error) {
    super(message);
    this.name = "DaemonError";
  }
}

/**
 * JSON-RPC 2.0 request
 */
interface JsonRpcRequest {
  jsonrpc: "2.0";
  method: string;
  params?: unknown;
  id: number | string;
}

/**
 * JSON-RPC 2.0 response (success)
 */
interface JsonRpcSuccess {
  jsonrpc: "2.0";
  result: unknown;
  id: number | string;
}

/**
 * JSON-RPC 2.0 response (error)
 */
interface JsonRpcError {
  jsonrpc: "2.0";
  error: {
    code: number;
    message: string;
    data?: unknown;
  };
  id: number | string;
}

type JsonRpcResponse = JsonRpcSuccess | JsonRpcError;

/**
 * Check if response is an error
 */
function isJsonRpcError(response: JsonRpcResponse): response is JsonRpcError {
  return "error" in response;
}

/**
 * Daemon client for JSON-RPC communication
 */
export class DaemonClient {
  private socketPath: string;
  private requestId = 0;
  private conn: Deno.UnixConn | null = null;

  constructor(socketPath?: string) {
    // Feature 037: System service socket location (not user runtime dir)
    this.socketPath = socketPath || "/run/i3-project-daemon/ipc.sock";
  }

  /**
   * Connect to daemon socket
   */
  async connect(): Promise<void> {
    if (this.conn) {
      return; // Already connected
    }

    try {
      this.conn = await Deno.connect({ path: this.socketPath, transport: "unix" });
    } catch (error) {
      throw new DaemonError(
        `Failed to connect to daemon at ${this.socketPath}. Is the daemon running?`,
        -1,
        error instanceof Error ? error : undefined,
      );
    }
  }

  /**
   * Disconnect from daemon
   */
  disconnect(): void {
    if (this.conn) {
      this.conn.close();
      this.conn = null;
    }
  }

  /**
   * Send JSON-RPC request and wait for response
   */
  async request<T = unknown>(method: string, params?: unknown): Promise<T> {
    await this.connect();

    if (!this.conn) {
      throw new DaemonError("Not connected to daemon");
    }

    const id = ++this.requestId;
    const request: JsonRpcRequest = {
      jsonrpc: "2.0",
      method,
      params,
      id,
    };

    // Send request
    const requestData = JSON.stringify(request) + "\n";
    const encoder = new TextEncoder();
    await this.conn.write(encoder.encode(requestData));

    // Read response
    const decoder = new TextDecoder();
    const buffer = new Uint8Array(65536); // 64KB buffer
    const bytesRead = await this.conn.read(buffer);

    if (bytesRead === null) {
      throw new DaemonError("Connection closed by daemon");
    }

    const responseText = decoder.decode(buffer.subarray(0, bytesRead));
    const response: JsonRpcResponse = JSON.parse(responseText);

    if (isJsonRpcError(response)) {
      throw new DaemonError(response.error.message, response.error.code);
    }

    return response.result as T;
  }

  /**
   * Send JSON-RPC request (alias for request)
   * Used by monitors.ts and other commands for compatibility
   */
  async sendRequest<T = unknown>(method: string, params?: unknown): Promise<T> {
    return await this.request<T>(method, params);
  }

  /**
   * Get daemon status
   */
  async getStatus(): Promise<{
    status: string;
    pid: number;
    uptime: number;
    active_project: string | null;
    events_processed: number;
    tracked_windows: number;
  }> {
    return await this.request("get_status");
  }

  /**
   * Get window state (i3 tree query)
   */
  async getWindowState(params?: {
    include_geometry?: boolean;
    workspace_filter?: number[];
  }): Promise<unknown> {
    return await this.request("get_window_state", params);
  }

  /**
   * Get active project from daemon
   */
  async getActiveProject(): Promise<string | null> {
    const status = await this.getStatus();
    return status.active_project;
  }

  /**
   * Close project windows (used before layout restore)
   */
  async closeProjectWindows(projectName: string): Promise<number> {
    const result = await this.request<{ closed_count: number }>(
      "close_project_windows",
      { project_name: projectName },
    );
    return result.closed_count;
  }

  /**
   * Send project switch notification to daemon
   * Daemon will filter windows based on /proc reading
   */
  async notifyProjectSwitch(projectName: string): Promise<void> {
    await this.request("notify_project_switch", { project_name: projectName });
  }

  /**
   * Clear project (return to global mode)
   */
  async notifyProjectClear(): Promise<void> {
    await this.request("notify_project_clear");
  }

  /**
   * Get recent daemon events (for debugging)
   */
  async getEvents(params?: {
    limit?: number;
    event_type?: string;
  }): Promise<unknown[]> {
    return await this.request("get_events", params);
  }

  /**
   * Subscribe to daemon event stream (async iterator)
   * Yields events as they are broadcast by the daemon
   */
  async *subscribeToEvents(): AsyncIterableIterator<{ type: string; data: unknown; timestamp: string }> {
    if (!this.conn) {
      throw new DaemonError("Not connected to daemon");
    }

    // Subscribe to events
    await this.request("subscribe_events", { subscribe: true });

    // Create text decoder for reading lines
    const decoder = new TextDecoder();
    let partialLine = "";

    try {
      // Read incoming messages (event broadcasts)
      for await (const chunk of this.conn.readable) {
        // Decode chunk and split by newlines
        const text = partialLine + decoder.decode(chunk);
        const lines = text.split("\n");

        // Keep the last incomplete line
        partialLine = lines.pop() || "";

        // Process complete lines
        for (const line of lines) {
          if (!line.trim()) continue;

          try {
            const message = JSON.parse(line);

            // Daemon broadcasts events as JSON-RPC notifications:
            // { jsonrpc: "2.0", method: "event_notification", params: {...} }
            if (message.method === "event_notification" && message.params) {
              const eventData = message.params;
              yield {
                type: eventData.event_type || "unknown",
                data: eventData,
                timestamp: eventData.timestamp || new Date().toISOString(),
              };
            }
          } catch (error) {
            // Ignore parse errors for now (might be fragmented JSON)
            continue;
          }
        }
      }
    } finally {
      // Unsubscribe when done
      try {
        await this.request("subscribe_events", { subscribe: false });
      } catch {
        // Ignore errors during cleanup
      }
    }
  }

  /**
   * Ping daemon (health check)
   */
  async ping(): Promise<boolean> {
    try {
      await this.request("ping");
      return true;
    } catch {
      return false;
    }
  }

  /**
   * Get launch registry statistics (Feature 041)
   *
   * Returns launch notification and correlation metrics from the daemon.
   */
  async getLaunchStats(): Promise<{
    total_pending: number;
    unmatched_pending: number;
    total_notifications: number;
    total_matched: number;
    total_expired: number;
    total_failed_correlation: number;
    match_rate: number;
    expiration_rate: number;
  }> {
    return await this.request("get_launch_stats");
  }

  /**
   * Get pending launches (Feature 041)
   *
   * Debug endpoint to inspect currently pending launch notifications.
   *
   * @param includeMatched - Include already-matched launches (default: false)
   */
  async getPendingLaunches(includeMatched = false): Promise<{
    pending_launches: Array<{
      launch_id: string;
      app_name: string;
      project_name: string;
      expected_class: string;
      workspace_number: number;
      age: number;
      matched: boolean;
    }>;
    count: number;
  }> {
    return await this.request("get_pending_launches", { include_matched: includeMatched });
  }

  /**
   * Get applications from daemon's registry
   *
   * Query the daemon's in-memory application registry to see what apps
   * it has loaded. Useful for debugging configuration sync issues.
   *
   * @param params - Optional filter parameters
   * @param params.name - Filter by application name
   * @param params.scope - Filter by scope (scoped/global)
   * @param params.workspace - Filter by preferred workspace number
   */
  async getDaemonApps(params?: {
    name?: string;
    scope?: string;
    workspace?: number;
  }): Promise<{
    applications: Array<unknown>;
    version: string;
    count: number;
    registry_path: string;
  }> {
    return await this.request("daemon.apps", params);
  }

  /**
   * Get daemon socket path
   */
  getSocketPath(): string {
    return this.socketPath;
  }

  /**
   * Check if connected
   */
  isConnected(): boolean {
    return this.conn !== null;
  }
}

/**
 * Helper function to execute daemon request with automatic connection management
 */
export async function withDaemonClient<T>(
  fn: (client: DaemonClient) => Promise<T>,
  socketPath?: string,
): Promise<T> {
  const client = new DaemonClient(socketPath);
  try {
    await client.connect();
    return await fn(client);
  } finally {
    client.disconnect();
  }
}
