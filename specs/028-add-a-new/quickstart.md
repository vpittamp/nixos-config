# Quickstart Guide: Enhanced CLI User Experience

**Feature**: Enhanced CLI User Experience with Real-Time Feedback
**Branch**: `028-add-a-new`
**Date**: 2025-10-22

## Overview

This guide shows how to use the CLI UX enhancement library to add progress indicators, semantic colors, interactive prompts, tables, and event streaming to your Deno CLI tools.

---

## Installation

### As a Library Module

```typescript
// Import from local module
import {
  OutputFormatter,
  ProgressBar,
  promptSelect,
  renderTable,
} from "@/specs/028-add-a-new/src/mod.ts";
```

### In Existing CLI Tools

Update existing commands to import the library:

```typescript
// home-modules/tools/i3pm/src/commands/windows.ts
import { OutputFormatter, renderTable } from "@cli-ux";
```

---

## Quick Examples

### 1. Basic Output Formatting

```typescript
import { OutputFormatter } from "@cli-ux";

const fmt = new OutputFormatter();

// Semantic messages with colors and symbols
console.log(fmt.success("Build completed!"));
console.log(fmt.error("Connection failed"));
console.log(fmt.warning("Deprecated API usage"));
console.log(fmt.info("Processing 10 files..."));

// Emphasis
console.log(fmt.bold("Important:") + " Please read this carefully");
console.log(fmt.dim("(Optional detail in parentheses)"));
```

**Output** (in color-enabled terminal):
```
✓ Build completed!
✗ Connection failed
⚠ Deprecated API usage
ℹ Processing 10 files...
Important: Please read this carefully
(Optional detail in parentheses)
```

---

### 2. Progress Bars

```typescript
import { ProgressBar } from "@cli-ux";

const progress = new ProgressBar({
  message: "Downloading file",
  total: 100,
});

progress.start();

for (let i = 0; i <= 100; i++) {
  progress.update(i);
  await new Promise((r) => setTimeout(r, 50)); // Simulate work
}

progress.finish("✓ Download complete");
```

**Output**:
```
[00:00:05] [████████████████████████████████] [100/100 MB]
✓ Download complete
```

---

### 3. Spinners for Unknown Duration

```typescript
import { Spinner } from "@cli-ux";

const spinner = new Spinner({
  message: "Connecting to server...",
});

spinner.start();

// ... do async work ...
await connectToServer();

spinner.finish("✓ Connected successfully");
```

**Output** (animated):
```
⠋ Connecting to server...
⠙ Connecting to server...
⠹ Connecting to server...
✓ Connected successfully
```

---

### 4. Interactive Selection Menus

```typescript
import { promptSelect } from "@cli-ux";

const project = await promptSelect({
  message: "Select project:",
  options: [
    { value: "nixos", label: "🔧 NixOS Configuration", description: "/etc/nixos" },
    { value: "stacks", label: "📦 Stacks Project", description: "~/projects/stacks" },
    { value: "personal", label: "🏠 Personal", description: "~/personal" },
  ],
});

console.log(`Selected: ${project}`);
```

**Output** (interactive):
```
? Select project: (Use arrow keys)
❯ 🔧 NixOS Configuration
  📦 Stacks Project
  🏠 Personal
```

---

### 5. Table Rendering

```typescript
import { renderTable } from "@cli-ux";

const data = [
  { id: 1, name: "Alice", age: 30, city: "New York" },
  { id: 2, name: "Bob", age: 25, city: "San Francisco" },
  { id: 3, name: "Charlie", age: 35, city: "Chicago" },
];

const table = renderTable(data, {
  columns: [
    { key: "id", header: "ID", alignment: "right", priority: 1 },
    { key: "name", header: "Name", alignment: "left", priority: 1 },
    { key: "age", header: "Age", alignment: "right", priority: 2 },
    { key: "city", header: "City", alignment: "left", priority: 3 },
  ],
});

console.log(table);
```

**Output**:
```
 ID │ Name    │ Age │ City
  1 │ Alice   │  30 │ New York
  2 │ Bob     │  25 │ San Francisco
  3 │ Charlie │  35 │ Chicago
```

---

### 6. Event Streaming

```typescript
import { streamEventsLive } from "@cli-ux";

async function* eventSource() {
  for (let i = 0; i < 100; i++) {
    yield {
      timestamp: Date.now(),
      type: "window",
      payload: { action: "focus", id: i },
    };
    await new Promise((r) => setTimeout(r, 100));
  }
}

await streamEventsLive(eventSource(), {
  formatter: (event) => `Window ${event.payload.id} focused`,
  filter: (event) => event.payload.id % 5 === 0, // Only every 5th event
});
```

**Output** (live streaming):
```
[12:34:56] Window 0 focused
[12:34:57] Window 5 focused
[12:34:58] Window 10 focused
...
```

