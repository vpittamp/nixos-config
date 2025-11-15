# PWA Helper Commands (Feature 056, Phase 6)
# Provides user-facing CLI tools for PWA management
{ config, lib, pkgs, ... }:

with lib;

let
  # Import PWA configuration
  pwaSitesConfig = import ../../shared/pwa-sites.nix { inherit lib; };
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
    echo "Installed PWAs (from firefoxpwa):"
    echo "================================="
    if command -v firefoxpwa >/dev/null 2>&1; then
      firefoxpwa profile list 2>/dev/null | grep "^- " || echo "  None installed"
    else
      echo "  firefoxpwa not available"
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
    echo "Checking installation status..."
    if ! command -v firefoxpwa >/dev/null 2>&1; then
      echo "  ⚠ firefoxpwa not installed"
      exit 0
    fi

    INSTALLED_NAMES=$(firefoxpwa profile list 2>/dev/null | grep "^- " | sed 's/^- \([^:]*\):.*/\1/' | sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//')

    MISSING=0
    ${lib.concatMapStrings (pwa: ''
      if echo "$INSTALLED_NAMES" | grep -qxF "${pwa.name}"; then
        echo "  ✓ ${pwa.name} - installed"
      else
        echo "  ✗ ${pwa.name} - NOT installed"
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

    echo "PWA IDs for taskbar pinning:"
    echo "============================"
    echo ""

    if ! command -v firefoxpwa >/dev/null 2>&1; then
      echo "Error: firefoxpwa not installed"
      exit 1
    fi

    firefoxpwa profile list 2>/dev/null | grep "^- " | while IFS=: read -r name_part rest; do
      name=$(echo "$name_part" | sed 's/^- //' | xargs)
      id=$(echo "$rest" | awk -F'[()]' '{print $2}' | xargs)
      if [ ! -z "$id" ]; then
        echo "  $name → $id"
      fi
    done

    echo ""
    echo "Use these IDs in panels.nix or Walker configuration"
  '';

  # T080: pwa-1password-status command
  pwa1PasswordStatus = pkgs.writeShellScriptBin "pwa-1password-status" ''
    #!/usr/bin/env bash

    echo "1Password Integration Status"
    echo "============================="
    echo ""

    RUNTIME_CONFIG="$HOME/.config/firefoxpwa/runtime.json"
    if [ -f "$RUNTIME_CONFIG" ]; then
      echo "✓ Runtime config exists: $RUNTIME_CONFIG"
      echo ""
      echo "Config contents:"
      ${pkgs.jq}/bin/jq '.' "$RUNTIME_CONFIG" 2>/dev/null || cat "$RUNTIME_CONFIG"
    else
      echo "✗ Runtime config missing"
      echo "  Expected location: $RUNTIME_CONFIG"
      echo "  Fix: Configure 1Password integration in NixOS config"
    fi
  '';

  # T081: pwa-install-guide command
  pwaInstallGuide = pkgs.writeShellScriptBin "pwa-install-guide" ''
    #!/usr/bin/env bash

    cat << 'EOF'
PWA Installation Guide (Feature 056)
=====================================

## Declarative Installation

This system uses DECLARATIVE PWA installation via NixOS home-manager.

### Quick Start

1. PWAs are defined in: /etc/nixos/shared/pwa-sites.nix
2. Enable the module in your configuration:

   programs.firefoxpwa-declarative.enable = true;

3. Rebuild your system:

   sudo nixos-rebuild switch --flake .#<target>

4. Verify installation:

   pwa-list
   pwa-validate

### Commands

- pwa-list: List configured and installed PWAs
- pwa-validate: Validate PWA configuration
- pwa-get-ids: Get PWA IDs for taskbar pinning
- pwa-1password-status: Check 1Password integration
- launch-pwa-by-name <name>: Launch PWA by name (cross-machine compatible)

### Cross-Machine Portability

ULIDs ensure PWAs work identically across machines. Use launch-pwa-by-name
instead of hardcoded IDs in scripts and Walker commands.

### Adding New PWAs

1. Generate ULID: https://www.ulidgenerator.com/
2. Add PWA definition to pwa-sites.nix
3. Rebuild: sudo nixos-rebuild switch
4. Verify: pwa-validate

### Troubleshooting

- PWAs not installing? Check: pwa-validate
- Missing desktop entries? Check: ~/.local/share/applications/FFPWA-*.desktop
- Walker not showing PWAs? Restart: systemctl --user restart elephant

For more details, see: /etc/nixos/specs/056-declarative-pwa-installation/quickstart.md
EOF
  '';

in
{
  home.packages = [
    pkgs.firefoxpwa
    pwaList
    pwaValidate
    pwaGetIds
    pwa1PasswordStatus
    pwaInstallGuide
  ];
}
