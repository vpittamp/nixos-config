# PWA Helper Commands - Validation and Documentation
# Provides commands to validate PWA installation status and guide manual installation
# Relies on manual Firefox GUI installation + declarative 1Password integration
{ config, lib, pkgs, ... }:

with lib;

let
  # Import centralized PWA site definitions
  pwaSitesConfig = import ./pwa-sites.nix { inherit lib; };
  pwas = pwaSitesConfig.pwaSites;

  # Validation command - checks installed PWAs against expected configuration
  pwaValidate = pkgs.writeShellScriptBin "pwa-validate" ''
    #!/usr/bin/env bash
    set -euo pipefail

    FFPWA="${pkgs.firefoxpwa}/bin/firefoxpwa"

    echo "PWA Installation Validation"
    echo "============================"
    echo ""

    # Get list of installed PWAs
    if ! command -v "$FFPWA" >/dev/null 2>&1; then
      echo "❌ firefoxpwa not installed"
      echo "   Install with: nix-shell -p firefoxpwa"
      exit 1
    fi

    # Get installed PWA names
    INSTALLED_NAMES=$($FFPWA profile list 2>/dev/null | grep "^- " | sed 's/^- \([^:]*\):.*/\1/' | sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//')

    echo "Expected PWAs (from configuration):"
    echo ""

    MISSING_COUNT=0
    FOUND_COUNT=0

    ${lib.concatMapStrings (pwa: ''
      if echo "$INSTALLED_NAMES" | grep -qx "${pwa.name}"; then
        echo "  ✅ ${pwa.name}"
        echo "     URL: ${pwa.url}"
        FOUND_COUNT=$((FOUND_COUNT + 1))
      else
        echo "  ❌ ${pwa.name} - NOT INSTALLED"
        echo "     URL: ${pwa.url}"
        echo "     Install: Open Firefox → Navigate to ${pwa.url} → Click 'Install' in address bar"
        MISSING_COUNT=$((MISSING_COUNT + 1))
      fi
      echo ""
    '') pwas}

    echo "=========================================="
    echo "Summary: $FOUND_COUNT installed, $MISSING_COUNT missing"
    echo ""

    if [ $MISSING_COUNT -gt 0 ]; then
      echo "To install missing PWAs:"
      echo "  1. Open Firefox"
      echo "  2. Navigate to the PWA URL"
      echo "  3. Click the 'Install' icon in the address bar"
      echo "  4. 1Password will auto-install (via declarative config)"
      echo ""
      exit 1
    else
      echo "✅ All configured PWAs are installed!"
      exit 0
    fi
  '';

  # List command - shows configured and installed PWAs
  pwaList = pkgs.writeShellScriptBin "pwa-list" ''
    #!/usr/bin/env bash
    FFPWA="${pkgs.firefoxpwa}/bin/firefoxpwa"

    echo "Configured PWAs (from pwa-sites.nix):"
    echo "====================================="
    ${lib.concatMapStrings (pwa: ''
      echo "  ${pwa.name}"
      echo "    URL: ${pwa.url}"
      echo "    Description: ${pwa.description}"
      echo ""
    '') pwas}

    echo ""
    echo "Installed PWAs (from firefoxpwa):"
    echo "================================="
    if command -v "$FFPWA" >/dev/null 2>&1; then
      $FFPWA profile list 2>/dev/null | grep "^- " || echo "  None installed"
    else
      echo "  firefoxpwa not available"
    fi
  '';

  # Installation guide command
  pwaInstallGuide = pkgs.writeShellScriptBin "pwa-install-guide" ''
    #!/usr/bin/env bash
    cat << 'EOF'
PWA Installation Guide
======================

Our PWA system uses MANUAL installation via Firefox GUI for maximum reliability.
1Password integration is handled declaratively (automatic).

Installation Steps:
-------------------

1. Open Firefox browser
2. Navigate to the PWA website (e.g., https://youtube.com)
3. Look for the "Install" icon in the address bar (usually on the right)
4. Click "Install" and confirm
5. PWA will open in its own window
6. 1Password extension will be auto-installed (via declarative config)
7. Pin 1Password to toolbar if needed

The PWA is now installed! It will appear in Walker launcher automatically.

Verification:
-------------
Run 'pwa-validate' to check installation status of all configured PWAs.

Launching PWAs:
---------------
- Via Walker: Press Meta+D, type PWA name, press Return
- Via CLI: launch-pwa-by-name "YouTube"

1Password Integration:
----------------------
1Password is automatically installed to all PWAs via declarative configuration.
Config location: ~/.config/firefoxpwa/runtime.json

For existing PWAs missing 1Password, run: pwa-enable-1password

Troubleshooting:
----------------
- PWA not appearing in Walker? Restart Elephant: systemctl --user restart elephant
- 1Password not working? Run: pwa-enable-1password
- Check installed PWAs: firefoxpwa profile list
- Validate configuration: pwa-validate

Cross-Machine Portability:
---------------------------
PWA profile IDs are system-generated and differ per machine.
Our launch-pwa-by-name script queries firefoxpwa dynamically at runtime,
so no configuration changes are needed when deploying to different machines.

Simply install PWAs manually on each machine via Firefox GUI.
All other integration (1Password, launcher, workspace assignment) is automatic.
EOF
  '';

  # Show 1Password status in PWAs
  pwa1PasswordStatus = pkgs.writeShellScriptBin "pwa-1password-status" ''
    #!/usr/bin/env bash
    set -euo pipefail

    echo "1Password Integration Status"
    echo "============================="
    echo ""

    # Check runtime config
    RUNTIME_CONFIG="$HOME/.config/firefoxpwa/runtime.json"
    if [ -f "$RUNTIME_CONFIG" ]; then
      echo "✅ Runtime config exists: $RUNTIME_CONFIG"
      echo ""
      echo "Config contents:"
      ${pkgs.jq}/bin/jq '.' "$RUNTIME_CONFIG" 2>/dev/null || cat "$RUNTIME_CONFIG"
    else
      echo "❌ Runtime config missing: $RUNTIME_CONFIG"
      echo "   Expected: Auto-created by firefox-pwa-1password.nix module"
      echo "   Fix: Run 'sudo nixos-rebuild switch'"
    fi

    echo ""
    echo "To manually enable 1Password in existing PWAs, run:"
    echo "  pwa-enable-1password"
  '';

in {
  home.packages = [
    pkgs.firefoxpwa
    pwaValidate
    pwaList
    pwaInstallGuide
    pwa1PasswordStatus
  ];
}
