import { parseArgs } from "@std/cli/parse-args";
import { DaemonClient } from "../services/daemon-client.ts";

interface CommandOptions {
  verbose?: boolean;
  debug?: boolean;
}

function showHelp(): void {
  console.log(`i3pm dashboard <snapshot|watch> [--json]`);
}

async function fetchSnapshot(client: DaemonClient): Promise<unknown> {
  return await client.request("dashboard.snapshot", {});
}

export async function dashboardCommand(args: string[], _flags: CommandOptions): Promise<number> {
  const parsed = parseArgs(args, {
    boolean: ["help", "json"],
    string: ["interval"],
    alias: { h: "help" },
  });
  const subcommand = String(parsed._[0] || "");
  if (parsed.help || !subcommand) {
    showHelp();
    return 0;
  }

  if (subcommand === "snapshot") {
    const client = new DaemonClient();
    try {
      const snapshot = await fetchSnapshot(client);
      console.log(parsed.json ? JSON.stringify(snapshot, null, 2) : JSON.stringify(snapshot, null, 2));
      return 0;
    } finally {
      client.disconnect();
    }
  }

  if (subcommand === "watch") {
    const intervalMs = Math.max(500, Number(parsed.interval || 2000));
    const client = new DaemonClient();
    let lastPayload = "";
    try {
      while (true) {
        const snapshot = await fetchSnapshot(client);
        const encoded = JSON.stringify(snapshot);
        if (encoded !== lastPayload) {
          console.log(encoded);
          lastPayload = encoded;
        }
        await new Promise((resolve) => setTimeout(resolve, intervalMs));
      }
    } finally {
      client.disconnect();
    }
  }

  showHelp();
  return 1;
}
