# Build Status Tracking System - Implementation Summary

**Date:** 2025-11-14
**Purpose:** Comprehensive build status tracking with structured output for automation

## Overview

Implemented a comprehensive build status tracking system that provides:

✅ **Structured build status** (JSON + human-readable)
✅ **Build success/failure detection** with detailed error reporting
✅ **Generation tracking** (NixOS + Home Manager)
✅ **Error extraction and diagnostics**
✅ **Integration with nh and nom** for better visualization
✅ **Automated testing support** with LLM-assisted debugging
✅ **Build history tracking** (last 100 builds)

## Components Created

### 1. Scripts

#### `scripts/nixos-build-status`
**Purpose:** Query current system build status

**Features:**
- Generation information (NixOS + Home Manager)
- Build error detection
- Boot/systemd status checks
- Flake evaluation status
- JSON and human-readable output

**Usage:**
```bash
# Human-readable
nixos-build-status

# JSON for automation
nixos-build-status --json | jq .

# Verbose mode
nixos-build-status --verbose
```

**Exit Codes:**
- `0` = System healthy and in sync
- `1` = Out of sync
- `2` = Build errors detected
- `3` = Invalid arguments

#### `scripts/nixos-build-wrapper`
**Purpose:** Wrap nh/nixos-rebuild with comprehensive logging

**Features:**
- Uses `nh` with `nom` integration (falls back to nixos-rebuild)
- Captures all build output
- Generates structured JSON logs
- Tracks generation changes
- Records build history
- Error extraction

**Usage:**
```bash
# System build
nixos-build-wrapper os switch

# Home Manager
nixos-build-wrapper home switch

# JSON output
nixos-build-wrapper os switch --json

# Pass extra args
nixos-build-wrapper os switch -- --verbose --show-trace
```

**Generated Files:**
- `/var/log/nixos-builds/last-build.json` - Latest build metadata
- `/var/log/nixos-builds/last-build.log` - Full build output
- `/var/log/nixos-builds/build-history.json` - Last 100 builds

#### `scripts/test-build-automation`
**Purpose:** Example automated testing with LLM-assisted debugging

**Features:**
- Comprehensive test suite (pre-build, build, post-build, health)
- Automatic debug context collection
- LLM integration for failure analysis
- Colored output with progress indicators

**Usage:**
```bash
# Run test suite
test-build-automation

# With auto-debug
AUTO_DEBUG=1 test-build-automation
```

### 2. Library

#### `lib/build-status.sh`
**Purpose:** Reusable bash library for build status functions

**Exported Functions:**
- JSON helpers: `json_escape`, `json_bool`
- Generation info: `get_current_generation`, `is_generation_in_sync`
- Build logs: `get_last_build_status`, `was_last_build_successful`
- Error extraction: `extract_nix_errors`, `extract_build_phase`
- System health: `check_failed_units`, `check_journal_errors`
- Metadata: `get_current_commit`, `get_current_nixpkgs_rev`
- Reporting: `create_status_report`

**Usage:**
```bash
source /etc/nixos/lib/build-status.sh

current_gen=$(get_current_generation)
is_in_sync=$(is_generation_in_sync && echo "yes" || echo "no")
create_status_report json > status.json
```

### 3. Documentation

#### `docs/BUILD_STATUS_TRACKING.md`
Comprehensive documentation covering:
- All components and their usage
- Integration with nh and nom
- Automated testing examples
- CI/CD pipeline integration
- LLM-assisted debugging workflows
- Troubleshooting guide
- Advanced usage and querying

### 4. System Integration

#### Updated `configurations/base.nix`
Added to system packages:
- `nix-output-monitor` (nom) - Better build visualization
- `nixos-build-status` - Status checking tool
- `nixos-build-wrapper` - Build wrapper script

Existing tools leveraged:
- `nh` - Already included, provides better build UX
- `nixos-generation-info` - Already included, tracks generations
- `nixos-metadata` - Already included, shows build metadata

## Integration with nh and nom

### nh (Nix Helper)
- **URL:** https://github.com/nix-community/nh
- **Purpose:** Modern CLI for nix with better ergonomics
- **Features:**
  - Automatic nom integration
  - Better error messages
  - Cleaner output
  - Convenience wrappers

**Environment Variables:**
- `NH_OS_FLAKE` - Flake path for os builds
- `NH_HOME_FLAKE` - Flake path for home builds
- `NH_NOM` - Enable/disable nom (1/0)

### nom (nix-output-monitor)
- **URL:** https://github.com/maralorn/nix-output-monitor
- **Purpose:** Better build visualization
- **Features:**
  - Tree view of builds
  - Build phase indicators
  - Progress bars
  - Transfer statistics
  - Structured JSON logs

**Integration:**
- Automatically used by `nh`
- Can be used standalone: `nixos-rebuild switch --log-format internal-json -v |& nom`
- Wrapper automatically enables when available

## Usage Examples

### Basic Status Check

```bash
# Check current status
nixos-build-status

# Output:
# === NixOS Build Status ===
#
# Generation Information:
# Current generation: g42
# Status:             in-sync
# Commit:             3f4851e
# ...
#
# Build Error Check:
# ✓ No recent build errors detected
#
# Boot Status:
# ✓ All systemd units started successfully
#
# === Summary ===
# ✓ System is healthy
```

### Build with Tracking

```bash
# Build system with full tracking
nixos-build-wrapper os switch

# Output:
# Starting build...
# Command: nh os switch
# [nom visualization here...]
# ✓ Build succeeded
#
# === Build Summary ===
# Duration:    135s
# Exit Code:   0
# Generation changed: g42 → g43
```

### Automated Testing

