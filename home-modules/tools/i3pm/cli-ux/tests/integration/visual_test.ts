import { assertEquals } from "@std/assert";
import { renderTable } from "../../src/table-renderer.ts";
import { OutputFormatter, ColorLevel } from "../../src/output-formatter.ts";

Deno.test("Table output matches golden file", async () => {
  const data = [
    { name: "Alice", age: 30, city: "New York" },
    { name: "Bob", age: 25, city: "San Francisco" },
  ];

  const result = renderTable(data, {
    columns: [
      { key: "name", header: "Name" },
      { key: "age", header: "Age", alignment: "right" },
      { key: "city", header: "City" },
    ],
    capabilities: {
      isTTY: false, // No colors for golden file
      colorSupport: ColorLevel.None,
      supportsUnicode: false,
      width: 80,
      height: 24,
    },
  });

  const expected = await Deno.readTextFile(
    "tests/fixtures/table-golden.txt",
  );

  assertEquals(result, expected.trim());
});

Deno.test("OutputFormatter produces consistent formatting", () => {
  const formatter = new OutputFormatter({
    isTTY: true,
    colorSupport: ColorLevel.Basic,
    supportsUnicode: true,
    width: 80,
    height: 24,
  });

  // Test all semantic message types
  const error = formatter.error("Test error");
  const warning = formatter.warning("Test warning");
  const success = formatter.success("Test success");
  const info = formatter.info("Test info");

  // Verify Unicode symbols are used
  assertEquals(error.includes("✗"), true);
  assertEquals(warning.includes("⚠"), true);
  assertEquals(success.includes("✓"), true);
  assertEquals(info.includes("ℹ"), true);

  // Verify ANSI codes are present
  assertEquals(error.includes("\x1b["), true);
  assertEquals(warning.includes("\x1b["), true);
  assertEquals(success.includes("\x1b["), true);
  assertEquals(info.includes("\x1b["), true);
});

Deno.test("OutputFormatter degrades to ASCII gracefully", () => {
  const formatter = new OutputFormatter({
    isTTY: true,
    colorSupport: ColorLevel.Basic,
    supportsUnicode: false, // ASCII mode
    width: 80,
    height: 24,
  });

  const error = formatter.error("Test error");
  const warning = formatter.warning("Test warning");
  const success = formatter.success("Test success");
  const info = formatter.info("Test info");

  // Verify ASCII symbols are used
  assertEquals(error.includes("[X]"), true);
  assertEquals(warning.includes("[!]"), true);
  assertEquals(success.includes("[OK]"), true);
  assertEquals(info.includes("[i]"), true);
});
