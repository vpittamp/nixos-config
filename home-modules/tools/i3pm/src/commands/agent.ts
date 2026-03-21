import { parseArgs } from "@std/cli/parse-args";
import { DaemonClient } from "../services/daemon-client.ts";

interface CommandOptions {
  verbose?: boolean;
  debug?: boolean;
}

function showHelp(): void {
  console.log(`i3pm agent <snapshot|watch|start|send|cancel|approve|deny> [options]

  i3pm agent snapshot [--json]
  i3pm agent watch
  i3pm agent start [--model <name>] [--cwd <path>] [--json]
  i3pm agent send <session_key> --text <prompt> [--json]
  i3pm agent cancel <session_key> [--json]
  i3pm agent approve <session_key> <request_id> [--json]
  i3pm agent deny <session_key> <request_id> [--json]`);
}

export async function agentCommand(args: string[], _flags: CommandOptions): Promise<number> {
  const parsed = parseArgs(args, {
    boolean: ["help", "json"],
    string: ["cwd", "model", "text"],
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
      const snapshot = await client.getAgentSnapshot();
      console.log(JSON.stringify(snapshot, null, parsed.json ? 2 : 0));
      return 0;
    } finally {
      client.disconnect();
    }
  }

  if (subcommand === "watch") {
    let lastPayload = "";
    while (true) {
      const snapshotClient = new DaemonClient();
      const subscriptionClient = new DaemonClient();
      try {
        await snapshotClient.connect();
        await subscriptionClient.connect();

        const emit = async (): Promise<void> => {
          const snapshot = await snapshotClient.getAgentSnapshot();
          const encoded = JSON.stringify(snapshot);
          if (encoded !== lastPayload) {
            console.log(encoded);
            lastPayload = encoded;
          }
        };

        await emit();
        for await (const _event of subscriptionClient.subscribeToStateChanges()) {
          await emit();
        }
      } catch (error) {
        const message = error instanceof Error ? error.message : String(error);
        console.error(`[i3pm agent watch] reconnecting after error: ${message}`);
      } finally {
        snapshotClient.disconnect();
        subscriptionClient.disconnect();
      }
      await new Promise((resolve) => setTimeout(resolve, 1000));
    }
  }

  const client = new DaemonClient();
  try {
    if (subcommand === "start") {
      const result = await client.request("agent.session.start", {
        cwd: parsed.cwd ? String(parsed.cwd) : undefined,
        model: parsed.model ? String(parsed.model) : undefined,
      });
      console.log(JSON.stringify(result, null, parsed.json ? 2 : 0));
      return 0;
    }

    if (subcommand === "send") {
      const sessionKey = String(parsed._[1] || "");
      const text = String(parsed.text || "");
      if (!sessionKey || !text) {
        showHelp();
        return 1;
      }
      const result = await client.request("agent.session.send", {
        session_key: sessionKey,
        text,
      });
      console.log(JSON.stringify(result, null, parsed.json ? 2 : 0));
      return 0;
    }

    if (subcommand === "cancel") {
      const sessionKey = String(parsed._[1] || "");
      if (!sessionKey) {
        showHelp();
        return 1;
      }
      const result = await client.request("agent.session.cancel", {
        session_key: sessionKey,
      });
      console.log(JSON.stringify(result, null, parsed.json ? 2 : 0));
      return 0;
    }

    if (subcommand === "approve" || subcommand === "deny") {
      const sessionKey = String(parsed._[1] || "");
      const requestId = String(parsed._[2] || "");
      if (!sessionKey || !requestId) {
        showHelp();
        return 1;
      }
      const result = await client.request("agent.session.respond", {
        session_key: sessionKey,
        request_id: requestId,
        decision: subcommand === "approve" ? "approve" : "deny",
      });
      console.log(JSON.stringify(result, null, parsed.json ? 2 : 0));
      return 0;
    }
  } finally {
    client.disconnect();
  }

  showHelp();
  return 1;
}
