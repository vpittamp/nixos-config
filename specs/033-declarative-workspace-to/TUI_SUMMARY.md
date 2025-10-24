# TUI Library Research Summary
## Quick Decision Guide

**Research Date**: 2025-10-23
**Full Documentation**: [TUI_LIBRARY_RESEARCH.md](TUI_LIBRARY_RESEARCH.md) | [TUI_QUICKSTART.md](TUI_QUICKSTART.md)

---

## TL;DR - What to Use

| Use Case | Library | Reason |
|----------|---------|--------|
| **Static table output** | Cliffy Table | Simple, type-safe, perfect for one-time renders |
| **Live auto-refresh dashboard** | deno_tui | Real-time updates, reactive signals, low overhead |
| **Interactive TUI with keybindings** | deno_tui | Full event handling, component library |
| **Minimal status display** | Raw ANSI | Absolute minimal footprint |

---

## The Winner: deno_tui 🏆

**Why**: Purpose-built for Deno, reactive architecture, rich components, 60 FPS rendering, zero dependencies

**Import**:
```typescript
import { Tui, Table, Signal, Computed } from "https://deno.land/x/tui@v2.1.11/mod.ts";
```

**Hello World**:
```typescript
const monitors = new Signal([{ name: "DP-1", workspaces: [1, 2] }]);
const tui = new Tui({ refreshRate: 1000 / 10 });

new Table({
  parent: tui,
  headers: [{ title: "Monitor" }, { title: "Workspaces" }],
  data: new Computed(() => monitors.value.map(m => [m.name, m.workspaces.join(", ")]))
});

tui.run();
```

---

## Implementation Roadmap

### Phase 1: Static Output (1-2 hours)
✅ **Use Cliffy Table**
✅ Implement `i3pm monitors list`
✅ Format: table, JSON, tree view

### Phase 2: Live Dashboard (4-8 hours)
✅ **Use deno_tui**
✅ Implement `i3pm monitors watch`
✅ Auto-refresh every 1s
✅ Display monitor assignments
✅ Show last update time

### Phase 3: Event-Driven Updates (8-12 hours)
✅ **Subscribe to i3 IPC events**
✅ React to monitor connect/disconnect
✅ React to workspace moves
✅ <100ms latency from event to UI

### Phase 4: Interactive TUI (8-16 hours)
✅ **Implement keyboard navigation**
✅ `j/k` or arrows for selection
✅ `m` to move workspace
✅ `r` to reload config
✅ `e` to edit config
✅ `q` to quit

---

## Key Comparison: deno_tui vs Cliffy

| Feature | deno_tui | Cliffy |
|---------|----------|--------|
| **Primary Purpose** | Full TUI apps | CLI parsing + static tables |
| **Live Updates** | ✅ Reactive signals | ❌ Manual refresh |
| **Keyboard Events** | ✅ Full support | ⚠️ Prompts only |
| **Components** | Table, Frame, Input, Button, etc. | Table only |
| **Event Loop** | ✅ Built-in | ❌ Not applicable |
| **Use for i3pm** | ✅ `watch` + `tui` modes | ✅ `list` mode only |

**Verdict**: Use **both** - Cliffy for static output, deno_tui for live/interactive modes.

---

## Performance Targets

| Metric | Target | How to Achieve |
|--------|--------|----------------|
| Event latency | <100ms | Signal updates + 10 FPS refresh |
| CPU (idle) | <2% | Event-driven, not polling |
| CPU (active) | <15% | Efficient diffing, debouncing |
| Memory | <30MB | Deno runtime + minimal state |
| Refresh rate | 10-60 FPS | Configurable via `refreshRate` |

---

## Critical Best Practices

### 1. Always Cleanup Terminal State
```typescript
// deno_tui auto-cleanup
tui.on("keyPress", ({ ctrl, key }) => {
  if (ctrl && key === "c") {
    tui.dispatch();  // Restores terminal
    Deno.exit(0);
  }
});
```

### 2. Use Reactive Signals for State
```typescript
const monitors = new Signal<Monitor[]>([]);

// UI auto-updates when monitors.value changes
new Table({
  data: new Computed(() => monitors.value.map(formatRow))
});

// Update state - UI redraws automatically
monitors.value = await fetchMonitorState();
```

### 3. Debounce High-Frequency Events
```typescript
const updateUI = debounce(() => {
  monitors.value = fetchMonitorState();
}, 100);  // Max 10 updates/second

eventStream.on("output", updateUI);
```

