# Deno/TypeScript TUI Library Research
## For i3 Workspace-to-Monitor Management CLI Tool

**Date**: 2025-10-23
**Context**: Building interactive TUI for `i3pm monitors` CLI tool with live-updating tables, event streaming, and keyboard-driven operations.

---

## Executive Summary

**Recommended Approach**: **deno_tui** with ANSI escape code fallbacks

**Rationale**:
- Full-featured TUI framework purpose-built for Deno
- Real-time updates via reactive signals (<100ms latency requirement)
- Rich component library (tables, frames, input handling)
- 60 FPS rendering capability with low overhead
- Active maintenance (41 releases, 737 commits)
- Zero dependencies, cross-platform support

**Alternative for Simple Cases**: Raw ANSI escape codes via `Deno.stdin.setRaw()` for minimal overhead when full TUI framework is overkill.

---

## 1. Library Comparison

### Top 3 Deno-Compatible TUI Libraries

| Feature | deno_tui | Cliffy | Raw ANSI + Deno Std |
|---------|----------|--------|---------------------|
| **Package** | `https://deno.land/x/tui` | `https://deno.land/x/cliffy` | `Deno.stdin` + escape codes |
| **Primary Purpose** | Full TUI applications | CLI argument parsing + tables | Manual low-level control |
| **Table Support** | ✅ Full Table component | ✅ CLI-Table module | ❌ Manual implementation |
| **Real-time Updates** | ✅ Signal-based reactivity | ⚠️ Manual refresh | ✅ Full control |
| **Keyboard Events** | ✅ Built-in handlers | ⚠️ Prompt-focused | ✅ Raw mode stdin |
| **Mouse Support** | ✅ Full support | ❌ Limited | ❌ Manual parsing |
| **Refresh Rate** | ✅ Configurable (60 FPS tested) | ⚠️ Not applicable | ✅ Unlimited |
| **Event Loop** | ✅ Built-in `tui.run()` | ❌ Not provided | ✅ Custom async loop |
| **Tree View** | ✅ Via nested components | ❌ Not built-in | ❌ Manual |
| **Dependencies** | ✅ Zero | ⚠️ Minimal | ✅ Zero (Deno std) |
| **Terminal Cleanup** | ✅ `tui.dispatch()` | ⚠️ Manual | ✅ Manual |
| **GitHub Stars** | 302 ⭐ | 1,000+ ⭐ | N/A |
| **Active Development** | ✅ Yes (v2.1.11) | ✅ Yes | ✅ Stable Deno API |
| **Learning Curve** | Medium | Low (for CLI) | High |
| **Use Case Fit** | ✅ Excellent | ⚠️ Partial | ⚠️ For simple cases |

### Detailed Analysis

#### 1. deno_tui (RECOMMENDED)

**Import**: `import { Tui, Signal, Computed } from "https://deno.land/x/tui/mod.ts"`

**Key Features**:
- Declarative component-based UI (Box, Text, Frame, Table, Button, etc.)
- Reactive state management via Signals and Computed values
- 60 FPS rendering (`refreshRate: 1000 / 60`)
- Full keyboard and mouse event handling
- Cross-platform (Linux, macOS, Windows, WSL)
- No external dependencies
- MIT licensed

**Performance Characteristics**:
- Built-in FPS monitoring and performance tracking
- Efficient diff-based rendering (only updates changed components)
- Configurable refresh rates for CPU optimization
- Event-driven architecture minimizes polling overhead

**Strengths**:
- Purpose-built for interactive TUI applications
- Rich component ecosystem for tables, inputs, progress bars
- Reactive updates perfect for real-time monitor/workspace status
- Handles terminal state management automatically
- Active community and development

**Limitations**:
- Requires understanding of Signal/Computed reactive patterns
- Larger API surface than raw ANSI approach
- Windows users need UTF-8 console (`chcp 65001`)

**Best For**: Full-featured interactive dashboards with live updates, multiple views, and complex keyboard navigation.

---

#### 2. Cliffy

**Import**: `import { Table } from "https://deno.land/x/cliffy/table/mod.ts"`

**Key Features**:
- Primary focus: CLI argument parsing and command frameworks
- Includes CLI-Table module for static table rendering
- Type-safe command creation with auto-generated help
- Built-in input validation and shell completions
- Interactive prompts (select, confirm, input, etc.)

