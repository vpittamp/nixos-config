# Research: Declarative PWA Installation

**Feature**: 056-declarative-pwa-installation
**Date**: 2025-11-02
**Status**: Complete

## Overview

This research addresses unknowns in implementing fully declarative Progressive Web App (PWA) installation using NixOS and home-manager. Current system requires manual Firefox GUI installation; this feature aims for zero-touch deployment.

## Research Areas

### 1. ULID Generation and Validation

**Decision**: Use `ulid` CLI tool from nixpkgs for ULID generation

**Rationale**:
- ULID specification: 26 characters from alphabet `0123456789ABCDEFGHJKMNPQRSTVWXYZ` (excludes I, L, O, U)
- Lexicographically sortable, 128-bit universally unique IDs
- `ulid` package available in nixpkgs (`pkgs.ulid`)
- Pure Nix alternative: Use `/dev/urandom` + base32 encoding, but ULID lib provides spec-compliant implementation

**Implementation**:
```nix
# Generate ULID at build time
let
  generateULID = name: pkgs.runCommand "ulid-${name}" { buildInputs = [ pkgs.ulid ]; } ''
    ulid > $out
  '';
in
```

**Alternatives Considered**:
- Pure Nix random generation: Complex to implement ULID spec correctly
- Hardcoded ULIDs: Violates cross-machine portability requirement
- UUID v4: Different format, not lexicographically sortable

**Validation Pattern**:
```bash
# ULID regex: ^[0-9A-HJKMNP-TV-Z]{26}$
echo "$ULID" | grep -qE '^[0-9A-HJKMNP-TV-Z]{26}$'
```

### 2. Web App Manifest Generation

**Decision**: Generate JSON manifests at build time, host via Python HTTP server or file:// URLs

**Rationale**:
- firefoxpwa requires manifest URL during installation
- Manifests need to be accessible during `firefoxpwa site install`
- File:// URLs work for local manifests (simpler than HTTP server)
- Python HTTP server as fallback for sites that reject file:// protocol

**Manifest Structure** (Web App Manifest spec):
```json
{
  "name": "YouTube",
  "short_name": "YouTube",
  "start_url": "https://www.youtube.com",
  "scope": "https://www.youtube.com/",
  "display": "standalone",
  "description": "YouTube Video Platform",
  "icons": [{
    "src": "file:///etc/nixos/assets/pwa-icons/youtube.png",
    "sizes": "512x512",
    "type": "image/png"
  }]
}
```

**Implementation**:
```nix
# Generate manifest for each PWA
manifestFile = pwa: pkgs.writeText "${pwa.name}-manifest.json" (builtins.toJSON {
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
```

**Alternatives Considered**:
- Nginx server for manifests: Too heavy, requires service management
- Dynamic generation in shell script: Less reliable, harder to test
- Inline JSON in firefoxpwa command: Doesn't support all fields

### 3. home-manager programs.firefoxpwa Module

**Decision**: Use home-manager's native firefoxpwa module if available, otherwise implement custom module

**Research Findings**:
- home-manager does NOT have built-in `programs.firefoxpwa` module (as of 2025-11)
- Need to create custom home-manager module for declarative configuration
- firefoxpwa config location: `~/.local/share/firefoxpwa/config.json`
- firefoxpwa runtime config: `~/.config/firefoxpwa/runtime.json`

**Config Structure** (from firefoxpwa docs):
```json
{
  "version": 5,
  "runtime_version": "2.12.3",
  "profiles": {
    "01HQ1Z9J8G7X2K5MNBVWXYZ012": {
      "name": "YouTube",
      "description": "YouTube Video Platform",
      "config": {},
      "sites": {
        "01HQ1Z9J8G7X2K5MNBVWXYZ013": {
          "name": "YouTube",
          "description": "YouTube Video Platform",
          "start_url": "https://www.youtube.com",
          "scope": "https://www.youtube.com/",
          "manifest_url": "file:///nix/store/.../youtube-manifest.json",
          "icon_path": "/etc/nixos/assets/pwa-icons/youtube.png"
        }
      }
    }
  }
}
```

**Implementation**:
```nix
# Custom home-manager module for firefoxpwa
{ config, lib, pkgs, ... }:
{
  xdg.configFile."firefoxpwa/config.json" = {
    text = builtins.toJSON {
      version = 5;
      runtime_version = pkgs.firefoxpwa.version;
      profiles = {
        # Default profile ID (hardcoded for simplicity)
        "00000000000000000000000000" = {
          name = "Default";
          description = "Default Firefox PWA Profile";
          config = {};
          sites = lib.listToAttrs (map (pwa: {
            name = generateULID pwa.name;
            value = {
              name = pwa.name;
              description = pwa.description;
              start_url = pwa.url;
              scope = pwa.scope or "https://${pwa.domain}/";
              manifest_url = "file://${manifestFile pwa}";
              icon_path = pwa.icon;
            };
          }) pwas);
        };
      };
    };
  };
}
```

**Alternatives Considered**:
- Direct JSON manipulation via jq: Fragile, hard to maintain
- Shell script generation: Less type-safe than Nix
- Using firefoxpwa CLI in activation script: Not truly declarative

### 4. ULID Persistence and Cross-Machine Portability

