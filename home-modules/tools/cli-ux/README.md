# CLI UX Enhancement Library

Modern CLI user experience patterns for Deno applications including progress indicators, semantic color coding, interactive prompts, table rendering, and event streaming.

## Features

- **Progress Indicators**: Progress bars and spinners for long-running operations
- **Semantic Colors**: WCAG AA compliant color coding (error/warning/success/info)
- **Interactive Prompts**: Selection menus with fuzzy filtering
- **Event Streaming**: Real-time event display with buffering
- **Table Rendering**: Smart column alignment with terminal width adaptation
- **Unicode Support**: Automatic fallback to ASCII for limited terminals

## Installation

This library is part of the NixOS home-modules configuration. It will be automatically available when the cli-ux module is imported.

## Quick Start

```typescript
import { setup } from "@cli-ux";

// Easy setup with automatic terminal detection
const { capabilities, formatter } = setup();

console.log(formatter.success("Build completed!"));
console.log(formatter.error("Connection failed"));
```

## Examples

### User Story 1: Live Progress Feedback

```typescript
import { ProgressBar, Spinner, withProgress } from "@cli-ux";

// Progress bar for known-duration operations
const progress = new ProgressBar({
  message: "Downloading file",
  total: 100,
  showAfter: 3000, // Only show if takes >3 seconds
});
progress.start();

for (let i = 0; i <= 100; i++) {
  progress.update(i);
  if (i === 25) progress.message = "Quarter done...";
  if (i === 50) progress.message = "Halfway there...";
  if (i === 75) progress.message = "Almost done...";
  await new Promise(r => setTimeout(r, 100));
}

progress.finish("Download complete!");

// Spinner for unknown-duration operations
const spinner = new Spinner({ message: "Connecting to server..." });
spinner.start();
await someAsyncOperation();
spinner.finish("Connected!");

// Wrapper function
await withProgress(
  async (progress) => {
    for (let i = 0; i <= 100; i++) {
      progress.update(i);
      await doWork(i);
    }
  },
  { message: "Processing", total: 100 }
);
```

### User Story 2: Color-Coded Output

```typescript
import { OutputFormatter } from "@cli-ux";

const fmt = new OutputFormatter();

// Semantic messages
console.log(fmt.error("Build failed!"));
console.log(fmt.warning("Deprecated API used"));
console.log(fmt.success("Tests passed"));
console.log(fmt.info("Processing 50 items"));

// Text formatting
console.log(fmt.bold("Important:"), "Please read carefully");
console.log(fmt.dim("Optional step..."));

// Strip ANSI codes for logging
const message = fmt.success("Done");
const plain = fmt.stripAnsi(message); // "✓ Done" without colors
```

### User Story 3: Interactive Selection

```typescript
import { promptSelect, promptConfirm, promptInput } from "@cli-ux";

// Single selection
const project = await promptSelect({
  message: "Which project?",
  options: [
    { value: "nixos", label: "NixOS Config" },
    { value: "stacks", label: "Stacks Platform" },
    { value: "personal", label: "Personal Projects" },
  ],
  default: "nixos",
});

// Confirmation
const confirmed = await promptConfirm({
  message: "Delete all files?",
  default: false,
});

// Text input with validation
const name = await promptInput({
  message: "Enter your name",
  validate: (value) => {
    if (value.length < 2) return "Name too short";
    return null;
  },
});
```

### User Story 4: Live Streaming Output

```typescript
import { EventStream, streamEventsLive } from "@cli-ux";

// Event buffering with aggregation
const stream = new EventStream({
  bufferSize: 500,
  flushInterval: 100, // Flush every 100ms
  aggregate: true,     // Combine duplicates
});

stream.on("flush", (events) => {
  events.forEach(event => {
    console.log(`[${event.type}] ${event.payload}`);
  });
});

stream.push({ timestamp: Date.now(), type: "log", payload: "Started" });
stream.push({ timestamp: Date.now(), type: "log", payload: "Processing" });

// Live streaming from async source
async function* generateEvents() {
  for (let i = 0; i < 10; i++) {
    yield { timestamp: Date.now(), type: "tick", payload: i };
    await new Promise(r => setTimeout(r, 100));
  }
}

await streamEventsLive(generateEvents(), {
  filter: (event) => event.payload > 5,
});
```

