# Data Model: Declarative PWA Installation

**Feature**: 056-declarative-pwa-installation
**Date**: 2025-11-02
**Status**: Complete

## Overview

This document defines the data structures for declarative PWA installation in NixOS. The system manages PWA metadata, ULID identifiers, Web App Manifests, and firefoxpwa configuration.

## Entity Definitions

### 1. PWA Site Definition

**Purpose**: Single source of truth for PWA metadata in app-registry-data.nix

**Location**: `shared/pwa-sites.nix`

**Nix Schema**:
```nix
{
  name = string;              # Display name (e.g., "YouTube")
  url = string;               # Start URL (e.g., "https://www.youtube.com")
  domain = string;            # Base domain (e.g., "youtube.com")
  icon = string;              # Icon path (file:// or https://)
  description = string;       # Short description
  categories = string;        # Desktop categories (optional)
  keywords = string;          # Search keywords (optional)
  scope = string or null;     # Web App scope (optional, defaults to https://${domain}/)
  ulid = string;              # Site ULID identifier (26 chars, ULID alphabet)
}
```

**Example**:
```nix
{
  name = "YouTube";
  url = "https://www.youtube.com";
  domain = "youtube.com";
  icon = "file:///etc/nixos/assets/pwa-icons/youtube.png";
  description = "YouTube Video Platform";
  categories = "AudioVideo;Video;";
  keywords = "video;streaming;";
  scope = "https://www.youtube.com/";
  ulid = "01HQ1Z9J8G7X2K5MNBVWXYZ013";
}
```

**Validation Rules**:
- `name`: Non-empty string, max 100 chars
- `url`: Valid HTTPS URL (or HTTP for localhost)
- `domain`: Valid domain name or "localhost"
- `icon`: Valid file:// or https:// URL
- `description`: Non-empty string, max 200 chars
- `ulid`: Exactly 26 characters, ULID alphabet [0-9A-HJKMNP-TV-Z]
- `scope`: If provided, must be valid HTTPS URL and prefix of `url`

**Relationships**:
- One PWA Site → One Web App Manifest
- One PWA Site → One firefoxpwa Site entry
- One PWA Site → One Desktop Entry (via firefoxpwa)

### 2. ULID Identifier

**Purpose**: Unique identifier for PWA sites, persistent across machines

**Format**: String, 26 characters from ULID alphabet

**ULID Alphabet**: `0123456789ABCDEFGHJKMNPQRSTVWXYZ` (excludes I, L, O, U)

**Generation Strategy**: Manually generated once, stored in pwa-sites.nix, committed to Git

**Example**: `01HQ1Z9J8G7X2K5MNBVWXYZ013`

**Validation**:
```bash
# Regex: ^[0-9A-HJKMNP-TV-Z]{26}$
echo "$ULID" | grep -qE '^[0-9A-HJKMNP-TV-Z]{26}$'
```

**Uniqueness Guarantee**:
- 128-bit entropy (same as UUID)
- Lexicographically sortable by creation time
- Case-insensitive
- URL-safe (no special characters)

### 3. Web App Manifest

**Purpose**: JSON manifest required by firefoxpwa for PWA installation

