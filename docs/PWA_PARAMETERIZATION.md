# PWA Configuration Parameterization Guide

**Status**: ✅ Implemented
**Last Updated**: 2025-10-10

## Overview

This document describes the centralized PWA configuration system that eliminates duplication and simplifies PWA management across Firefox configuration files.

## Architecture

### Single Source of Truth

All PWA sites are defined in `/etc/nixos/home-modules/tools/pwa-sites.nix`:

```nix
{
  pwaSites = [
    {
      name = "GitHub Codespaces";
      url = "https://github.com/codespaces";
      domain = "github.com";              # Used for Firefox policies
      icon = "file:///etc/nixos/assets/pwa-icons/github-codespaces.png";
      description = "GitHub Cloud Development Environment";
      categories = "Development;";
      keywords = "github;codespaces;cloud;ide;";
    }
    # ... 11 more PWAs ...
  ];

  additionalTrustedDomains = [
    "github.dev"
    "codespaces.githubusercontent.com"
    "claude.ai"
    "my.1password.com"
  ];
}
```

### Automatic Integration

The centralized configuration is automatically used by:

1. **firefox-pwas-declarative.nix** - PWA installation
2. **firefox.nix** - Tracking protection exceptions, clipboard permissions

### Helper Functions

The module provides helper functions for policy generation:

- `getBaseDomains` - Extracts unique domains from PWA sites
- `getDomainPatterns` - Generates Firefox policy patterns with wildcards

Example output:
```nix
[
  "https://github.com"
  "https://*.github.com"
  "https://chatgpt.com"
  "https://*.chatgpt.com"
  "http://localhost"
]
```

## Adding a New PWA

### 1. Prepare Icon

```bash
# Download icon
curl -o /etc/nixos/assets/pwa-icons/newservice.png https://newservice.com/icon.png

# Resize to 512x512
magick /etc/nixos/assets/pwa-icons/newservice.png -resize 512x512 \
  /etc/nixos/assets/pwa-icons/newservice.png
```

### 2. Add to Configuration

Edit `/etc/nixos/home-modules/tools/pwa-sites.nix`:

```nix
{
  pwaSites = [
    # ... existing PWAs ...
    {
      name = "New Service";
      url = "https://newservice.com";
      domain = "newservice.com";
      icon = "file:///etc/nixos/assets/pwa-icons/newservice.png";
      description = "Description of service";
      categories = "Development;";  # or "Network;", "Office;", etc.
      keywords = "keyword1;keyword2;keyword3;";
    }
  ];
}
```

### 3. Rebuild and Install

```bash
# Rebuild NixOS configuration
sudo nixos-rebuild switch --flake .#hetzner

# Install the new PWA
pwa-install-all

# Get PWA ID for taskbar pinning
pwa-get-ids
```

### 4. Add to Taskbar (Optional)

If you want to pin the PWA to your taskbar:

1. Get the PWA ID from `pwa-get-ids`
2. Edit `/etc/nixos/home-modules/desktop/project-activities/panels.nix`
3. Add the ID to `hetznerIds` (or `m1Ids` for M1 Mac)
4. Add to `pwaLaunchers` list
5. Rebuild: `sudo nixos-rebuild switch --flake .#hetzner`

## Adding a Trusted Domain (Without PWA)

If you need to grant Firefox permissions to a domain but NOT install it as a PWA:

Edit `/etc/nixos/home-modules/tools/pwa-sites.nix`:

```nix
{
  additionalTrustedDomains = [
    "github.dev"
    "claude.ai"
    "newdomain.com"  # ⭐ Add here
  ];
}
```

Rebuild, and the domain automatically gets:
- Tracking protection exception
- Clipboard read permissions
- Third-party cookie permissions

## Benefits

### Before Parameterization
- ❌ PWA sites defined in multiple files
- ❌ Domain lists duplicated for policies
- ❌ Adding a PWA requires editing 2+ files
- ❌ Risk of inconsistency

### After Parameterization
- ✅ Single source of truth (`pwa-sites.nix`)
- ✅ Automatic policy generation
- ✅ Adding a PWA requires editing 1 file
- ✅ Always consistent across configurations
- ✅ ~200 lines of duplicate code eliminated

## Files in the System

### Core Configuration
- `/etc/nixos/home-modules/tools/pwa-sites.nix` - Central PWA definitions
- `/etc/nixos/home-modules/tools/firefox-pwas-declarative.nix` - PWA installation
- `/etc/nixos/home-modules/tools/firefox.nix` - Firefox policies

### Supporting Files
- `/etc/nixos/assets/pwa-icons/*.png` - PWA icons (512x512)
- `/etc/nixos/home-modules/desktop/project-activities/panels.nix` - Taskbar configuration

## Current PWAs (2025-10-10)

1. Google AI
2. YouTube
3. Gitea (CNOE)
4. Backstage (CNOE)
5. Kargo (CNOE)
6. ArgoCD (CNOE)
7. Home Assistant
8. Uber Eats
9. GitHub Codespaces
10. Azure Portal
11. Hetzner Cloud
12. ChatGPT Codex

## Verification

### Check PWA List
```bash
pwa-list
```

### Check Firefox Policies
1. Open Firefox
2. Go to `about:policies`
3. Look for `WebsiteFilter` → `Exceptions`
4. Should see all PWA domains listed

### Check Installed PWAs
```bash
firefoxpwa profile list
```

## Troubleshooting

### PWA not installing
- Verify icon exists and is 512x512
- Check `pwa-install-all` output for errors
- Ensure URL is correct in `pwa-sites.nix`

### Tracking protection still blocking
- Verify domain is in `pwa-sites.nix`
- Rebuild configuration
- Restart Firefox/PWAs
- Check `about:policies` for active policies

### Icon not showing
- Ensure icon is 512x512 PNG
- Run `pwa-install-all` to regenerate icons
- Clear icon cache: `rm -rf ~/.cache/icon-cache.kcache`
- Rebuild KDE cache: `kbuildsycoca6 --noincremental`

## See Also

- [PWA_SYSTEM.md](./PWA_SYSTEM.md) - Complete PWA system documentation
- [PWA_COMPARISON.md](./PWA_COMPARISON.md) - Firefox vs Chromium PWA comparison
- [CLAUDE.md](../CLAUDE.md) - Project overview and quick commands
