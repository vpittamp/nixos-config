import { parseArgs } from "@std/cli/parse-args";
import { DaemonClient } from "../services/daemon-client.ts";

interface CommandOptions {
  verbose?: boolean;
  debug?: boolean;
}

function showHelp(): void {
  console.log(`i3pm session <list|focus> [session_key] [--json]`);
}

export async function sessionCommand(args: string[], _flags: CommandOptions): Promise<number> {
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
    if (subcommand === "list") {
      const result = await client.request("session.list", {});
      console.log(parsed.json ? JSON.stringify(result, null, 2) : JSON.stringify(result, null, 2));
      return 0;
    }
    if (subcommand === "focus") {
      const sessionKey = String(parsed._[1] || "");
      if (!sessionKey) {
        console.error("session focus requires a session key");
        return 1;
      }
      const result = await client.request("session.focus", { session_key: sessionKey });
      console.log(parsed.json ? JSON.stringify(result, null, 2) : JSON.stringify(result, null, 2));
      return 0;
    }
    showHelp();
    return 1;
  } finally {
    client.disconnect();
  }
}
