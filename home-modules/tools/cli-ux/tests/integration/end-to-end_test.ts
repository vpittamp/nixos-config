import { assertEquals } from "@std/assert";
import {
  detectTerminalCapabilities,
  OutputFormatter,
  ProgressBar,
  renderTable,
  setup,
} from "../../mod.ts";

Deno.test("E2E: Complete CLI workflow", async () => {
  // Detect capabilities
  const caps = detectTerminalCapabilities();
  assertEquals(typeof caps.width, "number");
  assertEquals(typeof caps.height, "number");
  assertEquals(typeof caps.isTTY, "boolean");

  // Format output
  const fmt = new OutputFormatter(caps);
  const message = fmt.success("Test");
  assertEquals(message.includes("Test"), true);

  // Progress bar
  const progress = new ProgressBar({
    message: "Testing",
    total: 10,
    showAfter: 0, // Show immediately for test
  });
  progress.start();
  progress.update(5);
  assertEquals(progress.percentage, 50);
  progress.stop();

  // Table rendering
  const table = renderTable(
    [{ name: "Test", value: 123 }],
    {
      columns: [
        { key: "name", header: "Name" },
        { key: "value", header: "Value", alignment: "right" },
      ],
      capabilities: caps,
    },
  );
  assertEquals(table.includes("Name"), true);
  assertEquals(table.includes("Test"), true);
});

Deno.test("E2E: setup() helper returns ready-to-use instances", () => {
  const { capabilities } = setup();

  // Verify capabilities are valid
  assertEquals(typeof capabilities.isTTY, "boolean");
  assertEquals(typeof capabilities.colorSupport, "number");
  assertEquals(typeof capabilities.supportsUnicode, "boolean");
  assertEquals(typeof capabilities.width, "number");
  assertEquals(typeof capabilities.height, "number");

  // Verify we can use capabilities immediately
  const fmt = new OutputFormatter(capabilities);
  const result = fmt.success("Ready!");
  assertEquals(result.includes("Ready!"), true);
});

Deno.test("E2E: Non-TTY context produces plain output", () => {
  const fmt = new OutputFormatter({
    isTTY: false,
    colorSupport: 0,
    supportsUnicode: false,
    width: 80,
    height: 24,
  });

  const success = fmt.success("Test");
  const error = fmt.error("Test");

  // Verify no ANSI escape codes
  assertEquals(success.includes("\x1b"), false);
  assertEquals(error.includes("\x1b"), false);

  // Verify ASCII symbols used
  assertEquals(success.includes("[OK]"), true);
  assertEquals(error.includes("[X]"), true);
});

Deno.test("E2E: Table adapts to narrow terminal", () => {
  const data = [
    {
      id: 1,
      name: "Alice",
      email: "alice@example.com",
      role: "Admin",
      status: "Active",
    },
    {
      id: 2,
      name: "Bob",
      email: "bob@example.com",
      role: "User",
      status: "Inactive",
    },
  ];

  const columns = [
    { key: "id", header: "ID", priority: 1 },
    { key: "name", header: "Name", priority: 1 },
    { key: "email", header: "Email", priority: 2 },
    { key: "role", header: "Role", priority: 3 },
    { key: "status", header: "Status", priority: 4 },
  ];

  // Wide terminal - all columns
  const wideTable = renderTable(data, {
    columns,
    capabilities: {
      isTTY: true,
      colorSupport: 16,
      supportsUnicode: true,
      width: 120,
      height: 24,
    },
  });

  // Narrow terminal - only high-priority columns
  const narrowTable = renderTable(data, {
    columns,
    capabilities: {
      isTTY: true,
      colorSupport: 16,
      supportsUnicode: true,
      width: 40,
      height: 24,
    },
  });

  // Wide table should have more content
  assertEquals(wideTable.length > narrowTable.length, true);

  // Both should include ID and Name (priority 1)
  assertEquals(narrowTable.includes("ID"), true);
  assertEquals(narrowTable.includes("Name"), true);
});

Deno.test("E2E: Progress indicators respect showAfter threshold", async () => {
  const progress = new ProgressBar({
    message: "Test",
    total: 100,
    showAfter: 3000, // 3 second delay
  });

  progress.start();

  // Should not be visible immediately
  assertEquals(progress.isVisible, false);

  // Should be visible after delay
  await new Promise((r) => setTimeout(r, 3100));
  assertEquals(progress.isVisible, true);

  progress.stop();
});