---

## Common Patterns

### Pattern 1: Wrap Long Operations with Progress

```typescript
import { withProgress } from "@cli-ux";

const result = await withProgress(
  async (progress) => {
    // Long-running operation
    const data = await fetchData();

    // Update progress mid-operation
    if (progress instanceof ProgressBar) {
      progress.update(50);
    }

    return processData(data);
  },
  {
    message: "Processing data",
    total: 100,
  },
);
```

### Pattern 2: Conditional Color Output

```typescript
import { OutputFormatter, detectTerminalCapabilities } from "@cli-ux";

const caps = detectTerminalCapabilities();
const fmt = new OutputFormatter(caps);

// Colors automatically disabled if not a TTY or NO_COLOR is set
console.log(fmt.success("This works in pipes too!"));

// Output when piped: [OK] This works in pipes too! (no ANSI codes)
```

### Pattern 3: Responsive Table Layouts

```typescript
import { TableRenderer, onTerminalResize } from "@cli-ux";

const renderer = new TableRenderer({
  columns: [
    { key: "name", header: "Name", priority: 1 },
    { key: "status", header: "Status", priority: 1 },
    { key: "workspace", header: "WS", priority: 2 },
    { key: "output", header: "Output", priority: 3 },
  ],
});

// Re-render on terminal resize
const cleanup = onTerminalResize(({ columns }) => {
  renderer.updateLayout(columns);
  console.clear();
  console.log(renderer.render(data));
});

// Initial render
console.log(renderer.render(data));
```

### Pattern 4: Multi-Step Operations with Progress Updates

```typescript
import { ProgressBar } from "@cli-ux";

const progress = new ProgressBar({
  message: "Building project",
  total: 5,
});

progress.start();

progress.message = "Step 1/5: Installing dependencies";
progress.update(1);
await installDependencies();

progress.message = "Step 2/5: Compiling TypeScript";
progress.update(2);
await compileTypeScript();

progress.message = "Step 3/5: Running tests";
progress.update(3);
await runTests();

progress.message = "Step 4/5: Building production bundle";
progress.update(4);
await buildBundle();

progress.message = "Step 5/5: Generating documentation";
progress.update(5);
await generateDocs();

progress.finish("✓ Build complete!");
```

### Pattern 5: Input Validation with Prompts

```typescript
import { promptInput } from "@cli-ux";

const projectName = await promptInput({
  message: "Enter project name:",
  validate: (input) => {
    if (!input) return "Name cannot be empty";
    if (!/^[a-z0-9-]+$/.test(input)) {
      return "Use only lowercase letters, numbers, and hyphens";
    }
    if (input.length > 50) return "Name too long (max 50 characters)";
    return null; // Valid
  },
});

console.log(`Creating project: ${projectName}`);
```

---

## Integration with Existing Tools

### Enhancing `i3pm windows` Command

**Before** (plain text):
```typescript
// home-modules/tools/i3pm/src/commands/windows.ts
export async function windowsCommand(args: Args) {
  const windows = await getWindows();
  windows.forEach(w => console.log(`${w.id}: ${w.title}`));
}
```

**After** (with table and colors):
```typescript
import { renderTable, OutputFormatter } from "@cli-ux";

export async function windowsCommand(args: Args) {
  const fmt = new OutputFormatter();
  const windows = await getWindows();

  if (args.tree) {
    // Tree view (existing implementation)
  } else {
    // Enhanced table view
    const table = renderTable(windows, {
      columns: [
        { key: "id", header: "ID", alignment: "right", priority: 1 },
        { key: "class", header: "Class", priority: 1 },
        { key: "title", header: "Title", priority: 2, maxWidth: 40 },
        { key: "workspace", header: "WS", alignment: "center", priority: 3 },
      ],
      sortBy: args.sort,
    });

    console.log(table);
    console.log(fmt.dim(`\nTotal: ${windows.length} windows`));
  }
}
```

### Adding Progress to `i3-project-switch`

```typescript
import { Spinner } from "@cli-ux";

export async function switchProject(name: string) {
  const spinner = new Spinner({
    message: `Switching to ${name}...`,
  });

  spinner.start();

  await markCurrentProjectWindows();
  spinner.updateMessage("Hiding current project windows...");

  await sendTickEvent(name);
  spinner.updateMessage("Updating workspace labels...");

  await waitForDaemonProcessing();

  spinner.finish(`✓ Switched to ${name}`);
}
```

---

## Testing

### Unit Tests

```typescript
import { assertEquals } from "@std/assert";
import { OutputFormatter, detectTerminalCapabilities } from "@cli-ux";

Deno.test("OutputFormatter strips ANSI in non-TTY", () => {
  // Mock non-TTY environment
  const caps = {
    isTTY: false,
    colorSupport: ColorLevel.None,
    supportsUnicode: false,
    width: 80,
    height: 24,
  };

  const fmt = new OutputFormatter(caps);
  const result = fmt.success("Test");

  // Should have no ANSI codes
  assertEquals(result.includes("\x1b"), false);
});
```

