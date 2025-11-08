/**
 * Empty Workspace Fixture (T059)
 *
 * Ensures workspace 1 is empty and focused for clean test state.
 */

import type { Fixture, FixtureContext } from "./types.ts";

const emptyWorkspace: Fixture = {
  name: "emptyWorkspace",
  description: "Clears workspace 1 and ensures it is empty for testing",
  tags: ["workspace", "cleanup"],

  async setup(context: FixtureContext): Promise<void> {
    // Switch to workspace 1
    await context.swayClient.sendCommand("workspace number 1");

    // Get current tree to find windows on workspace 1
    const tree = await context.swayClient.getTree();
    const ws1 = tree.nodes.flatMap((output) =>
      output.nodes.filter((ws) => ws.num === 1)
    )[0];

    // Close all windows on workspace 1
    if (ws1 && ws1.nodes) {
      for (const node of ws1.nodes) {
        if (node.id) {
          await context.swayClient.sendCommand(`[con_id=${node.id}] kill`);
        }
      }
    }

    // Store initial workspace number
    context.state.initialWorkspace = 1;
  },

  async teardown(context: FixtureContext): Promise<void> {
    // Optional: return to initial workspace
    const initialWs = context.state.initialWorkspace as number || 1;
    await context.swayClient.sendCommand(`workspace number ${initialWs}`);
  },
};

export default emptyWorkspace;