### 4. Check Terminal Size
```typescript
const { columns, rows } = Deno.consoleSize();
if (columns < 80 || rows < 24) {
  console.error("Terminal too small. Minimum: 80x24");
  Deno.exit(1);
}
```

---

## Code Examples

### Static Table (Cliffy)
```typescript
import { Table } from "https://deno.land/x/cliffy/table/mod.ts";

new Table()
  .header(["Monitor", "Workspaces"])
  .body([["DP-1", "1, 2"], ["HDMI-1", "3, 4, 5"]])
  .render();
```

### Live Dashboard (deno_tui)
```typescript
import { Tui, Table, Signal, Computed } from "https://deno.land/x/tui/mod.ts";

const monitors = new Signal([]);
const tui = new Tui({ refreshRate: 1000 / 10 });

new Table({
  parent: tui,
  data: new Computed(() => monitors.value.map(m => [m.name, m.workspaces.join(", ")]))
});

setInterval(async () => {
  monitors.value = await fetchMonitorState();
}, 1000);

tui.run();
```

### Event-Driven (i3 IPC)
```typescript
async function subscribeToI3() {
  const proc = Deno.run({
    cmd: ["i3-msg", "-t", "subscribe", "-m", '["output"]'],
    stdout: "piped"
  });

  for await (const chunk of proc.stdout.readable) {
    const event = JSON.parse(new TextDecoder().decode(chunk));
    monitors.value = await fetchMonitorState();  // UI auto-updates
  }
}
```

### Interactive Keybindings
```typescript
tui.on("keyPress", async ({ key }) => {
  switch (key) {
    case "j": case "ArrowDown":
      selectedRow.value++;
      break;
    case "m":
      await moveWorkspace(monitors.value[selectedRow.value]);
      break;
    case "q":
      tui.dispatch();
      Deno.exit(0);
  }
});
```

---

## Resources

### Documentation
- **deno_tui GitHub**: https://github.com/Im-Beast/deno_tui
- **deno_tui Demo**: https://github.com/Im-Beast/deno_tui/blob/main/examples/demo.ts
- **Cliffy Docs**: https://cliffy.io/
- **ANSI Escape Codes**: https://gist.github.com/fnky/458719343aabd01cfb17a3a4f7296797

### Tutorials
- **Creating a Universal TUI**: https://developer.mamezou-tech.com/en/blogs/2023/11/03/deno-tui/
- **TUI Performance**: https://textual.textualize.io/blog/2024/12/12/algorithms-for-high-performance-terminal-apps/

---

## Next Steps

1. ✅ **Read**: [TUI_QUICKSTART.md](TUI_QUICKSTART.md) for copy-paste examples
2. ✅ **Prototype**: Start with Cliffy for `i3pm monitors list`
3. ✅ **Implement**: Build live dashboard with deno_tui
4. ✅ **Test**: Verify on Linux, WSL, macOS
5. ✅ **Polish**: Add error handling, help screens, config

---

## Decision Matrix

**Choose deno_tui if**:
- ✅ Need real-time updates
- ✅ Want interactive keyboard navigation
- ✅ Building a dashboard or monitor
- ✅ Need multiple views/panes

**Choose Cliffy if**:
- ✅ One-time static output
- ✅ Traditional CLI tool
- ✅ Simple table display
- ✅ No interactivity needed

**Choose Raw ANSI if**:
- ⚠️ Building something extremely minimal
- ⚠️ Need absolute control
- ⚠️ Framework overhead is unacceptable
- ⚠️ You enjoy pain

---

## Risk Assessment

| Risk | Impact | Mitigation |
|------|--------|------------|
| deno_tui breaking changes | Medium | Pin to v2.1.11, monitor releases |
| Terminal compatibility | Low | Universal ANSI support |
| Performance on old hardware | Low | Configurable refresh rate |
| Keyboard event edge cases | Medium | Comprehensive testing |

---

**Final Recommendation**: Start with **deno_tui** for all interactive features. Use **Cliffy** only for simple static table output. Avoid raw ANSI unless absolutely necessary.

For detailed analysis and comprehensive code examples, see:
- [TUI_LIBRARY_RESEARCH.md](TUI_LIBRARY_RESEARCH.md) - Full research document (781 lines)
- [TUI_QUICKSTART.md](TUI_QUICKSTART.md) - Practical patterns and snippets (643 lines)
