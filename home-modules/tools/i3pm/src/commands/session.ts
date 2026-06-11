import { parseArgs } from "@std/cli/parse-args";
import { DaemonClient } from "../services/daemon-client.ts";

interface CommandOptions {
  verbose?: boolean;
  debug?: boolean;
}

function showHelp(): void {
  console.log(`i3pm session <list|cleanup|doctor> [--json]

  i3pm session list [--json]
  i3pm session cleanup [--json]
  i3pm session doctor [--json]`);
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
    if (subcommand === "cleanup") {
      const result = await client.request("session.cleanup", {});
      console.log(parsed.json ? JSON.stringify(result, null, 2) : JSON.stringify(result, null, 2));
      return 0;
    }
    if (subcommand === "doctor") {
      const result = await client.request("session.doctor", {});
      console.log(parsed.json ? JSON.stringify(result, null, 2) : JSON.stringify(result, null, 2));
      return 0;
    }
    showHelp();
    return 1;
  } finally {
    client.disconnect();
  }
}
