# NixOS Build Status Tracking System

**Version:** 1.0.0
**Date:** 2025-11-14

## Overview

Comprehensive build status tracking system for NixOS and Home Manager that provides:

- **Structured build status** (JSON + human-readable)
- **Build success/failure detection**
- **Generation tracking** with metadata
- **Error extraction and reporting**
- **Home Manager activation status**
- **Integration with nh and nom** for better visualization
- **Automated testing support**

## Components

### 1. `nixos-build-status`

Main status checking tool that reports current system state.

**Features:**
- Current and latest generation numbers
- Git commit information
- Home Manager generation tracking
- Build error detection
- Boot/systemd status checks
- Flake evaluation status

**Usage:**
```bash
# Human-readable output
nixos-build-status

# JSON output for automation
nixos-build-status --json

# Verbose mode with details
nixos-build-status --verbose

# Integration example
if nixos-build-status --json | jq -e '.overallStatus == "success"'; then
  echo "System is healthy"
fi
```

**Output Formats:**

**Human-readable:**
```
=== NixOS Build Status ===

Generation Information:
Current generation: g42
Latest generation:  g42
Status:             in-sync
Home Manager user:  vpittamp
HM generation:      hm12
HM status:          in-sync
Commit:             3f4851e
...

Build Error Check:
✓ No recent build errors detected

Boot Status:
✓ All systemd units started successfully

Flake Status:
✓ Flake can be evaluated

=== Summary ===
✓ System is healthy
```

**JSON:**
```json
{
  "timestamp": "2025-11-14T15:30:00+00:00",
  "hostname": "nixos-hetzner-sway",
  "generation": {
    "generation": "g42",
    "generationRaw": "42",
    "latestGeneration": "g42",
    "status": "in-sync",
    "commit": "3f4851e",
    "homeManagerGeneration": "hm12",
    "homeManagerStatus": "in-sync"
  },
  "buildErrors": {
    "errorCount": 0,
    "errors": []
  },
  "bootStatus": {
    "bootFailed": false,
    "failedUnits": ""
  },
  "buildability": {
    "canBuild": true,
    "buildError": ""
  },
  "overallStatus": "success",
  "exitCode": 0
}
```

**Exit Codes:**
- `0` - System in sync, no issues
- `1` - Out of sync (system or home-manager)
- `2` - Build errors detected
- `3` - Invalid arguments

### 2. `nixos-build-wrapper`

Wrapper for `nh`/`nixos-rebuild` that captures build output and generates structured logs.

**Features:**
- Uses `nh` with `nom` integration for better visualization
- Captures all build output
- Generates JSON build logs
- Tracks generation changes
- Records build history
- Provides error extraction

**Usage:**
```bash
# Standard system rebuild (uses nh if available)
nixos-build-wrapper os switch

# Home Manager activation
nixos-build-wrapper home switch

# Dry run
nixos-build-wrapper os dry-build

# Build without activation
nixos-build-wrapper os build

# Use specific flake
nixos-build-wrapper os switch --flake ~/nixos-config

# Pass extra arguments
nixos-build-wrapper os switch -- --verbose --show-trace

# Force traditional nixos-rebuild
nixos-build-wrapper os switch --no-nh

# JSON output only
nixos-build-wrapper os switch --json
```

**Generated Files:**
- `/var/log/nixos-builds/last-build.json` - Latest build metadata
- `/var/log/nixos-builds/last-build.log` - Full build output
- `/var/log/nixos-builds/build-history.json` - Last 100 builds

**Build Log Structure:**
```json
{
  "buildStart": "2025-11-14T15:30:00+00:00",
  "buildEnd": "2025-11-14T15:32:15+00:00",
  "buildDuration": 135,
  "target": "os",
  "action": "switch",
  "tool": "nh",
  "flakePath": "/etc/nixos",
  "exitCode": 0,
  "success": true,
  "hostname": "nixos-hetzner-sway",
  "user": "vpittamp",
  "command": "nh os switch",
  "preGeneration": { /* generation info before build */ },
  "postGeneration": { /* generation info after build */ },
  "buildLogPath": "/var/log/nixos-builds/last-build.log",
  "errors": ""
}
```

