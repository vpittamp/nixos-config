import { parseArgs } from "@std/cli/parse-args";
import { DaemonClient } from "../services/daemon-client.ts";

interface CommandOptions {
  verbose?: boolean;
  debug?: boolean;
}

function showHelp(): void {
  console.log("i3pm workspace focus <workspace> [--json]");
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

  if (subcommand !== "focus") {
    showHelp();
    return 1;
  }

  const workspace = String(parsed._[1] || "").trim();
  if (!workspace) {
    console.error("workspace focus requires a workspace name or number");
    return 1;
  }

  const client = new DaemonClient();
  try {
    const result = await client.request<{ success?: boolean; workspace?: string }>("workspace.focus", { workspace });
    if (parsed.json) {
      console.log(JSON.stringify(result, null, 2));
    } else {
      const target = String(result.workspace || workspace);
      console.log(`Focused workspace ${target}`);
    }
    return 0;
  } finally {
    client.disconnect();
  }
}
