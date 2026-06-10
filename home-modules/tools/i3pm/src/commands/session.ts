import { parseArgs } from "@std/cli/parse-args";
import { DaemonClient } from "../services/daemon-client.ts";

interface CommandOptions {
  verbose?: boolean;
  debug?: boolean;
}

interface SessionPreviewInfo {
  success: boolean;
  session_key: string;
  preview_mode: string;
  preview_reason: string;
  message?: string;
  lines: number;
  is_live: boolean;
  is_remote: boolean;
  tool: string;
  project_name: string;
  host_name: string;
  connection_key: string;
  focus_connection_key: string;
  execution_mode: string;
  focus_mode: string;
  availability_state: string;
  focusability_reason: string;
  window_id: number;
  bridge_window_id: number;
  bridge_state: string;
  pane_label: string;
  pane_title: string;
  tmux_socket: string;
  tmux_session: string;
  tmux_window: string;
  tmux_pane: string;
  remote_user: string;
  remote_host: string;
  remote_port: number;
  surface_key: string;
  session_phase: string;
  session_phase_label: string;
  turn_owner: string;
  turn_owner_label: string;
  activity_substate: string;
  activity_substate_label: string;
  status_reason: string;
}

function showHelp(): void {
  console.log(`i3pm session <list|focus|close|preview|cleanup|doctor> [session_key] [--json]

  i3pm session preview <session_key> [--follow] [--lines <n>] [--jsonl]
  i3pm session close <session_key> [--json]
  i3pm session cleanup [--json]
  i3pm session doctor [--json]`);
}

function emitPreviewFrame(frame: Record<string, unknown>): void {
  console.log(JSON.stringify(frame));
}

function buildPreviewFrame(
  info: SessionPreviewInfo,
  {
    status,
    kind,
    content = "",
    message = "",
    isLive = false,
  }: {
    status: string;
    kind: string;
    content?: string;
    message?: string;
    isLive?: boolean;
  },
): Record<string, unknown> {
  return {
    kind,
    status,
    session_key: info.session_key,
    preview_mode: info.preview_mode,
    preview_reason: info.preview_reason,
    is_live: isLive,
    is_remote: info.is_remote,
    tool: info.tool,
    project_name: info.project_name,
    host_name: info.host_name,
    connection_key: info.connection_key,
    execution_mode: info.execution_mode,
    focus_mode: info.focus_mode,
    availability_state: info.availability_state,
    focusability_reason: info.focusability_reason,
    window_id: info.window_id,
    bridge_window_id: info.bridge_window_id,
    bridge_state: info.bridge_state,
    pane_label: info.pane_label,
    pane_title: info.pane_title,
    tmux_session: info.tmux_session,
    tmux_window: info.tmux_window,
    tmux_pane: info.tmux_pane,
    surface_key: info.surface_key,
    session_phase: info.session_phase,
    session_phase_label: info.session_phase_label,
    turn_owner: info.turn_owner,
    turn_owner_label: info.turn_owner_label,
    activity_substate: info.activity_substate,
    activity_substate_label: info.activity_substate_label,
    status_reason: info.status_reason,
    content,
    message,
    updated_at: new Date().toISOString(),
  };
}

function previewFallbackMessage(info: SessionPreviewInfo): string {
  const daemonMessage = String(info.message || "").trim();
  if (daemonMessage) {
    return daemonMessage;
  }
  if (info.preview_reason === "herdr_focus_only") {
    return "Focus this Herdr pane to inspect live output.";
  }
  if (info.preview_reason === "herdr_focus_required") {
    return "Live tmux preview has been retired. Focus the corresponding Herdr pane for live inspection.";
  }
  if (info.preview_reason === "missing_tmux_identity") {
    return "This session has no tmux pane identity, so there is nothing stable to preview.";
  }
  if (info.preview_reason === "stale_remote_source") {
    return "The remote session source is stale, so live preview is temporarily unavailable.";
  }
  return "Preview is unavailable for this session.";
}

async function runPreview(client: DaemonClient, subArgs: string[]): Promise<number> {
  const parsed = parseArgs(subArgs, {
    boolean: ["help", "json", "follow", "jsonl"],
    string: ["lines"],
    alias: { h: "help" },
  });

  const sessionKey = String(parsed._[0] || "");
  const jsonl = Boolean(parsed.jsonl);
  const lineCount = Math.max(20, Math.min(200, Number(parsed.lines || 100) || 100));

  if (parsed.help || !sessionKey) {
    showHelp();
    return 0;
  }

  const info = await client.request<SessionPreviewInfo>("session.preview", {
    session_key: sessionKey,
    lines: lineCount,
  });

  if (parsed.json && !parsed.follow && !jsonl) {
    console.log(JSON.stringify(info, null, 2));
    return 0;
  }

  emitPreviewFrame(buildPreviewFrame(info, {
    kind: "status",
    status: info.preview_mode === "focus_only" ? "focus_required" : "unavailable",
    message: previewFallbackMessage(info),
    isLive: false,
  }));
  return 0;
}

export async function sessionCommand(args: string[], _flags: CommandOptions): Promise<number> {
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
    if (subcommand === "list") {
      const result = await client.request("session.list", {});
      console.log(parsed.json ? JSON.stringify(result, null, 2) : JSON.stringify(result, null, 2));
      return 0;
    }
    if (subcommand === "focus") {
      const sessionKey = String(parsed._[1] || "");
      if (!sessionKey) {
        console.error("session focus requires a session key");
        return 1;
      }
      const result = await client.request("session.focus", { session_key: sessionKey });
      console.log(parsed.json ? JSON.stringify(result, null, 2) : JSON.stringify(result, null, 2));
      return 0;
    }
    if (subcommand === "close") {
      const sessionKey = String(parsed._[1] || "");
      if (!sessionKey) {
        console.error("session close requires a session key");
        return 1;
      }
      const result = await client.request("session.close", { session_key: sessionKey });
      console.log(parsed.json ? JSON.stringify(result, null, 2) : JSON.stringify(result, null, 2));
      return 0;
    }
    if (subcommand === "preview") {
      return await runPreview(client, args.slice(1));
    }
    if (subcommand === "cleanup") {
      const result = await client.request("session.cleanup", {});
      console.log(parsed.json ? JSON.stringify(result, null, 2) : JSON.stringify(result, null, 2));
      return 0;
    }
    if (subcommand === "doctor") {
      const result = await client.request("session.doctor", {});
      console.log(parsed.json ? JSON.stringify(result, null, 2) : JSON.stringify(result, null, 2));
      return 0;
    }
    showHelp();
    return 1;
  } finally {
    client.disconnect();
  }
}
