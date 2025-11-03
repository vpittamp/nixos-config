# Nix API Contract: Declarative PWA Installation

**Feature**: 056-declarative-pwa-installation
**Date**: 2025-11-02
**Version**: 1.0.0

## Overview

This contract defines the Nix functions and module interfaces for declarative PWA installation. These are the "APIs" for the Nix-based system.

## Public Functions

### 1. generateManifest

**Purpose**: Generate Web App Manifest JSON file for a PWA

**Signature**:
```nix
generateManifest :: PWASite -> Derivation
```

**Input**:
```nix
{
  name = "YouTube";
  url = "https://www.youtube.com";
  domain = "youtube.com";
  icon = "file:///etc/nixos/assets/pwa-icons/youtube.png";
  description = "YouTube Video Platform";
  scope = "https://www.youtube.com/";  # optional
}
```

**Output**: Nix store path to JSON manifest file

**Example Output Path**: `/nix/store/abc123.../youtube-manifest.json`

**Contract**:
- MUST validate input PWASite has required fields (name, url, domain, icon, description)
- MUST generate valid JSON conforming to Web App Manifest spec
- MUST use `scope` if provided, otherwise default to `https://${domain}/`
- MUST produce deterministic output (same input → same store path)
- MUST handle special characters in name/description (JSON escaping)

**Error Conditions**:
- Missing required field → Build error with clear message
- Invalid URL format → Build error
- Invalid icon path → Build error

**Usage**:
```nix
let
  manifest = generateManifest {
    name = "YouTube";
    url = "https://www.youtube.com";
    domain = "youtube.com";
    icon = "file:///etc/nixos/assets/pwa-icons/youtube.png";
    description = "YouTube Video Platform";
  };
in
  # Use manifest in firefoxpwa config
```

---

### 2. validateULID

**Purpose**: Validate ULID format compliance

**Signature**:
```nix
validateULID :: String -> Bool
```

**Input**: String of length 26

**Output**: Boolean (true if valid ULID)

**Contract**:
- MUST accept exactly 26 characters
- MUST validate alphabet: `0123456789ABCDEFGHJKMNPQRSTVWXYZ` (excludes I, L, O, U)
- MUST be case-sensitive (uppercase only)
- MUST return false for any invalid input (not throw error)

**Examples**:
```nix
validateULID "01HQ1Z9J8G7X2K5MNBVWXYZ013"  # → true
validateULID "01HQ1Z9J8G7X2K5MNBVWXYZ01"   # → false (25 chars)
validateULID "01HQ1Z9J8G7X2K5MNBVWXYZ01I"  # → false (contains I)
validateULID "01hq1z9j8g7x2k5mnbvwxyz013"  # → false (lowercase)
```

**Usage**:
```nix
lib.assertMsg (validateULID pwa.ulid) "Invalid ULID for ${pwa.name}: ${pwa.ulid}"
```

---

### 3. generateFirefoxPWAConfig

**Purpose**: Generate complete firefoxpwa config.json from PWA site list

**Signature**:
```nix
generateFirefoxPWAConfig :: [PWASite] -> AttrSet
```

**Input**: List of PWA site definitions

**Output**: Attribute set ready for `builtins.toJSON`

**Contract**:
- MUST use hardcoded profile ULID: `00000000000000000000000000`
- MUST validate all site ULIDs are unique
- MUST generate manifest file paths for each site
- MUST use firefoxpwa config schema version 5
- MUST handle empty input list (return config with empty sites)

**Output Structure**:
```nix
{
  version = 5;
  runtime_version = "${pkgs.firefoxpwa.version}";
  profiles = {
    "00000000000000000000000000" = {
      name = "Default";
      description = "Default Firefox PWA Profile";
      config = {};
      sites = {
        "[SITE_ULID_1]" = { ... };
        "[SITE_ULID_2]" = { ... };
      };
    };
  };
}
```

**Error Conditions**:
- Duplicate ULID in input list → Build error
- Invalid site definition → Build error
- Missing manifest file → Build error

**Usage**:
```nix
xdg.configFile."firefoxpwa/config.json" = {
  text = builtins.toJSON (generateFirefoxPWAConfig pwaSites);
};
```