**Decision**: Use deterministic ULID generation based on PWA name hash + machine-independent seed

**Rationale**:
- Problem: ULIDs generated randomly differ per machine
- Solution: Use `builtins.hashString "sha256" pwa.name` as seed for deterministic generation
- Trade-off: Not true ULIDs (not time-based), but maintains uniqueness and portability

**Implementation**:
```nix
# Generate deterministic ULID from PWA name
generateDeterministicULID = name:
  let
    # Hash the name to get a 256-bit value
    hash = builtins.hashString "sha256" name;
    # Take first 26 characters and map to ULID alphabet
    ulidAlphabet = "0123456789ABCDEFGHJKMNPQRSTVWXYZ";
    # Convert hash to ULID format (simplified - full implementation more complex)
    hashToULID = hash: lib.substring 0 26 (lib.toUpper hash);
  in
    hashToULID hash;
```

**Better Alternative** (Post-research decision):
- Store ULID mappings in `pwa-sites.nix` as static data
- Generate ULIDs once, commit to version control
- Benefits: True ULIDs, cross-machine identical, no complex hashing logic
- Drawback: Manual maintenance when adding new PWAs

**Final Decision**: Static ULID mapping in pwa-sites.nix

### 5. firefoxpwa Installation Process

**Decision**: Use `firefoxpwa site install` via activation script with generated manifests

**Best Practices** (from firefoxpwa documentation):
- Installation command: `firefoxpwa site install <manifest-url> --document-url <url> --name <name> --description <desc> --icon-url <icon>`
- Idempotency: Check if site already installed before attempting installation
- Profile management: Use default profile `00000000000000000000000000` for all PWAs
- Desktop integration: firefoxpwa auto-creates desktop files in `~/.local/share/firefox-pwas/`

**Installation Script Pattern**:
```bash
# Check if PWA already installed
if firefoxpwa profile list | grep -q "YouTube"; then
  echo "YouTube already installed"
else
  # Install with manifest
  firefoxpwa site install \
    "file:///nix/store/.../youtube-manifest.json" \
    --document-url "https://www.youtube.com" \
    --name "YouTube" \
    --description "YouTube Video Platform" \
    --icon-url "file:///etc/nixos/assets/pwa-icons/youtube.png"
fi
```

**Error Handling**:
- Network failures: Skip installation, log warning
- Invalid manifest: Validate JSON before passing to firefoxpwa
- Missing icons: Use default icon or skip icon parameter

### 6. Desktop Entry Symlinks and Launcher Integration

**Decision**: Reuse existing symlink approach from Feature 055 (pwa-helpers.nix)

**Rationale**:
- firefoxpwa creates desktop files in `~/.local/share/firefox-pwas/`
- Walker expects desktop files in `~/.local/share/applications/`
- Existing activation script in pwa-helpers.nix handles this correctly
- No changes needed, just ensure activation runs after PWA installation

**Implementation**: Already handled by `home.activation.linkPWADesktopFiles` in pwa-helpers.nix

### 7. Idempotency and State Management

**Decision**: Use firefoxpwa's native state for idempotency checks

**Pattern**:
```bash
# Query installed PWAs
INSTALLED_PWAS=$(firefoxpwa profile list | grep "^- " | sed 's/^- \([^:]*\):.*/\1/')

# Check if PWA already installed
if echo "$INSTALLED_PWAS" | grep -qx "YouTube"; then
  echo "Already installed"
else
  # Install PWA
  firefoxpwa site install ...
fi
```

**State File Alternatives Rejected**:
- JSON state file in ~/.config/firefoxpwa/: Redundant with firefoxpwa's own state
- Nix store state: Not persistent across generations
- Database: Overkill for this use case

## Technology Stack Summary

| Component | Technology | Rationale |
|-----------|-----------|-----------|
| ULID Generation | Static mapping in pwa-sites.nix | Cross-machine portability, version controlled |
| Manifest Generation | Nix `builtins.toJSON` + `pkgs.writeText` | Type-safe, build-time generation |
| Config Management | Custom home-manager module | Native Nix integration, declarative |
| Installation | firefoxpwa CLI via activation script | Official tool, reliable |
| Idempotency | Query firefoxpwa profile list | Single source of truth |
| Desktop Integration | Symlinks via home.activation | Existing proven approach |

## Implementation Plan Summary

1. **Phase 1**: Extend pwa-sites.nix with ULID mappings
2. **Phase 2**: Create manifest generation function in Nix
3. **Phase 3**: Build custom home-manager firefoxpwa module
4. **Phase 4**: Implement activation script for installation
5. **Phase 5**: Test on Hetzner, M1, WSL configurations
6. **Phase 6**: Update documentation and helper commands

## Open Questions Resolved

- ✅ How to generate ULIDs declaratively? → Static mapping in pwa-sites.nix
- ✅ How to host manifest files? → file:// URLs with Nix store paths
- ✅ Does home-manager have firefoxpwa module? → No, need custom module
- ✅ How to ensure idempotency? → Query firefoxpwa profile list before install
- ✅ How to handle cross-machine deployment? → Static ULIDs committed to version control
- ✅ How to integrate with launcher? → Existing symlink activation script

## Next Steps

Proceed to Phase 1: Design data models and API contracts
