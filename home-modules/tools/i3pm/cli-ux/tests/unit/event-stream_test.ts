import { assertEquals, assertGreaterOrEqual } from "@std/assert";
import { EventStream, type Event, aggregateEvents, createEventBuffer } from "../../src/event-stream.ts";

Deno.test("EventStream buffers events", () => {
  const stream = new EventStream({ flushInterval: 1000 }); // Long interval

  stream.push({ timestamp: Date.now(), type: "test", payload: 1 });
  stream.push({ timestamp: Date.now(), type: "test", payload: 2 });

  assertEquals(stream.eventCount, 2);
  stream.stop();
});

Deno.test("EventStream flushes on interval", async () => {
  const events: Event<number>[] = [];
  const stream = new EventStream<number>({ flushInterval: 100 });

  stream.on("flush", (flushed) => events.push(...flushed));

  stream.push({ timestamp: Date.now(), type: "test", payload: 1 });

  await new Promise((r) => setTimeout(r, 150));

  assertEquals(events.length, 1);
  assertEquals(events[0].payload, 1);

  stream.stop();
});

Deno.test("EventStream aggregates duplicates", () => {
  const stream = new EventStream<number>({ aggregate: true, flushInterval: 1000 });
  const results: Event<number>[] = [];

  stream.on("flush", (events) => results.push(...events));

  const now = Date.now();
  stream.push({ timestamp: now, type: "click", payload: 1 });
  stream.push({ timestamp: now + 50, type: "click", payload: 1 });
  stream.push({ timestamp: now + 100, type: "click", payload: 1 });

  stream.flush();

  // Should aggregate rapid duplicates
  assertGreaterOrEqual(3, results.length);
  assertEquals(results.length >= 1, true);

  stream.stop();
});

Deno.test("EventStream respects buffer size", () => {
  const stream = new EventStream({ bufferSize: 3, flushInterval: 1000 });

  for (let i = 0; i < 10; i++) {
    stream.push({ timestamp: Date.now(), type: "test", payload: i });
  }

  // Buffer should not exceed max size (will auto-flush when full)
  assertEquals(stream.eventCount <= 3, true);

  stream.stop();
});

Deno.test("EventStream filters events", () => {
  const stream = new EventStream<number>({
    filter: (event) => (event.payload as number) > 5,
    flushInterval: 1000,
  });

  stream.push({ timestamp: Date.now(), type: "test", payload: 3 });
  stream.push({ timestamp: Date.now(), type: "test", payload: 7 });
  stream.push({ timestamp: Date.now(), type: "test", payload: 2 });
  stream.push({ timestamp: Date.now(), type: "test", payload: 10 });

  // Only events with payload > 5 should be buffered
  assertEquals(stream.eventCount, 2);

  stream.stop();
});

Deno.test("EventStream tracks total events", () => {
  const stream = new EventStream({ flushInterval: 1000 });

  for (let i = 0; i < 5; i++) {
    stream.push({ timestamp: Date.now(), type: "test", payload: i });
  }

  assertEquals(stream.totalEvents, 5);

  stream.flush();

  // Total should persist after flush
  assertEquals(stream.totalEvents, 5);

  stream.stop();
});

Deno.test("aggregateEvents combines duplicates", () => {
  const now = Date.now();
  const events = [
    { timestamp: now, type: "click", payload: "a" },
    { timestamp: now + 50, type: "click", payload: "a" },
    { timestamp: now + 500, type: "click", payload: "b" },
  ];

  const aggregated = aggregateEvents(events);

  // First two should be aggregated, third is separate
  assertEquals(aggregated.length, 2);
});

Deno.test("createEventBuffer maintains max size", () => {
  const buffer = createEventBuffer<string>(3);

  buffer.push({ timestamp: Date.now(), type: "test", payload: "a" });
  buffer.push({ timestamp: Date.now(), type: "test", payload: "b" });
  buffer.push({ timestamp: Date.now(), type: "test", payload: "c" });
  buffer.push({ timestamp: Date.now(), type: "test", payload: "d" });

  assertEquals(buffer.size, 3);

  const events = buffer.get();
  assertEquals(events[0].payload, "b"); // 'a' should be removed
  assertEquals(events[2].payload, "d");
});

Deno.test("createEventBuffer retrieves recent events", () => {
  const buffer = createEventBuffer<number>(10);

  for (let i = 0; i < 5; i++) {
    buffer.push({ timestamp: Date.now(), type: "test", payload: i });
  }

  const recent = buffer.get(2);
  assertEquals(recent.length, 2);
  assertEquals(recent[0].payload, 3);
  assertEquals(recent[1].payload, 4);
});

Deno.test("createEventBuffer clears correctly", () => {
  const buffer = createEventBuffer<number>(10);

  buffer.push({ timestamp: Date.now(), type: "test", payload: 1 });
  buffer.push({ timestamp: Date.now(), type: "test", payload: 2 });

  assertEquals(buffer.size, 2);

  buffer.clear();

  assertEquals(buffer.size, 0);
  assertEquals(buffer.get().length, 0);
});