---

### 4. installPWAScript

**Purpose**: Generate activation script to install PWAs idempotently

**Signature**:
```nix
installPWAScript :: [PWASite] -> Derivation
```

**Input**: List of PWA site definitions

**Output**: Shell script derivation

**Contract**:
- MUST check if PWA already installed before attempting installation
- MUST use `firefoxpwa site install` with manifest URL
- MUST handle installation failures gracefully (continue with remaining PWAs)
- MUST log installation status (installed, skipped, failed)
- MUST be idempotent (safe to run multiple times)
- MUST update desktop entries after new installations

**Script Behavior**:
1. Query currently installed PWAs via `firefoxpwa profile list`
2. For each configured PWA:
   - If installed → log "already installed", skip
   - If not installed → run `firefoxpwa site install` with manifest URL
3. Update desktop database and icon cache
4. Return summary: N installed, M skipped, K failed

**Error Handling**:
- firefoxpwa not available → Exit with error
- Installation fails for one PWA → Log error, continue with others
- Manifest file missing → Log error, skip PWA

**Usage**:
```nix
home.activation.installPWAs = lib.hm.dag.entryAfter ["writeBoundary"] ''
  ${installPWAScript pwaSites}
'';
```

---

## Module Options

### programs.firefoxpwa.enable

**Type**: `boolean`

**Default**: `false`

**Description**: Enable declarative Firefox PWA installation

**Effect**: When enabled, activates PWA installation automation

---

### programs.firefoxpwa.sites

**Type**: `listOf PWASite`

**Default**: `[]` (imported from pwa-sites.nix)

**Description**: List of PWA sites to install declaratively

**Example**:
```nix
programs.firefoxpwa.sites = import ./pwa-sites.nix;
```

**Validation**: Each site must have valid ULID, URL, name, description, icon

---

### programs.firefoxpwa.autoInstall

**Type**: `boolean`

**Default**: `true`

**Description**: Automatically install PWAs during home activation

**Effect**: If false, only generates config files without running installation

---

## Activation Scripts

### home.activation.managePWAs

**Trigger**: After `writeBoundary` in home-manager activation

**Purpose**: Install PWAs, create desktop entries, update launcher cache

**Phases**:
1. **Validation**: Check firefoxpwa availability
2. **Installation**: Run installPWAScript
3. **Desktop Integration**: Create/update desktop entries
4. **Icon Processing**: Resize icons if needed
5. **Cache Update**: Update desktop database and icon cache
6. **Symlinks**: Link desktop files to applications directory

**Idempotency**: Safe to run multiple times, skips already-installed PWAs

**Output**: Logs to home-manager activation output

---

### home.activation.linkPWADesktopFiles

**Trigger**: After `writeBoundary` in home-manager activation

**Purpose**: Create symlinks for PWA desktop files in standard XDG location

**Behavior**:
1. Clean up legacy PWA files from old system
2. Symlink all files from `~/.local/share/firefox-pwas/` to `~/.local/share/applications/`
3. Remove broken symlinks

**Idempotency**: Safe to run multiple times

---

## Helper Commands

### pwa-install-all

**Purpose**: Manually trigger PWA installation for all configured PWAs

**Signature**: `pwa-install-all :: IO ()`

**Behavior**: Same as installPWAScript, but runnable from command line

**Output**: Human-readable summary of installation results

**Exit Codes**:
- `0`: All PWAs installed successfully (or already installed)
- `1`: One or more PWAs failed to install

---

### pwa-list

**Purpose**: List configured and installed PWAs

**Signature**: `pwa-list :: IO ()`

**Output**:
```
Configured PWAs:
  - YouTube: https://www.youtube.com
  - Google AI: https://www.google.com/search?udm=50
  ...

Installed PWAs:
  - YouTube (01HQ1Z9J8G7X2K5MNBVWXYZ013)
  - Google AI (01HQ1Z9J8G7X2K5MNBVWXYZ014)
```

---

### pwa-validate

**Purpose**: Validate all configured PWAs are installed correctly

**Signature**: `pwa-validate :: IO ()`

**Behavior**:
1. Read configured PWAs from pwa-sites.nix
2. Query installed PWAs from firefoxpwa
3. Compare and report missing PWAs

