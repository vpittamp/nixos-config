# Quick Start: Sway Test Framework Usability Improvements

**Feature**: 070-sway-test-improvements
**Status**: Implementation Planning Complete
**Prerequisites**: Feature 069 (Sync Test Framework), firefoxpwa installed

## What's New

Feature 070 enhances the sway-test framework with five developer experience improvements:

1. **🔍 Clear Error Diagnostics** - Structured errors with remediation steps
2. **🧹 Graceful Cleanup** - Automatic process/window cleanup + manual CLI command
3. **📱 PWA Support** - First-class Progressive Web App testing
4. **📦 Registry Integration** - Name-based app launches with metadata
5. **📋 CLI Discovery** - List available apps and PWAs

## Installation

Feature 070 is integrated into the sway-test framework (NixOS module):

```bash
# Rebuild to include latest sway-test version
sudo nixos-rebuild switch --flake .#hetzner-sway

# Verify installation
sway-test --version
```

## 5-Minute Tutorial

### 1. List Available Applications

Discover what apps are available for testing:

```bash
# List all applications
sway-test list-apps

# Filter by name
sway-test list-apps firefox

# Filter by workspace
sway-test list-apps --workspace 3

# JSON output for scripting
sway-test list-apps --json > apps.json
```

**Output Example**:
```
NAME          COMMAND        WORKSPACE  MONITOR     SCOPE
firefox       firefox        3          secondary   global
code          code           2          primary     scoped
alacritty     alacritty      1          primary     global

50 applications found
```

### 2. List Available PWAs

Discover what PWAs are available for testing:

```bash
# List all PWAs
sway-test list-pwas

# Filter by name
sway-test list-pwas youtube

# Show full URLs
sway-test list-pwas --verbose

# Lookup by ULID
sway-test list-pwas --ulid 01K666N2V6BQMDSBMX3AY74TY7
```

**Output Example**:
```
NAME      URL                      ULID                       WORKSPACE  MONITOR
youtube   https://www.youtube.com  01K666N2V6BQMDSBMX3AY74TY7  50         tertiary
claude    https://claude.ai        01JCYF8Z2VQRST123456789ABC  52         tertiary

15 PWAs found
```

### 3. Write PWA Test

Create a test using friendly PWA names:

```json
{
  "name": "YouTube PWA launches on workspace 50",
  "actions": [
    {
      "type": "launch_pwa_sync",
      "params": {
        "pwa_name": "youtube"
      }
    }
  ],
  "expectedState": {
    "focusedWorkspace": 50,
    "windowCount": 1
  }
}
```

**Run the test**:
```bash
sway-test run tests/test_youtube_pwa.json
```

### 4. Handle Errors Gracefully

When tests fail, you get clear error messages:

**Example Error** (PWA not found):
```
❌ PWA_NOT_FOUND: PWA "youtube" not found in registry

Context:
  pwa_name: youtube
  registry_path: ~/.config/i3/pwa-registry.json
  available_pwas: ["claude", "github", "youtube-music"]

Suggested fixes:
  1. Check PWA name spelling (case-sensitive)
  2. List available PWAs: sway-test list-pwas
  3. Verify registry file: cat ~/.config/i3/pwa-registry.json
```

**Example Error** (Invalid ULID):
```
❌ INVALID_ULID: Invalid ULID format

Context:
  provided_ulid: "01K666N2V6BQMDSBMX3AY74TY7-INVALID"
  ulid_length: 33
  expected_length: 26

Suggested fixes:
  1. ULID must be exactly 26 characters
  2. Valid characters: 0-9, A-Z (excluding I, L, O, U)
  3. Example valid ULID: 01K666N2V6BQMDSBMX3AY74TY7
```

### 5. Manual Cleanup

After interrupted tests, clean up orphaned processes/windows:

```bash
# Clean up everything
sway-test cleanup

# Dry run to see what would be cleaned
sway-test cleanup --dry-run --verbose

# Clean up specific window markers
sway-test cleanup --markers test_firefox_123,test_alacritty_456

# JSON output for scripting
sway-test cleanup --json > cleanup-report.json
```

**Output Example**:
```
🧹 Cleaning up test state...

Processes:
  ✓ Terminated PID 12345 (firefox) - SIGTERM in 450ms
  ✓ Terminated PID 12346 (firefoxpwa) - SIGTERM in 380ms

Windows:
  ✓ Closed test_firefox_123 (workspace 3) in 120ms

Summary: 2 processes, 1 window cleaned in 1.25s
Success rate: 100%
```

## Common Use Cases

### Test PWA Launch by Name

**Before (manual ULID lookup)**:
```json
{
  "type": "launch_pwa_sync",
  "params": {
    "pwa_ulid": "01K666N2V6BQMDSBMX3AY74TY7"
  }
}
```

