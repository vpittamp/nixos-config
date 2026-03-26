import { parseArgs } from "@std/cli/parse-args";
import { DaemonClient } from "../services/daemon-client.ts";

interface CommandOptions {
  verbose?: boolean;
  debug?: boolean;
}

function showHelp(): void {
  console.log(
    `i3pm launch <open|preview> <app_name> [--host <name>] [--project <qualified_name>] [--json]\n` +
      `i3pm launch status <launch_id> [--json]`,
  );
}

export async function launchCommand(args: string[], _flags: CommandOptions): Promise<number> {
  const parsed = parseArgs(args, {
    boolean: ["help", "json"],
    string: ["project", "qualified-name", "host"],
    alias: { h: "help" },
  });
  const subcommand = String(parsed._[0] || "");
  const appName = String(parsed._[1] || "");
  if (parsed.help || !subcommand) {
    showHelp();
    return 0;
  }
  if (subcommand === "status") {
    if (!appName) {
      console.error("launch status requires a launch id");
      return 1;
    }
    const client = new DaemonClient();
    try {
      const result = await client.request("launch.status", { launch_id: appName });
      console.log(JSON.stringify(result, null, 2));
      return 0;
    } finally {
      client.disconnect();
    }
  }

  if (!appName) {
    console.error("launch requires an app name");
    return 1;
  }

  const client = new DaemonClient();
  try {
    const method = subcommand === "preview" ? "launch.preview" : subcommand === "open" ? "launch.open" : "";
    if (!method) {
      showHelp();
      return 1;
    }
    const result = await client.request(method, {
      app_name: appName,
      target_host: parsed.host || "",
      qualified_name: parsed.project || parsed["qualified-name"] || "",
    });
    console.log(parsed.json ? JSON.stringify(result, null, 2) : JSON.stringify(result, null, 2));
    return 0;
  } finally {
    client.disconnect();
  }
}
