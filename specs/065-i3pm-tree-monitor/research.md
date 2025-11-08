# Research: i3pm Tree Monitor Integration

**Feature**: 065-i3pm-tree-monitor
**Date**: 2025-11-08
**Purpose**: Document research findings on best practices, technology choices, and integration patterns

---

## RPC Protocol Analysis

### Daemon RPC Server

**Location**: `/nix/store/.../sway_tree_monitor/rpc/server.py`
**Protocol**: JSON-RPC 2.0 over Unix socket
**Transport**: Newline-delimited JSON over SOCK_STREAM
**Socket Path**: `$XDG_RUNTIME_DIR/sway-tree-monitor.sock` (default)
**Permissions**: 0600 (owner read/write only)

### Available RPC Methods

| Method | Parameters | Returns | Purpose | Perf Target |
|--------|------------|---------|---------|-------------|
| `ping` | None | `{"status": "ok", "timestamp": float}` | Health check / latency test | <1ms |
| `query_events` | `last?: int, since?: str, until?: str, filter?: str` | `{"events": [...]}` | Query historical events with filters | <2ms (50 events) |
| `get_event` | `event_id: str` | `{"event": {...}}` | Get detailed event with diff/correlation | <5ms |
| `get_statistics` | None | `{"stats": {...}}` | Daemon performance metrics | <2ms |
| `get_daemon_status` | None | `{"status": {...}}` | Daemon health/buffer state | <1ms |

### RPC Protocol Details

**Request Format** (JSON-RPC 2.0):
```json
{
  "jsonrpc": "2.0",
  "method": "query_events",
  "params": {"last": 10, "filter": "window::new"},
  "id": "uuid-or-number"
}
```

**Response Format** (Success):
```json
{
  "jsonrpc": "2.0",
  "result": {"events": [...]},
  "id": "uuid-or-number"
}
```

**Response Format** (Error):
```json
{
  "jsonrpc": "2.0",
  "error": {
    "code": -32600,
    "message": "Invalid Request",
    "data": "Additional error details"
  },
  "id": null
}
```

**Transport**: Each message is newline-delimited. Client sends request + `\n`, daemon responds with response + `\n`.

---

## Deno Standard Library Research

### Decision: Use Deno std library for all CLI operations

**Rationale**: Principle XIII (Deno CLI Development Standards) mandates heavy reliance on Deno std library. Reduces third-party dependencies, improves security, and ensures long-term stability.

### Required Modules

| Module | Purpose | Usage |
|--------|---------|-------|
| `@std/cli/parse-args` | Command-line argument parsing | Parse `i3pm tree-monitor [subcommand] [flags]` |
| `@std/cli/unicode-width` | Terminal width calculations | Table column formatting |
| `@std/cli/unstable-ansi` | Terminal colors/escape codes | Event coloring, cursor movement |
| `@std/fs` | File system operations | Read socket path, check daemon connectivity |
| `@std/path` | Path manipulation | Resolve `$XDG_RUNTIME_DIR` socket path |
| `@std/json` | JSON operations | Parse/stringify RPC messages |
| `@std/async` | Async utilities | Debouncing, retry logic |

### Alternatives Considered

- **npm `minimist`**: Rejected - Deno std `parseArgs()` provides equivalent functionality
- **npm `chalk`**: Rejected - Deno std ANSI utilities sufficient for coloring
- **npm `cli-table3`**: Rejected - Will implement custom table renderer using `unicodeWidth()` for better control

---

## Unix Socket Communication Best Practices

### Decision: Use Deno's native socket APIs

**Rationale**: Deno provides `Deno.connect({ transport: "unix", path: "..." })` for Unix sockets. No external dependencies needed.

### Connection Pattern

```typescript
// Connect to daemon socket
const socketPath = Deno.env.get("XDG_RUNTIME_DIR") + "/sway-tree-monitor.sock";
const conn = await Deno.connect({ transport: "unix", path: socketPath });

// Newline-delimited JSON protocol
const encoder = new TextEncoder();
const decoder = new TextDecoder();

// Send request
const request = { jsonrpc: "2.0", method: "ping", id: crypto.randomUUID() };
await conn.write(encoder.encode(JSON.stringify(request) + "\n"));

// Read response (line-by-line)
const reader = conn.readable.pipeThrough(new TextDecoderStream()).pipeThrough(new TextLineStream());
for await (const line of reader) {
  const response = JSON.parse(line);
  // Handle response
  break; // Single response per request
}
```

