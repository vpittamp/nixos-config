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

function normalizeLines(text: string, limit: number): string[] {
  const normalized = text.replace(/\r\n?/g, "\n");
  const trimmed = normalized.endsWith("\n") ? normalized.slice(0, -1) : normalized;
  if (!trimmed) {
    return [];
  }
  const lines = trimmed.split("\n");
  return lines.slice(Math.max(0, lines.length - limit));
}

function shellQuote(value: string): string {
  return `'${value.replaceAll("'", `'\\''`)}'`;
}

async function* readLines(stream: ReadableStream<Uint8Array>): AsyncGenerator<string> {
  const reader = stream.pipeThrough(new TextDecoderStream()).getReader();
  let buffer = "";

  try {
    while (true) {
      const { value, done } = await reader.read();
      if (done) {
        break;
      }

      buffer += value;
      const parts = buffer.split("\n");
      buffer = parts.pop() ?? "";
      for (const line of parts) {
        yield line;
      }
    }

    if (buffer.length > 0) {
      yield buffer;
    }
  } finally {
    reader.releaseLock();
  }
}

async function capturePaneContent(info: SessionPreviewInfo): Promise<string> {
  if (!info.tmux_pane) {
    return "";
  }

  let result: Deno.CommandOutput;
  if (info.preview_mode === "ssh_stream") {
    const destination = info.remote_user
      ? `${info.remote_user}@${info.remote_host}`
      : info.remote_host;
    const tmuxCmd = info.tmux_socket
      ? `tmux -S ${shellQuote(info.tmux_socket)}`
      : "tmux";
    const remoteScript = `${tmuxCmd} capture-pane -p -J -S -${info.lines} -t ${shellQuote(info.tmux_pane)}`;
    result = await new Deno.Command("ssh", {
      args: [
        "-o",
        "BatchMode=yes",
        "-o",
        "ConnectTimeout=2",
        "-p",
        String(info.remote_port || 22),
        destination,
        `bash -lc ${shellQuote(remoteScript)}`,
      ],
      stdout: "piped",
      stderr: "piped",
    }).output();
  } else {
    result = await new Deno.Command("tmux", {
      args: ["capture-pane", "-p", "-J", "-S", `-${info.lines}`, "-t", info.tmux_pane],
      stdout: "piped",
      stderr: "piped",
    }).output();
  }

  if (!result.success) {
    const error = new TextDecoder().decode(result.stderr).trim();
    throw new Error(error || `tmux capture-pane failed for ${info.tmux_pane}`);
  }

  return normalizeLines(new TextDecoder().decode(result.stdout), info.lines).join("\n");
}

async function emitSnapshot(info: SessionPreviewInfo): Promise<void> {
  const content = await capturePaneContent(info);
  emitPreviewFrame(buildPreviewFrame(info, {
    kind: "snapshot",
    status: "live",
    content,
    isLive: true,
  }));
}

function previewFallbackMessage(info: SessionPreviewInfo): string {
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
    boolean: ["help", "json"],
    string: ["lines"],
    alias: { h: "help" },
  });

  const sessionKey = String(parsed._[0] || "");
  const follow = subArgs.includes("--follow");
  const jsonl = subArgs.includes("--jsonl");
  const lineCount = Math.max(20, Math.min(200, Number(parsed.lines || 100) || 100));

  if (parsed.help || !sessionKey) {
    showHelp();
    return 0;
  }

  const info = await client.request<SessionPreviewInfo>("session.preview", {
    session_key: sessionKey,
    lines: lineCount,
  });

  if (parsed.json && !follow && !jsonl) {
    console.log(JSON.stringify(info, null, 2));
    return 0;
  }

  if (info.preview_mode !== "local_stream" && info.preview_mode !== "ssh_stream") {
    emitPreviewFrame(buildPreviewFrame(info, {
      kind: "status",
      status: "fallback",
      message: previewFallbackMessage(info),
      isLive: false,
    }));
    return 0;
  }

  try {
    await emitSnapshot(info);
  } catch (error) {
    emitPreviewFrame(buildPreviewFrame(info, {
      kind: "error",
      status: "error",
      message: error instanceof Error ? error.message : String(error),
      isLive: false,
    }));
    return 1;
  }

  if (!follow) {
    return 0;
  }

  if (info.preview_mode === "ssh_stream") {
    let lastContent = "";
    while (true) {
      await new Promise((resolve) => setTimeout(resolve, 1000));
      try {
        const content = await capturePaneContent(info);
        if (content === lastContent) {
          continue;
        }
        lastContent = content;
        emitPreviewFrame(buildPreviewFrame(info, {
          kind: "snapshot",
          status: "live",
          content,
          isLive: true,
        }));
      } catch (error) {
        emitPreviewFrame(buildPreviewFrame(info, {
          kind: "error",
          status: "error",
          message: error instanceof Error ? error.message : String(error),
          isLive: false,
        }));
        return 1;
      }
    }
  }

  const child = new Deno.Command("tmux", {
    args: [
      "-C",
      "attach-session",
      "-t",
      info.tmux_session,
      "-f",
      "read-only,ignore-size,pause-after=1",
    ],
    stdin: "piped",
    stdout: "piped",
    stderr: "piped",
  }).spawn();

  let pendingSnapshot: number | null = null;

  const scheduleSnapshot = () => {
    if (pendingSnapshot !== null) {
      return;
    }
    pendingSnapshot = setTimeout(async () => {
      pendingSnapshot = null;
      try {
        await emitSnapshot(info);
      } catch (error) {
        emitPreviewFrame(buildPreviewFrame(info, {
          kind: "error",
          status: "error",
          message: error instanceof Error ? error.message : String(error),
          isLive: false,
        }));
      }
    }, 90);
  };

  const handleControlLine = (line: string) => {
    if (!line) {
      return;
    }
    if (
      line.startsWith(`%output ${info.tmux_pane} `) ||
      line.startsWith(`%extended-output ${info.tmux_pane} `)
    ) {
      scheduleSnapshot();
      return;
    }
    if (line.startsWith("%exit")) {
      emitPreviewFrame(buildPreviewFrame(info, {
        kind: "status",
        status: "closed",
        message: "Pane preview ended.",
        isLive: false,
      }));
    }
  };

  const stdoutTask = (async () => {
    if (!child.stdout) {
      return;
    }
    for await (const line of readLines(child.stdout)) {
      handleControlLine(line);
    }
  })();

  const stderrTask = (async () => {
    if (!child.stderr) {
      return;
    }
    for await (const line of readLines(child.stderr)) {
      const message = line.trim();
      if (!message) {
        continue;
      }
      emitPreviewFrame(buildPreviewFrame(info, {
        kind: "error",
        status: "error",
        message,
        isLive: false,
      }));
    }
  })();

  try {
    const [, , status] = await Promise.all([stdoutTask, stderrTask, child.status]);
    if (!status.success) {
      emitPreviewFrame(buildPreviewFrame(info, {
        kind: "error",
        status: "error",
        message: "tmux control-mode preview exited unexpectedly.",
        isLive: false,
      }));
      return 1;
    }
  } finally {
    if (pendingSnapshot !== null) {
      clearTimeout(pendingSnapshot);
    }
    try {
      child.kill("SIGTERM");
    } catch {
      // Ignore cleanup failures for already-exited control clients.
    }
  }

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
