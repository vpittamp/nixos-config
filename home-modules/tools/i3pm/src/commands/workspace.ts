import { parseArgs } from "@std/cli/parse-args";
import { DaemonClient } from "../services/daemon-client.ts";

interface CommandOptions {
  verbose?: boolean;
  debug?: boolean;
}

function showHelp(): void {
  console.log("i3pm workspace <focus|move-to-output> ... [--json]");
}

export async function workspaceCommand(args: string[], _flags: CommandOptions): Promise<number> {
  const parsed = parseArgs(args, {
    boolean: ["help", "json"],
    alias: { h: "help" },
  });
  const subcommand = String(parsed._[0] || "");
  if (parsed.help || !subcommand) {
    showHelp();
    return 0;
  }

  const client = new DaemonClient();
  try {
    if (subcommand === "focus") {
      const workspace = String(parsed._[1] || "").trim();
      if (!workspace) {
        console.error("workspace focus requires a workspace name or number");
        return 1;
      }

      const result = await client.request<{ success?: boolean; workspace?: string }>("workspace.focus", { workspace });
      if (result.success === false) {
        console.error(`Failed to focus workspace ${workspace}`);
        return 1;
      }
      if (parsed.json) {
        console.log(JSON.stringify(result, null, 2));
      } else {
        const target = String(result.workspace || workspace);
        console.log(`Focused workspace ${target}`);
      }
      return 0;
    }

    if (subcommand === "move-to-output") {
      const workspace = String(parsed._[1] || "").trim();
      const outputName = String(parsed._[2] || "").trim();
      if (!workspace || !outputName) {
        console.error("workspace move-to-output requires a workspace and output name");
        return 1;
      }

      const result = await client.request<{ success?: boolean; workspace?: string; output_name?: string }>(
        "workspace.move_to_output",
        { workspace, output_name: outputName },
      );
      if (result.success === false) {
        console.error(`Failed to move workspace ${workspace} to ${outputName}`);
        return 1;
      }
      if (parsed.json) {
        console.log(JSON.stringify(result, null, 2));
      } else {
        console.log(`Moved workspace ${String(result.workspace || workspace)} to ${String(result.output_name || outputName)}`);
      }
      return 0;
    }

    showHelp();
    return 1;
  } finally {
    client.disconnect();
  }
}
