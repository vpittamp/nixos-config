# Declarative Firefox PWA Management with Automatic Installation
# This module provides a declarative interface for PWAs with automatic installation
{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.programs.firefoxpwa-declarative;

  # Generate consistent PWA IDs
  generatePwaId = name: let
    hash = builtins.substring 0 24 (builtins.hashString "sha256" "pwa-${name}-nixos");
  in "01${toUpper hash}";

  # PWA installation script
  installPwaScript = pwa: ''
    PWA_ID="${pwa.id or ""}"
    PWA_NAME="${pwa.name}"
    MANIFEST_URL="${pwa.manifest}"
    START_URL="${pwa.url}"
    ICON_URL="${pwa.iconUrl or ""}"

    # Check if PWA is already installed by searching for the URL
    EXISTING_DESKTOP=$(grep -l "$START_URL" "$HOME/.local/share/applications/FFPWA-"*.desktop 2>/dev/null | head -1 || true)

    if [ -n "$EXISTING_DESKTOP" ]; then
      echo "PWA '$PWA_NAME' already installed (found: $(basename $EXISTING_DESKTOP))"
    else
      echo "Installing PWA: $PWA_NAME"

      # Build firefoxpwa install command
      INSTALL_CMD="${pkgs.firefoxpwa}/bin/firefoxpwa site install"
      INSTALL_CMD="$INSTALL_CMD --name \"$PWA_NAME\""
      INSTALL_CMD="$INSTALL_CMD --start-url \"$START_URL\""

      [ -n "$ICON_URL" ] && INSTALL_CMD="$INSTALL_CMD --icon-url \"$ICON_URL\""
      [ -n "${pwa.description or ""}" ] && INSTALL_CMD="$INSTALL_CMD --description \"${pwa.description}\""
      [ -n "${pwa.categories or ""}" ] && INSTALL_CMD="$INSTALL_CMD --categories \"${pwa.categories}\""
      [ -n "${pwa.keywords or ""}" ] && INSTALL_CMD="$INSTALL_CMD --keywords \"${pwa.keywords}\""

      INSTALL_CMD="$INSTALL_CMD \"$MANIFEST_URL\""

      # Execute installation
      eval $INSTALL_CMD 2>&1 | grep -E "(installed|ERROR)" || true
    fi
  '';

  # User activation script for PWA installation
  userActivationScript = pkgs.writeShellScript "install-pwas" ''
    set -e
    echo "Checking PWA installations..."

    # Ensure firefoxpwa directories exist
    mkdir -p "$HOME/.local/share/applications"
    mkdir -p "$HOME/.local/share/firefoxpwa"
    mkdir -p "$HOME/.mozilla/native-messaging-hosts"

    # Link native messaging host if needed
    if [ ! -f "$HOME/.mozilla/native-messaging-hosts/firefoxpwa.json" ]; then
      ln -sf "${pkgs.firefoxpwa}/lib/mozilla/native-messaging-hosts/firefoxpwa.json" \
        "$HOME/.mozilla/native-messaging-hosts/firefoxpwa.json" 2>/dev/null || true
    fi

    ${concatMapStrings (name: installPwaScript cfg.pwas.${name}) (attrNames cfg.pwas)}

    # Update desktop database
    if command -v update-desktop-database &>/dev/null; then
      update-desktop-database "$HOME/.local/share/applications" 2>/dev/null || true
    fi

    # Update KDE if running
    if [ -n "$KDE_FULL_SESSION" ]; then
      kbuildsycoca6 --noincremental 2>/dev/null || \
      kbuildsycoca5 --noincremental 2>/dev/null || true
    fi

    echo "PWA installation check complete"
  '';

  # System activation script
  systemActivationScript = ''
    # Ensure firefoxpwa is properly set up system-wide
    echo "Setting up FirefoxPWA system integration..."

    # Create system directories if needed
    mkdir -p /run/current-system/sw/share/applications

    # Generate icon cache updates
    if [ -x /run/current-system/sw/bin/gtk-update-icon-cache ]; then
      for theme in /run/current-system/sw/share/icons/*/; do
        if [ -d "$theme" ]; then
          /run/current-system/sw/bin/gtk-update-icon-cache -qf "$theme" 2>/dev/null || true
        fi
      done
    fi
  '';

in {
  options.programs.firefoxpwa-declarative = {
    enable = mkEnableOption "Declarative Firefox PWA management with automatic installation";

    pwas = mkOption {
      type = types.attrsOf (types.submodule {
        options = {
          name = mkOption {
            type = types.str;
            description = "Display name for the PWA";
          };

          url = mkOption {
            type = types.str;
            description = "Start URL for the PWA";
          };

          manifest = mkOption {
            type = types.str;
            description = "URL to the web app manifest";
          };

          id = mkOption {
            type = types.str;
            default = "";
            description = "PWA ID (auto-generated if empty)";
          };

          icon = mkOption {
            type = types.str;
            default = "";
            description = "Local icon path";
          };

          iconUrl = mkOption {
            type = types.str;
            default = "";
            description = "Remote icon URL";
          };

          description = mkOption {
            type = types.str;
            default = "";
            description = "PWA description";
          };

          categories = mkOption {
            type = types.str;
            default = "Network";
            description = "Desktop categories";
          };

          keywords = mkOption {
            type = types.str;
            default = "";
            description = "Search keywords";
          };
        };
      });
      default = {};
      description = "PWA definitions to be automatically installed";
    };

    autoInstall = mkOption {
      type = types.bool;
      default = true;
      description = "Automatically install PWAs on activation";
    };

    fallbackToFirefox = mkOption {
      type = types.bool;
      default = true;
      description = "Create Firefox fallback entries for PWAs that fail to install";
    };
  };

  config = mkIf cfg.enable {
    # Configure Firefox to use firefoxpwa
    programs.firefox = {
      enable = true;
      nativeMessagingHosts.packages = [ pkgs.firefoxpwa ];
    };

    # System activation script
    system.activationScripts.firefoxpwa = systemActivationScript;

    # Create systemd user service for PWA installation
    systemd.user.services.install-pwas = mkIf cfg.autoInstall {
      description = "Install Firefox PWAs";
      wantedBy = [ "graphical-session.target" ];
      after = [ "graphical-session.target" ];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = userActivationScript;
      };
    };

    # Environment variables
    environment.variables = {
      MOZ_ENABLE_WAYLAND = mkDefault "1";
      MOZ_USE_XINPUT2 = mkDefault "1";
    };

    # Install firefoxpwa and pwa-manager command
    environment.systemPackages = with pkgs; [
      firefoxpwa
      firefox
      (pkgs.writeScriptBin "pwa-manager" ''
        #!/usr/bin/env bash
        case "$1" in
          install)
            ${userActivationScript}
            ;;
          list)
            echo "Installed PWAs:"
            ls ~/.local/share/applications/FFPWA-*.desktop 2>/dev/null | while read f; do
              name=$(grep "^Name=" "$f" | cut -d= -f2)
              id=$(basename "$f" | sed 's/FFPWA-//;s/.desktop//')
              echo "  - $name ($id)"
            done
            ;;
          launch)
            if [ -z "$2" ]; then
              echo "Usage: pwa-manager launch <name>"
              exit 1
            fi
            desktop_file=$(ls ~/.local/share/applications/*"$2"*.desktop 2>/dev/null | head -1)
            if [ -f "$desktop_file" ]; then
              gtk-launch "$(basename "$desktop_file" .desktop)"
            else
              echo "PWA '$2' not found"
            fi
            ;;
          *)
            echo "Usage: pwa-manager {install|list|launch <name>}"
            ;;
        esac
      '')
    ];
  };
}