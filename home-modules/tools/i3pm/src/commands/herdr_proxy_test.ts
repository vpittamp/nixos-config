import { assertEquals } from "jsr:@std/assert";
import { buildHerdrProxyEvent } from "./herdr-proxy.ts";

Deno.test("buildHerdrProxyEvent emits compact payload for Herdr events", () => {
  const event = buildHerdrProxyEvent({
    event_type: "herdr.changed",
    generation: 12,
    snapshot_version: 12,
    session_generation: 21,
    focus_generation: 31,
    changed_keys: ["focus_state", "active_ai_sessions", "herdr"],
    timestamp: 123.5,
    payload: {
      schema_version: "i3pm.dashboard.v2",
      generation: 12,
      snapshot_version: 12,
      session_generation: 21,
      focus_generation: 31,
      focus_state: { current_herdr_pane_id: "pane-a" },
      active_ai_sessions: [{ session_key: "session-a" }],
      herdr: { local_herdr_generation: 4 },
      projects: [{ name: "not-proxied" }],
    },
  });

  assertEquals(event, {
    schema_version: "i3pm.herdr_proxy.event.v1",
    protocol_version: 1,
    event_type: "herdr.changed",
    generation: 12,
    snapshot_version: 12,
    session_generation: 21,
    focus_generation: 31,
    changed_keys: ["focus_state", "active_ai_sessions", "herdr"],
    timestamp: 123.5,
    payload: {
      schema_version: "i3pm.dashboard.v2",
      generation: 12,
      snapshot_version: 12,
      session_generation: 21,
      focus_generation: 31,
      focus_state: { current_herdr_pane_id: "pane-a" },
      active_ai_sessions: [{ session_key: "session-a" }],
      herdr: { local_herdr_generation: 4 },
    },
  });
});

Deno.test("buildHerdrProxyEvent filters unrelated dashboard events", () => {
  const event = buildHerdrProxyEvent({
    event_type: "display.changed",
    generation: 12,
    changed_keys: ["outputs"],
    payload: { outputs: [{ name: "eDP-1" }] },
  });

  assertEquals(event, null);
});

Deno.test("buildHerdrProxyEvent tolerates missing daemon payload", () => {
  const event = buildHerdrProxyEvent({
    event_type: "session.changed",
    generation: 12,
    changed_keys: ["active_ai_sessions"],
    timestamp: 123.5,
  });

  assertEquals(event, {
    schema_version: "i3pm.herdr_proxy.event.v1",
    protocol_version: 1,
    event_type: "session.changed",
    generation: 12,
    snapshot_version: 12,
    session_generation: 0,
    focus_generation: 0,
    changed_keys: ["active_ai_sessions"],
    timestamp: 123.5,
    payload: {},
  });
});
