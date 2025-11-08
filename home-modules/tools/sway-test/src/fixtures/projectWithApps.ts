/**
 * Project with Apps Fixture (T059)
 *
 * Sets up a typical project workspace with terminal, editor, and file manager.
 */

import type { Fixture, FixtureContext } from "./types.ts";

const projectWithApps: Fixture = {
  name: "projectWithApps",
  description: "Sets up workspace with terminal, VS Code, and file manager",
  tags: ["project", "apps", "development"],

  async setup(context: FixtureContext): Promise<void> {
    // Switch to workspace 1
    await context.swayClient.sendCommand("workspace number 1");

    // Launch terminal (Alacritty)
    await context.swayClient.sendCommand("exec alacritty");
    await delay(500); // Wait for window to appear

    // Launch VS Code
    await context.swayClient.sendCommand("exec code");
    await delay(1000); // VS Code takes longer to start

    // Launch file manager (Yazi in terminal)
    await context.swayClient.sendCommand("exec alacritty -e yazi");
    await delay(500);

    // Store launched apps for teardown
    context.state.launchedApps = ["Alacritty", "Code", "Yazi"];
    context.state.workspace = 1;
  },

  async teardown(context: FixtureContext): Promise<void> {
    // Close windows by app_id
    const apps = context.state.launchedApps as string[] || [];

    for (const app of apps) {
      try {
        await context.swayClient.sendCommand(`[app_id="${app}"] kill`);
      } catch {
        // Ignore errors if window already closed
      }
    }

    // Ensure workspace is empty
    await context.swayClient.sendCommand("workspace number 1");
  },
};

// Helper delay function
function delay(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

export default projectWithApps;