### 3. `lib/build-status.sh`

Reusable bash library for build status functions.

**Usage:**
```bash
# Source the library
source /etc/nixos/lib/build-status.sh

# Use the functions
current_gen=$(get_current_generation)
is_in_sync=$(is_generation_in_sync && echo "yes" || echo "no")
last_build=$(get_last_build_status)

# Create status report
create_status_report json > status.json
create_status_report human
```

**Available Functions:**

**JSON Helpers:**
- `json_escape <string>` - Escape string for JSON
- `json_bool <value>` - Convert to JSON boolean

**Generation Info:**
- `get_current_generation` - Get current generation number
- `get_current_generation_json` - Get full generation info as JSON
- `get_generation_short` - Get short generation string
- `is_generation_in_sync` - Check if in sync (returns 0/1)

**Build Log Helpers:**
- `get_last_build_status [log_dir]` - Get last build JSON
- `get_last_build_exit_code [log_dir]` - Get exit code
- `was_last_build_successful [log_dir]` - Check success (returns 0/1)
- `get_build_history [log_dir]` - Get build history JSON
- `get_build_history_summary [log_dir] [count]` - Get summary

**Error Extraction:**
- `extract_nix_errors <log_file>` - Extract error messages
- `extract_build_phase <log_file>` - Extract last build phase

**System Health:**
- `check_failed_units` - Get failed systemd units as JSON array
- `check_journal_errors [since]` - Count journal errors

**Metadata:**
- `get_current_commit` - Get current config commit
- `get_current_nixpkgs_rev` - Get nixpkgs revision
- `get_home_manager_generation` - Get HM generation

**Reporting:**
- `create_status_report [format]` - Create full status report

## Integration with nh and nom

The system integrates with:

**nh (Nix Helper):**
- Modern CLI tool that wraps nix commands
- Provides better ergonomics
- Automatic nom integration
- Controlled via `NH_OS_FLAKE` and `NH_HOME_FLAKE` env vars

**nom (nix-output-monitor):**
- Better build visualization with tree view
- Shows build phases
- Progress indicators
- Controlled via `NH_NOM` env var

**Automatic detection:**
- Wrapper automatically uses `nh` if available
- Falls back to `nixos-rebuild` if not
- Uses `nom` when available for better output

## Automated Testing Integration

### Example: CI/CD Pipeline

```bash
#!/usr/bin/env bash
# CI/CD build verification script

set -euo pipefail

echo "Building NixOS configuration..."
if nixos-build-wrapper os build --json > build-result.json; then
  echo "✓ Build succeeded"

  # Check if everything is healthy
  if nixos-build-status --json | jq -e '.overallStatus == "success"'; then
    echo "✓ System is healthy"
    exit 0
  else
    echo "✗ System has issues"
    nixos-build-status --verbose
    exit 1
  fi
else
  echo "✗ Build failed"

  # Extract errors
  jq -r '.errors' build-result.json

  # Show error details
  cat /var/log/nixos-builds/last-build.log

  exit 2
fi
```

### Example: Automated Debugging Workflow

```bash
#!/usr/bin/env bash
# Auto-debug build failures and send to LLM

source /etc/nixos/lib/build-status.sh

# Run build
if ! nixos-build-wrapper os switch --json > build.json; then
  echo "Build failed, collecting diagnostics..."

  # Collect comprehensive error context
  {
    echo "=== Build Status ==="
    create_status_report json

    echo "=== Build Log ==="
    cat /var/log/nixos-builds/last-build.log

    echo "=== Nix Errors ==="
    extract_nix_errors /var/log/nixos-builds/last-build.log

    echo "=== Failed Units ==="
    check_failed_units

    echo "=== Recent Journal Errors ==="
    journalctl -p err --since "1 hour ago" --no-pager

  } > debug-context.txt

  # Send to LLM for analysis (example)
  # claude-code debug debug-context.txt

  exit 1
fi
```

### Example: Test Framework Integration

