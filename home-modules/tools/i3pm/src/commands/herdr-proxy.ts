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
  events [--jsonl]                    Stream Herdr proxy event envelopes
  focus <pane_id> [--json]            Focus one local Herdr pane through the daemon`);
}

function printResult(result: unknown, json: boolean): void {
  console.log(JSON.stringify(result, null, json ? 0 : 2));
}

export async function herdrProxyCommand(args: string[], _flags: CommandOptions): Promise<number> {
  const parsed = parseArgs(args, {
    boolean: ["help", "json", "jsonl", "refresh"],
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

    if (subcommand === "events") {
      await client.connect();
      for await (const event of client.subscribeToStateChanges()) {
        const changedKeys = Array.isArray(event.changed_keys) ? event.changed_keys : [];
        const eventType = String(event.event_type || "");
        const isHerdrEvent = eventType === "herdr.changed"
          || eventType === "session.changed"
          || changedKeys.includes("herdr")
          || changedKeys.includes("active_ai_sessions")
          || changedKeys.includes("focus_state");
        if (!isHerdrEvent) {
          continue;
        }
        console.log(JSON.stringify({
          schema_version: "i3pm.herdr_proxy.event.v1",
          protocol_version: 1,
          event_type: eventType || "herdr.changed",
          generation: event.generation ?? event.snapshot_version ?? 0,
          changed_keys: changedKeys,
          timestamp: event.timestamp || Date.now(),
        }));
      }
      return 0;
    }
  } finally {
    client.disconnect();
  }

  showHelp();
  return 1;
}
