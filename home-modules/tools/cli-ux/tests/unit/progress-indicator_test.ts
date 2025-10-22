import { assertEquals } from "@std/assert";
import { ProgressBar, Spinner } from "../../src/progress-indicator.ts";

Deno.test("ProgressBar shows after showAfter delay", async () => {
  const progress = new ProgressBar({
    message: "Test",
    total: 100,
    showAfter: 100, // 100ms for faster testing
  });

  progress.start();
  assertEquals(progress.isVisible, false);

  await new Promise((r) => setTimeout(r, 150));
  assertEquals(progress.isVisible, true);

  progress.stop();
});

Deno.test("ProgressBar calculates percentage correctly", () => {
  const progress = new ProgressBar({
    message: "Test",
    total: 100,
  });

  progress.update(50);
  assertEquals(progress.percentage, 50);

  progress.update(75);
  assertEquals(progress.percentage, 75);
});

Deno.test("ProgressBar increments correctly", () => {
  const progress = new ProgressBar({
    message: "Test",
    total: 100,
  });

  progress.increment();
  assertEquals(progress.current, 1);

  progress.increment(5);
  assertEquals(progress.current, 6);
});

Deno.test("Spinner animates frames", async () => {
  const spinner = new Spinner({
    message: "Loading",
    showAfter: 0, // Show immediately for testing
    updateInterval: 50,
  });

  spinner.start();
  await new Promise((r) => setTimeout(r, 200));
  spinner.stop();

  // Test passed if no errors thrown
});

Deno.test("Spinner updates message", () => {
  const spinner = new Spinner({
    message: "Initial",
  });

  assertEquals(spinner.message, "Initial");

  spinner.updateMessage("Updated");
  assertEquals(spinner.message, "Updated");
});