**After (friendly name)**:
```json
{
  "type": "launch_pwa_sync",
  "params": {
    "pwa_name": "youtube"
  }
}
```

### Test App Launch by Name

**With registry integration**:
```json
{
  "type": "launch_app_sync",
  "params": {
    "app_name": "firefox"
  }
}
```

The framework automatically resolves:
- Command: `firefox`
- Expected class: `firefox`
- Workspace: `3`
- Monitor role: `secondary`

### Allow Failures in Tests

For optional PWA launches:

```json
{
  "type": "launch_pwa_sync",
  "params": {
    "pwa_name": "experimental-pwa",
    "allow_failure": true
  }
}
```

Test continues even if PWA launch fails.

### Filter Tests by Workspace

```bash
# List all apps on workspace 3
sway-test list-apps --workspace 3

# Then write tests for those specific apps
```

## Troubleshooting

### Registry File Not Found

**Error**:
```
❌ REGISTRY_ERROR: PWA registry file not found
```

**Fix**:
```bash
# Rebuild NixOS config to generate registry
sudo nixos-rebuild switch --flake .#hetzner-sway

# Verify file exists
cat ~/.config/i3/pwa-registry.json
```

### firefoxpwa Command Not Found

**Error**:
```
❌ LAUNCH_FAILED: firefoxpwa command not found
```

**Fix**:
```bash
# Verify firefoxpwa installation
which firefoxpwa

# If missing, add to NixOS configuration:
# environment.systemPackages = [ pkgs.firefoxpwa ];

# Then rebuild
sudo nixos-rebuild switch
```

### Cleanup Fails to Terminate Process

**Warning**:
```
⚠️  Process did not respond to SIGTERM within 500ms timeout, force-killed
```

This is expected for processes that don't handle SIGTERM gracefully. The cleanup manager automatically escalates to SIGKILL.

### Invalid ULID Format

**Error**:
```
❌ INVALID_ULID: Invalid ULID format
```

**Fix**:
- ULIDs must be exactly 26 characters
- Valid characters: `0-9`, `A-Z` (excluding `I`, `L`, `O`, `U`)
- Get correct ULID: `sway-test list-pwas`

## Performance Targets

| Operation | Target | Measured |
|-----------|--------|----------|
| Registry loading | <50ms | ~7ms (both registries) |
| PWA launch | <5s | ~2-3s |
| Cleanup (10 resources) | <2s | ~1.25s |
| Error formatting | <10ms | ~2ms |

### Enable Benchmarking

Track performance of registry loading and cleanup operations:

```bash
# Run any command with benchmarking enabled
SWAY_TEST_BENCHMARK=1 sway-test list-apps
SWAY_TEST_BENCHMARK=1 sway-test cleanup

# Example output:
# [BENCHMARK] App registry load breakdown:
#   - File read: 1.23ms
#   - JSON parse: 0.45ms
#   - Validation: 2.10ms
#   - Map conversion: 0.18ms
#   - TOTAL: 3.96ms (target: <50ms)
#   - Apps loaded: 22
```

## Advanced Features

### JSON Output for Scripting

All commands support `--json` for machine-readable output:

```bash
# Export apps to JSON
sway-test list-apps --json > apps.json

# Parse with jq
sway-test list-apps --json | jq '.applications[] | select(.workspace == 3)'

# Export cleanup report
sway-test cleanup --json | jq '.summary.success_rate'
```

### CSV Export for Spreadsheets

```bash
# Export to CSV
sway-test list-apps --format csv > apps.csv
sway-test list-pwas --format csv > pwas.csv

# Open in spreadsheet software
```

### Verbose Output

```bash
# Show all app metadata
sway-test list-apps --verbose

# Show full PWA URLs
sway-test list-pwas --verbose

# Show detailed cleanup progress
sway-test cleanup --verbose
```

### Dry Run Cleanup

Test cleanup without actually terminating processes:

```bash
# See what would be cleaned
sway-test cleanup --dry-run --verbose
```

## Next Steps

- **Write tests**: See `tests/sway-tests/` for examples
- **Custom registries**: Edit `app-registry-data.nix` and `pwa-sites.nix`
- **CI/CD integration**: Use `--json` output for automated reporting
- **Error catalog**: See `contracts/error-format.schema.json` for all error types

## Help & Documentation

```bash
# General help
sway-test --help

# Command-specific help
sway-test cleanup --help
sway-test list-apps --help
sway-test list-pwas --help

# View version
sway-test --version
```

## See Also

- **Feature 069**: Sync Test Framework (foundation)
- **Constitution Principle XV**: Sway Test Framework Standards
- **data-model.md**: Complete data structure reference
- **contracts/**: API contracts and schemas
- **tests/**: Example test cases

---

**Last Updated**: 2025-11-10
**Implementation Status**: ✅ **COMPLETE** - All phases implemented and tested
