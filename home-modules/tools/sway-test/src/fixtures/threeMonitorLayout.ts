/**
 * Three Monitor Layout Fixture (T059)
 *
 * Sets up 3 virtual monitors (HEADLESS-1, HEADLESS-2, HEADLESS-3) for testing.
 */

import type { Fixture, FixtureContext } from "./types.ts";

const threeMonitorLayout: Fixture = {
  name: "threeMonitorLayout",
  description: "Configures 3 virtual displays for multi-monitor testing",
  tags: ["monitors", "layout", "multi-display"],

  async setup(context: FixtureContext): Promise<void> {
    // Create 3 headless outputs (1920x1080 each)
    await context.swayClient.sendCommand(
      "create_output HEADLESS-1 1920 1080",
    );
    await context.swayClient.sendCommand(
      "create_output HEADLESS-2 1920 1080",
    );
    await context.swayClient.sendCommand(
      "create_output HEADLESS-3 1920 1080",
    );

    // Position monitors side by side
    await context.swayClient.sendCommand(
      "output HEADLESS-1 pos 0 0",
    );
    await context.swayClient.sendCommand(
      "output HEADLESS-2 pos 1920 0",
    );
    await context.swayClient.sendCommand(
      "output HEADLESS-3 pos 3840 0",
    );

    // Store monitor names for teardown
    context.state.monitors = ["HEADLESS-1", "HEADLESS-2", "HEADLESS-3"];
  },

  async teardown(context: FixtureContext): Promise<void> {
    // Disable the headless outputs
    const monitors = context.state.monitors as string[] || [];
    for (const monitor of monitors) {
      await context.swayClient.sendCommand(`output ${monitor} disable`);
    }
  },
};

export default threeMonitorLayout;
