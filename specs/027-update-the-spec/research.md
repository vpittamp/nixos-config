# Research: Deno Standard Library Integration for i3pm CLI

**Feature**: Complete i3pm Deno CLI with Extensible Architecture
**Date**: 2025-10-22
**Status**: Complete

## Executive Summary

This research consolidates findings on integrating Deno standard library modules for the i3pm CLI rewrite. All technical unknowns from the Technical Context have been resolved through analysis of the Deno std CLI library documentation (from `docs/denoland-std-cli.txt`) and constitutional requirements (Principle XIII). The CLI will leverage `@std/cli` extensively for argument parsing (`parseArgs`), terminal formatting (ANSI utilities), and string width calculations (`unicode Width`), with TypeScript strict mode and Zod for runtime validation.

---

## Research Task 1: Command-Line Argument Parsing with `parseArgs()`

### Decision: Use `@std/cli/parse-args` with minimist-style API

**Rationale**:
- **Constitutional mandate**: Principle XIII explicitly requires `parseArgs()` from `@std/cli/parse-args`
- **Proven API**: minimist-style interface is battle-tested and familiar to Node.js/JavaScript developers
- **Type safety**: Returns strongly-typed `Args<TArgs, TDoubleDash>` with automatic type inference from options
- **Feature completeness**: Supports boolean flags, string options, defaults, aliases, collect (array values), negatable flags, custom validation

**Alternatives Considered**:
1. **Third-party library (commander, yargs)**: Rejected - violates Principle XIII requirement to use Deno std library
2. **Manual parsing with Deno.args**: Rejected - reinventing the wheel, no type safety, high maintenance burden
3. **cliffy (Deno third-party)**: Rejected - adds unnecessary dependency when std library provides sufficient functionality

**Implementation Pattern**:
```typescript
import { parseArgs } from "@std/cli/parse-args";

// Type-safe argument parsing with explicit options
const args = parseArgs(Deno.args, {
  boolean: ["live", "tree", "table", "json", "version", "help", "verbose", "debug"],
  string: ["project", "format", "type", "limit", "since-id"],
  collect: ["filter"],  // Allow multiple --filter flags
  negatable: ["hidden"], // Support --no-hidden
  default: { format: "tree", limit: "20" },
  alias: {
    h: "help",
    v: "version",
    l: "limit",
    t: "type"
  },
  stopEarly: true,  // For subcommand parsing
  "--": true,       // Capture args after -- for pass-through
});

// Access parsed values with type safety
if (args.help) {
  showHelp();
  Deno.exit(0);
}

const format: string = args.format as string;  // Type-safe access
const filters: string[] = args.filter as string[];  // Collected array
```

**Key Features Used**:
- **boolean**: Flags without values (`--live`, `--version`)
- **string**: Options with string values (`--project nixos`, `--format=tree`)
- **collect**: Options that can be specified multiple times, collected into array
- **negatable**: Options that can be negated with `--no-` prefix (`--no-hidden`)
- **default**: Default values for options not provided
- **alias**: Short aliases for long options (`-h` → `help`, `-v` → `version`)
- **stopEarly**: Stop parsing at first non-option (for subcommand support)
- **"--"**: Capture arguments after `--` separator for pass-through scenarios