**Format**: JSON file conforming to [Web App Manifest spec](https://www.w3.org/TR/appmanifest/)

**Location**: Nix store (generated at build time)

**JSON Schema**:
```json
{
  "name": string,              // Display name
  "short_name": string,        // Short name (same as name)
  "start_url": string,         // PWA start URL
  "scope": string,             // URL scope
  "display": "standalone",     // Display mode (always standalone)
  "description": string,       // Description
  "icons": [                   // Icon array
    {
      "src": string,           // Icon URL (file:// or https://)
      "sizes": "512x512",      // Icon size
      "type": "image/png"      // Icon MIME type
    }
  ]
}
```

**Example**:
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

**Generation**:
```nix
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

### 4. firefoxpwa Configuration

**Purpose**: Declarative configuration for firefoxpwa runtime

**Location**: `~/.config/firefoxpwa/config.json` (managed by home-manager)

**JSON Schema**:
```json
{
  "version": number,           // Config schema version (5)
  "runtime_version": string,   // firefoxpwa version
  "profiles": {
    "[PROFILE_ULID]": {
      "name": string,          // Profile name
      "description": string,   // Profile description
      "config": {},            // Profile config (empty)
      "sites": {
        "[SITE_ULID]": {
          "name": string,              // Site name
          "description": string,       // Site description
          "start_url": string,         // Start URL
          "scope": string,             // URL scope
          "manifest_url": string,      // Manifest file:// URL
          "icon_path": string          // Icon file path
        }
      }
    }
  }
}
```

**Example**:
```json
{
  "version": 5,
  "runtime_version": "2.12.3",
  "profiles": {
    "00000000000000000000000000": {
      "name": "Default",
      "description": "Default Firefox PWA Profile",
      "config": {},
      "sites": {
        "01HQ1Z9J8G7X2K5MNBVWXYZ013": {
          "name": "YouTube",
          "description": "YouTube Video Platform",
          "start_url": "https://www.youtube.com",
          "scope": "https://www.youtube.com/",
          "manifest_url": "file:///nix/store/.../youtube-manifest.json",
          "icon_path": "file:///etc/nixos/assets/pwa-icons/youtube.png"
        }
      }
    }
  }
}
```

**Profile ULID**: Hardcoded to `00000000000000000000000000` (default profile)

**Site ULIDs**: From pwa-sites.nix, unique per PWA

### 5. Desktop Entry

**Purpose**: XDG desktop entry for launcher integration

**Location**: `~/.local/share/firefox-pwas/FFPWA-[ULID].desktop` (created by firefoxpwa)

**Format**: Standard XDG desktop entry

**Example**:
```ini
[Desktop Entry]
Type=Application
Version=1.4
Name=YouTube
Comment=Firefox Progressive Web App - https://www.youtube.com
Icon=FFPWA-01HQ1Z9J8G7X2K5MNBVWXYZ013
Exec=/nix/store/.../firefoxpwa site launch 01HQ1Z9J8G7X2K5MNBVWXYZ013 --protocol %u
Terminal=false
StartupNotify=true
StartupWMClass=FFPWA-01HQ1Z9J8G7X2K5MNBVWXYZ013
Categories=Network;AudioVideo;Video;
MimeType=x-scheme-handler/https;x-scheme-handler/http;
X-KDE-Activities=00000000-0000-0000-0000-000000000000
```

**Symlink Location**: `~/.local/share/applications/FFPWA-[ULID].desktop` (for Walker)

**Icon Handling**: firefoxpwa manages icons in `~/.local/share/icons/hicolor/*/apps/`

## Data Flow

```
1. pwa-sites.nix (Source of Truth)
   ↓
2. Manifest Generation (Build Time)
   ↓ file:///nix/store/.../manifest.json
3. firefoxpwa config.json (Home Activation)
   ↓
4. firefoxpwa site install (Activation Script)
   ↓
5. Desktop Entry Creation (firefoxpwa)
   ↓
6. Symlink to Applications (Home Activation)
   ↓
7. Walker Launcher Visibility
```

## State Transitions

### PWA Installation Lifecycle

```
[Declared in pwa-sites.nix]
   ↓
   → Check if already installed (firefoxpwa profile list)
   ↓
   ├─ Already Installed → Skip installation
   │                    → Update desktop entry if needed
   │                    → Create symlink
   │
   └─ Not Installed → Generate manifest
                    → Run firefoxpwa site install
                    → Desktop entry created by firefoxpwa
                    → Create symlink
                    → Update launcher cache
```

### Configuration Update Flow

```
User edits pwa-sites.nix
   ↓
nixos-rebuild switch / home-manager switch
   ↓
Manifest files regenerated (Nix build)
   ↓
Home activation runs
   ↓
Installation script checks each PWA
   ↓
New PWAs installed, existing PWAs skipped
   ↓
Desktop entries updated
   ↓
Launcher sees new PWAs
```

## Validation Rules Summary

| Entity | Field | Validation |
|--------|-------|------------|
| PWA Site | name | Non-empty, max 100 chars, unique |
| PWA Site | url | Valid HTTP/HTTPS URL |
| PWA Site | ulid | Exactly 26 chars, ULID alphabet |
| PWA Site | icon | Valid file:// or https:// URL, file exists |
| PWA Site | scope | If present, valid HTTPS URL, prefix of url |
| ULID | format | ^[0-9A-HJKMNP-TV-Z]{26}$ |
| Manifest | name | Non-empty string |
| Manifest | start_url | Valid HTTP/HTTPS URL |
| Manifest | icons | At least one icon with valid src |

## Error Handling

### Invalid ULID
- **Detection**: Regex validation during build
- **Action**: Build error with clear message
- **Recovery**: Fix ULID in pwa-sites.nix, rebuild

### Duplicate ULID
- **Detection**: Nix attribute name collision
- **Action**: Build error
- **Recovery**: Generate new ULID, update pwa-sites.nix

### Missing Icon File
- **Detection**: file:// path validation during activation
- **Action**: Warning logged, PWA installed without custom icon
- **Recovery**: Add icon file, rebuild

### firefoxpwa Installation Failure
- **Detection**: Non-zero exit code from firefoxpwa
- **Action**: Error logged, continue with remaining PWAs
- **Recovery**: Check manifest validity, retry installation

### Network Failure (for remote icons)
- **Detection**: HTTP request timeout/error
- **Action**: Warning logged, use placeholder icon
- **Recovery**: Retry on next rebuild

## Cross-Machine Portability

### Portable Data
- PWA Site Definitions (pwa-sites.nix)
- ULID Mappings (static, version controlled)
- Manifest Templates (generated from definitions)
- Icon Files (committed to repo)

### Machine-Specific Data
- Desktop Entry Files (generated by firefoxpwa)
- Icon Cache (generated by freedesktop tools)
- firefoxpwa Internal Database (~/.local/share/firefoxpwa/)

### Deployment Strategy
1. Commit pwa-sites.nix with all PWA definitions and ULIDs
2. Deploy configuration to target machine
3. firefoxpwa installs PWAs using portable manifests
4. Desktop entries created with machine-specific paths
5. Launcher integration automatic via symlinks

**No configuration changes required across machines** - ULIDs and manifests are identical, only internal firefoxpwa state differs.

## Future Extensions

### Workspace Assignment
- Add `preferred_workspace` field to PWA Site Definition
- Integrate with i3pm daemon for automatic workspace placement
- Example: `preferred_workspace = 3;`

### Custom Launch Parameters
- Add `launch_args` field for firefoxpwa-specific options
- Example: `launch_args = "--private";`

### Icon Variants
- Support multiple icon sizes in manifest
- Auto-resize icons at build time
- Example: `icons = [ { sizes = "128x128"; } { sizes = "512x512"; } ];`

### Profile Management
- Support multiple profiles beyond default
- Profile-specific PWA sets
- Example: `profile = "work";`

## References

- [Web App Manifest Spec](https://www.w3.org/TR/appmanifest/)
- [ULID Specification](https://github.com/ulid/spec)
- [firefoxpwa Documentation](https://github.com/filips123/PWAsForFirefox)
- [XDG Desktop Entry Spec](https://specifications.freedesktop.org/desktop-entry-spec/latest/)
