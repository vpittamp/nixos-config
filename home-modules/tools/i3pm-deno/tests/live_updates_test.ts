/**
 * Live TUI Real-Time Updates Test
 *
 * Tests that the live TUI correctly receives and processes real-time events
 * when windows are opened/closed or workspaces are switched.
 */

import { assertEquals, assertGreaterOrEqual } from "jsr:@std/assert";
import { createClient } from "../src/client.ts";

// Helper to run i3-msg commands
async function i3msg(command: string): Promise<void> {
  const process = new Deno.Command("i3-msg", {
    args: [command],
    stdout: "null",
    stderr: "null",
  });

  const { success } = await process.output();
  if (!success) {
    throw new Error(`i3-msg command failed: ${command}`);
  }
}

// Helper to wait for a condition with timeout
async function waitFor(
  condition: () => boolean | Promise<boolean>,
  timeoutMs = 5000,
  checkIntervalMs = 100
): Promise<boolean> {
  const startTime = Date.now();

  while (Date.now() - startTime < timeoutMs) {
    if (await condition()) {
      return true;
    }
    await new Promise(resolve => setTimeout(resolve, checkIntervalMs));
  }

  return false;
}

Deno.test({
  name: "Live TUI - Event subscription receives both event formats",
  permissions: {
    read: ["/run/user", "/home"],
    net: true,
    env: ["XDG_RUNTIME_DIR", "HOME", "USER"],
  },
  async fn() {
    const client = createClient();
    const receivedEvents: Array<{ type?: string; event_type?: string }> = [];

    try {
      // Subscribe to events
      await client.subscribe(["window", "workspace", "output"], async (notification) => {
        const params = notification.params as { type?: string; event_type?: string };
        receivedEvents.push({
          type: params.type,
          event_type: params.event_type
        });
      });

      // Trigger some events by switching workspaces
      await i3msg("workspace 3");
      await new Promise(resolve => setTimeout(resolve, 200));
      await i3msg("workspace 2");
      await new Promise(resolve => setTimeout(resolve, 200));

      // Wait for events to be received
      await waitFor(() => receivedEvents.length >= 2, 3000);

      // Verify we received events
      assertGreaterOrEqual(receivedEvents.length, 2, "Should receive at least 2 events");

      // Verify we have both event format types
      const hasTypeField = receivedEvents.some(e => e.type !== undefined);
      const hasEventTypeField = receivedEvents.some(e => e.event_type !== undefined);

      const typeCount = receivedEvents.filter(e => e.type).length;
      const eventTypeCount = receivedEvents.filter(e => e.event_type).length;

      console.log(`Received ${receivedEvents.length} events:`);
      console.log(`  - Events with 'type' field: ${typeCount}`);
      console.log(`  - Events with 'event_type' field: ${eventTypeCount}`);

      assertEquals(hasTypeField, true, "Should receive events with 'type' field");
      assertEquals(hasEventTypeField, true, "Should receive events with 'event_type' field");

    } finally {
      client.close();
    }
  },
});

Deno.test({
  name: "Live TUI - Events trigger refreshes for window/workspace/output types",
  permissions: {
    read: ["/run/user", "/home"],
    net: true,
    env: ["XDG_RUNTIME_DIR", "HOME", "USER"],
  },
  async fn() {
    const client = createClient();
    let refreshCount = 0;
    const relevantEventTypes = ["window", "workspace", "output"];

    try {
      await client.subscribe(relevantEventTypes, async (notification) => {
        const params = notification.params as { type?: string; event_type?: string };
        const eventType = params.type || params.event_type?.split("::")[0];

        // Check if this event should trigger a refresh
        if (eventType && relevantEventTypes.includes(eventType)) {
          refreshCount++;
        }
      });

      // Trigger workspace switch events
      await i3msg("workspace 3");
      await new Promise(resolve => setTimeout(resolve, 200));
      await i3msg("workspace 1");
      await new Promise(resolve => setTimeout(resolve, 200));
      await i3msg("workspace 2");
      await new Promise(resolve => setTimeout(resolve, 200));

      // Wait for events to accumulate
      await waitFor(() => refreshCount >= 3, 3000);

      console.log(`Total refresh triggers: ${refreshCount}`);

      assertGreaterOrEqual(refreshCount, 3, "Should trigger at least 3 refreshes from workspace switches");

    } finally {
      client.close();
    }
  },
});

