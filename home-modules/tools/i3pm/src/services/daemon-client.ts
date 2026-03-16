/**
 * Daemon client service
 * Feature 035: Registry-Centric Project & Workspace Management
 *
 * JSON-RPC 2.0 client for communicating with the Python i3pm daemon
 */

export class DaemonError extends Error {
  constructor(message: string, public code?: number, public override cause?: Error) {
    super(message);
    this.name = "DaemonError";
  }
}

function isIgnorableSocketCloseError(error: unknown): boolean {
  if (!(error instanceof Error)) {
    return false;
  }
  const message = String(error.message || "");
  return message.includes("Bad resource ID")
    || message.includes("Broken pipe")
    || message.includes("not connected")
    || message.includes("closed");
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
    // Feature 117: User socket only (daemon runs as user service)
    if (socketPath) {
      this.socketPath = socketPath;
    } else {
      const runtimeDir = Deno.env.get("XDG_RUNTIME_DIR") ?? `/run/user/${Deno.uid()}`;
      this.socketPath = `${runtimeDir}/i3-project-daemon/ipc.sock`;
    }
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
      try {
        this.conn.close();
      } catch (error) {
        if (!isIgnorableSocketCloseError(error)) {
          throw error;
        }
      }
      this.conn = null;
    }
  }

  /**
   * Compatibility alias for callers that expect an async close method.
   */
  async close(): Promise<void> {
    this.disconnect();
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

    // Read one newline-delimited JSON response. Large dashboard payloads routinely
    // exceed 64KB, so a single fixed-size read is not reliable.
    const decoder = new TextDecoder();
    const buffer = new Uint8Array(16384);
    const TIMEOUT_MS = 30000;
    let responseText = "";

    while (true) {
      const readPromise = this.conn.read(buffer);
      let timeoutHandle: number | null = null;
      const timeoutPromise = new Promise<never>((_, reject) => {
        timeoutHandle = setTimeout(
          () => reject(new DaemonError(`Daemon response timeout after ${TIMEOUT_MS}ms`)),
          TIMEOUT_MS,
        );
      });

      let bytesRead: number | null;
      try {
        bytesRead = await Promise.race([readPromise, timeoutPromise]) as number | null;
      } catch (e) {
        await this.close();
        throw e;
      } finally {
        if (timeoutHandle !== null) {
          clearTimeout(timeoutHandle);
        }
      }

      if (bytesRead === null) {
        throw new DaemonError("Connection closed by daemon");
      }

      responseText += decoder.decode(buffer.subarray(0, bytesRead));
      if (responseText.includes("\n")) {
        responseText = responseText.split("\n", 1)[0];
        break;
      }
    }

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
    connected: boolean;
    uptime: number;
    active_project: string | null;
    window_count: number;
    workspace_count: number;
    event_count: number;
    error_count: number;
    version: string;
    socket_path: string;
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

  async getActiveContext<T = unknown>(): Promise<T> {
    return await this.request<T>("context.current", {});
  }

  async ensureContext<T = unknown>(params: {
    qualified_name?: string;
    project_name?: string;
    target_variant?: "local" | "ssh";
    prefer_local?: boolean;
    clear?: boolean;
  }): Promise<T> {
    return await this.request<T>("context.ensure", params);
  }

  async getRuntimeSnapshot<T = unknown>(): Promise<T> {
    return await this.request<T>("dashboard.snapshot", {});
  }

  async getDashboardSnapshot<T = unknown>(): Promise<T> {
    return await this.request<T>("dashboard.snapshot", {});
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
   * Subscribe to daemon state change notifications.
   * Yields lightweight invalidation events that consumers can use to refetch
   * heavier dashboard/session state only when needed.
   */
  async *subscribeToStateChanges(): AsyncIterableIterator<{
    type: string;
    timestamp: number;
    snapshot_version?: number;
    session_generation?: number;
    display_generation?: number;
  }> {
    if (!this.conn) {
      throw new DaemonError("Not connected to daemon");
    }

    await this.request("subscribe_state_changes", {});

    const decoder = new TextDecoder();
    let partialLine = "";

    for await (const chunk of this.conn.readable) {
      const text = partialLine + decoder.decode(chunk);
      const lines = text.split("\n");
      partialLine = lines.pop() || "";

      for (const line of lines) {
        if (!line.trim()) continue;

        try {
          const message = JSON.parse(line);
          if (message.method !== "state_changed" || !message.params) {
            continue;
          }

          const params = message.params as Record<string, unknown>;
          yield {
            type: String(params.type || "state_changed"),
            timestamp: Number(params.timestamp || Date.now()),
            snapshot_version: params.snapshot_version === undefined ? undefined : Number(params.snapshot_version),
            session_generation: params.session_generation === undefined ? undefined : Number(params.session_generation),
            display_generation: params.display_generation === undefined ? undefined : Number(params.display_generation),
          };
        } catch {
          // Ignore malformed notification lines and continue consuming the stream.
        }
      }
    }
  }

  /**
   * Ping daemon (health check)
   */
  async ping(): Promise<boolean> {
    try {
      const status = await this.getStatus();
      return status.status === "running";
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
