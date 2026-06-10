import { parseArgs } from "@std/cli/parse-args";
import { DaemonClient } from "../services/daemon-client.ts";

interface CommandOptions {
  verbose?: boolean;
  debug?: boolean;
}

function showHelp(): void {
  console.log(`i3pm herdr-proxy <snapshot|focus> [--json]

Ryzen-side Herdr proxy used by remote dashboard aggregation.

Commands:
  snapshot [--refresh] [--json]       Emit one local-only Herdr proxy snapshot
  focus <pane_id> [--json]            Focus one local Herdr pane through the daemon`);
}

function printResult(result: unknown, json: boolean): void {
  console.log(JSON.stringify(result, null, json ? 0 : 2));
}

export async function herdrProxyCommand(args: string[], _flags: CommandOptions): Promise<number> {
  const parsed = parseArgs(args, {
    boolean: ["help", "json", "refresh"],
    alias: { h: "help" },
  });
  const subcommand = String(parsed._[0] || "");
  if (parsed.help || !subcommand) {
    showHelp();
    return 0;
  }

  const client = new DaemonClient();
  try {
    if (subcommand === "snapshot") {
      const result = await client.request("herdr.proxy.snapshot", {
        refresh: Boolean(parsed.refresh),
      });
      printResult(result, Boolean(parsed.json));
      return 0;
    }

    if (subcommand === "focus") {
      const paneId = String(parsed._[1] || "").trim();
      if (!paneId) {
        console.error("Usage: i3pm herdr-proxy focus <pane_id> [--json]");
        return 1;
      }
      const result = await client.request("herdr.proxy.pane.focus", {
        pane_id: paneId,
      });
      printResult(result, Boolean(parsed.json));
      return Boolean((result as { success?: boolean }).success) ? 0 : 1;
    }
  } finally {
    client.disconnect();
  }

  showHelp();
  return 1;
}