**Performance Characteristics**:
- Tables are static renders (not live-updating)
- Suitable for one-time output or manual refresh patterns
- Minimal overhead for simple table display

**Strengths**:
- Excellent for traditional CLI tools with table output
- Strong type safety and developer experience
- Well-documented with extensive examples
- Large community adoption (1,000+ stars)

**Limitations**:
- **Not designed for real-time TUI applications**
- Tables are static (no built-in live update mechanism)
- No event loop or reactive state management
- Limited to CLI prompts, not full TUI interfaces

**Best For**: Traditional command-line tools that output tables as results, not live dashboards.

---

#### 3. Raw ANSI Escape Codes + Deno Std

**Approach**: Manual terminal control via `Deno.stdin.setRaw()` and ANSI sequences

**Available Tools**:
```typescript
// Deno built-in APIs
Deno.stdin.setRaw(true);              // Enable raw mode for keyboard
const { columns, rows } = Deno.consoleSize();  // Get terminal dimensions
Deno.stdout.write(new TextEncoder().encode("\x1b[2J"));  // Clear screen

// Deno std library (@std/cli)
import { parseArgs } from "@std/cli/parse-args";
import { promptSecret } from "@std/cli/prompt-secret";
// Note: @std/cli has minimal TUI features (mainly CLI parsing)

// Third-party ANSI libraries for Deno
// deno_ansi: https://github.com/justjavac/deno_ansi
import { cursorLeft, cursorUp } from "https://deno.land/x/ansi/mod.ts";

// cursor module: https://deno.land/x/cursor
import * as cursor from "https://deno.land/x/cursor/mod.ts";
```

