# Sway Test Framework

Test-driven development framework for Sway window manager system testing. Enables comparison of expected vs actual system state from `swaymsg tree` output.

## Features

- **State Comparison**: Compare expected vs actual Sway window tree states with clear diff output
- **Action Sequences**: Execute multi-step workflows (launch apps, send IPC commands, simulate keybindings)
- **Tree-Monitor Integration**: Leverage existing `sway-tree-monitor` daemon for event capture and diagnostics
- **Interactive Debugging**: Pause test execution, inspect state, modify tests on the fly
- **I3_SYNC-Style Synchronization**: Deterministic test execution with 0% flakiness
- **CI/CD Ready**: Headless mode support for GitHub Actions, GitLab CI, Docker
- **Test Organization**: Fixtures, suites, and reusable helpers for maintainable test codebases

## Quick Start

### Installation

```bash
# Build Deno CLI executable
cd /etc/nixos/home-modules/tools/sway-test
deno task compile

# Run tests
./sway-test run tests/sway-tests/basic/
```

### Writing Your First Test

Create a test definition file `test_window_launch.json`:

```json
{
  "name": "Launch window and verify state",
  "description": "Test that launching Alacritty creates a window on workspace 1",
  "actions": [
    {
      "type": "launch_app",
      "params": { "command": "alacritty" }
    }
  ],
  "expectedState": {
    "workspaces": [
      {
        "num": 1,
        "windows": [
          { "app_id": "Alacritty" }
        ]
      }
    ]
  }
}
```

Run the test:

```bash
./sway-test run test_window_launch.json
```

## Architecture

- **CLI (Deno/TypeScript)**: User-facing test runner, state comparison, reporting
- **Daemon Enhancements (Python)**: sway-tree-monitor extensions for sync markers and test-scoped event filtering
- **Test Definitions (JSON)**: Declarative test cases with actions and expected states

## Documentation

- `docs/quickstart.md` - Quick start guide with examples
- `docs/api-reference.md` - Complete API documentation
- `/etc/nixos/specs/001-test-driven-development/` - Design docs, architecture, research

## Development

```bash
# Run in development mode with auto-reload
deno task dev

# Run unit tests
deno task test

# Format code
deno task fmt

# Lint code
deno task lint

# Type check
deno task check
```

## Requirements

- Deno 1.40+
- Sway window manager
- sway-tree-monitor daemon (for event diagnostics)

## License

Part of the NixOS configuration at `/etc/nixos/`