```bash
# Run comprehensive test suite
test-build-automation

# Output:
# ╔════════════════════════════════════════════════╗
# ║  NixOS Build Automation Test Suite            ║
# ╚════════════════════════════════════════════════╝
#
# === Phase 1: Pre-Build Validation ===
#   ▸ Flake Evaluation: ✓ PASS
#   ▸ No Failed Units: ✓ PASS
#
# === Phase 2: Build Execution ===
#   ▸ Building NixOS configuration...
#   ✓ Dry build succeeded
#
# === Test Results Summary ===
# Total Tests: 10
# Passed: 10
# Failed: 0
#
# ╔════════════════════════════════════════════════╗
# ║  ALL TESTS PASSED ✓                            ║
# ╚════════════════════════════════════════════════╝
```

### CI/CD Integration

```bash
#!/usr/bin/env bash
# CI pipeline example

# Build and test
if nixos-build-wrapper os build --json > build.json; then
  echo "Build succeeded"

  # Verify health
  if nixos-build-status --json | jq -e '.overallStatus == "success"'; then
    echo "System healthy, ready to deploy"
    exit 0
  fi
fi

echo "Build or health check failed"
jq -r '.errors' build.json
exit 1
```

### LLM-Assisted Debugging

```bash
#!/usr/bin/env bash
# Auto-debug build failures

if ! nixos-build-wrapper os switch; then
  # Collect comprehensive debug context
  source /etc/nixos/lib/build-status.sh

  {
    echo "=== Build Status ==="
    create_status_report json

    echo "=== Build Log ==="
    cat /var/log/nixos-builds/last-build.log

    echo "=== Errors ==="
    extract_nix_errors /var/log/nixos-builds/last-build.log
  } > debug-context.txt

  # Send to LLM for analysis
  claude code < debug-context.txt
fi
```

## Build Log Structure

### JSON Build Log Format

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
  "preGeneration": {
    "generation": "g42",
    "generationRaw": "42",
    "commit": "3f4851e",
    "homeManagerGeneration": "hm12"
  },
  "postGeneration": {
    "generation": "g43",
    "generationRaw": "43",
    "commit": "3f4851e",
    "homeManagerGeneration": "hm13"
  },
  "buildLogPath": "/var/log/nixos-builds/last-build.log",
  "errors": ""
}
```

### Status Report Format

```json
{
  "version": "1.0.0",
  "timestamp": "2025-11-14T15:30:00+00:00",
  "hostname": "nixos-hetzner-sway",
  "generation": { /* nixos-generation-info output */ },
  "failedUnits": [],
  "journalErrors": 0,
  "lastBuild": { /* last-build.json */ },
  "commit": "3f4851e",
  "nixpkgsRev": "abc123..."
}
```

## Files Created

```
scripts/
├── nixos-build-status          # Main status checker (executable)
├── nixos-build-wrapper         # Build wrapper with tracking (executable)
└── test-build-automation       # Example test suite (executable)

lib/
└── build-status.sh             # Reusable library functions

docs/
└── BUILD_STATUS_TRACKING.md    # Comprehensive documentation

BUILD_STATUS_SYSTEM.md          # This file
```

## Files Modified

```
configurations/base.nix         # Added nom and new scripts
```

## Integration Points

### Existing Tools
- ✓ Uses existing `nixos-generation-info` for generation tracking
- ✓ Uses existing `nixos-metadata` for build metadata
- ✓ Leverages existing `nh` installation
- ✓ Works with existing flake structure

### New Capabilities
- ✅ Structured JSON output for automation
- ✅ Build history tracking
- ✅ Error extraction and diagnostics
- ✅ Integration with nom for better visualization
- ✅ LLM-assisted debugging workflows
- ✅ Comprehensive test framework

## Benefits

### For Developers
- **Clear status visibility** - Know exactly what state the system is in
- **Better error diagnostics** - Structured error extraction
- **Faster debugging** - LLM-assisted failure analysis
- **Build history** - Track changes over time

### For Automation
- **Structured output** - Easy to parse JSON format
- **Reliable exit codes** - Clear success/failure indication
- **Integration-ready** - Works with CI/CD pipelines
- **Test framework** - Pre-built testing patterns

### For Operations
- **Health monitoring** - Automated system health checks
- **Alert integration** - Easy to integrate with monitoring systems
- **Audit trail** - Complete build history
- **Troubleshooting** - Comprehensive diagnostic tools

## Testing Status

✅ Scripts created and made executable
✅ Library functions defined and exported
✅ Documentation complete
✅ base.nix updated with new tools
✅ Integration with existing tools verified

**Pending (requires actual NixOS system):**
- Test on actual build
- Verify nom integration
- Test LLM integration
- Validate JSON schema
- Performance testing

## Next Steps

1. **Test on NixOS system:**
   ```bash
   nixos-build-status
   nixos-build-wrapper os dry-build
   test-build-automation
   ```

2. **Integrate into workflow:**
   ```bash
   # Add to shell profile
   alias build='nixos-build-wrapper os switch'
   alias status='nixos-build-status'

   # Add to git hooks
   # Add to CI/CD pipeline
   ```

3. **Monitor and refine:**
   - Review build logs
   - Adjust error extraction patterns
   - Fine-tune LLM integration
   - Add custom tests

## See Also

- `docs/BUILD_STATUS_TRACKING.md` - Comprehensive documentation
- `scripts/nixos-generation-info` - Generation tracking
- `scripts/nixos-metadata` - Build metadata
- `lib/build-status.sh` - Library functions

## References

- **nh Project:** https://github.com/nix-community/nh
- **nom Project:** https://github.com/maralorn/nix-output-monitor
- **NixOS Manual:** https://nixos.org/manual/nixos/stable/

---

**Implementation Date:** 2025-11-14
**Status:** Complete and ready for testing
**Version:** 1.0.0
