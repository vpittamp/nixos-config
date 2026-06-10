import { parseArgs } from "@std/cli/parse-args";
import { DaemonClient } from "../services/daemon-client.ts";

interface CommandOptions {
  verbose?: boolean;
  debug?: boolean;
}

function showHelp(): void {
  console.log(`i3pm dashboard <snapshot|watch|events> [--json]

watch emits one initial snapshot, then refetches only after daemon invalidation events.
events streams typed dashboard event envelopes as JSON Lines.

Options:
  --count <n>  Stop after n events (events only)`);
}

async function fetchSnapshot(client: DaemonClient): Promise<unknown> {
  return await client.getDashboardSnapshot();
}

export async function dashboardCommand(args: string[], _flags: CommandOptions): Promise<number> {
  const parsed = parseArgs(args, {
    boolean: ["help", "json"],
    string: ["count", "interval"],
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
    let lastPayload = "";
    let lastSeenGeneration = -1;

    while (true) {
      const snapshotClient = new DaemonClient();
      const subscriptionClient = new DaemonClient();
      let snapshotInFlight = false;
      let snapshotQueued = false;

      const emitSnapshot = async (): Promise<void> => {
        if (snapshotInFlight) {
          snapshotQueued = true;
          return;
        }

        snapshotInFlight = true;
        try {
          do {
            snapshotQueued = false;
            const snapshot = await fetchSnapshot(snapshotClient);
            if (snapshot === undefined || snapshot === null) {
              continue;
            }

            const encoded = JSON.stringify(snapshot);
            if (!encoded || encoded === "undefined") {
              continue;
            }

            if (snapshot && typeof snapshot === "object") {
              const generation = Number((snapshot as { snapshot_version?: unknown }).snapshot_version ?? -1);
              if (Number.isFinite(generation)) {
                lastSeenGeneration = Math.max(lastSeenGeneration, generation);
              }
            }

            if (encoded !== lastPayload) {
              console.log(encoded);
              lastPayload = encoded;
            }
          } while (snapshotQueued);
        } finally {
          snapshotInFlight = false;
        }
      };

      try {
        await snapshotClient.connect();
        await subscriptionClient.connect();
        await emitSnapshot();

        for await (const event of subscriptionClient.subscribeToStateChanges()) {
          const generation = Number(event.generation ?? event.snapshot_version ?? -1);
          if (Number.isFinite(generation) && generation >= 0 && generation <= lastSeenGeneration) {
            continue;
          }
          await emitSnapshot();
        }
      } catch (error) {
        const message = error instanceof Error ? error.message : String(error);
        console.error(`[i3pm dashboard watch] reconnecting after error: ${message}`);
      } finally {
        subscriptionClient.disconnect();
        snapshotClient.disconnect();
      }

      await new Promise((resolve) => setTimeout(resolve, 1000));
    }
  }

  if (subcommand === "events") {
    const countRaw = String(parsed.count || "").trim();
    const maxEvents = countRaw ? Math.max(0, Number.parseInt(countRaw, 10) || 0) : 0;
    const client = new DaemonClient();
    let emitted = 0;
    try {
      await client.connect();
      for await (const event of client.subscribeToStateChanges()) {
        console.log(JSON.stringify(event));
        emitted += 1;
        if (maxEvents > 0 && emitted >= maxEvents) {
          break;
        }
      }
      return 0;
    } finally {
      client.disconnect();
    }
  }

  showHelp();
  return 1;
}