**Exit Codes**:
- `0`: All configured PWAs are installed
- `1`: One or more PWAs missing

**Output**:
```
✅ YouTube - installed
✅ Google AI - installed
❌ Gitea - NOT INSTALLED
   Install: firefoxpwa site install https://gitea.cnoe.localtest.me:8443

Summary: 2 installed, 1 missing
```

---

## Type Definitions

### PWASite

```nix
{
  name = string;              # Display name
  url = string;               # Start URL (HTTPS or HTTP for localhost)
  domain = string;            # Base domain
  icon = string;              # Icon path (file:// or https://)
  description = string;       # Short description
  ulid = string;              # Site ULID (26 chars, ULID alphabet)
  scope = string or null;     # Optional scope (defaults to https://${domain}/)
  categories = string or null;  # Optional desktop categories
  keywords = string or null;    # Optional search keywords
}
```

---

## Versioning

**API Version**: 1.0.0

**Breaking Changes**:
- Changing PWASite required fields
- Changing ULID format
- Changing firefoxpwa config schema version
- Removing public functions

**Non-Breaking Changes**:
- Adding optional fields to PWASite
- Adding new helper commands
- Improving error messages
- Performance optimizations

---

## Testing Contract

### Unit Tests (Build-Time)

1. **ULID Validation**: Test validateULID with valid/invalid inputs
2. **Manifest Generation**: Test generateManifest produces valid JSON
3. **Config Generation**: Test generateFirefoxPWAConfig handles edge cases

### Integration Tests (Runtime)

1. **Installation Idempotency**: Run installPWAScript twice, verify same result
2. **Cross-Machine Portability**: Deploy same config to different machines, verify ULIDs match
3. **Helper Commands**: Test pwa-list, pwa-validate, pwa-install-all
4. **Launcher Integration**: Verify PWAs visible in Walker after installation

### Acceptance Tests

1. Fresh NixOS install → Deploy config → All PWAs installed
2. Add new PWA to pwa-sites.nix → Rebuild → New PWA installed, existing PWAs untouched
3. Remove PWA from config → Rebuild → PWA remains installed (manual removal required)

---

## Deprecation Policy

**Deprecated APIs**: Will be marked with clear warnings and maintained for 2 NixOS releases

**Removal Process**:
1. Mark deprecated in documentation
2. Add runtime warnings
3. Maintain for 2 releases
4. Remove in 3rd release

**Current Deprecated APIs**: None

---

## Examples

### Complete Integration Example

```nix
# home-modules/tools/firefox-pwas.nix
{ config, lib, pkgs, ... }:

let
  pwaSites = import ./pwa-sites.nix { inherit lib; };

  generateManifest = pwa: pkgs.writeText "${pwa.name}-manifest.json" (builtins.toJSON {
    name = pwa.name;
    short_name = pwa.name;
    start_url = pwa.url;
    scope = pwa.scope or "https://${pwa.domain}/";
    display = "standalone";
    description = pwa.description;
    icons = [{
      src = pwa.icon;
      sizes = "512x512";
      type = "image/png";
    }];
  });

  installScript = pkgs.writeShellScript "install-pwas" ''
    # ... (as defined in installPWAScript contract)
  '';

in {
  # Generate firefoxpwa config
  xdg.configFile."firefoxpwa/config.json" = {
    text = builtins.toJSON (generateFirefoxPWAConfig pwaSites.pwaSites);
  };

  # Install PWAs on activation
  home.activation.installPWAs = lib.hm.dag.entryAfter ["writeBoundary"] ''
    ${installScript}
  '';

  # Provide helper commands
  home.packages = [
    pkgs.firefoxpwa
    (pkgs.writeShellScriptBin "pwa-install-all" "${installScript}")
    # ... other helpers
  ];
}
```

---

## References

- [Nix Manual - Functions](https://nixos.org/manual/nix/stable/expressions/language-constructs.html#functions)
- [home-manager Activation Scripts](https://nix-community.github.io/home-manager/index.html#sec-usage-configuration)
- [firefoxpwa CLI Reference](https://github.com/filips123/PWAsForFirefox/wiki/Command-Line-Interface)
