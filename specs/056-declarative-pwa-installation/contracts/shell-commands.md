# Shell Command Contracts: PWA Helper Scripts

**Feature**: 056-declarative-pwa-installation
**Date**: 2025-11-02
**Version**: 1.0.0

## Overview

This contract defines the command-line interfaces for PWA management helper scripts. These commands are packaged as Nix derivations and made available in user PATH.

---

## pwa-install-all

**Purpose**: Install all declaratively-configured PWAs

**Signature**:
```bash
pwa-install-all [OPTIONS]
```

**Options**: None

**Exit Codes**:
- `0`: All PWAs installed successfully (or already installed)
- `1`: One or more PWAs failed to install (but some may have succeeded)
- `2`: firefoxpwa not available or other system error

**Output Format**:
```
Checking configured PWAs (idempotent operation)...

Currently installed PWAs:
  - YouTube (01HQ1Z9J8G7X2K5MNBVWXYZ013)
  - Google AI (01HQ1Z9J8G7X2K5MNBVWXYZ014)

Installing Gitea...
✓ Gitea - successfully installed

✓ YouTube - already installed
✓ Google AI - already installed

Installation complete:
  - Installed: 1
  - Skipped (already installed): 2
  - Failed: 0
```

**Behavior**:
1. Query currently installed PWAs via `firefoxpwa profile list`
2. For each configured PWA:
   - Check if already installed (by name match)
   - If installed: Print "already installed", increment skipped count
   - If not installed: Attempt installation, print result
3. Print summary of results

**Error Handling**:
- firefoxpwa not found → Exit 2 with error message
- Installation fails for one PWA → Print error, continue with others, exit 1 at end
- Network timeout → Print warning, mark as failed, continue

**Idempotency**: Safe to run multiple times. Already-installed PWAs are skipped.

**Examples**:
```bash
# Install all configured PWAs
pwa-install-all

# Check exit code
pwa-install-all && echo "Success" || echo "Some failures"
```

---

## pwa-list

**Purpose**: List configured and installed PWAs

**Signature**:
```bash
pwa-list [OPTIONS]
```

**Options**: None

**Exit Codes**:
- `0`: Always (informational command)

**Output Format**:
```
Configured PWAs (from pwa-sites.nix):
=====================================
  YouTube
    URL: https://www.youtube.com
    Description: YouTube Video Platform

  Google AI
    URL: https://www.google.com/search?udm=50
    Description: Google AI Search

Installed PWAs (from firefoxpwa):
=================================
  - YouTube (01HQ1Z9J8G7X2K5MNBVWXYZ013)
  - Google AI (01HQ1Z9J8G7X2K5MNBVWXYZ014)
  - Gitea (01HQ1Z9J8G7X2K5MNBVWXYZ015)
```

**Behavior**:
1. Print all configured PWAs from pwa-sites.nix with details
2. Print all installed PWAs from firefoxpwa with ULIDs

**Error Handling**:
- firefoxpwa not available → Print "firefoxpwa not available" in installed section

**Examples**:
```bash
# List all PWAs
pwa-list

# Check if specific PWA is configured
pwa-list | grep "YouTube"
```

---

## pwa-validate

**Purpose**: Validate all configured PWAs are installed

**Signature**:
```bash
pwa-validate [OPTIONS]
```

**Options**: None

**Exit Codes**:
- `0`: All configured PWAs are installed
- `1`: One or more configured PWAs are missing
- `2`: System error (firefoxpwa not available)

**Output Format**:
```
PWA Installation Validation
============================

Expected PWAs (from configuration):

  ✅ YouTube
     URL: https://www.youtube.com

  ✅ Google AI
     URL: https://www.google.com/search?udm=50

  ❌ Gitea - NOT INSTALLED
     URL: https://gitea.cnoe.localtest.me:8443
     Install: Open Firefox → Navigate to URL → Click 'Install' in address bar

==========================================
Summary: 2 installed, 1 missing

To install missing PWAs:
  1. Open Firefox
  2. Navigate to the PWA URL
  3. Click the 'Install' icon in the address bar
  4. 1Password will auto-install (via declarative config)
```

