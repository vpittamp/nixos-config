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
  return await client.getDashboardSnapshot();
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
    const intervalMs = Math.max(1500, Number(parsed.interval || 5000));
    let lastPayload = "";

    while (true) {
      const client = new DaemonClient();
      let heartbeat: number | undefined;

      const emitSnapshot = async (): Promise<void> => {
        const snapshot = await fetchSnapshot(client);
        const encoded = JSON.stringify(snapshot);
        if (encoded !== lastPayload) {
          console.log(encoded);
          lastPayload = encoded;
        }
      };

      try {
        await client.connect();
        await emitSnapshot();

        heartbeat = setInterval(() => {
          void emitSnapshot().catch(() => {
            // Allow the outer loop to recover on the next stream failure.
          });
        }, intervalMs);

        for await (const _event of client.subscribeToStateChanges()) {
          await emitSnapshot();
        }
      } catch (error) {
        const message = error instanceof Error ? error.message : String(error);
        console.error(`[i3pm dashboard watch] reconnecting after error: ${message}`);
      } finally {
        if (heartbeat !== undefined) {
          clearInterval(heartbeat);
        }
        client.disconnect();
      }

      await new Promise((resolve) => setTimeout(resolve, 1000));
    }
  }

  showHelp();
  return 1;
}