**Best Practices**:
1. Define options object with explicit types for IDE autocomplete
2. Use type assertions for accessing parsed values (`args.format as string`)
3. Validate required arguments after parsing (parseArgs doesn't enforce required)
4. Provide clear error messages for invalid combinations
5. Use `stopEarly: true` for multi-level command structures

---

## Research Task 2: Terminal UI with ANSI Escape Codes

### Decision: Use `@std/cli/unstable-ansi` for ANSI formatting

**Rationale**:
- **Constitutional mandate**: Principle XIII requires ANSI utilities from `@std/cli/unstable-ansi` (FR-049)
- **Comprehensive coverage**: Provides all necessary ANSI escape codes for colors, cursor control, screen management
- **Raw access**: Exposes low-level encoder/decoder for custom TUI implementations
- **Type-safe**: TypeScript type definitions for all escape code utilities
- **No dependencies**: Part of Deno std library, no third-party packages

**Alternatives Considered**:
1. **chalk (npm package)**: Rejected - third-party dependency, overkill for terminal formatting
2. **Manual ANSI codes**: Rejected - error-prone, poor maintainability, no type safety
3. **cliffy/ansi (third-party)**: Rejected - duplicates std library functionality

**Implementation Patterns from Deno std CLI**:

```typescript
// From docs/denoland-std-cli.txt: cli/_prompt_select.ts
const encoder = new TextEncoder();
const decoder = new TextDecoder();

const CLEAR_ALL = encoder.encode("\x1b[J"); // Clear all lines after cursor
const HIDE_CURSOR = encoder.encode("\x1b[?25l");
const SHOW_CURSOR = encoder.encode("\x1b[?25h");

// Writing ANSI codes to stdout
output.writeSync(HIDE_CURSOR);
output.writeSync(encoder.encode(`\x1b[${clearLength}A`)); // Move cursor up
output.writeSync(CLEAR_ALL);
output.writeSync(SHOW_CURSOR);

// Reading from stdin with raw mode for interactive TUI
input.setRaw(true);
const buffer = new Uint8Array(4);
const n = input.readSync(buffer);
const string = decoder.decode(buffer.slice(0, n));
input.setRaw(false);
```

**Key ANSI Escape Codes**:
- **Cursor control**: `\x1b[<N>A` (up), `\x1b[<N>B` (down), `\x1b[<N>C` (forward), `\x1b[<N>D` (back)
- **Screen management**: `\x1b[J` (clear after), `\x1b[2J` (clear all), `\x1b[H` (home)
- **Cursor visibility**: `\x1b[?25l` (hide), `\x1b[?25h` (show)
- **Alternate screen**: `\x1b[?1049h` (enter), `\x1b[?1049l` (exit)
- **Colors**: `\x1b[31m` (red), `\x1b[32m` (green), `\x1b[0m` (reset)
- **Styles**: `\x1b[1m` (bold), `\x1b[4m` (underline), `\x1b[7m` (invert)

**Best Practices**:
1. Always restore terminal state on exit (show cursor, leave alternate screen, reset raw mode)
2. Use TextEncoder/TextDecoder for UTF-8 safety
3. Handle Ctrl+C gracefully with signal listeners
4. Test terminal resize events (`Deno.consoleSize()`)
5. Provide fallback for non-ANSI terminals (check `Deno.noColor`)

---

## Research Task 3: Unicode String Width Calculation

### Decision: Use `@std/cli/unicode-width` for table formatting

**Rationale**:
- **Constitutional mandate**: Principle XIII requires `unicodeWidth()` from `@std/cli/unicode-width` (FR-050)
- **Correct rendering**: Handles CJK (Chinese, Japanese, Korean) characters and emoji width properly
- **Table alignment**: Essential for proper column alignment in table view mode
- **Unicode 15.0.0**: Based on Unicode standard width definitions (from docs: `cli/_data.json` declares "UNICODE_VERSION": "15.0.0")
- **Run-length encoding**: Compact storage of Unicode width tables via base64-encoded run-length data

**Alternatives Considered**:
1. **string.length**: Rejected - incorrect for multi-byte characters and emoji
2. **Custom width calculation**: Rejected - complex Unicode rules, high maintenance
3. **wcwidth (npm)**: Rejected - third-party dependency when std library provides equivalent

**Implementation Pattern**:
```typescript
import { unicodeWidth } from "@std/cli/unicode-width";

// Calculate display width for table columns
function padRight(text: string, width: number): string {
  const textWidth = unicodeWidth(text);
  const padding = " ".repeat(Math.max(0, width - textWidth));
  return text + padding;
}

function padLeft(text: string, width: number): string {
  const textWidth = unicodeWidth(text);
  const padding = " ".repeat(Math.max(0, width - textWidth));
  return padding + text;
}

// Example: Table row formatting
const columns = [
  { header: "ID", width: 10 },
  { header: "Class", width: 20 },
  { header: "Title", width: 40 },
  { header: "Project", width: 15 },
];

function formatRow(values: string[]): string {
  return columns.map((col, i) =>
    padRight(values[i] || "", col.width)
  ).join(" | ");
}

// Handles emoji and CJK characters correctly
console.log(formatRow(["1", "Firefox", "📧 Email - 日本語", "[nixos]"]));
```

**Key Use Cases**:
1. **Table column alignment**: Ensure columns align regardless of character width
2. **Progress bar rendering**: Calculate exact bar width for visual accuracy
3. **Text truncation**: Truncate to display width, not byte/character count
4. **Padding calculation**: Add correct amount of padding for visual alignment

**Best Practices**:
1. Always use `unicodeWidth()` for terminal width calculations, never `string.length`
2. Pre-calculate column widths based on maximum unicodeWidth of all values
3. Handle overflow with truncation + ellipsis ("...") at exact width boundary
4. Test with emoji, CJK characters, and combining characters
5. Cache width calculations for repeated rendering (live TUI)

---

## Research Task 4: JSON-RPC 2.0 Client Implementation

### Decision: Implement custom JSON-RPC 2.0 client with TypeScript types

**Rationale**:
- **Protocol simplicity**: JSON-RPC 2.0 is simple enough to implement directly without library dependency
- **Type safety**: Custom implementation allows TypeScript types for all RPC methods and parameters
- **Unix socket support**: Deno's `Deno.connect({ path: socketPath, transport: "unix" })` natively supports Unix sockets
- **Event streaming**: Custom implementation supports bidirectional communication for event subscriptions
- **No third-party dependency**: Keeps binary size small and aligns with Principle XIII

**Alternatives Considered**:
1. **jsonrpc-lite (npm)**: Rejected - adds dependency for simple protocol
2. **rpc-websockets**: Rejected - overkill, requires WebSocket vs Unix socket
3. **Manual JSON over socket**: Rejected - reinvents JSON-RPC without benefits

**Implementation Pattern**:
```typescript
// src/client.ts - JSON-RPC 2.0 Client

interface JsonRpcRequest {
  jsonrpc: "2.0";
  method: string;
  params?: unknown;
  id: number;
}

interface JsonRpcResponse<T = unknown> {
  jsonrpc: "2.0";
  result?: T;
  error?: {
    code: number;
    message: string;
    data?: unknown;
  };
  id: number;
}

interface JsonRpcNotification {
  jsonrpc: "2.0";
  method: string;
  params?: unknown;
}

export class DaemonClient {
  private socketPath: string;
  private conn: Deno.UnixConn | null = null;
  private requestId = 0;
  private pendingRequests = new Map<number, {
    resolve: (value: unknown) => void;
    reject: (error: Error) => void;
  }>();

  constructor(socketPath?: string) {
    const runtime_dir = Deno.env.get("XDG_RUNTIME_DIR") || `/run/user/${Deno.uid()}`;
    this.socketPath = socketPath || `${runtime_dir}/i3-project-daemon/ipc.sock`;
  }

  async connect(): Promise<void> {
    try {
      this.conn = await Deno.connect({
        path: this.socketPath,
        transport: "unix"
      }) as Deno.UnixConn;
    } catch (err) {
      throw new Error(`Failed to connect to daemon at ${this.socketPath}: ${err.message}`);
    }
  }

  async request<T = unknown>(method: string, params?: unknown): Promise<T> {
    if (!this.conn) await this.connect();

    const id = ++this.requestId;
    const request: JsonRpcRequest = {
      jsonrpc: "2.0",
      method,
      params,
      id,
    };

    // Send request
    const requestData = JSON.stringify(request) + "\n";
    await this.conn!.write(new TextEncoder().encode(requestData));

    // Wait for response
    return new Promise((resolve, reject) => {
      this.pendingRequests.set(id, { resolve, reject });
      // Timeout after 5 seconds (FR-014)
      setTimeout(() => {
        this.pendingRequests.delete(id);
        reject(new Error(`Request timeout for method: ${method}`));
      }, 5000);
    });
  }

  async subscribe(
    method: string,
    callback: (notification: JsonRpcNotification) => void
  ): Promise<void> {
    // Subscribe to event stream
    await this.request("subscribe_events", { event_types: ["window", "workspace", "output"] });

    // Start reading notifications in background
    const buffer = new Uint8Array(8192);
    let partial = "";

    while (this.conn) {
      const n = await this.conn.read(buffer);
      if (n === null) break;

      partial += new TextDecoder().decode(buffer.subarray(0, n));
      const lines = partial.split("\n");
      partial = lines.pop() || "";

      for (const line of lines) {
        if (!line.trim()) continue;
        const msg = JSON.parse(line);

        if ("id" in msg) {
          // Response to request
          const pending = this.pendingRequests.get(msg.id);
          if (pending) {
            this.pendingRequests.delete(msg.id);
            if (msg.error) {
              pending.reject(new Error(msg.error.message));
            } else {
              pending.resolve(msg.result);
            }
          }
        } else {
          // Notification (event)
          callback(msg);
        }
      }
    }
  }

  close(): void {
    this.conn?.close();
    this.conn = null;
  }
}
```

**Best Practices**:
1. Implement request timeout (5 seconds per FR-014)
2. Handle connection errors with user-friendly messages
3. Support both request-response and notification patterns
4. Parse JSON line-by-line to handle streaming responses
5. Implement exponential backoff for reconnection attempts
6. Validate JSON-RPC response structure against TypeScript types

---

## Research Task 5: Runtime Type Validation with Zod

### Decision: Use Zod for runtime validation of daemon responses

**Rationale**:
- **Type-script compatibility**: Zod schemas generate TypeScript types automatically
- **Runtime safety**: Validates JSON-RPC responses at runtime to catch protocol violations
- **Clear error messages**: Zod provides descriptive validation errors for debugging
- **Optional dependency**: Can use TypeScript types alone, Zod adds safety layer (FR-055)
- **Small footprint**: Zod adds ~20KB to compiled binary, acceptable for safety benefits

**Alternatives Considered**:
1. **TypeScript only**: Rejected - no runtime validation, silent failures on protocol changes
2. **JSON Schema**: Rejected - verbose, no automatic TypeScript type generation
3. **Custom validation**: Rejected - reinvents wheel, maintenance burden
4. **io-ts**: Rejected - less ergonomic API than Zod

**Implementation Pattern**:
```typescript
import { z } from "https://deno.land/x/zod/mod.ts";

// Define Zod schemas for entities (from spec.md Key Entities)
export const WindowStateSchema = z.object({
  id: z.number(),
  class: z.string(),
  instance: z.string().optional(),
  title: z.string(),
  workspace: z.string(),
  output: z.string(),
  marks: z.array(z.string()),
  focused: z.boolean(),
  hidden: z.boolean(),
  floating: z.boolean(),
  fullscreen: z.boolean(),
  geometry: z.object({
    x: z.number(),
    y: z.number(),
    width: z.number(),
    height: z.number(),
  }),
});

export const WorkspaceSchema = z.object({
  number: z.number(),
  name: z.string(),
  focused: z.boolean(),
  visible: z.boolean(),
  output: z.string(),
  windows: z.array(WindowStateSchema),
});

export const OutputSchema = z.object({
  name: z.string(),
  active: z.boolean(),
  primary: z.boolean(),
  geometry: z.object({
    x: z.number(),
    y: z.number(),
    width: z.number(),
    height: z.number(),
  }),
  current_workspace: z.string(),
  workspaces: z.array(WorkspaceSchema),
});

// Infer TypeScript types from Zod schemas
export type WindowState = z.infer<typeof WindowStateSchema>;
export type Workspace = z.infer<typeof WorkspaceSchema>;
export type Output = z.infer<typeof OutputSchema>;

// Validate daemon responses
async function getWindowState(): Promise<Output[]> {
  const response = await daemonClient.request("get_windows");

  // Runtime validation with Zod
  const OutputArraySchema = z.array(OutputSchema);
  const validated = OutputArraySchema.parse(response);

  return validated;  // Type: Output[]
}

// Handle validation errors gracefully
try {
  const outputs = await getWindowState();
  renderTree(outputs);
} catch (err) {
  if (err instanceof z.ZodError) {
    console.error("Invalid daemon response:", err.errors);
    console.error("This may indicate a protocol version mismatch");
    Deno.exit(1);
  }
  throw err;
}
```

**Best Practices**:
1. Define Zod schemas for all daemon response types
2. Use `z.infer<typeof Schema>` to generate TypeScript types
3. Validate at API boundaries (daemon responses, config files)
4. Provide clear error messages for validation failures
5. Consider optional validation in production (via --debug flag)

---

## Research Task 6: NixOS Packaging and Compilation

### Decision: Package as Deno compiled binary via custom derivation

**Rationale**:
- **Self-contained**: `deno compile` produces standalone executable with embedded runtime
- **Zero dependencies**: No Deno runtime required on target system (SC-008)
- **Fast startup**: Compiled binary starts in <100ms vs source execution
- **Permissions baked in**: Compile-time permissions (`--allow-net`, `--allow-read`) embedded in binary
- **NixOS integration**: Custom derivation or buildDenoApplication from nixpkgs

**Implementation Pattern**:

```nix
# home-modules/tools/i3pm-deno.nix
{ config, lib, pkgs, ... }:

{
  home.packages = [
    (pkgs.stdenv.mkDerivation {
      pname = "i3pm";
      version = "2.0.0";

      src = /etc/nixos/home-modules/tools/i3pm-deno;

      nativeBuildInputs = [ pkgs.deno ];

      buildPhase = ''
        # Compile TypeScript to standalone binary
        deno compile \
          --allow-net \
          --allow-read=/run/user,/home \
          --allow-env=XDG_RUNTIME_DIR,HOME,USER \
          --output=i3pm \
          main.ts
      '';

      installPhase = ''
        mkdir -p $out/bin
        cp i3pm $out/bin/
      '';

      meta = {
        description = "i3 project management CLI tool";
        license = lib.licenses.mit;
        platforms = lib.platforms.linux;
      };
    })
  ];
}
```

**Compilation Flags**:
- `--allow-net`: Required for Unix socket communication with daemon (FR-010)
- `--allow-read`: Read access to daemon socket and config files (FR-011)
- `--allow-env`: Access to environment variables (XDG_RUNTIME_DIR, HOME)
- `--output`: Name of compiled binary (i3pm)

**Best Practices**:
1. Use minimal permissions required for functionality
2. Test compiled binary independently of source
3. Version binary with semantic versioning
4. Include deno.lock for reproducible builds
5. Cache dependencies during compilation for faster rebuilds

---

## Research Task 7: Live TUI Event Handling

### Decision: Event-driven architecture with signal handling and terminal resize

**Rationale**:
- **Real-time updates**: Subscribe to daemon events via JSON-RPC notifications (FR-012)
- **Signal handling**: Graceful exit on Ctrl+C with terminal restoration (FR-009, FR-052)
- **Terminal resize**: Detect and redraw on window size changes (FR-032)
- **Keyboard input**: Raw mode for interactive navigation (Tab, H, Q, Ctrl+C)
- **Non-blocking**: Async event loop prevents UI freezing

**Implementation Pattern**:

```typescript
// src/ui/live.ts - Live TUI with event handling

class LiveTUI {
  private client: DaemonClient;
  private running = false;
  private outputs: Output[] = [];
  private showHidden = false;

  constructor(client: DaemonClient) {
    this.client = client;
  }

  async run(): Promise<void> {
    // Setup signal handlers
    this.setupSignalHandlers();

    // Enter alternate screen buffer
    const encoder = new TextEncoder();
    Deno.stdout.writeSync(encoder.encode("\x1b[?1049h")); // Alternate screen
    Deno.stdout.writeSync(encoder.encode("\x1b[?25l"));   // Hide cursor

    // Set raw mode for keyboard input
    Deno.stdin.setRaw(true);

    this.running = true;

    // Start event subscription in background
    const eventPromise = this.subscribeToEvents();

    // Start keyboard input handling
    const keyboardPromise = this.handleKeyboard();

    // Initial render
    await this.refresh();

    // Wait for exit
    await Promise.race([eventPromise, keyboardPromise]);

    // Cleanup
    await this.exit();
  }

  private setupSignalHandlers(): void {
    // Handle Ctrl+C gracefully
    Deno.addSignalListener("SIGINT", () => {
      this.running = false;
    });

    // Handle terminal resize
    Deno.addSignalListener("SIGWINCH", async () => {
      await this.refresh();
    });
  }

  private async subscribeToEvents(): Promise<void> {
    await this.client.subscribe("event_notification", async (notification) => {
      if (!this.running) return;

      // Update display on window events
      const params = notification.params as { event_type: string };
      if (["window", "workspace", "output"].includes(params.event_type)) {
        await this.refresh();
      }
    });
  }

  private async handleKeyboard(): Promise<void> {
    const buffer = new Uint8Array(4);
    const decoder = new TextDecoder();

    while (this.running) {
      const n = await Deno.stdin.read(buffer);
      if (n === null) break;

      const key = decoder.decode(buffer.slice(0, n));

      switch (key) {
        case "q":
        case "Q":
          this.running = false;
          break;
        case "h":
        case "H":
          this.showHidden = !this.showHidden;
          await this.refresh();
          break;
        case "\t": // Tab key
          // Toggle between tree and table view
          await this.toggleView();
          break;
        case "\x03": // Ctrl+C
          this.running = false;
          break;
      }
    }
  }

  private async refresh(): Promise<void> {
    // Clear screen
    const encoder = new TextEncoder();
    Deno.stdout.writeSync(encoder.encode("\x1b[2J\x1b[H"));

    // Fetch fresh state from daemon
    this.outputs = await this.client.request<Output[]>("get_windows");

    // Render tree/table view
    const output = this.showHidden
      ? this.renderTreeAll(this.outputs)
      : this.renderTreeFiltered(this.outputs);

    console.log(output);
  }

  private async exit(): Promise<void> {
    // Restore terminal state
    const encoder = new TextEncoder();
    Deno.stdout.writeSync(encoder.encode("\x1b[?25h"));   // Show cursor
    Deno.stdout.writeSync(encoder.encode("\x1b[?1049l")); // Leave alternate screen

    // Restore normal mode
    Deno.stdin.setRaw(false);

    // Close daemon connection
    this.client.close();
  }
}
```

**Best Practices**:
1. Always use alternate screen buffer for full-screen TUI (preserves terminal history)
2. Always hide cursor during rendering, show on exit
3. Always restore raw mode on exit (Deno.stdin.setRaw(false))
4. Handle SIGINT (Ctrl+C) and SIGWINCH (terminal resize) signals
5. Use double Ctrl+C for immediate exit (check if pressed within 1 second)
6. Limit refresh rate to prevent flickering (<250ms minimum between refreshes)
7. Debounce terminal resize events to avoid excessive redraws

---

## Summary of Key Technologies

| Technology | Version | Purpose | Constitutional Requirement |
|------------|---------|---------|---------------------------|
| **Deno** | 1.40+ | Runtime and compiler | Principle XIII |
| **TypeScript** | Latest (via Deno) | Type-safe language | Principle XIII |
| **@std/cli/parse-args** | Latest | Command-line argument parsing | Principle XIII, FR-003 |
| **@std/cli/unstable-ansi** | Latest | Terminal ANSI formatting | Principle XIII, FR-049 |
| **@std/cli/unicode-width** | Latest | Unicode string width calculation | Principle XIII, FR-050 |
| **@std/fs** | Latest | File system operations | Principle XIII |
| **@std/path** | Latest | Path manipulation | Principle XIII |
| **Zod** | 3.x | Runtime type validation | Optional, FR-055 |
| **NixOS** | Current stable | Packaging and deployment | FR-057, FR-059 |

---

## Implementation Readiness

All technical unknowns have been resolved. Implementation can proceed to Phase 1 (data-model.md and contracts/).

**Key Implementation Priorities**:
1. **Start with models.ts**: Define TypeScript types for all entities (WindowState, Workspace, Output, Project, Event)
2. **Implement client.ts**: JSON-RPC 2.0 client with Unix socket communication
3. **Build CLI routing in main.ts**: parseArgs()-based command router with parent command structure
4. **Implement formatters**: tree.ts and table.ts for window visualization
5. **Add live TUI**: live.ts with event subscriptions and keyboard handling
6. **Package for NixOS**: Custom derivation with deno compile

**No Blockers Identified**: All dependencies are available in Deno std library or as lightweight third-party modules (Zod).