**Key ANSI Escape Sequences**:
```typescript
// Cursor control
const ESC = "\x1b";
const clearScreen = `${ESC}[2J`;
const moveCursor = (row: number, col: number) => `${ESC}[${row};${col}H`;
const saveCursor = `${ESC}7`;
const restoreCursor = `${ESC}8`;
const hideCursor = `${ESC}[?25l`;
const showCursor = `${ESC}[?25h`;

// Alternate screen buffer (isolate TUI from scrollback)
const enterAltScreen = `${ESC}[?1049h`;
const exitAltScreen = `${ESC}[?1049l`;

// Colors (256-color mode)
const fg256 = (code: number) => `${ESC}[38;5;${code}m`;
const bg256 = (code: number) => `${ESC}[48;5;${code}m`;
const reset = `${ESC}[0m`;
```

**Performance Characteristics**:
- Zero overhead (direct system calls)
- Full control over every byte written to terminal
- Minimal latency for high-frequency updates
- Efficient when carefully managed (buffer writes)

**Strengths**:
- Maximum performance and control
- No framework overhead or learning curve
- Simple for basic use cases
- Works everywhere (universal ANSI support)

**Limitations**:
- **High implementation cost** for complex UIs
- **Manual state tracking** (what's on screen vs. desired state)
- **No built-in components** (tables, boxes, etc.)
- **Error-prone** (easy to leave terminal in bad state)
- Requires handling terminal resize, cleanup, signal handlers manually

**Best For**: Simple status displays, progress bars, or when absolute minimal footprint is required.

---

## 2. Deno Standard Library for TUI

### @std/cli Analysis

The `@std/cli` package provides **minimal TUI capabilities** and is primarily focused on:

**Available Modules**:
- `parseArgs` - Command-line argument parsing
- `promptSecret` - Secure password/token input with masking
- `Spinner` (unstable) - Loading animations
- `ProgressBar` (unstable) - Progress tracking
- ANSI cursor control (unstable) - Basic terminal manipulation

**Verdict**: **Not suitable for full TUI applications**. Use for CLI argument parsing, combine with deno_tui for TUI features.

### Deno Built-in APIs for TUI

```typescript
// Terminal dimensions (stable)
const { columns, rows } = Deno.consoleSize();

// Raw mode for keyboard input (stable since Deno 1.27)
Deno.stdin.setRaw(true);
const reader = Deno.stdin.readable.getReader();

// Signal handling for terminal resize
Deno.addSignalListener("SIGWINCH", () => {
  const size = Deno.consoleSize();
  console.log(`Terminal resized to ${size.columns}x${size.rows}`);
});

// Reading keyboard input in raw mode
while (true) {
  const { value, done } = await reader.read();
  if (done) break;
  const key = value[0];
  if (key === 3) break;  // Ctrl+C
  if (key === 27) {      // ESC or arrow keys (multi-byte)
    // Parse escape sequences...
  }
}
```

---

## 3. Best Practices for TUI Development

### Real-Time Terminal Updates

**Pattern**: Event subscription → State update → Reactive render

```typescript
// deno_tui approach (RECOMMENDED)
import { Tui, Signal, Table } from "https://deno.land/x/tui/mod.ts";

// Reactive state for monitor/workspace data
const monitors = new Signal([
  { name: "DP-1", workspaces: [1, 2] },
  { name: "HDMI-1", workspaces: [3, 4, 5] }
]);

const tui = new Tui({ refreshRate: 1000 / 10 }); // 10 FPS (sufficient for most UIs)

const table = new Table({
  parent: tui,
  data: new Computed(() =>
    monitors.value.map(m => [m.name, m.workspaces.join(", ")])
  )
});

// Subscribe to i3 events (via i3ipc or external process)
async function subscribeToI3Events() {
  const proc = Deno.run({
    cmd: ["i3-msg", "-t", "subscribe", "-m", '["workspace","output"]'],
    stdout: "piped"
  });

  for await (const line of readLines(proc.stdout)) {
    const event = JSON.parse(line);
    // Update reactive state - UI updates automatically
    monitors.value = parseI3State(event);
  }
}

subscribeToI3Events();
tui.run();
```

**Key Principles**:
1. **Single source of truth**: Reactive signals hold canonical state
2. **Automatic propagation**: Computed values and components update on signal changes
3. **Efficient diffing**: Framework only redraws changed components
4. **Event-driven**: External events trigger state updates, not UI redraws

### Handling Terminal Resize

```typescript
// deno_tui handles this automatically via its render loop

// For manual ANSI approach:
Deno.addSignalListener("SIGWINCH", () => {
  const { columns, rows } = Deno.consoleSize();
  redrawUI(columns, rows);  // Recalculate layout and redraw
});

// Graceful degradation for narrow terminals
if (columns < 80) {
  // Switch to compact layout or warn user
  console.error("Terminal too narrow. Minimum width: 80 columns");
  Deno.exit(1);
}
```

### Clean Shutdown and Terminal Restoration

```typescript
// deno_tui approach
const tui = new Tui({});
handleInput(tui);

// Graceful shutdown on Ctrl+C
tui.on("keyPress", ({ ctrl, key }) => {
  if (ctrl && key === "c") {
    tui.dispatch();  // Cleanup and restore terminal
    Deno.exit(0);
  }
});

tui.run();
```

```typescript
// Manual ANSI approach - ALWAYS restore terminal state
const ESC = "\x1b";
const showCursor = `${ESC}[?25h`;
const exitAltScreen = `${ESC}[?1049l`;
const resetColors = `${ESC}[0m`;

function cleanupTerminal() {
  Deno.stdout.writeSync(new TextEncoder().encode(
    showCursor + exitAltScreen + resetColors
  ));
  Deno.stdin.setRaw(false);
}

// Register cleanup handlers
globalThis.addEventListener("unload", cleanupTerminal);
Deno.addSignalListener("SIGINT", () => {
  cleanupTerminal();
  Deno.exit(0);
});
Deno.addSignalListener("SIGTERM", () => {
  cleanupTerminal();
  Deno.exit(0);
});
```

**Critical Cleanup Steps**:
1. Exit alternate screen buffer (`\x1b[?1049l`)
2. Show cursor (`\x1b[?25h`)
3. Reset colors/formatting (`\x1b[0m`)
4. Disable raw mode (`Deno.stdin.setRaw(false)`)
5. Flush stdout/stderr

### Performance Optimization for High-Frequency Updates

**Problem**: Monitor events may fire multiple times per second. Redrawing entire UI each time causes flickering and CPU waste.

**Solutions**:

#### 1. Rate Limiting (Debouncing)
```typescript
import { debounce } from "https://deno.land/std/async/debounce.ts";

const updateUI = debounce(() => {
  monitors.value = fetchMonitorState();
}, 100);  // Max 10 updates/second

eventStream.on("output", updateUI);
```

#### 2. Diff-Based Rendering (deno_tui built-in)
```typescript
// deno_tui automatically compares previous and current state
// Only changed components are redrawn
const table = new Table({
  data: new Computed(() => monitors.value.map(formatRow))
  // Framework handles diffing
});
```

#### 3. Double Buffering (Manual ANSI)
```typescript
let previousState = "";
function render(state: string) {
  if (state === previousState) return;  // Skip if unchanged

  const diff = computeDiff(previousState, state);
  for (const change of diff) {
    Deno.stdout.writeSync(new TextEncoder().encode(
      moveCursor(change.row, change.col) + change.text
    ));
  }
  previousState = state;
}
```

#### 4. Buffered Writes
```typescript
// BAD: Multiple small writes (slow syscalls)
Deno.stdout.writeSync(encodeText(moveCursor(1, 1)));
Deno.stdout.writeSync(encodeText("Hello"));
Deno.stdout.writeSync(encodeText(moveCursor(2, 1)));
Deno.stdout.writeSync(encodeText("World"));

// GOOD: Single buffered write
const buffer = [
  moveCursor(1, 1), "Hello",
  moveCursor(2, 1), "World"
].join("");
Deno.stdout.writeSync(encodeText(buffer));
```

#### 5. Selective Refresh
```typescript
// Only update changed sections
const sections = {
  header: new Signal(""),
  table: new Signal([]),
  footer: new Signal("")
};

// Only header changed - table doesn't redraw
sections.header.value = "New Title";
```

**Performance Targets**:
- **Latency**: <100ms from event to UI update ✅
- **CPU**: <5% idle, <20% during updates ✅
- **Refresh rate**: 10-60 FPS depending on use case ✅
- **Memory**: <50MB for typical TUI ✅

---

## 4. Code Examples

### Example 1: Basic Table with deno_tui

```typescript
import { Tui, Table, Signal, Computed, handleInput } from "https://deno.land/x/tui/mod.ts";
import { crayon } from "https://deno.land/x/crayon/mod.ts";

// Reactive state for monitors
const monitors = new Signal([
  { name: "DP-1", primary: true, workspaces: [1, 2] },
  { name: "HDMI-1", primary: false, workspaces: [3, 4, 5] }
]);

// Create TUI instance
const tui = new Tui({
  style: crayon.bgBlack,
  refreshRate: 1000 / 60  // 60 FPS
});

// Create table with reactive data
const table = new Table({
  parent: tui,
  theme: {
    base: crayon.bgBlack.white,
    header: { base: crayon.bgBlack.bold.lightBlue },
    selectedRow: { base: crayon.bold.bgBlue.white }
  },
  rectangle: { column: 2, row: 2, height: 10, width: 50 },
  headers: [
    { title: "Output" },
    { title: "Primary" },
    { title: "Workspaces" }
  ],
  data: new Computed(() =>
    monitors.value.map(m => [
      m.name,
      m.primary ? "✓" : "",
      m.workspaces.join(", ")
    ])
  ),
  charMap: "rounded"
});

// Handle keyboard input
handleInput(tui);

// Graceful shutdown
tui.on("keyPress", ({ ctrl, key }) => {
  if (ctrl && key === "c") {
    tui.dispatch();
    Deno.exit(0);
  }
});

// Start event loop
tui.run();
```

### Example 2: Live-Updating Dashboard

```typescript
import { Tui, Box, Text, Table, Signal, Computed } from "https://deno.land/x/tui/mod.ts";

// State
const monitors = new Signal([]);
const lastEvent = new Signal("");

// TUI setup
const tui = new Tui({ refreshRate: 1000 / 10 });  // 10 FPS sufficient

// Header
new Text({
  parent: tui,
  text: new Computed(() => `i3pm monitors watch - Last: ${lastEvent.value}`),
  rectangle: { column: 1, row: 1 }
});

// Monitor table
new Table({
  parent: tui,
  rectangle: { column: 1, row: 3, height: 15 },
  headers: [{ title: "Monitor" }, { title: "Workspaces" }],
  data: new Computed(() =>
    monitors.value.map(m => [m.name, m.workspaces.join(", ")])
  )
});

// Event subscription (external process)
async function watchI3Events() {
  const proc = Deno.run({
    cmd: ["i3-msg", "-t", "subscribe", "-m", '["output"]'],
    stdout: "piped"
  });

  const decoder = new TextDecoder();
  for await (const chunk of proc.stdout.readable) {
    const line = decoder.decode(chunk);
    const event = JSON.parse(line);

    // Update state - UI auto-updates
    lastEvent.value = new Date().toISOString();
    monitors.value = await fetchMonitorState();
  }
}

watchI3Events();
tui.run();
```

### Example 3: Interactive Keybindings

```typescript
import { Tui, Table, Signal } from "https://deno.land/x/tui/mod.ts";

const monitors = new Signal([/* ... */]);
const selectedRow = new Signal(0);

const tui = new Tui({});
const table = new Table({
  parent: tui,
  data: new Computed(() => monitors.value.map(formatRow)),
  // Table tracks selected row internally
});

// Custom keybindings
tui.on("keyPress", ({ key, ctrl, shift }) => {
  switch (key) {
    case "j":  // Vim-style down
    case "ArrowDown":
      selectedRow.value = Math.min(
        selectedRow.value + 1,
        monitors.value.length - 1
      );
      break;

    case "k":  // Vim-style up
    case "ArrowUp":
      selectedRow.value = Math.max(selectedRow.value - 1, 0);
      break;

    case "m":  // Move workspace
      if (shift) {
        moveWorkspaceToMonitor(selectedRow.value);
      }
      break;

    case "r":  // Reload config
      reloadI3Config();
      break;

    case "e":  // Edit config
      editMonitorConfig();
      tui.dispatch();  // Exit TUI temporarily
      Deno.exit(0);
      break;

    case "q":  // Quit
      tui.dispatch();
      Deno.exit(0);
      break;
  }
});

tui.run();
```

### Example 4: Manual ANSI Approach (Minimal)

```typescript
// For comparison - simple status display without framework

const ESC = "\x1b";
const clear = `${ESC}[2J${ESC}[H`;
const hideCursor = `${ESC}[?25l`;
const showCursor = `${ESC}[?25h`;
const bold = `${ESC}[1m`;
const reset = `${ESC}[0m`;

function write(text: string) {
  Deno.stdout.writeSync(new TextEncoder().encode(text));
}

function cleanup() {
  write(showCursor + reset);
  Deno.stdin.setRaw(false);
}

Deno.addSignalListener("SIGINT", () => { cleanup(); Deno.exit(0); });

// Main loop
Deno.stdin.setRaw(true);
write(hideCursor + clear);

while (true) {
  const monitors = await fetchMonitorState();

  write(clear);
  write(`${bold}Monitors:${reset}\n\n`);

  for (const m of monitors) {
    write(`${m.name}: ${m.workspaces.join(", ")}\n`);
  }

  write(`\nPress 'q' to quit`);

  // Check for input (non-blocking)
  const reader = Deno.stdin.readable.getReader({ mode: "byob" });
  const buffer = new Uint8Array(1);
  const { value } = await reader.read(buffer);
  reader.releaseLock();

  if (value && value[0] === 113) break;  // 'q'

  await new Promise(resolve => setTimeout(resolve, 1000));
}

cleanup();
```

---

## 5. Recommendation for i3pm monitors

### Command Structure

```bash
# Live dashboard (read-only, auto-refresh)
i3pm monitors watch [--mode=<tree|table|compact>] [--refresh=<ms>]

# Interactive TUI (keybindings for actions)
i3pm monitors tui

# One-time output (use Cliffy or manual table)
i3pm monitors list [--format=<table|json|tree>]
```

### Implementation Plan

#### Phase 1: Static Table Output (`list` command)
**Library**: Cliffy Table
**Why**: Simple, type-safe, perfect for one-time renders
**Effort**: Low (1-2 hours)

```typescript
import { Table } from "https://deno.land/x/cliffy/table/mod.ts";

const monitors = await fetchMonitorState();
new Table()
  .header(["Monitor", "Primary", "Workspaces"])
  .body(monitors.map(m => [m.name, m.primary ? "✓" : "", m.workspaces.join(", ")]))
  .render();
```

#### Phase 2: Live Dashboard (`watch` command)
**Library**: deno_tui
**Why**: Real-time updates with reactive signals
**Effort**: Medium (4-8 hours)

Features:
- Auto-refresh at configurable interval (default 1s)
- Real-time event streaming display
- Multiple display modes (tree/table via component switching)
- Graceful error handling and reconnection

#### Phase 3: Interactive TUI (`tui` command)
**Library**: deno_tui
**Why**: Full keyboard event handling and component interaction
**Effort**: High (8-16 hours)

Features:
- Keyboard navigation (j/k or arrows)
- Action keybindings (m=move, r=reload, e=edit)
- Help overlay (press 'h' or '?')
- Visual feedback for actions
- Multi-pane layout (status + table + logs)

### Specific Recommendations

1. **Start with Cliffy** for basic table output
2. **Migrate to deno_tui** once real-time features are needed
3. **Use Signal/Computed** for all state management
4. **Implement event debouncing** (100-250ms) for i3 events
5. **Add terminal size checks** (min 80x24)
6. **Always use alternate screen buffer** for TUI mode
7. **Test on all platforms** (Linux, WSL, macOS)
8. **Provide fallback** to JSON output if terminal detection fails

### Performance Expectations

| Metric | Target | Approach |
|--------|--------|----------|
| Event latency | <100ms | Signal updates + 10 FPS refresh |
| CPU usage (idle) | <2% | Event-driven, not polling |
| CPU usage (active) | <15% | Efficient diffing |
| Memory footprint | <30MB | Deno runtime + minimal state |
| Terminal compatibility | 95%+ | ANSI escape codes (universal) |

---

## 6. Additional Resources

### Documentation
- **deno_tui**: https://github.com/Im-Beast/deno_tui
- **deno_tui examples**: https://github.com/Im-Beast/deno_tui/tree/main/examples
- **Cliffy docs**: https://cliffy.io/
- **Deno std CLI**: https://deno.land/std/cli
- **ANSI escape codes**: https://gist.github.com/fnky/458719343aabd01cfb17a3a4f7296797

### Tutorials
- **Creating a Universal TUI with Deno**: https://developer.mamezou-tech.com/en/blogs/2023/11/03/deno-tui/
- **Deno keyboard input**: https://dev.to/shinshin86/how-to-read-keystrokes-from-stdin-at-deno-3h0c
- **TUI performance optimization**: https://textual.textualize.io/blog/2024/12/12/algorithms-for-high-performance-terminal-apps/

### Code Examples
- **deno_tui demo**: https://github.com/Im-Beast/deno_tui/blob/main/examples/demo.ts
- **Cliffy examples**: https://github.com/c4spar/deno-cliffy/tree/main/examples

---

## 7. Risk Assessment

| Risk | Impact | Mitigation |
|------|--------|------------|
| deno_tui breaking changes | Medium | Pin to specific version, monitor releases |
| Terminal compatibility issues | Low | Universal ANSI support, test across platforms |
| Performance on old hardware | Low | Configurable refresh rate, fallback to static mode |
| Keyboard event edge cases | Medium | Comprehensive testing, fallback to simple input |
| User unfamiliarity with TUI | Low | Provide help overlay, clear keybinding hints |

---

## Conclusion

**deno_tui is the clear winner** for building the i3pm monitors TUI:

✅ **Purpose-built** for interactive terminal applications
✅ **Reactive architecture** aligns with <100ms latency requirement
✅ **Rich components** (tables, frames) eliminate boilerplate
✅ **Performance** proven at 60 FPS with low overhead
✅ **Active development** and community support
✅ **Zero dependencies** and cross-platform compatibility

Start with **Cliffy for static output**, transition to **deno_tui for live/interactive modes**. Avoid raw ANSI unless building something extremely minimal.

---

**Next Steps**:
1. Prototype basic table with Cliffy (`i3pm monitors list`)
2. Build live dashboard skeleton with deno_tui
3. Add i3 event subscription and reactive updates
4. Implement keyboard navigation and actions
5. Test across Linux, WSL, macOS
6. Add comprehensive error handling and cleanup