**Behavior**:
1. Query installed PWAs via `firefoxpwa profile list`
2. For each configured PWA:
   - Check if installed (by name match)
   - Print ✅ if installed, ❌ if missing
3. Print summary with counts
4. If missing PWAs, print installation instructions

**Error Handling**:
- firefoxpwa not available → Exit 2 with error message

**Examples**:
```bash
# Validate PWAs in CI pipeline
pwa-validate || exit 1

# Check status before deployment
pwa-validate && echo "All PWAs ready"
```

---

## pwa-get-ids

**Purpose**: Get ULID identifiers for all installed PWAs (for manual config updates)

**Signature**:
```bash
pwa-get-ids [OPTIONS]
```

**Options**: None

**Exit Codes**:
- `0`: Always (informational command)

**Output Format**:
```
Current PWA IDs (for configuration reference):

      youtubeId = "01HQ1Z9J8G7X2K5MNBVWXYZ013";  # YouTube
      googleaiId = "01HQ1Z9J8G7X2K5MNBVWXYZ014";  # Google AI
      giteaId = "01HQ1Z9J8G7X2K5MNBVWXYZ015";  # Gitea

Copy these IDs to pwa-sites.nix if needed.
```

**Behavior**:
1. Query installed PWAs via `firefoxpwa profile list`
2. For each PWA, extract name and ULID
3. Generate Nix-style variable names from PWA names
4. Print in format suitable for copy-paste to pwa-sites.nix

**Examples**:
```bash
# Get all PWA IDs
pwa-get-ids

# Extract specific PWA ID
pwa-get-ids | grep "youtube"
```

---

## pwa-install-guide

**Purpose**: Display installation guide for manual PWA installation

**Signature**:
```bash
pwa-install-guide
```

**Options**: None

**Exit Codes**:
- `0`: Always (informational command)

**Output**: Multi-page guide covering:
- Installation steps via Firefox GUI
- 1Password integration
- Launching PWAs via Walker
- Troubleshooting common issues
- Cross-machine portability

**Behavior**:
Prints comprehensive installation guide (see output in data-model.md)

---

## pwa-1password-status

**Purpose**: Check 1Password integration status for PWAs

**Signature**:
```bash
pwa-1password-status [OPTIONS]
```

**Options**: None

**Exit Codes**:
- `0`: 1Password config exists and valid
- `1`: 1Password config missing or invalid

**Output Format**:
```
1Password Integration Status
=============================

✅ Runtime config exists: ~/.config/firefoxpwa/runtime.json

Config contents:
{
  "version": 1,
  "extensions": [
    {
      "id": "{d634138d-c276-4fc8-924b-40a0ea21d284}",
      "name": "1Password – Password Manager",
      "url": "https://downloads.1password.com/firefox/firefox-latest.xpi"
    }
  ]
}
```

**Behavior**:
1. Check if `~/.config/firefoxpwa/runtime.json` exists
2. If exists: Display config contents (pretty-printed JSON)
3. If missing: Show error and fix instructions

**Examples**:
```bash
# Check 1Password status
pwa-1password-status

# Verify before using PWA
pwa-1password-status && echo "1Password ready"
```

---

## firefoxpwa CLI (External Dependency)

**Purpose**: Official firefoxpwa command-line tool

**Signature**:
```bash
firefoxpwa [COMMAND] [OPTIONS]
```

**Commands Used by Our System**:

### firefoxpwa site install

**Purpose**: Install a PWA from manifest URL

**Signature**:
```bash
firefoxpwa site install <MANIFEST_URL> [OPTIONS]
```

**Required Options**:
- `--document-url <URL>`: PWA start URL
- `--name <NAME>`: PWA display name
- `--description <DESC>`: PWA description

**Optional Options**:
- `--icon-url <URL>`: Custom icon URL
- `--categories <CATS>`: Desktop categories (semicolon-separated)
- `--keywords <KEYWORDS>`: Search keywords (semicolon-separated)

**Example**:
```bash
firefoxpwa site install \
  "file:///nix/store/.../youtube-manifest.json" \
  --document-url "https://www.youtube.com" \
  --name "YouTube" \
  --description "YouTube Video Platform" \
  --icon-url "file:///etc/nixos/assets/pwa-icons/youtube.png"
```