### Error Handling

| Error | Cause | Recovery |
|-------|-------|----------|
| `ENOENT` | Socket file doesn't exist | Display: "Daemon not running. Start with: systemctl --user start sway-tree-monitor" |
| `ECONNREFUSED` | Daemon not listening | Same as ENOENT |
| `ETIMEDOUT` | Request timeout (5s) | Offer retry with `--retry` flag |
| `EACCES` | Permission denied | Check socket permissions (should be 0600) |
| `Parse error` | Malformed JSON | Display error + raw response for debugging |

---

## Terminal UI Patterns

### Decision: Mirror `i3pm windows --live` UX

**Rationale**: Users are already familiar with the real-time TUI interface from `i3pm windows --live`. Consistency reduces learning curve.

### Existing Patterns to Reuse

**From `/etc/nixos/home-modules/tools/i3pm/src/ui/live.ts`**:
- Full-screen alternate buffer (`\x1b[?1049h`)
- Hide cursor during rendering (`\x1b[?25l`)
- Keyboard event handling (`q` quit, arrow keys navigate, `r` refresh)
- Table rendering with fixed headers
- Real-time updates via event stream
- Status bar at bottom with legend

### Keyboard Shortcuts (Consistency with i3pm windows)

| Key | Action | Context |
|-----|--------|---------|
| `q` | Quit / return to shell | All views |
| `↑` / `↓` | Navigate events | History, Live |
| `Enter` | Drill down / inspect event | History, Live |
| `b` | Back to previous view | Detail inspection |
| `r` | Refresh / force update | All views |
| `f` | Focus filter input | History |
| `Esc` | Clear filter | History |
| `/` | Search | History |

### Color Scheme (ANSI 24-bit)

**Confidence Indicators** (from spec FR-012):
- 🟢 Very Likely (>90%): `\x1b[38;2;0;255;0m` (green)
- 🟡 Likely (>70%): `\x1b[38;2;255;255;0m` (yellow)
- 🟠 Possible (>50%): `\x1b[38;2;255;165;0m` (orange)
- 🔴 Unlikely (>30%): `\x1b[38;2;255;0;0m` (red)
- ⚫ Very Unlikely (<30%): `\x1b[38;2;128;128;128m` (gray)

**Event Types**:
- `window::new` - Blue (`\x1b[38;2;0;120;212m`)
- `window::focus` - Cyan (`\x1b[38;2;0;188;212m`)
- `workspace::focus` - Purple (`\x1b[38;2;156;39;176m`)
- Other - Default white

---

## Time Parsing Best Practices

### Decision: Support human-friendly time formats

**Rationale**: FR-011 mandates formats like `5m`, `1h`, `30s`, `2d`. Standard pattern in CLI tools (kubectl, journalctl, etc.)

### Parsing Logic

```typescript
function parseTimeFilter(input: string): Date {
  const match = input.match(/^(\d+)([smhd])$/);
  if (!match) throw new Error(`Invalid time format: ${input}. Use format: 5m, 1h, 30s, 2d`);

  const value = parseInt(match[1]);
  const unit = match[2];
  const now = Date.now();

  const multipliers = { s: 1000, m: 60 * 1000, h: 60 * 60 * 1000, d: 24 * 60 * 60 * 1000 };
  return new Date(now - value * multipliers[unit]);
}
```

**Examples**:
- `--since 5m` → Events from last 5 minutes
- `--since 1h` → Events from last hour
- `--since 30s` → Events from last 30 seconds
- `--since 2d` → Events from last 2 days

---

## Testing Strategy

### Decision: Use Deno.test() for unit and integration tests

**Rationale**: Principle XIV (Test-Driven Development) mandates comprehensive testing. Deno's built-in test runner requires zero configuration.

