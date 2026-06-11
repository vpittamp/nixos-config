import { assertEquals } from "jsr:@std/assert";
import { applyDashboardEvent, isDeltaEvent } from "./dashboard.ts";

Deno.test("isDeltaEvent accepts typed payload events", () => {
  assertEquals(
    isDeltaEvent({
      event_type: "focus.changed",
      changed_keys: ["focus_state", "projects"],
      payload: { focus_state: { current_window_id: 101 } },
    }),
    true,
  );
});

Deno.test("isDeltaEvent rejects invalidation events", () => {
  assertEquals(
    isDeltaEvent({
      event_type: "dashboard.invalidated",
      changed_keys: ["dashboard"],
      payload: { status: "invalidated" },
    }),
    false,
  );
});

Deno.test("isDeltaEvent rejects dashboard-wide changed keys", () => {
  assertEquals(
    isDeltaEvent({
      event_type: "window.changed",
      changed_keys: ["dashboard"],
      payload: { projects: [] },
    }),
    false,
  );
});

Deno.test("applyDashboardEvent merges partial payload and generations", () => {
  const snapshot = {
    schema_version: "i3pm.dashboard.v2",
    generation: 10,
    snapshot_version: 10,
    session_generation: 20,
    display_generation: 30,
    focus_generation: 40,
    focus_state: { current_window_id: 101 },
    active_ai_sessions: [{ session_key: "old" }],
  };

  const next = applyDashboardEvent(snapshot, {
    generation: 11,
    session_generation: 21,
    focus_generation: 41,
    payload: {
      focus_state: { current_window_id: 202 },
      active_ai_sessions: [{ session_key: "new" }],
    },
  });

  assertEquals(next.generation, 11);
  assertEquals(next.snapshot_version, 11);
  assertEquals(next.session_generation, 21);
  assertEquals(next.display_generation, 30);
  assertEquals(next.focus_generation, 41);
  assertEquals(next.focus_state, { current_window_id: 202 });
  assertEquals(next.active_ai_sessions, [{ session_key: "new" }]);
});
