# i3pm Deno CLI

**Version**: 2.0.0
**Language**: TypeScript with Deno runtime
**Purpose**: i3 project management CLI tool with type safety and extensible architecture

## Overview

Complete TypeScript/Deno rewrite of the i3pm CLI, replacing the Python CLI with a type-safe, compiled executable. This CLI provides:

- **Project Context Switching**: Switch between project contexts with window visibility management
- **Window State Visualization**: Real-time window state in tree, table, JSON, and live TUI modes
- **Daemon Monitoring**: Status and event stream monitoring for troubleshooting
- **Window Classification**: Rules management and testing for window scoping
- **Interactive Dashboard**: Multi-pane real-time monitoring

All functionality communicates with the existing Python daemon via JSON-RPC 2.0 over Unix socket.

## Quick Start

### Development

```bash
# Run in development mode
deno task dev -- --help

# Run with arguments
deno task dev -- project list
deno task dev -- windows --tree
```

### Compilation

```bash
# Compile to standalone executable
deno task compile

# Binary will be created as ./i3pm
./i3pm --version
```

### Testing

```bash
# Run all tests
deno task test

# Watch mode for TDD
deno task test:watch
```

## Project Structure

```
i3pm-deno/
├── deno.json                   # Deno configuration
├── main.ts                     # CLI entry point
├── mod.ts                      # Public API exports
├── README.md                   # This file
├── src/
│   ├── commands/              # Command implementations
│   │   ├── project.ts         # Project management
│   │   ├── windows.ts         # Window visualization
│   │   ├── daemon.ts          # Daemon status/events
│   │   ├── rules.ts           # Classification rules
│   │   ├── monitor.ts         # Interactive dashboard
│   │   └── app-classes.ts     # Application classes
│   ├── models.ts              # TypeScript type definitions
│   ├── client.ts              # JSON-RPC 2.0 client
│   ├── validation.ts          # Zod schemas
│   ├── ui/                    # Terminal UI components
│   │   ├── tree.ts            # Tree view formatter
│   │   ├── table.ts           # Table view formatter
│   │   ├── live.ts            # Live TUI
│   │   ├── monitor-dashboard.ts  # Multi-pane dashboard
│   │   └── ansi.ts            # ANSI utilities
│   └── utils/
│       ├── socket.ts          # Unix socket connection
│       ├── errors.ts          # Error handling
│       └── signals.ts         # Signal handling
└── tests/
    ├── unit/                  # Unit tests
    ├── integration/           # Integration tests
    └── fixtures/              # Test fixtures and mocks
```

## Commands

### Project Management

```bash
i3pm project list              # List all projects
i3pm project current           # Show active project
i3pm project switch <name>     # Switch to project
i3pm project clear             # Clear active project (global mode)
i3pm project create            # Create new project
i3pm project show <name>       # Show project details
i3pm project validate          # Validate all projects
i3pm project delete <name>     # Delete project
```

### Window Visualization

```bash
i3pm windows                   # Tree view (default)
i3pm windows --table           # Table view
i3pm windows --json            # JSON output
i3pm windows --live            # Live TUI with real-time updates
```

### Daemon Monitoring

```bash
i3pm daemon status             # Show daemon status
i3pm daemon events             # Show recent events
i3pm daemon events --type=window --limit=50  # Filter events
```

### Window Classification

```bash
i3pm rules list                # List classification rules
i3pm rules classify --class=Ghostty  # Test classification
i3pm rules validate            # Validate all rules
i3pm rules test --class=Firefox  # Test rule matching
i3pm app-classes               # Show application classes
```

### Interactive Monitoring

```bash
i3pm monitor                   # Launch multi-pane dashboard
```

## Architecture

### Design Principles

1. **Type Safety**: TypeScript strict mode with comprehensive type definitions
2. **Zero Dependencies**: Compiled to standalone executable (no runtime dependencies)
3. **Deno Standard Library**: Extensive use of `@std/cli` for parsing, formatting, and terminal control
4. **Runtime Validation**: Zod schemas for daemon response validation
5. **Extensible Commands**: Parent command structure supports future expansion

### Communication Protocol

- **Protocol**: JSON-RPC 2.0 over Unix socket
- **Socket**: `$XDG_RUNTIME_DIR/i3-project-daemon/ipc.sock`
- **Timeout**: 5 seconds for all requests
- **Events**: Real-time event subscriptions for live modes

### Performance Targets

- **CLI Startup**: <300ms
- **Project Switch**: <2 seconds
- **Live TUI Update**: <100ms
- **Binary Size**: <20MB
- **Memory Usage**: <50MB during extended live monitoring

## NixOS Integration

This module is packaged as a compiled Deno binary and integrated into NixOS via home-manager:

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
    })
  ];
}
```

## Development

### Prerequisites

- Deno 1.40+ installed
- i3 window manager
- i3-project-event-daemon running

### Running Tests

```bash
# Run all tests
deno task test