```bash
#!/usr/bin/env bash
# NixOS configuration test suite

source /etc/nixos/lib/build-status.sh

run_test() {
  local test_name="$1"
  shift
  local test_cmd=("$@")

  echo "Running test: $test_name"
  if "${test_cmd[@]}"; then
    echo "✓ $test_name passed"
    return 0
  else
    echo "✗ $test_name failed"
    return 1
  fi
}

# Test 1: Configuration builds
run_test "Configuration builds" \
  nixos-build-wrapper os build --no-nh

# Test 2: System is in sync
run_test "System in sync" \
  is_generation_in_sync

# Test 3: No failed units
run_test "No failed systemd units" \
  bash -c '[[ $(check_failed_units | jq "length") -eq 0 ]]'

# Test 4: Flake evaluates
run_test "Flake evaluates" \
  nix flake show /etc/nixos --no-write-lock-file

# Test 5: Home Manager builds
run_test "Home Manager builds" \
  nixos-build-wrapper home build

echo "All tests passed!"
```

## Best Practices

### 1. Regular Status Checks

Add to your shell profile:
```bash
# ~/.bashrc or ~/.zshrc
alias status='nixos-build-status'
alias build='nixos-build-wrapper os switch'
alias build-home='nixos-build-wrapper home switch'
```

### 2. Pre-Commit Hooks

```bash
#!/usr/bin/env bash
# .git/hooks/pre-push

echo "Verifying NixOS configuration builds..."
if ! nixos-build-wrapper os dry-build --json > /tmp/build-check.json; then
  echo "Configuration doesn't build! Aborting push."
  jq -r '.errors' /tmp/build-check.json
  exit 1
fi
```

### 3. Monitoring Integration

```bash
#!/usr/bin/env bash
# /etc/cron.hourly/nixos-health-check

# Check system health and alert if issues
if ! nixos-build-status --json | jq -e '.overallStatus == "success"' > /dev/null; then
  # Send alert (email, webhook, etc.)
  nixos-build-status --json | \
    curl -X POST https://monitoring.example.com/alerts \
      -H "Content-Type: application/json" \
      -d @-
fi
```

## Troubleshooting

### Issue: Build logs not being saved

**Solution:**
```bash
# Ensure log directory exists and is writable
sudo mkdir -p /var/log/nixos-builds
sudo chmod 755 /var/log/nixos-builds
```

### Issue: Permission denied errors

**Solution:**
```bash
# Run with sudo for system builds
sudo nixos-build-wrapper os switch

# Or use nh directly (handles sudo automatically)
nh os switch
```

### Issue: JSON parsing errors

**Solution:**
```bash
# Verify JSON output is valid
nixos-build-status --json | jq .

# If errors, check for missing dependencies
command -v jq || nix-env -iA nixpkgs.jq
```

## Advanced Usage

### Querying Build History

```bash
# Get last 10 builds
jq '.[-10:]' /var/log/nixos-builds/build-history.json

# Find failed builds
jq '.[] | select(.success == false)' /var/log/nixos-builds/build-history.json

# Average build duration
jq '[.[] | .buildDuration] | add / length' /var/log/nixos-builds/build-history.json

# Builds by date
jq '.[] | {date: .buildStart, exitCode: .exitCode}' \
  /var/log/nixos-builds/build-history.json
```

### Custom Status Reports

```bash
# Source the library
source /etc/nixos/lib/build-status.sh

# Create custom report
{
  echo "=== Custom NixOS Status ==="
  echo "Generation: $(get_generation_short)"
  echo "Commit: $(get_current_commit)"
  echo "In Sync: $(is_generation_in_sync && echo 'Yes' || echo 'No')"
  echo "Last Build: $(was_last_build_successful && echo 'Success' || echo 'Failed')"
  echo "Failed Units: $(check_failed_units | jq 'length')"
} > custom-status.txt
```

## See Also

- `nixos-metadata` - View build metadata for any generation
- `nixos-generation-info` - Detailed generation information
- `nh --help` - Nix helper documentation
- `nom --help` - Nix output monitor documentation

## References

- **nh Project:** https://github.com/nix-community/nh
- **nom Project:** https://github.com/maralorn/nix-output-monitor
- **NixOS Manual:** https://nixos.org/manual/nixos/stable/
- **Home Manager Manual:** https://nix-community.github.io/home-manager/

---

**Last Updated:** 2025-11-14
**Maintainer:** NixOS Configuration Team
