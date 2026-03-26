import { parseArgs } from "@std/cli/parse-args";
import { DaemonClient } from "../services/daemon-client.ts";

interface CommandOptions {
  verbose?: boolean;
  debug?: boolean;
}

function showHelp(): void {
  console.log(`i3pm context <current|ensure|clear> [options]`);
}

export async function contextCommand(args: string[], _flags: CommandOptions): Promise<number> {
  const parsed = parseArgs(args, {
    boolean: ["help", "json", "clear"],
    string: ["host"],
    alias: { h: "help" },
  });
  const subcommand = String(parsed._[0] || "");
  if (parsed.help || !subcommand) {
    showHelp();
    return 0;
  }

  const client = new DaemonClient();
  try {
    if (subcommand === "current") {
      const result = await client.request("context.current", {});
      console.log(parsed.json ? JSON.stringify(result, null, 2) : JSON.stringify(result, null, 2));
      return 0;
    }
    if (subcommand === "ensure") {
      const qualifiedName = String(parsed._[1] || "");
      if (!qualifiedName) {
        console.error("context ensure requires a qualified worktree name");
        return 1;
      }
      const result = await client.request("context.ensure", {
        qualified_name: qualifiedName,
        target_host: parsed.host || "",
      });
      console.log(parsed.json ? JSON.stringify(result, null, 2) : JSON.stringify(result, null, 2));
      return 0;
    }
    if (subcommand === "clear") {
      const result = await client.request("context.ensure", { clear: true });
      console.log(parsed.json ? JSON.stringify(result, null, 2) : JSON.stringify(result, null, 2));
      return 0;
    }
    showHelp();
    return 1;
  } finally {
    client.disconnect();
  }
}