### Visual Tests (Golden Files)

```typescript
import { renderTable } from "@cli-ux";

Deno.test("renderTable matches golden output", async () => {
  const data = [
    { name: "Alice", age: 30 },
    { name: "Bob", age: 25 },
  ];

  const result = renderTable(data, {
    columns: [
      { key: "name", header: "Name" },
      { key: "age", header: "Age", alignment: "right" },
    ],
  });

  const expected = await Deno.readTextFile(
    "./test-fixtures/table-golden.txt",
  );

  assertEquals(result, expected);
});
```

---

## Performance Considerations

### Progress Update Rate

```typescript
// Don't update too frequently - wastes CPU
// ❌ Bad: 60 FPS is overkill for terminal
const progress = new ProgressBar({ total: 100, updateInterval: 16 });

// ✅ Good: 2-4 Hz is sufficient
const progress = new ProgressBar({ total: 100, updateInterval: 250 });
```

### Event Buffering

```typescript
// Buffer rapid events to prevent terminal flooding
import { EventStream } from "@cli-ux";

const stream = new EventStream({
  bufferSize: 500,
  flushInterval: 100, // <100ms perceived latency
  aggregate: true,    // Combine duplicates
});

stream.on("flush", (events) => {
  // Process batched events
  console.log(`Processing ${events.length} events`);
});
```

---

## Troubleshooting

### Colors Not Showing

```bash
# Check terminal capabilities
deno run --allow-env debug-terminal.ts

# Force color output
FORCE_COLOR=1 i3pm windows

# Disable colors explicitly
NO_COLOR=1 i3pm windows
# or
i3pm windows --no-color
```

### Interactive Prompts Failing

```typescript
import { canPrompt } from "@cli-ux";

if (!canPrompt()) {
  console.error("Error: Interactive prompts require a TTY");
  console.error("Hint: Use --project=<name> flag instead");
  Deno.exit(1);
}

const project = await promptSelect({ /* ... */ });
```

### Table Not Fitting in Terminal

```typescript
// Tables automatically adapt to terminal width
// Columns hidden based on priority (higher = hide first)

const table = renderTable(data, {
  columns: [
    { key: "id", header: "ID", priority: 1 },       // Always visible
    { key: "name", header: "Name", priority: 1 },   // Always visible
    { key: "status", header: "Status", priority: 2 }, // Hide if < 80 cols
    { key: "details", header: "Details", priority: 3 }, // Hide if < 100 cols
  ],
});

// For very narrow terminals (< 40 cols), use list format instead
if (Deno.consoleSize().columns < 40) {
  data.forEach(item => console.log(`${item.id}: ${item.name}`));
} else {
  console.log(table);
}
```

---

## CLI Flags Reference

### Standard Flags (Recommended for All Commands)

| Flag | Description | Default |
|------|-------------|---------|
| `--no-color` | Disable colored output | Enabled if TTY |
| `--no-unicode` | Use ASCII symbols instead of Unicode | Auto-detect |
| `--format=<type>` | Output format: `table`, `json`, `plain` | `table` |
| `--sort=<column>` | Sort table by column | None |
| `--sort-dir=<asc\|desc>` | Sort direction | `asc` |

### Example Command with All Flags

```bash
# Compact output for narrow terminal
i3pm windows --format=plain --no-unicode --sort=name

# Machine-readable output for scripts
i3pm windows --format=json --no-color > windows.json

# Full-featured interactive output
i3pm windows --format=table --sort=workspace --sort-dir=desc
```

---

## Migration Checklist

When updating an existing CLI command to use the new library:

- [ ] Replace plain `console.log()` with `OutputFormatter` methods
- [ ] Add progress indicators for operations >3 seconds
- [ ] Convert option selection to `promptSelect()` where appropriate
- [ ] Replace manual table formatting with `renderTable()`
- [ ] Add `--no-color` and `--format` flags
- [ ] Update help text to document new features
- [ ] Add unit tests for formatting logic
- [ ] Test in non-TTY environment (pipes/redirects)
- [ ] Test with narrow terminal width (< 80 columns)
- [ ] Update documentation with new output examples

---

## Next Steps

1. **Review contracts**: See `/specs/028-add-a-new/contracts/` for complete API reference
2. **Read research**: See `/specs/028-add-a-new/research.md` for design decisions
3. **Implementation**: Follow `/specs/028-add-a-new/tasks.md` (generated by `/speckit.tasks`)

---

**Last Updated**: 2025-10-22
**Status**: Ready for implementation (Phase 1 complete)
