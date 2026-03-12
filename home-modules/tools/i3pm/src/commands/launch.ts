import { parseArgs } from "@std/cli/parse-args";
import { DaemonClient } from "../services/daemon-client.ts";

interface CommandOptions {
  verbose?: boolean;
  debug?: boolean;
}

function showHelp(): void {
  console.log(`i3pm launch <open|preview> <app_name> [--local|--variant <local|ssh>] [--json]`);
}

export async function launchCommand(args: string[], _flags: CommandOptions): Promise<number> {
  const parsed = parseArgs(args, {
    boolean: ["help", "json", "local"],
    string: ["variant"],
    alias: { h: "help" },
  });
  const subcommand = String(parsed._[0] || "");
  const appName = String(parsed._[1] || "");
  if (parsed.help || !subcommand) {
    showHelp();
    return 0;
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
      context_variant_override: parsed.variant || (parsed.local ? "local" : ""),
    });
    console.log(parsed.json ? JSON.stringify(result, null, 2) : JSON.stringify(result, null, 2));
    return 0;
  } finally {
    client.disconnect();
  }
}
