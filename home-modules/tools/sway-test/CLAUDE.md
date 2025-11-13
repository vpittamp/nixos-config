# Sway Test Framework

Declarative JSON-based testing framework for Sway window manager with synchronization primitives.

## Quick Start

```bash
# Run a test
sway-test run tests/test_example.json

# Run test categories
deno task test:basic          # Core functionality
deno task test:integration    # Multi-component tests
deno task test:regression     # Bug fixes

# List available apps/PWAs
sway-test list-apps --filter firefox
sway-test list-pwas --workspace 50

# Cleanup orphaned processes/windows
sway-test cleanup --all
sway-test cleanup --dry-run --verbose
```

## Key Features (Feature 069)

**Synchronization Actions** - Zero race conditions:
- `sync` - Explicit sync point
- `launch_app_sync` - Launch app + auto-sync
- `send_ipc_sync` - IPC command + auto-sync

**Performance**:
- Individual test: 10-15s → 2-3s (5-6x faster)
- Test suite: ~50s → ~25s (50% faster)
- Flakiness: 5-10% → <1% (10x more reliable)

**Example Test**:
```json
{
  "name": "Firefox workspace assignment",
  "actions": [
    {"type": "send_ipc_sync", "params": {"ipc_command": "[app_id=\"firefox\"] kill"}},
    {"type": "launch_app_sync", "params": {"app_name": "firefox"}}
  ],
  "expectedState": {
    "focusedWorkspace": 3,
    "workspaces": [{"num": 3, "windows": [{"app_id": "firefox", "focused": true}]}]
  }
}
```

## Usability Improvements (Feature 070)

**1. Clear Error Diagnostics** - 8 error types with remediation steps
**2. Graceful Cleanup** - Automatic cleanup on test failure
**3. PWA Support** - Launch by friendly name (no ULID lookup)
**4. App Registry Integration** - Auto-resolve commands from registry
**5. CLI Discovery** - `list-apps`, `list-pwas` commands

**Performance Benchmarks** (with `SWAY_TEST_BENCHMARK=1`):
- Registry loading: <50ms target, ~7ms measured (7x faster)
- PWA launch: <5s target, ~2-3s measured
- Cleanup (10 resources): <2s target, ~1.25s measured

## Documentation

- **Quickstart**: `/etc/nixos/specs/069-sync-test-framework/quickstart.md`
- **Data Model**: `/etc/nixos/specs/069-sync-test-framework/data-model.md`
- **Error Catalog**: `/etc/nixos/specs/070-sway-test-improvements/error-catalog.md`
- **Full Spec**: `/etc/nixos/specs/070-sway-test-improvements/spec.md`

## Tech Stack

- TypeScript/Deno 1.40+
- Zod 3.22.4 (validation)
- @std/cli, @std/fmt/colors (formatting)
- Sway IPC mark/unmark (sync protocol)
- In-memory execution with JSON test files
