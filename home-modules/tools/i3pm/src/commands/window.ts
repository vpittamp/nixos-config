import { parseArgs } from "@std/cli/parse-args";
import { DaemonClient } from "../services/daemon-client.ts";

interface CommandOptions {
  verbose?: boolean;
  debug?: boolean;
}

function showHelp(): void {
  console.log(`i3pm window <focus|action> <window_id> [action] [--project <name>] [--host <name>] [--connection-key <key>] [--json]`);
}

function focusParams(parsed: ReturnType<typeof parseArgs>, windowId: number): Record<string, unknown> {
  const connectionKey = String(parsed["connection-key"] || "");
  const targetHost = String(parsed.host || "");
  return {
    window_id: windowId,
    project_name: parsed.project || "",
    target_host: targetHost,
    target_variant: connectionKey || targetHost ? "ssh" : "local",
    connection_key: connectionKey,
  };
}

export async function windowCommand(args: string[], _flags: CommandOptions): Promise<number> {
  const parsed = parseArgs(args, {
    boolean: ["help", "json"],
    string: ["project", "host", "connection-key"],
    alias: { h: "help" },
  });
  const subcommand = String(parsed._[0] || "");
  const windowId = Number(parsed._[1] || 0);
  if (parsed.help || !subcommand) {
    showHelp();
    return 0;
  }
  if (!Number.isInteger(windowId) || windowId <= 0) {
    console.error("window requires a positive integer window_id");
    return 1;
  }

  const client = new DaemonClient();
  try {
    let result: unknown;
    if (subcommand === "focus") {
      const params = focusParams(parsed, windowId);
      result = await client.request("window.focus_fast", params);
      if (
        result &&
        typeof result === "object" &&
        (result as { success?: unknown }).success === false &&
        (result as { fallback_method?: unknown }).fallback_method === "window.focus"
      ) {
        result = await client.request("window.focus", params);
      }
    } else if (subcommand === "action") {
      const requestedAction = String(parsed._[2] || "");
      if (!requestedAction) {
        console.error("window action requires an action name");
        return 1;
      }
      const action = requestedAction === "close" ? "kill" : requestedAction;
      result = await client.request("window.action", {
        window_id: windowId,
        action,
        project_name: parsed.project || "",
        target_host: parsed.host || "",
        connection_key: parsed["connection-key"] || "",
      });
    } else {
      showHelp();
      return 1;
    }
    console.log(parsed.json ? JSON.stringify(result, null, 2) : JSON.stringify(result, null, 2));
    return 0;
  } finally {
    client.disconnect();
  }
}