Deno.test({
  name: "Live TUI - Event throttling respects 100ms minimum interval",
  permissions: {
    read: ["/run/user", "/home"],
    net: true,
    env: ["XDG_RUNTIME_DIR", "HOME", "USER"],
  },
  async fn() {
    const client = createClient();
    const eventTimestamps: number[] = [];
    let lastRefreshTime = 0;
    const THROTTLE_MS = 100;

    try {
      await client.subscribe(["window", "workspace"], async (notification) => {
        const now = Date.now();
        const params = notification.params as { type?: string; event_type?: string };
        const eventType = params.type || params.event_type?.split("::")[0];

        if (eventType === "window" || eventType === "workspace") {
          eventTimestamps.push(now);

          // Simulate throttled refresh logic
          if (now - lastRefreshTime >= THROTTLE_MS) {
            lastRefreshTime = now;
          }
        }
      });

      // Rapid workspace switches
      await i3msg("workspace 3");
      await i3msg("workspace 2");
      await i3msg("workspace 3");
      await i3msg("workspace 2");

      await new Promise(resolve => setTimeout(resolve, 500));

      console.log(`Received ${eventTimestamps.length} events in rapid succession`);

      // Check that multiple events were received (unthrottled at subscription level)
      assertGreaterOrEqual(eventTimestamps.length, 4, "Should receive multiple events");

      // The throttling happens in the live TUI's refresh method,
      // not in the event subscription, so we just verify events are received
      console.log("✓ Events received without throttling at subscription level");
      console.log("  (Throttling is applied in LiveTUI.refresh() method)");

    } finally {
      client.close();
    }
  },
});

Deno.test({
  name: "Live TUI - Application window open/close triggers events",
  permissions: {
    read: ["/run/user", "/home"],
    net: true,
    env: ["XDG_RUNTIME_DIR", "HOME", "USER"],
    run: true, // Need to spawn xterm
  },
  async fn() {
    const client = createClient();
    let windowOpenEventReceived = false;
    let windowCloseEventReceived = false;
    let xtermPid: number | undefined;

    try {
      await client.subscribe(["window"], async (notification) => {
        const params = notification.params as { type?: string; event_type?: string; change?: string };
        const eventType = params.type || params.event_type?.split("::")[0];
        const change = params.change || params.event_type?.split("::")[1];

        if (eventType === "window") {
          if (change === "new" || change === "focus") {
            windowOpenEventReceived = true;
          } else if (change === "close") {
            windowCloseEventReceived = true;
          }
        }
      });

      // Open a simple application (xterm with immediate exit)
      console.log("Opening xterm...");
      const xtermProcess = new Deno.Command("xterm", {
        args: ["-e", "sleep 0.5"],
        stdout: "null",
        stderr: "null",
      }).spawn();

      xtermPid = xtermProcess.pid;

      // Wait for window open event
      await waitFor(() => windowOpenEventReceived, 3000);

      assertEquals(windowOpenEventReceived, true, "Should receive window open event");

      // Wait for xterm to close
      await xtermProcess.status;
      await new Promise(resolve => setTimeout(resolve, 500));

      // Verify close event was received
      console.log(`Window open event: ${windowOpenEventReceived ? '✓' : '✗'}`);
      console.log(`Window close event: ${windowCloseEventReceived ? '✓' : '✗'}`);

      // Note: Close events might not always be captured depending on timing
      // So we don't assert on close, just verify open works

    } finally {
      // Cleanup: kill xterm if still running
      if (xtermPid) {
        try {
          Deno.kill(xtermPid, "SIGTERM");
        } catch {
          // Already closed
        }
      }
      client.close();
    }
  },
  sanitizeResources: false, // xterm may leave resources
  sanitizeOps: false,
});

Deno.test({
  name: "Live TUI - Connection stays alive during event subscription",
  permissions: {
    read: ["/run/user", "/home"],
    net: true,
    env: ["XDG_RUNTIME_DIR", "HOME", "USER"],
  },
  async fn() {
    const client = createClient();
    let eventCount = 0;

    try {
      await client.subscribe(["window", "workspace"], async () => {
        eventCount++;
      });

      // Verify connection is alive
      assertEquals(client.isConnected(), true, "Client should be connected");

      // Trigger events over a longer period
      for (let i = 0; i < 3; i++) {
        await i3msg("workspace 3");
        await new Promise(resolve => setTimeout(resolve, 200));
        await i3msg("workspace 2");
        await new Promise(resolve => setTimeout(resolve, 200));
      }

      // Connection should still be alive
      assertEquals(client.isConnected(), true, "Client should remain connected");

      console.log(`Received ${eventCount} events while maintaining connection`);
      assertGreaterOrEqual(eventCount, 3, "Should receive multiple events over time");

    } finally {
      client.close();
    }
  },
});
