/**
 * Demo script to showcase the MVP (User Story 1: Live Progress Feedback)
 *
 * Run with: deno run --allow-env demo.ts
 */

import { ProgressBar, Spinner, detectTerminalCapabilities } from "./mod.ts";

console.log("=== CLI-UX MVP Demo ===\n");

// Show terminal capabilities
const caps = detectTerminalCapabilities();
console.log("Terminal Capabilities:");
console.log(`  TTY: ${caps.isTTY}`);
console.log(`  Color Support: ${caps.colorSupport} (${caps.colorSupport === 16 ? "Basic" : caps.colorSupport === 256 ? "256-color" : "None"})`);
console.log(`  Unicode: ${caps.supportsUnicode}`);
console.log(`  Size: ${caps.width}x${caps.height}`);
console.log();

// Demo 1: Progress Bar
console.log("Demo 1: Progress Bar (10-second operation)");
const progress = new ProgressBar({
  message: "Processing files",
  total: 100,
  showAfter: 1000, // Show after 1 second for demo
});

progress.start();

for (let i = 0; i <= 100; i++) {
  await new Promise((r) => setTimeout(r, 100)); // 100ms per step = 10 seconds total
  progress.update(i);

  // Update message at milestones
  if (i === 25) progress.message = "Processing files (25% complete)";
  if (i === 50) progress.message = "Processing files (halfway there)";
  if (i === 75) progress.message = "Processing files (almost done)";
}

progress.finish("✅ Processing complete!");
console.log();

// Demo 2: Spinner
console.log("Demo 2: Spinner (5-second operation)");
const spinner = new Spinner({
  message: "Connecting to server...",
  showAfter: 1000,
});

spinner.start();

await new Promise((r) => setTimeout(r, 2000));
spinner.updateMessage("Authenticating...");

await new Promise((r) => setTimeout(r, 2000));
spinner.updateMessage("Loading data...");

await new Promise((r) => setTimeout(r, 1000));
spinner.finish("✅ Connected successfully!");
console.log();

console.log("=== MVP Demo Complete ===");
console.log("\nMVP Features Demonstrated:");
console.log("  ✓ Terminal capability detection");
console.log("  ✓ Progress bar for known-duration operations");
console.log("  ✓ Spinner for unknown-duration operations");
console.log("  ✓ Auto-hide for operations <3 seconds");
console.log("  ✓ Smooth updates at ≥2 Hz (500ms intervals)");
