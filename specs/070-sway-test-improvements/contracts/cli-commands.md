# CLI Command Contracts

**Feature**: 070-sway-test-improvements
**Purpose**: Define command-line interface for sway-test framework
**Status**: Phase 1 - Contract Definition

## Overview

This document specifies the command-line interface for Feature 070's three new commands: `cleanup`, `list-apps`, and `list-pwas`. All commands follow Constitution Principle XIII (Deno CLI Development Standards).

## Command: `sway-test cleanup`

**Purpose**: Manually clean up test state (processes and windows) from interrupted or failed test sessions (FR-007, FR-010)

### Syntax

```bash
sway-test cleanup [options]
```

### Options

| Option | Short | Type | Default | Description |
|--------|-------|------|---------|-------------|
| `--all` | `-a` | boolean | `true` | Clean up both processes and windows |
| `--processes` | `-p` | boolean | `false` | Clean up processes only |
| `--windows` | `-w` | boolean | `false` | Clean up windows only |
| `--markers` | `-m` | string[] | `[]` | Specific window markers to clean (comma-separated) |
| `--pids` | | number[] | `[]` | Specific PIDs to terminate (comma-separated) |
| `--timeout` | `-t` | number | `500` | Graceful termination timeout in milliseconds |
| `--force` | `-f` | boolean | `false` | Skip graceful termination, force-kill immediately |
| `--json` | | boolean | `false` | Output CleanupReport as JSON |
| `--verbose` | `-v` | boolean | `false` | Show detailed cleanup progress |
| `--dry-run` | | boolean | `false` | Show what would be cleaned without executing |

### Examples

```bash
# Clean up everything (default)
sway-test cleanup

# Clean up windows only
sway-test cleanup --windows

# Clean up specific window markers
sway-test cleanup --markers test_firefox_123,test_alacritty_456

# Clean up processes only with immediate force-kill
sway-test cleanup --processes --force

# Dry run to see what would be cleaned
sway-test cleanup --dry-run --verbose

# JSON output for scripting
sway-test cleanup --json > cleanup-report.json
```

### Exit Codes

| Code | Meaning |
|------|---------|
| `0` | Cleanup completed successfully (100% success rate) |
| `1` | Partial cleanup (some resources failed to clean) |
| `2` | Complete cleanup failure (no resources cleaned) |
| `3` | Invalid arguments or configuration error |

### Output Format

**Default (Human-Readable)**:
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

**JSON Format (--json)**:
See `cleanup-report.schema.json` for complete schema.

## Command: `sway-test list-apps`

**Purpose**: Display all applications from app registry with metadata (FR-021, FR-024, FR-023, FR-025)

### Syntax

```bash
sway-test list-apps [options] [filter]
```

### Arguments

| Argument | Type | Optional | Description |
|----------|------|----------|-------------|
| `filter` | string | yes | Filter pattern (fuzzy match on app name or command) |

### Options

| Option | Short | Type | Default | Description |
|--------|-------|------|---------|-------------|
| `--json` | | boolean | `false` | Output JSON instead of table |
| `--format` | `-f` | string | `table` | Output format: `table`, `json`, `csv` |
| `--workspace` | `-w` | number | | Filter by preferred workspace number |
| `--monitor` | `-m` | string | | Filter by monitor role: `primary`, `secondary`, `tertiary` |
| `--scope` | `-s` | string | | Filter by scope: `global`, `scoped` |
| `--verbose` | `-v` | boolean | `false` | Include all metadata (description, icon, nix_package) |

### Examples

```bash
# List all applications (table format)
sway-test list-apps

# Filter by name pattern
sway-test list-apps firefox

# Filter by workspace
sway-test list-apps --workspace 3

# Filter by monitor role
sway-test list-apps --monitor primary

# Filter by scope
sway-test list-apps --scope global

# JSON output for scripting
sway-test list-apps --json > apps.json

# CSV output for spreadsheets
sway-test list-apps --format csv > apps.csv

# Verbose output with all metadata
sway-test list-apps --verbose firefox
```

### Exit Codes

| Code | Meaning |
|------|---------|
| `0` | Success (applications listed) |
| `1` | Registry file not found or invalid |
| `2` | No applications match filter criteria |

### Output Format

**Default (Table)**:
```
NAME          COMMAND               WORKSPACE  MONITOR     SCOPE
firefox       firefox               3          secondary   global
code          code                  2          primary     scoped
alacritty     alacritty             1          primary     global
youtube-pwa   firefoxpwa site ...   50         tertiary    global

50 applications found
```

**Verbose Table**:
```
NAME          COMMAND        WORKSPACE  MONITOR     SCOPE    DESCRIPTION               NIX_PACKAGE
firefox       firefox        3          secondary   global   Web Browser               firefox
code          code           2          primary     scoped   VS Code Editor            vscode
alacritty     alacritty      1          primary     global   Terminal Emulator         alacritty

3 applications found
```

**JSON Format (--json)**:
```json
{
  "version": "1.0.0",
  "count": 50,
  "applications": [
    {
      "name": "firefox",
      "display_name": "Firefox",
      "command": "firefox",
      "preferred_workspace": 3,
      "preferred_monitor_role": "secondary",
      "scope": "global",
      "expected_class": "firefox",
      "description": "Web Browser",
      "nix_package": "firefox"
    }
  ]
}
```

