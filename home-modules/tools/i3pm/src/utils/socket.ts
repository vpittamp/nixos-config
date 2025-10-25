/**
 * Unix Socket Utilities
 *
 * Handles Unix socket connection management for daemon communication.
 */

/**
 * Get the daemon socket path from environment
 */
export function getSocketPath(): string {
  // Feature 037: System service socket location (not user runtime dir)
  return `/run/i3-project-daemon/ipc.sock`;
}

/**
 * Check if socket file exists
 */
export async function socketExists(path: string): Promise<boolean> {
  try {
    const stat = await Deno.stat(path);
    return stat.isFile || (stat.isSocket === true);
  } catch {
    return false;
  }
}

/**
 * Connect to Unix socket with timeout
 */
export async function connectWithTimeout(
  path: string,
  timeoutMs = 5000,
): Promise<Deno.UnixConn> {
  const connectPromise = Deno.connect({
    path,
    transport: "unix",
  }) as Promise<Deno.UnixConn>;

  const timeoutPromise = new Promise<never>((_resolve, reject) => {
    setTimeout(() => reject(new Error("Connection timeout")), timeoutMs);
  });

  try {
    return await Promise.race([connectPromise, timeoutPromise]);
  } catch (err) {
    if (err instanceof Error && err.message === "Connection timeout") {
      throw new Error(
        `Timeout connecting to daemon socket at ${path}.\n` +
          "The daemon may be unresponsive. Try restarting:\n" +
          "  systemctl --user restart i3-project-event-listener",
      );
    }
    throw err;
  }
}

/**
 * Exponential backoff retry configuration
 */
export interface RetryConfig {
  maxRetries: number;
  initialDelayMs: number;
  maxDelayMs: number;
  backoffFactor: number;
}

export const DEFAULT_RETRY_CONFIG: RetryConfig = {
  maxRetries: 3,
  initialDelayMs: 100,
  maxDelayMs: 2000,
  backoffFactor: 2,
};

/**
 * Retry connection with exponential backoff
 */
export async function connectWithRetry(
  path: string,
  config: RetryConfig = DEFAULT_RETRY_CONFIG,
): Promise<Deno.UnixConn> {
  let lastError: Error | null = null;
  let delayMs = config.initialDelayMs;

  for (let attempt = 0; attempt <= config.maxRetries; attempt++) {
    try {
      return await connectWithTimeout(path);
    } catch (err) {
      lastError = err instanceof Error ? err : new Error(String(err));

      if (attempt < config.maxRetries) {
        // Wait before retry
        await new Promise((resolve) => setTimeout(resolve, delayMs));
        delayMs = Math.min(delayMs * config.backoffFactor, config.maxDelayMs);
      }
    }
  }

  throw new Error(
    `Failed to connect after ${config.maxRetries + 1} attempts:\n${lastError?.message}`,
  );
}