### User Story 5: Structured Tables

```typescript
import { renderTable, TableRenderer } from "@cli-ux";

const data = [
  { id: 1, name: "Alice", role: "Admin", status: "Active" },
  { id: 2, name: "Bob", role: "User", status: "Inactive" },
];

// Simple rendering
const table = renderTable(data, {
  columns: [
    { key: "id", header: "ID", alignment: "right", priority: 1 },
    { key: "name", header: "Name", priority: 1 },
    { key: "role", header: "Role", priority: 2 },
    { key: "status", header: "Status", priority: 3 },
  ],
  sortBy: "name",
  sortDirection: "asc",
});

console.log(table);

// Reusable renderer
const renderer = new TableRenderer({
  columns: [
    { key: "name", header: "Name" },
    { key: "value", header: "Value", formatter: (v) => `$${v}` },
  ],
});

console.log(renderer.render(data1));
console.log(renderer.render(data2));
```

### User Story 6: Unicode Support

The library automatically detects Unicode capabilities:

```typescript
import { OutputFormatter, detectTerminalCapabilities } from "@cli-ux";

const caps = detectTerminalCapabilities();
console.log("Unicode supported:", caps.supportsUnicode);

// Force specific mode
const unicodeFmt = new OutputFormatter({ supportsUnicode: true });
const asciiFmt = new OutputFormatter({ supportsUnicode: false });

console.log(unicodeFmt.success("Done")); // "✓ Done"
console.log(asciiFmt.success("Done"));   // "[OK] Done"
```

## API Reference

See [contracts/](../../specs/028-add-a-new/contracts/) for complete TypeScript interface definitions.

## Testing

```bash
# Run all tests
deno task test

# Type check
deno task check

# Format code
deno task fmt

# Lint code
deno task lint
```

## Architecture

The library is organized into focused modules:

- `terminal-capabilities.ts` - Terminal detection (TTY, colors, Unicode, dimensions)
- `output-formatter.ts` - Semantic color coding and symbols
- `progress-indicator.ts` - Progress bars and spinners
- `interactive-prompts.ts` - Selection menus and user input
- `table-renderer.ts` - Table formatting and layout
- `event-stream.ts` - Real-time event streaming

## Unicode Symbol Support

The library automatically detects terminal Unicode capabilities and provides graceful fallbacks:

**Unicode-capable terminals** (most modern terminals):
- Success: ✓
- Error: ✗
- Warning: ⚠
- Info: ℹ
- Progress bar: █░
- Spinner: ⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏

**ASCII fallback** (limited terminals):
- Success: [OK]
- Error: [X]
- Warning: [!]
- Info: [i]
- Progress bar: #-
- Spinner: |/-\

Detection is automatic based on:
- `LANG` environment variable (checks for UTF-8)
- `TERM` environment variable (linux console = ASCII)
- TTY status (non-TTY = ASCII)

Force Unicode mode:
```typescript
const formatter = new OutputFormatter({
  supportsUnicode: true,
  // ... other capabilities
});
```

## Performance

- Progress indicators: ≥2 Hz update rate (500ms intervals)
- Selection filtering: <50ms response time
- Event streaming: <100ms latency from event to display
- Color output: WCAG AA contrast (4.5:1 minimum)

## Contributing

This library follows the NixOS modular configuration standards:

1. All code must be TypeScript with strict type checking
2. Use Deno standard library (@std/cli) for terminal operations
3. Maintain WCAG AA color contrast requirements
4. Include unit tests for all public APIs
5. Follow Constitution XIII: Deno CLI Development Standards

## License

MIT