### Test Pyramid

**Unit Tests (70%)**:
- RPC client request/response serialization
- Time parser edge cases
- Table formatter layout calculations
- ANSI escape code generation

**Integration Tests (20%)**:
- Daemon connection and RPC method calls
- Unix socket error handling
- JSON-RPC protocol compliance

**End-to-End Tests (10%)**:
- Full CLI command execution
- Output format validation (table, JSON)
- Filter and query parameter handling

### Mock Strategy

**Mock Daemon**: Implement minimal RPC server in test suite:
```typescript
Deno.test("query_events: filters by event type", async () => {
  // Start mock daemon
  const mockServer = await startMockDaemon({
    events: [
      { id: "1", type: "window::new", timestamp: 1234567890 },
      { id: "2", type: "workspace::focus", timestamp: 1234567891 },
    ]
  });

  // Run CLI command
  const result = await runCLI(["tree-monitor", "history", "--filter", "window::new"]);

  // Verify only matching events returned
  assertEquals(result.events.length, 1);
  assertEquals(result.events[0].type, "window::new");

  await mockServer.close();
});
```

---

## Performance Optimization

### Decision: Prioritize CLI startup speed over feature completeness

**Rationale**: SC-003 requires <50ms startup time (10x faster than Python Textual). Deno's fast V8 startup + compiled binary enables this.

### Optimization Techniques

1. **Lazy imports**: Import UI modules only when needed
2. **Compiled binary**: Use `deno compile` for production deployment
3. **Stream processing**: Process RPC responses line-by-line, don't buffer entire response
4. **Throttled rendering**: Update TUI at max 10 FPS (100ms) to prevent flicker

### Benchmarking

```bash
# Measure CLI startup
time i3pm tree-monitor history --last 1 --json

# Target: <50ms total (includes socket connect, RPC call, JSON parse, output)
```

---

## Integration with Existing i3pm CLI

### Decision: Add as subcommand to i3pm, not standalone binary

**Rationale**: Spec assumption #6 states integration into existing `i3pm` CLI structure. Reduces user cognitive load (single entrypoint).

### Command Structure

```
i3pm tree-monitor <subcommand> [options]
  ├── live [--socket-path PATH]
  ├── history [--last N] [--since TIME] [--filter TYPE] [--json]
  ├── inspect <event-id> [--json]
  └── stats [--since TIME] [--watch] [--json]
```

### Entry Point Modification

**File**: `/etc/nixos/home-modules/tools/i3pm/src/main.ts`

Add to command router:
```typescript
case "tree-monitor":
  await import("./commands/tree-monitor.ts").then(m => m.run(args));
  break;
```

---

## Summary of Decisions

| Topic | Decision | Rationale |
|-------|----------|-----------|
| **RPC Client** | Deno native Unix sockets | No external deps, built-in support |
| **Argument Parsing** | `@std/cli/parse-args` | Constitution Principle XIII |
| **Terminal UI** | Custom renderer using ANSI | Match `i3pm windows --live` UX |
| **Table Formatting** | `unicodeWidth()` + custom logic | Full control over layout |
| **Time Parsing** | Regex-based human format | Standard CLI pattern |
| **Testing** | `Deno.test()` with mock daemon | Zero config, fast execution |
| **Performance** | Lazy imports + compiled binary | <50ms startup target |
| **Integration** | Subcommand of `i3pm` | Single CLI entrypoint |

**Alternatives Rejected**:
- ❌ Standalone binary → Violates spec assumption #6
- ❌ npm dependencies for parsing/formatting → Violates Principle XIII
- ❌ Python CLI client → Doesn't meet <50ms startup requirement
- ❌ Websocket transport → Daemon uses Unix socket only

---

## Next Steps (Phase 1)

1. Generate `data-model.md` - TypeScript interfaces for events, stats, RPC protocol
2. Generate `contracts/` - JSON schemas for RPC methods
3. Generate `quickstart.md` - User-facing documentation
4. Update `.specify/memory/claude-context.md` with Deno std library patterns

**All "NEEDS CLARIFICATION" items from Technical Context are now resolved.**
