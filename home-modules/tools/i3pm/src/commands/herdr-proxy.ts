import { parseArgs } from "@std/cli/parse-args";
import { DaemonClient } from "../services/daemon-client.ts";

interface CommandOptions {
  verbose?: boolean;
  debug?: boolean;
}

type StateChangeEvent = {
  event_type?: string;
  generation?: number;
  changed_keys?: unknown[];
  payload?: Record<string, unknown>;
  timestamp?: number;
  snapshot_version?: number;
  session_generation?: number;
  display_generation?: number;
  focus_generation?: number;
};

const HERDR_PROXY_PAYLOAD_KEYS = [
  "schema_version",
  "generation",
  "snapshot_version",
  "session_generation",
  "focus_generation",
  "active_ai_sessions",
  "focus_state",
  "focus_intent",
  "herdr",
] as const;

function asRecord(value: unknown): Record<string, unknown> {
  return value && typeof value === "object" && !Array.isArray(value)
    ? value as Record<string, unknown>
    : {};
}

function nonEmptyString(value: unknown): boolean {
  return typeof value === "string" && value.trim().length > 0;
}

function hasHerdrFocusPayload(payload: Record<string, unknown>): boolean {
  const focusState = asRecord(payload.focus_state);
  if (nonEmptyString(focusState.current_herdr_pane_id) || nonEmptyString(focusState.current_session_key)) {
    return true;
  }
  const activeSession = asRecord(focusState.active_session);
  return nonEmptyString(activeSession.herdr_session) ||
    nonEmptyString(activeSession.pane_id) ||
    activeSession.source === "herdr";
}

function showHelp(): void {
  console.log(`i3pm herdr-proxy <snapshot|events|focus> [--json|--jsonl]

Ryzen-side Herdr proxy used by remote dashboard aggregation.

Commands:
  snapshot [--refresh] [--json]       Emit one local-only Herdr proxy snapshot
  events [--jsonl]                    Stream Herdr proxy event envelopes
  focus <pane_id> [--json]            Focus one local Herdr pane through the daemon`);
}

function printResult(result: unknown, json: boolean): void {
  console.log(JSON.stringify(result, null, json ? 0 : 2));
}

export function buildHerdrProxyEvent(
  event: StateChangeEvent,
): Record<string, unknown> | null {
  const changedKeys = Array.isArray(event.changed_keys)
    ? event.changed_keys.map((key) => String(key)).filter(Boolean)
    : [];
  const eventType = String(event.event_type || "");
  const sourcePayload = asRecord(event.payload);
  const isFocusOnly = changedKeys.length > 0 && changedKeys.every((key) => key === "focus_state");
  const isHerdrEvent = eventType === "herdr.changed" ||
    eventType === "session.changed" ||
    changedKeys.includes("herdr") ||
    changedKeys.includes("active_ai_sessions") ||
    (changedKeys.includes("focus_state") && (!isFocusOnly || hasHerdrFocusPayload(sourcePayload)));
  if (!isHerdrEvent) {
    return null;
  }

  const payload: Record<string, unknown> = {};
  for (const key of HERDR_PROXY_PAYLOAD_KEYS) {
    if (sourcePayload[key] !== undefined) {
      payload[key] = sourcePayload[key];
    }
  }

  return {
    schema_version: "i3pm.herdr_proxy.event.v1",
    protocol_version: 1,
    event_type: eventType || "herdr.changed",
    generation: event.generation ?? event.snapshot_version ?? 0,
    snapshot_version: event.snapshot_version ?? event.generation ?? 0,
    session_generation: event.session_generation ?? 0,
    focus_generation: event.focus_generation ?? 0,
    changed_keys: changedKeys,
    timestamp: event.timestamp || Date.now(),
    payload,
  };
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

      // Prevent orphaned processes when ssh session or parent dies
      const initialPpid = Deno.ppid;
      const ppidInterval = setInterval(() => {
        if (Deno.ppid !== initialPpid) {
          clearInterval(ppidInterval);
          client.disconnect();
          Deno.exit(0);
        }
      }, 5000);
      Deno.unrefTimer(ppidInterval);

      for await (const event of client.subscribeToStateChanges()) {
        const proxyEvent = buildHerdrProxyEvent(event);
        if (!proxyEvent) {
          continue;
        }
        console.log(JSON.stringify(proxyEvent));
      }
      return 0;
    }
  } finally {
    client.disconnect();
  }

  showHelp();
  return 1;
}