**Exit Codes**:
- `0`: PWA installed successfully
- `1`: Installation failed (manifest invalid, network error, etc.)

### firefoxpwa profile list

**Purpose**: List all installed PWA profiles and sites

**Signature**:
```bash
firefoxpwa profile list
```

**Output Format**:
```
- Default Profile (00000000000000000000000000):
  - YouTube (01HQ1Z9J8G7X2K5MNBVWXYZ013): https://www.youtube.com
  - Google AI (01HQ1Z9J8G7X2K5MNBVWXYZ014): https://www.google.com/search?udm=50
```

**Exit Codes**:
- `0`: Success
- `1`: Error (firefoxpwa not configured, database corrupted, etc.)

---

## Common Patterns

### Check Installation Status

```bash
# Check if specific PWA installed
if pwa-list | grep -q "YouTube"; then
  echo "YouTube is installed"
fi

# Validate all PWAs before deployment
pwa-validate || {
  echo "Some PWAs missing, running installation..."
  pwa-install-all
}
```

### CI/CD Integration

```bash
# In CI pipeline - ensure all PWAs installed
pwa-validate || pwa-install-all
if [ $? -ne 0 ]; then
  echo "PWA installation failed in CI"
  exit 1
fi
```

### Manual Installation Check

```bash
# After manual Firefox PWA installation, verify config
pwa-list
pwa-get-ids  # Get ULID for updating config if needed
```

---

## Error Messages

### Standard Error Format

All commands use consistent error message format:

```
❌ <Command Name>: <Error Summary>
   Details: <Detailed error message>
   Fix: <Actionable fix instructions>
```

**Examples**:

```
❌ pwa-install-all: firefoxpwa not found
   Details: firefoxpwa binary not available in PATH
   Fix: Install with: nix-shell -p firefoxpwa

❌ pwa-validate: PWA installation incomplete
   Details: 3 PWAs configured, only 2 installed
   Fix: Run 'pwa-install-all' to install missing PWAs

❌ pwa-1password-status: Runtime config missing
   Details: ~/.config/firefoxpwa/runtime.json does not exist
   Fix: Run 'sudo nixos-rebuild switch' to generate config
```

---

## Logging

### Verbosity Levels

**Normal Output** (default):
- Summary information
- Success/failure indicators
- Essential error messages

**No Verbose Mode** (keep commands simple):
- Commands always print useful output
- No silent mode (always show results)
- No debug mode (not needed for user-facing scripts)

### Log Locations

**stdout**: Normal command output, status messages
**stderr**: Error messages only

**No Log Files**: Commands are short-lived, output goes to terminal

---

## Testing Contracts

### Unit Tests (per command)

1. **pwa-install-all**:
   - Empty PWA list → Success, "0 installed"
   - All installed → Success, "N skipped"
   - Mix installed/not installed → Correct counts
   - firefoxpwa unavailable → Exit 2 with error

2. **pwa-validate**:
   - All installed → Exit 0
   - Some missing → Exit 1 with list
   - firefoxpwa unavailable → Exit 2

3. **pwa-list**:
   - Always exits 0
   - Shows configured PWAs
   - Shows installed PWAs
   - Handles firefoxpwa unavailable gracefully

### Integration Tests

1. Fresh system → pwa-install-all → pwa-validate → Success
2. Add PWA to config → pwa-install-all → Only new PWA installed
3. Remove PWA from config → pwa-validate → Reports extra PWA (does not uninstall)

---

## Deprecation Policy

**Command Changes**: Use versioned command names for breaking changes

**Example**: If pwa-install-all changes significantly, introduce pwa-install-all-v2

**Backward Compatibility**: Maintain old command with deprecation warning for 2 releases

---

## References

- [firefoxpwa CLI Documentation](https://github.com/filips123/PWAsForFirefox/wiki/Command-Line-Interface)
- [Bash Exit Codes Convention](https://tldp.org/LDP/abs/html/exitcodes.html)
- [XDG Base Directory Spec](https://specifications.freedesktop.org/basedir-spec/basedir-spec-latest.html)
