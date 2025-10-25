import { assertEquals } from "@std/assert";
import { OutputFormatter, ColorLevel } from "../../src/output-formatter.ts";

Deno.test("OutputFormatter strips ANSI in non-TTY", () => {
  const formatter = new OutputFormatter({
    isTTY: false,
    colorSupport: ColorLevel.None,
    supportsUnicode: false,
    width: 80,
    height: 24,
  });

  const result = formatter.success("Test");
  assertEquals(result.includes("\x1b"), false);
  assertEquals(result.includes("[OK]"), true); // ASCII symbol
});

Deno.test("OutputFormatter uses Unicode in capable terminal", () => {
  const formatter = new OutputFormatter({
    isTTY: true,
    colorSupport: ColorLevel.Basic,
    supportsUnicode: true,
    width: 80,
    height: 24,
  });

  const result = formatter.success("Test");
  assertEquals(result.includes("✓"), true); // Unicode symbol
});

Deno.test("OutputFormatter.stripAnsi removes escape codes", () => {
  const formatter = new OutputFormatter();
  const colored = "\x1b[91mError\x1b[0m";
  const plain = formatter.stripAnsi(colored);
  assertEquals(plain, "Error");
});

Deno.test("OutputFormatter.error formats correctly", () => {
  const formatter = new OutputFormatter({
    isTTY: true,
    colorSupport: ColorLevel.Basic,
    supportsUnicode: true,
    width: 80,
    height: 24,
  });

  const result = formatter.error("Test error");
  assertEquals(result.includes("✗"), true);
  assertEquals(result.includes("Test error"), true);
  assertEquals(result.includes("\x1b[91m"), true); // Bright red
});

Deno.test("OutputFormatter.warning formats correctly", () => {
  const formatter = new OutputFormatter({
    isTTY: true,
    colorSupport: ColorLevel.Basic,
    supportsUnicode: true,
    width: 80,
    height: 24,
  });

  const result = formatter.warning("Test warning");
  assertEquals(result.includes("⚠"), true);
  assertEquals(result.includes("Test warning"), true);
  assertEquals(result.includes("\x1b[93m"), true); // Bright yellow
});

Deno.test("OutputFormatter.info formats correctly", () => {
  const formatter = new OutputFormatter({
    isTTY: true,
    colorSupport: ColorLevel.Basic,
    supportsUnicode: true,
    width: 80,
    height: 24,
  });

  const result = formatter.info("Test info");
  assertEquals(result.includes("ℹ"), true);
  assertEquals(result.includes("Test info"), true);
  assertEquals(result.includes("\x1b[37m"), true); // Gray
});

Deno.test("OutputFormatter.dim formats correctly", () => {
  const formatter = new OutputFormatter({
    isTTY: true,
    colorSupport: ColorLevel.Basic,
    supportsUnicode: true,
    width: 80,
    height: 24,
  });

  const result = formatter.dim("Dimmed text");
  assertEquals(result.includes("\x1b[2m"), true); // Dim code
  assertEquals(result.includes("Dimmed text"), true);
});

Deno.test("OutputFormatter.bold formats correctly", () => {
  const formatter = new OutputFormatter({
    isTTY: true,
    colorSupport: ColorLevel.Basic,
    supportsUnicode: true,
    width: 80,
    height: 24,
  });

  const result = formatter.bold("Bold text");
  assertEquals(result.includes("\x1b[1m"), true); // Bold code
  assertEquals(result.includes("Bold text"), true);
});

Deno.test("OutputFormatter uses ASCII symbols in limited terminal", () => {
  const formatter = new OutputFormatter({
    isTTY: true,
    colorSupport: ColorLevel.Basic,
    supportsUnicode: false,
    width: 80,
    height: 24,
  });

  const success = formatter.success("Test");
  const error = formatter.error("Test");
  const warning = formatter.warning("Test");
  const info = formatter.info("Test");

  assertEquals(success.includes("[OK]"), true);
  assertEquals(error.includes("[X]"), true);
  assertEquals(warning.includes("[!]"), true);
  assertEquals(info.includes("[i]"), true);
});
