# Declarative PWA Icon Management
{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.services.firefox-pwa-icons;

  # Icon definitions - maps PWA IDs to icon URLs
  iconMappings = {
    # Google AI
    "01K5SRD32G3CDN8FC5KM8HMQNP" = {
      name = "Google AI";
      iconUrl = "https://www.gstatic.com/images/branding/product/2x/googleg_96dp.png";
    };

    # YouTube
    "01K5SC803TS46ABVVPYZ8HYHYK" = {
      name = "YouTube";
      iconUrl = "https://www.youtube.com/s/desktop/5e8e6962/img/favicon_144x144.png";
    };

    # Add more mappings as PWAs are created
    # These IDs are generated when PWAs are installed
  };

  # Script to update PWA icons
  updateIconsScript = pkgs.writeShellScriptBin "update-pwa-icons" ''
    #!/usr/bin/env bash
    set -e

    # Function to install icon in multiple sizes
    install_icon() {
        local pwa_id="$1"
        local icon_url="$2"
        local name="$3"

        echo "Updating icon for $name (ID: $pwa_id)..."

        # Download icon
        temp_icon="/tmp/pwa-icon-''${pwa_id}.png"
        ${pkgs.curl}/bin/curl -L "$icon_url" -o "$temp_icon" 2>/dev/null

        # Install in multiple sizes
        for size in 16 32 48 64 96 128 192 256 512; do
            icon_dir="$HOME/.local/share/icons/hicolor/''${size}x''${size}/apps"
            mkdir -p "$icon_dir"

            # Resize icon
            ${pkgs.imagemagick}/bin/convert "$temp_icon" \
                -resize ''${size}x''${size} \
                "$icon_dir/FFPWA-''${pwa_id}.png"
        done

        # Clean up
        rm -f "$temp_icon"
        echo "✓ Icon updated for $name"
    }

    # Update each configured icon
    ${concatStringsSep "\n" (mapAttrsToList (id: cfg: ''
      if [ -f "$HOME/.local/share/applications/FFPWA-${id}.desktop" ]; then
        install_icon "${id}" "${cfg.iconUrl}" "${cfg.name}"
      fi
    '') cfg.icons)}

    # Update icon cache
    ${pkgs.gtk3}/bin/gtk-update-icon-cache -f -t ~/.local/share/icons/hicolor 2>/dev/null || true

    echo "All PWA icons updated!"
  '';

  # Systemd service to update icons
  iconUpdateService = {
    description = "Update Firefox PWA Icons";
    wantedBy = [ "graphical-session.target" ];
    after = [ "graphical-session.target" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${updateIconsScript}/bin/update-pwa-icons";
      RemainAfterExit = true;
    };
  };

in
{
  options.services.firefox-pwa-icons = {
    enable = mkEnableOption "Firefox PWA custom icons management";

    icons = mkOption {
      type = types.attrsOf (types.submodule {
        options = {
          name = mkOption {
            type = types.str;
            description = "Display name for the PWA";
          };
          iconUrl = mkOption {
            type = types.str;
            description = "URL of the icon to use";
          };
        };
      });
      default = iconMappings;
      description = "PWA icon mappings";
      example = literalExpression ''
        {
          "01K5EXAMPLE123456789" = {
            name = "My App";
            iconUrl = "https://example.com/icon.png";
          };
        }
      '';
    };

    autoUpdate = mkOption {
      type = types.bool;
      default = true;
      description = "Automatically update icons on system activation";
    };
  };

  config = mkIf cfg.enable {
    # Install required packages
    environment.systemPackages = with pkgs; [
      imagemagick
      curl
      updateIconsScript
    ];

    # Create systemd user service
    systemd.user.services.firefox-pwa-icons = mkIf cfg.autoUpdate iconUpdateService;

    # Activation script to update icons
    system.activationScripts.firefox-pwa-icons = mkIf cfg.autoUpdate ''
      echo "Setting up Firefox PWA icons..."
      # Run as the user, not root
      if [ -n "''${SUDO_USER:-}" ]; then
        sudo -u "$SUDO_USER" ${updateIconsScript}/bin/update-pwa-icons || true
      fi
    '';

    # Shell alias for manual updates
    environment.shellAliases = {
      "pwa-update-icons" = "${updateIconsScript}/bin/update-pwa-icons";
    };
  };
}