import { parseArgs } from "@std/cli/parse-args";
import { DaemonClient } from "../services/daemon-client.ts";

interface CommandOptions {
  verbose?: boolean;
  debug?: boolean;
}

function showHelp(): void {
  console.log(`i3pm display <snapshot|apply|cycle|toggle-output|set-scale> [layout|output] [--json]`);
  console.log(`  set-scale <output> <scale>  Set scale factor for an output (e.g. set-scale DP-1 1.25)`);
}

export async function displayCommand(args: string[], _flags: CommandOptions): Promise<number> {
  const parsed = parseArgs(args, {
    boolean: ["help", "json"],
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
      const snapshot = await client.request("display.snapshot", {});
      console.log(JSON.stringify(snapshot, null, 2));
      return 0;
    }

    if (subcommand === "cycle") {
      const snapshot = await client.request("display.cycle", {});
      console.log(JSON.stringify(snapshot, null, 2));
      return 0;
    }

    if (subcommand === "apply") {
      const layout = String(parsed._[1] || "");
      if (!layout) {
        console.error("display apply requires a layout name");
        return 1;
      }
      const snapshot = await client.request("display.apply", { layout });
      console.log(JSON.stringify(snapshot, null, 2));
      return 0;
    }

    if (subcommand === "toggle-output") {
      const output = String(parsed._[1] || "");
      if (!output) {
        console.error("display toggle-output requires an output name");
        return 1;
      }
      const snapshot = await client.request("display.toggle_output", { output });
      console.log(JSON.stringify(snapshot, null, 2));
      return 0;
    }

    if (subcommand === "set-scale") {
      const output = String(parsed._[1] || "");
      const scale = String(parsed._[2] || "");
      if (!output || !scale) {
        console.error("display set-scale requires <output> <scale>");
        return 1;
      }
      const scaleNum = parseFloat(scale);
      if (isNaN(scaleNum) || scaleNum <= 0) {
        console.error("scale must be a positive number");
        return 1;
      }
      const snapshot = await client.request("display.set_scale", { output, scale: scaleNum });
      console.log(JSON.stringify(snapshot, null, 2));
      return 0;
    }

    showHelp();
    return 1;
  } finally {
    client.disconnect();
  }
}