# Run specific test file
deno test tests/unit/models_test.ts

# Watch mode
deno task test:watch
```

### Code Style

- **Formatting**: Enforced by `deno fmt` (2-space indents, 100-char line width)
- **Linting**: Enforced by `deno lint` (recommended rules)
- **Types**: Strict TypeScript with no implicit any

## Environment Variables

The CLI uses the following environment variables:

- **XDG_RUNTIME_DIR**: Location of daemon Unix socket (required)
  - Default socket path: `$XDG_RUNTIME_DIR/i3-project-daemon/ipc.sock`
  - Typically: `/run/user/<uid>/i3-project-daemon/ipc.sock`

- **HOME**: Used for project directory resolution and validation
- **USER**: Used for generating default project directories

All environment variables are embedded at compile time with `--allow-env`.

## Logging and Debugging

### Verbose Logging

```bash
# Show connection and RPC request information
i3pm --verbose project list
i3pm --verbose windows --live
```

### Debug Logging

```bash
# Show detailed socket, RPC, and terminal state information
i3pm --debug daemon status
i3pm --debug project switch nixos
```

Debug logging includes:
- Socket connection details and paths
- Full JSON-RPC request/response payloads
- Terminal state changes (raw mode, alternate screen)
- Signal handling events (SIGINT, SIGWINCH)
- Validation details for daemon responses

## Troubleshooting

### Daemon Not Running

**Symptom**: `Failed to connect to daemon` error

```bash
# Check daemon status
systemctl --user status i3-project-event-listener

# View daemon logs
journalctl --user -u i3-project-event-listener -n 50

# Start daemon
systemctl --user start i3-project-event-listener

# Restart daemon
systemctl --user restart i3-project-event-listener
```

### Socket Connection Issues

**Symptom**: `Socket not found` or `Permission denied` errors

```bash
# Verify socket exists
ls -l $XDG_RUNTIME_DIR/i3-project-daemon/ipc.sock

# Check XDG_RUNTIME_DIR is set
echo $XDG_RUNTIME_DIR

# Test socket manually
echo '{"jsonrpc":"2.0","method":"get_status","id":1}' | \
  nc -U $XDG_RUNTIME_DIR/i3-project-daemon/ipc.sock

# Debug socket connection
i3pm --debug daemon status
```

### Request Timeout

**Symptom**: `Request timeout for method: <method>` error

```bash
# Check daemon is responsive
i3pm daemon status

# View recent daemon events for errors
i3pm daemon events --limit=20

# Restart daemon if hung
systemctl --user restart i3-project-event-listener
```

### Terminal State Issues

**Symptom**: Cursor missing, terminal garbled, or raw mode stuck after Ctrl+C

If terminal state is corrupted after exiting live TUI:

```bash
# Restore terminal (preferred)
reset

# Or restore specific settings
echo -e "\x1b[?25h"  # Show cursor
echo -e "\x1b[?1049l"  # Exit alternate screen
stty sane             # Restore terminal settings

# Restart shell if needed
exec $SHELL
```

### Binary Not Found After Rebuild

**Symptom**: `command not found: i3pm` after `nixos-rebuild`

```bash
# Verify binary is in PATH
which i3pm

# Check if home-manager module is loaded
home-manager packages | grep i3pm

# Rebuild explicitly
sudo nixos-rebuild switch --flake .#<hostname>

# Or rebuild home-manager only
home-manager switch --flake .#<user>@<hostname>
```

### Common Errors

| Error | Cause | Solution |
|-------|-------|----------|
| `Failed to connect to daemon` | Daemon not running | `systemctl --user start i3-project-event-listener` |
| `Socket not found` | XDG_RUNTIME_DIR not set | Check environment variables |
| `Permission denied` | Socket file permissions | Check file ownership: `ls -l $XDG_RUNTIME_DIR/i3-project-daemon/` |
| `Request timeout` | Daemon hung or slow | Restart daemon |
| `Project not found` | Typo in project name | Run `i3pm project list` to see valid names |
| `Validation error` | Daemon protocol mismatch | Ensure daemon and CLI versions are compatible |

## References

- **Full Specification**: `/etc/nixos/specs/027-update-the-spec/spec.md`
- **Data Model**: `/etc/nixos/specs/027-update-the-spec/data-model.md`
- **API Contract**: `/etc/nixos/specs/027-update-the-spec/contracts/json-rpc-api.md`
- **Quick Start**: `/etc/nixos/specs/027-update-the-spec/quickstart.md`
- **Constitution**: `/etc/nixos/.specify/memory/constitution.md` (Principle XIII)

## License

MIT

## Version History

### 2.0.0 (2025-10-22)
- Complete TypeScript/Deno rewrite
- Replaces Python CLI with compiled binary
- Extensible parent command architecture
- Real-time event subscriptions
- Comprehensive type safety with Zod validation