**CSV Format (--format csv)**:
```csv
name,display_name,command,workspace,monitor,scope
firefox,Firefox,firefox,3,secondary,global
code,VS Code,code,2,primary,scoped
```

## Command: `sway-test list-pwas`

**Purpose**: Display all PWAs from PWA registry with metadata (FR-022, FR-024, FR-023, FR-025)

### Syntax

```bash
sway-test list-pwas [options] [filter]
```

### Arguments

| Argument | Type | Optional | Description |
|----------|------|----------|-------------|
| `filter` | string | yes | Filter pattern (fuzzy match on PWA name or URL) |

### Options

| Option | Short | Type | Default | Description |
|--------|-------|------|---------|-------------|
| `--json` | | boolean | `false` | Output JSON instead of table |
| `--format` | `-f` | string | `table` | Output format: `table`, `json`, `csv` |
| `--workspace` | `-w` | number | | Filter by preferred workspace number |
| `--monitor` | `-m` | string | | Filter by monitor role: `primary`, `secondary`, `tertiary` |
| `--verbose` | `-v` | boolean | `false` | Show full URLs (truncated by default) |
| `--ulid` | `-u` | string | | Filter by specific ULID |

### Examples

```bash
# List all PWAs (table format)
sway-test list-pwas

# Filter by name pattern
sway-test list-pwas youtube

# Filter by workspace
sway-test list-pwas --workspace 50

# Filter by monitor role
sway-test list-pwas --monitor tertiary

# Show full URLs
sway-test list-pwas --verbose

# Lookup PWA by ULID
sway-test list-pwas --ulid 01K666N2V6BQMDSBMX3AY74TY7

# JSON output for scripting
sway-test list-pwas --json > pwas.json
```

### Exit Codes

| Code | Meaning |
|------|---------|
| `0` | Success (PWAs listed) |
| `1` | Registry file not found or invalid |
| `2` | No PWAs match filter criteria |
| `3` | Invalid ULID format provided |

### Output Format

**Default (Table)**:
```
NAME           URL                              ULID                       WORKSPACE  MONITOR
youtube        https://www.youtube.com          01K666N2V6BQMDSBMX3AY74TY7  50         tertiary
claude         https://claude.ai                01JCYF8Z2VQRST123456789ABC  52         tertiary
github         https://github.com               01ABCDEFGHJKMNPQRSTVWXYZ01  3          secondary

15 PWAs found
```

**Verbose Table (--verbose)**:
```
NAME           URL                                      ULID                       WORKSPACE  MONITOR
youtube        https://www.youtube.com                  01K666N2V6BQMDSBMX3AY74TY7  50         tertiary
claude         https://claude.ai                        01JCYF8Z2VQRST123456789ABC  52         tertiary
github         https://github.com                       01ABCDEFGHJKMNPQRSTVWXYZ01  3          secondary

3 PWAs found
```

**JSON Format (--json)**:
```json
{
  "version": "1.0.0",
  "count": 15,
  "pwas": [
    {
      "name": "youtube",
      "url": "https://www.youtube.com",
      "ulid": "01K666N2V6BQMDSBMX3AY74TY7",
      "preferred_workspace": 50,
      "preferred_monitor_role": "tertiary"
    }
  ]
}
```

**CSV Format (--format csv)**:
```csv
name,url,ulid,workspace,monitor
youtube,https://www.youtube.com,01K666N2V6BQMDSBMX3AY74TY7,50,tertiary
claude,https://claude.ai,01JCYF8Z2VQRST123456789ABC,52,tertiary
```

## Global Options

All commands support these global options:

| Option | Short | Type | Default | Description |
|--------|-------|------|---------|-------------|
| `--help` | `-h` | boolean | `false` | Show command help |
| `--version` | | boolean | `false` | Show sway-test version |
| `--config` | `-c` | string | `~/.config/sway-test/config.json` | Path to config file |
| `--registry-path` | | string | `~/.config/i3/` | Path to registry directory |

## Error Handling

All commands follow StructuredError format (see `error-format.schema.json`):

**Registry Missing**:
```
❌ REGISTRY_ERROR: PWA registry file not found

Context:
  registry_path: ~/.config/i3/pwa-registry.json

Suggested fixes:
  1. Rebuild NixOS config: sudo nixos-rebuild switch
  2. Verify file exists: cat ~/.config/i3/pwa-registry.json
  3. Check app-registry.nix configuration
```

**Invalid Arguments**:
```
❌ MALFORMED_TEST: Invalid argument combination

Context:
  provided_args: --processes --windows

Suggested fixes:
  1. Use --all for both, or specify one: --processes OR --windows
  2. See help: sway-test cleanup --help
```

## Implementation Requirements

1. **Argument Parsing**: Use `@std/cli/parse-args` (Constitution Principle XIII)
2. **Table Formatting**: Use `@std/cli/unicode-width` for column alignment
3. **JSON Output**: Use native `JSON.stringify()` with proper formatting
4. **CSV Output**: Use `@std/csv` for RFC 4180 compliant CSV generation
5. **Error Handling**: All errors must use StructuredError format
6. **Exit Codes**: Must match documented exit codes for scripting compatibility

## Testing Requirements

Each command must have:
1. Unit tests for argument parsing
2. Integration tests with mock registries
3. Error scenario tests (missing registry, invalid args)
4. Output format tests (table, JSON, CSV)
5. Exit code verification tests

See `tests/cli/` for test implementations.
