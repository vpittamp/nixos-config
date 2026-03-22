import { parseArgs } from "@std/cli/parse-args";
import { DaemonClient } from "../services/daemon-client.ts";

interface CommandOptions {
  verbose?: boolean;
  debug?: boolean;
}

function positionalArg(parsed: ReturnType<typeof parseArgs>, index: number): string {
  const value = parsed._[index];
  return value === undefined || value === null ? "" : String(value);
}

function showHelp(): void {
  console.log(`i3pm agent <snapshot|watch|desktop-snapshot|desktop-watch|start|send|cancel|approve|deny> [options]

  i3pm agent snapshot [--json]
  i3pm agent watch
  i3pm agent desktop-snapshot [--processes] [--limit <n>] [--json]
  i3pm agent desktop-watch [--processes] [--limit <n>]
  i3pm agent start [--qualified-name <account/repo:branch>] [--model <name>] [--cwd <path>] [--json]
  i3pm agent send <session_key> --text <prompt> [--json]
  i3pm agent cancel <session_key> [--json]
  i3pm agent approve <session_key> <request_id> [--json]
  i3pm agent deny <session_key> <request_id> [--json]`);
}

export async function agentCommand(args: string[], _flags: CommandOptions): Promise<number> {
  const parsed = parseArgs(args, {
    boolean: ["help", "json", "processes"],
    string: ["cwd", "model", "qualified-name", "text", "limit"],
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
    while (true) {
      const client = new DaemonClient();
      try {
        await client.connect();
        const snapshot = await client.getAgentSnapshot();
        console.log(JSON.stringify({
          kind: "snapshot",
          snapshot,
        }));

        for await (const event of client.subscribeToAgentEvents()) {
          console.log(JSON.stringify({
            kind: "event",
            event,
          }));
        }
      } catch (error) {
        const message = error instanceof Error ? error.message : String(error);
        console.error(`[i3pm agent watch] reconnecting after error: ${message}`);
      } finally {
        client.disconnect();
      }
      await new Promise((resolve) => setTimeout(resolve, 1000));
    }
  }

  if (subcommand === "desktop-snapshot") {
    const client = new DaemonClient();
    try {
      const snapshot = await client.getAssistantDesktopSnapshot({
        include_processes: Boolean(parsed.processes),
        process_limit: parsed.limit ? Number(parsed.limit) : undefined,
      });
      console.log(JSON.stringify(snapshot, null, parsed.json ? 2 : 0));
      return 0;
    } finally {
      client.disconnect();
    }
  }

  if (subcommand === "desktop-watch") {
    const includeProcesses = Boolean(parsed.processes);
    const processLimit = parsed.limit ? Number(parsed.limit) : undefined;
    const shouldRefreshForEvent = (eventType: string): boolean => {
      return [
        "state_changed",
        "window",
        "workspace",
        "project",
        "display",
        "scratchpad",
        "agent_session",
        "focus",
      ].some((fragment) => eventType.includes(fragment));
    };

    while (true) {
      const client = new DaemonClient();
      try {
        await client.connect();
        const snapshot = await client.getAssistantDesktopSnapshot({
          include_processes: includeProcesses,
          process_limit: processLimit,
        });
        console.log(JSON.stringify({
          kind: "snapshot",
          snapshot,
        }));

        for await (const event of client.subscribeToStateChanges()) {
          if (!shouldRefreshForEvent(String(event.type || ""))) {
            continue;
          }
          const snapshotClient = new DaemonClient();
          try {
            const nextSnapshot = await snapshotClient.getAssistantDesktopSnapshot({
              include_processes: includeProcesses,
              process_limit: processLimit,
            });
            console.log(JSON.stringify({
              kind: "snapshot",
              cause: event.type,
              snapshot: nextSnapshot,
            }));
          } finally {
            snapshotClient.disconnect();
          }
        }
      } catch (error) {
        const message = error instanceof Error ? error.message : String(error);
        console.error(`[i3pm agent desktop-watch] reconnecting after error: ${message}`);
      } finally {
        client.disconnect();
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
        qualified_name: parsed["qualified-name"] ? String(parsed["qualified-name"]) : undefined,
      });
      console.log(JSON.stringify(result, null, parsed.json ? 2 : 0));
      return 0;
    }

    if (subcommand === "send") {
      const sessionKey = positionalArg(parsed, 1);
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
      const sessionKey = positionalArg(parsed, 1);
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
      const sessionKey = positionalArg(parsed, 1);
      const requestId = positionalArg(parsed, 2);
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
