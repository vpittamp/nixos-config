# PWA Helper Commands (Feature 056, Phase 6)
# Provides user-facing CLI tools for PWA management
{ config, lib, pkgs, osConfig, ... }:

with lib;

let
  # Import PWA configuration
  # Feature 125: Pass hostName for host-specific parameterization
  hostName = if osConfig ? networking && osConfig.networking ? hostName then osConfig.networking.hostName else "";
  pwaSitesConfig = import ../../shared/pwa-sites.nix { inherit lib hostName; };
  pwas = pwaSitesConfig.pwaSites;

  # T077: pwa-list command
  pwaList = pkgs.writeShellScriptBin "pwa-list" ''
    #!/usr/bin/env bash

    echo "Configured PWAs (from pwa-sites.nix):"
    echo "====================================="
    ${lib.concatMapStrings (pwa: ''
      echo "  ${pwa.name}"
      echo "    URL: ${pwa.url}"
      echo "    ULID: ${pwa.ulid}"
      echo ""
    '') pwas}

    echo ""
    echo "Declared PWAs in Registry (pwa-registry.json):"
    echo "====================================="
    if [ -f "$HOME/.config/i3/pwa-registry.json" ]; then
      ${pkgs.jq}/bin/jq -r '.pwas[] | "  - \(.name) [\(.ulid)] -> \(.url)"' "$HOME/.config/i3/pwa-registry.json" || echo "  Failed to parse registry"
    else
      echo "  Registry file not found"
    fi
  '';

  # T078: pwa-validate command
  pwaValidate = pkgs.writeShellScriptBin "pwa-validate" ''
    #!/usr/bin/env bash
    set -euo pipefail

    echo "PWA Configuration Validation"
    echo "============================="
    echo ""

    # Check ULID format
    echo "Checking ULIDs..."
    ${lib.concatMapStrings (pwa: ''
      ulid="${pwa.ulid}"
      if echo "$ulid" | grep -qE '^[0-9A-HJKMNP-TV-Z]{26}$'; then
        echo "  ✓ ${pwa.name}: $ulid"
      else
        echo "  ✗ ${pwa.name}: Invalid ULID format" >&2
        exit 1
      fi
    '') pwas}

    echo ""
    echo "Checking desktop entries..."

    MISSING=0
    ${lib.concatMapStrings (pwa: ''
      APP_NAME=$(echo "${pwa.name}" | tr '[:upper:]' '[:lower:]' | tr ' ' '-')
      if [ -f "$HOME/.local/share/i3pm-applications/applications/''${APP_NAME}-pwa.desktop" ]; then
        echo "  ✓ ${pwa.name} - desktop file exists"
      else
        echo "  ✗ ${pwa.name} - desktop file missing"
        MISSING=$((MISSING + 1))
      fi
    '') pwas}

    echo ""
    if [ $MISSING -eq 0 ]; then
      echo "✓ All PWAs configured correctly"
      exit 0
    else
      echo "✗ $MISSING PWAs missing - run 'sudo nixos-rebuild switch' to install"
      exit 1
    fi
  '';

  # T079: pwa-get-ids command
  pwaGetIds = pkgs.writeShellScriptBin "pwa-get-ids" ''
    #!/usr/bin/env bash

    echo "PWA Logical IDs for Application Registry"
    echo "========================================"
    echo ""

    if [ -f "$HOME/.config/i3/pwa-registry.json" ]; then
      ${pkgs.jq}/bin/jq -r '.pwas[] | "Name: \(.name)\nULID: \(.ulid)\nRegistry ID: WebApp-\(.ulid)\n"' "$HOME/.config/i3/pwa-registry.json"
    else
      echo "Registry not found at $HOME/.config/i3/pwa-registry.json"
    fi
    echo ""
    echo "Runtime Chrome app ids on Wayland may appear as chrome-<domain>...-Default."
    echo "The registry still uses WebApp-<ULID> as the logical PWA identifier."
  '';

  # T081: pwa-install-guide command
  pwaInstallGuide = pkgs.writeShellScriptBin "pwa-install-guide" ''
    #!/usr/bin/env bash

    cat << 'EOF'
PWA Installation Guide
======================

## Declarative Installation

This system uses DECLARATIVE Google Chrome PWAs via NixOS home-manager.

### Quick Start

1. PWAs are defined in: /etc/nixos/shared/pwa-sites.nix
2. Rebuild your system:

   sudo nixos-rebuild switch --flake .#<target>

3. Verify installation:

   pwa-list
   pwa-validate

### Commands

- pwa-list: List configured PWAs
- pwa-validate: Validate PWA configuration
- pwa-get-ids: Get PWA classes for taskbar pinning
- launch-pwa-by-name <name>: Launch PWA by name (cross-machine compatible)

### Adding New PWAs

1. Generate ULID: https://www.ulidgenerator.com/
2. Add PWA definition to pwa-sites.nix
3. Rebuild: sudo nixos-rebuild switch
4. Verify: pwa-validate

### Troubleshooting

- PWAs not installing? Check: pwa-validate
- Missing desktop entries? Check: ~/.local/share/i3pm-applications/applications/*-pwa.desktop
- Walker not showing PWAs? Restart: systemctl --user restart elephant
- 1Password + Chrome PWAs: launch-pwa-by-name uses your main Chrome profile on purpose
EOF
  '';

in
{
  home.packages = [
    pwaList
    pwaValidate
    pwaGetIds
    pwaInstallGuide
  ];
}
