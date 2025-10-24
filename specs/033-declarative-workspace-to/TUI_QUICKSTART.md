# TUI Quick Start Guide
## Practical Code Snippets for i3pm monitors CLI

**Quick Links**: [Full Research](TUI_LIBRARY_RESEARCH.md) | [deno_tui Docs](https://github.com/Im-Beast/deno_tui)

---

## Installation & Setup

### Import deno_tui

```typescript
// mod.ts or main.ts
import {
  Tui,
  Signal,
  Computed,
  Table,
  Text,
  Frame,
  handleInput,
  handleKeyboardControls,
  handleMouseControls
} from "https://deno.land/x/tui@v2.1.11/mod.ts";

// Optional: Styling with Crayon
import { crayon } from "https://deno.land/x/crayon@3.3.3/mod.ts";
```

### Import Cliffy (for simple tables)

```typescript
import { Table } from "https://deno.land/x/cliffy@v1.0.0-rc.4/table/mod.ts";
import { Command } from "https://deno.land/x/cliffy@v1.0.0-rc.4/command/mod.ts";
```

---

## Pattern 1: Simple Static Table (Cliffy)

**Use Case**: `i3pm monitors list` - One-time output

```typescript
import { Table } from "https://deno.land/x/cliffy/table/mod.ts";

interface Monitor {
  name: string;
  primary: boolean;
  workspaces: number[];
  resolution: string;
}

async function listMonitors() {
  const monitors: Monitor[] = await fetchMonitorState();

  new Table()
    .header(["Monitor", "Primary", "Workspaces", "Resolution"])
    .body(monitors.map(m => [
      m.name,
      m.primary ? "✓" : "",
      m.workspaces.join(", "),
      m.resolution
    ]))
    .border(true)
    .render();
}

listMonitors();
```

---

## Pattern 2: Live Auto-Refreshing Dashboard (deno_tui)

**Use Case**: `i3pm monitors watch` - Read-only live view

```typescript
import { Tui, Table, Text, Signal, Computed, handleInput } from "https://deno.land/x/tui/mod.ts";
import { crayon } from "https://deno.land/x/crayon/mod.ts";

// State
const monitors = new Signal<Monitor[]>([]);
const lastUpdate = new Signal<string>(new Date().toISOString());

// Create TUI
const tui = new Tui({
  style: crayon.bgBlack,
  refreshRate: 1000 / 10  // 10 FPS (sufficient for monitoring)
});

// Header
new Text({
  parent: tui,
  text: new Computed(() => `i3pm monitors watch | Last update: ${lastUpdate.value}`),
  rectangle: { column: 1, row: 1 },
  style: crayon.bold.lightBlue
});

// Monitor table
const table = new Table({
  parent: tui,
  theme: {
    base: crayon.bgBlack.white,
    frame: { base: crayon.bgBlack.gray },
    header: { base: crayon.bgBlack.bold.lightBlue },
    selectedRow: {
      base: crayon.bold.bgBlue.white
    }
  },
  rectangle: { column: 1, row: 3, height: 20, width: 80 },
  headers: [
    { title: "Monitor" },
    { title: "Primary" },
    { title: "Workspaces" },
    { title: "Resolution" }
  ],
  data: new Computed(() =>
    monitors.value.map(m => [
      m.name,
      m.primary ? "✓" : "",
      m.workspaces.join(", "),
      m.resolution
    ])
  ),
  charMap: "rounded",
  zIndex: 0
});

// Footer help
new Text({
  parent: tui,
  text: "Press Ctrl+C to quit",
  rectangle: { column: 1, row: 24 },
  style: crayon.gray
});

// Handle input
handleInput(tui);

// Quit on Ctrl+C
tui.on("keyPress", ({ ctrl, key }) => {
  if (ctrl && key === "c") {
    tui.dispatch();
    Deno.exit(0);
  }
});

// Auto-refresh loop
async function autoRefresh(intervalMs: number = 1000) {
  while (true) {
    monitors.value = await fetchMonitorState();
    lastUpdate.value = new Date().toLocaleTimeString();
    await new Promise(resolve => setTimeout(resolve, intervalMs));
  }
}

// Start
autoRefresh(1000);
tui.run();
```

---

## Pattern 3: Event-Driven Live Updates (i3 IPC subscription)

**Use Case**: Real-time updates triggered by i3 events (not polling)

```typescript
import { Tui, Table, Signal, Computed } from "https://deno.land/x/tui/mod.ts";

const monitors = new Signal<Monitor[]>([]);
const events = new Signal<string[]>([]);

// Create TUI (same as Pattern 2)
const tui = new Tui({ refreshRate: 1000 / 10 });

// ... create table component ...

// Subscribe to i3 events
async function subscribeToI3Events() {
  const proc = Deno.run({
    cmd: ["i3-msg", "-t", "subscribe", "-m", '["output","workspace"]'],
    stdout: "piped"
  });

  const decoder = new TextDecoder();
  for await (const chunk of proc.stdout.readable) {
    const line = decoder.decode(chunk);
    try {
      const event = JSON.parse(line);

      // Update state - UI auto-updates via reactive signals
      if (event.change === "unspecified" || event.change === "new") {
        monitors.value = await fetchMonitorState();
        events.value = [...events.value.slice(-10), `${new Date().toLocaleTimeString()}: ${event.change}`];
      }
    } catch (err) {
      console.error("Failed to parse i3 event:", err);
    }
  }
}

// Start subscription in background
subscribeToI3Events();

// Start TUI
handleInput(tui);
tui.run();
```

---

## Pattern 4: Interactive TUI with Keybindings

**Use Case**: `i3pm monitors tui` - Full interactive mode with actions

```typescript
import { Tui, Table, Text, Frame, Signal, Computed, handleInput, handleKeyboardControls } from "https://deno.land/x/tui/mod.ts";

const monitors = new Signal<Monitor[]>([]);
const selectedRow = new Signal(0);
const statusMsg = new Signal("");

const tui = new Tui({ refreshRate: 1000 / 10 });

// Main frame
const mainFrame = new Frame({
  parent: tui,
  rectangle: { column: 0, row: 0, height: 30, width: 100 },
  style: crayon.bgBlack
});

// Status bar
new Text({
  parent: mainFrame,
  text: new Computed(() => statusMsg.value || "Ready"),
  rectangle: { column: 1, row: 1 },
  style: crayon.yellow
});

// Monitor table (with selection tracking)
const table = new Table({
  parent: mainFrame,
  rectangle: { column: 1, row: 3, height: 20 },
  headers: [{ title: "Monitor" }, { title: "Workspaces" }],
  data: new Computed(() =>
    monitors.value.map((m, idx) => [
      idx === selectedRow.value ? `> ${m.name}` : `  ${m.name}`,
      m.workspaces.join(", ")
    ])
  ),
  charMap: "rounded"
});

// Help footer
new Text({
  parent: mainFrame,
  text: "Keys: ↑/↓ or j/k: Navigate | m: Move workspace | r: Reload | e: Edit config | q: Quit",
  rectangle: { column: 1, row: 25 },
  style: crayon.gray
});

// Keyboard event handlers
handleInput(tui);
handleKeyboardControls(tui);

tui.on("keyPress", async ({ key, ctrl, shift }) => {
  const maxRow = monitors.value.length - 1;

  switch (key) {
    // Navigation
    case "j":
    case "ArrowDown":
      selectedRow.value = Math.min(selectedRow.value + 1, maxRow);
      break;

    case "k":
    case "ArrowUp":
      selectedRow.value = Math.max(selectedRow.value - 1, 0);
      break;

    case "g":
      if (shift) selectedRow.value = maxRow;  // Shift+G = bottom
      else selectedRow.value = 0;             // g = top
      break;

    // Actions
    case "m":
      const monitor = monitors.value[selectedRow.value];
      statusMsg.value = `Moving workspace to ${monitor.name}...`;
      await moveWorkspaceToMonitor(monitor.name);
      statusMsg.value = `Workspace moved to ${monitor.name}`;
      monitors.value = await fetchMonitorState();
      break;

    case "r":
      statusMsg.value = "Reloading i3 config...";
      await reloadI3Config();
      statusMsg.value = "Config reloaded";
      monitors.value = await fetchMonitorState();
      break;

    case "e":
      tui.dispatch();
      await editConfig();
      Deno.exit(0);
      break;

    case "q":
      tui.dispatch();
      Deno.exit(0);
      break;

    case "?":
    case "h":
      statusMsg.value = "Help: j/k=nav, m=move, r=reload, e=edit, q=quit";
      break;
  }
});

// Quit on Ctrl+C
tui.on("keyPress", ({ ctrl, key }) => {
  if (ctrl && key === "c") {
    tui.dispatch();
    Deno.exit(0);
  }
});

// Initial load
monitors.value = await fetchMonitorState();

// Start TUI
tui.run();
```

---

## Pattern 5: Multiple Panes (Tree + Table + Events)

**Use Case**: Complex dashboard with multiple views

```typescript
import { Tui, Frame, Text, Table, Box, Signal, Computed } from "https://deno.land/x/tui/mod.ts";

const monitors = new Signal<Monitor[]>([]);
const events = new Signal<string[]>([]);
const { columns, rows } = Deno.consoleSize();

const tui = new Tui({ refreshRate: 1000 / 10 });

// Left pane - Monitor tree view
const leftPane = new Frame({
  parent: tui,
  rectangle: { column: 0, row: 0, height: rows - 2, width: columns / 2 },
  title: "Monitor Tree"
});

new Text({
  parent: leftPane,
  text: new Computed(() =>
    monitors.value.map(m =>
      `📺 ${m.name}\n` +
      m.workspaces.map(w => `  └─ Workspace ${w}`).join("\n")
    ).join("\n\n")
  ),
  rectangle: { column: 1, row: 1 }
});

// Right pane - Events stream
const rightPane = new Frame({
  parent: tui,
  rectangle: { column: columns / 2, row: 0, height: rows - 2, width: columns / 2 },
  title: "Event Stream"
});

new Text({
  parent: rightPane,
  text: new Computed(() => events.value.slice(-15).join("\n")),
  rectangle: { column: 1, row: 1 }
});

// ... rest of setup ...
```

---

## Helper Functions

### Fetch Monitor State (example)

```typescript
interface Monitor {
  name: string;
  primary: boolean;
  workspaces: number[];
  resolution: string;
}

async function fetchMonitorState(): Promise<Monitor[]> {
  // Using i3-msg to get outputs
  const outputsProc = Deno.run({
    cmd: ["i3-msg", "-t", "get_outputs"],
    stdout: "piped"
  });

  const outputsData = await outputsProc.output();
  const outputs = JSON.parse(new TextDecoder().decode(outputsData));

  // Using i3-msg to get workspaces
  const wsProc = Deno.run({
    cmd: ["i3-msg", "-t", "get_workspaces"],
    stdout: "piped"
  });

  const wsData = await wsProc.output();
  const workspaces = JSON.parse(new TextDecoder().decode(wsData));

  // Map workspaces to outputs
  return outputs
    .filter((o: any) => o.active)
    .map((o: any) => ({
      name: o.name,
      primary: o.primary,
      resolution: `${o.current_mode?.width}x${o.current_mode?.height}`,
      workspaces: workspaces
        .filter((w: any) => w.output === o.name)
        .map((w: any) => w.num)
        .sort((a: number, b: number) => a - b)
    }));
}
```

### Move Workspace Action

```typescript
async function moveWorkspaceToMonitor(outputName: string): Promise<void> {
  const proc = Deno.run({
    cmd: ["i3-msg", `move workspace to output ${outputName}`],
    stdout: "piped",
    stderr: "piped"
  });

  const status = await proc.status();
  if (!status.success) {
    const error = new TextDecoder().decode(await proc.stderrOutput());
    throw new Error(`Failed to move workspace: ${error}`);
  }
}
```

### Reload i3 Config

```typescript
async function reloadI3Config(): Promise<void> {
  await Deno.run({ cmd: ["i3-msg", "reload"] }).status();
}
```

### Edit Config (exit TUI, open editor)

```typescript
async function editConfig(): Promise<void> {
  const editor = Deno.env.get("EDITOR") || "vim";
  const configPath = `${Deno.env.get("HOME")}/.config/i3/monitor-config.json`;

  await Deno.run({
    cmd: [editor, configPath],
    stdin: "inherit",
    stdout: "inherit",
    stderr: "inherit"
  }).status();
}
```

---

## Terminal Cleanup Pattern (Critical!)

**Always cleanup terminal state on exit:**

```typescript
const ESC = "\x1b";
const showCursor = `${ESC}[?25h`;
const resetColors = `${ESC}[0m`;
const exitAltScreen = `${ESC}[?1049l`;

function cleanupTerminal() {
  Deno.stdout.writeSync(new TextEncoder().encode(
    showCursor + resetColors + exitAltScreen
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

// deno_tui handles this via tui.dispatch()
tui.on("keyPress", ({ ctrl, key }) => {
  if (ctrl && key === "c") {
    tui.dispatch();  // Automatic cleanup
    Deno.exit(0);
  }
});
```

---

## Terminal Size Handling

**Check minimum size and handle resize:**

```typescript
function checkTerminalSize(minWidth = 80, minHeight = 24): boolean {
  const { columns, rows } = Deno.consoleSize();

  if (columns < minWidth || rows < minHeight) {
    console.error(`Terminal too small. Minimum: ${minWidth}x${minHeight}, Current: ${columns}x${rows}`);
    return false;
  }

  return true;
}

// Handle resize events
Deno.addSignalListener("SIGWINCH", () => {
  const { columns, rows } = Deno.consoleSize();
  // deno_tui auto-handles, but you can react to changes:
  console.log(`Terminal resized to ${columns}x${rows}`);
});

// Before starting TUI:
if (!checkTerminalSize()) {
  Deno.exit(1);
}
```

---

## Performance Tips

### 1. Debounce High-Frequency Events

```typescript
function debounce<T extends (...args: any[]) => any>(
  fn: T,
  delayMs: number
): (...args: Parameters<T>) => void {
  let timeoutId: number | undefined;

  return (...args: Parameters<T>) => {
    if (timeoutId !== undefined) {
      clearTimeout(timeoutId);
    }
    timeoutId = setTimeout(() => fn(...args), delayMs);
  };
}

const updateUI = debounce(async () => {
  monitors.value = await fetchMonitorState();
}, 100);  // Max 10 updates/second

eventStream.on("output", updateUI);
```

### 2. Optimize Refresh Rate

```typescript
// For static dashboards: 10 FPS (100ms) is plenty
const tui = new Tui({ refreshRate: 100 });

// For smooth animations: 30-60 FPS
const tui = new Tui({ refreshRate: 1000 / 60 });

// Adaptive refresh based on activity
let isActive = false;
const tui = new Tui({
  refreshRate: new Computed(() => isActive ? 1000 / 60 : 1000)
});
```

### 3. Limit Event History

```typescript
const events = new Signal<string[]>([]);

function addEvent(event: string) {
  // Keep only last 100 events
  events.value = [...events.value.slice(-99), event];
}
```

---

## Testing Checklist

- [ ] Test on Linux native terminal
- [ ] Test on WSL (Windows Terminal)
- [ ] Test on macOS Terminal.app
- [ ] Test terminal resize behavior
- [ ] Test Ctrl+C cleanup (no leftover artifacts)
- [ ] Test minimum terminal size enforcement
- [ ] Test with slow i3 responses (add timeouts)
- [ ] Test with no monitors connected (edge case)
- [ ] Profile CPU usage (should be <5% idle)
- [ ] Profile memory usage (should be <30MB)

---

## Common Issues & Solutions

### Issue: Flickering display
**Solution**: Increase refresh rate or use diff-based rendering (deno_tui does this automatically)

### Issue: Terminal left in bad state after crash
**Solution**: Ensure cleanup handlers are registered for all exit paths

### Issue: Keyboard input not working
**Solution**: Check `handleInput(tui)` is called before `tui.run()`

### Issue: Colors not showing
**Solution**: Check terminal supports 256 colors (`echo $TERM` should be `xterm-256color`)

### Issue: High CPU usage
**Solution**: Reduce refresh rate or implement debouncing for event handlers

---

## Next Steps

1. **Prototype**: Start with Pattern 1 (Cliffy static table)
2. **Live View**: Implement Pattern 2 or 3 (deno_tui dashboard)
3. **Interactive**: Add Pattern 4 (keyboard navigation + actions)
4. **Polish**: Add error handling, help screens, config options

**See Also**: [Full Research Document](TUI_LIBRARY_RESEARCH.md) for detailed analysis and best practices.
