# Declarative PWA Icon Management with Local File Support
{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.services.firefox-pwa-icons;

  # Local icon assets directory
  iconAssetsDir = ../../assets/icons/pwas;

  # Icon definitions - supports both URLs and local files
  defaultIconMappings = {
    # Google AI - using local file
    "01K5SRD32G3CDN8FC5KM8HMQNP" = {
      name = "Google AI";
      iconFile = "${iconAssetsDir}/google-ai.png";
    };

    # ArgoCD - using local file
    "01K5V5G5BVA6HNRPE7BFGZECKJ" = {
      name = "ArgoCD";
      iconFile = "${iconAssetsDir}/ArgoCD.png";
    };

    # Gitea - using local file
    "01K5V5GCYQ3JVFZQGDAK57P69E" = {
      name = "Gitea";
      iconFile = "${iconAssetsDir}/Gitea.png";
    };

    # Backstage - using local file
    "01K5V5GD1MCFJJZMWGM5WS1TDK" = {
      name = "Backstage";
      iconFile = "${iconAssetsDir}/Backstage.png";
    };

    # Headlamp - using local file
    "01K5V5GD4YJTD95867CP4W5WXP" = {
      name = "Headlamp";
      iconFile = "${iconAssetsDir}/Headlamp.png";
    };

    # Kargo - using local file
    "01K5V5GD81REQB1T1TZ049BRFR" = {
      name = "Kargo";
      iconFile = "${iconAssetsDir}/Kargo.png";
    };

    # YouTube - keep using URL for now
    "01K5SC803TS46ABVVPYZ8HYHYK" = {
      name = "YouTube";
      iconUrl = "https://www.youtube.com/s/desktop/5e8e6962/img/favicon_144x144.png";
    };

    # Applications Tiles - Argo CD (separate instance)
    "01K5V4JT1K204VC4R1EV5ETY1Y" = {
      name = "Argo CD Apps";
      iconFile = "${iconAssetsDir}/ArgoCD.png";  # Reuse ArgoCD icon
    };
  };

  # Merge default and user-provided icon mappings
  finalIconMappings = defaultIconMappings // cfg.icons;

  # Script to update PWA icons - handles both URLs and local files
  updateIconsScript = pkgs.writeShellScriptBin "update-pwa-icons" ''
    #!/usr/bin/env bash
    set -e

    # Function to install icon in multiple sizes
    install_icon() {
        local pwa_id="$1"
        local icon_source="$2"
        local name="$3"
        local is_url="$4"

        echo "Updating icon for $name (ID: $pwa_id)..."

        # Get icon file
        temp_icon="/tmp/pwa-icon-''${pwa_id}.png"

        if [ "$is_url" = "true" ]; then
            # Download from URL
            ${pkgs.curl}/bin/curl -L "$icon_source" -o "$temp_icon" 2>/dev/null || {
                echo "Failed to download icon from $icon_source"
                return 1
            }
        else
            # Copy local file
            if [ -f "$icon_source" ]; then
                cp "$icon_source" "$temp_icon"
            else
                echo "Icon file not found: $icon_source"
                return 1
            fi
        fi

        # Install in multiple sizes
        for size in 16 32 48 64 96 128 192 256 512; do
            icon_dir="$HOME/.local/share/icons/hicolor/''${size}x''${size}/apps"
            mkdir -p "$icon_dir"

            # Resize icon using ImageMagick
            ${pkgs.imagemagick}/bin/convert "$temp_icon" \
                -resize ''${size}x''${size} \
                -background transparent \
                -gravity center \
                -extent ''${size}x''${size} \
                "$icon_dir/FFPWA-''${pwa_id}.png"
        done

        # Clean up
        rm -f "$temp_icon"
        echo "✓ Icon updated for $name"
    }

    # Update each configured icon
    ${concatStringsSep "\n" (mapAttrsToList (id: cfg:
      let
        hasUrl = cfg ? iconUrl && cfg.iconUrl != null;
        hasFile = cfg ? iconFile && cfg.iconFile != null;
        iconSource = if hasUrl then cfg.iconUrl else cfg.iconFile;
        isUrl = if hasUrl then "true" else "false";
      in ''
      if [ -f "$HOME/.local/share/applications/FFPWA-${id}.desktop" ]; then
        install_icon "${id}" "${iconSource}" "${cfg.name}" "${isUrl}"
      fi
    '') finalIconMappings)}

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
            type = types.nullOr types.str;
            default = null;
            description = "URL of the icon to download";
          };
          iconFile = mkOption {
            type = types.nullOr types.path;
            default = null;
            description = "Local path to the icon file";
          };
        };
      });
      default = {};
      description = "PWA icon mappings (overrides defaults)";
      example = literalExpression ''
        {
          "01K5EXAMPLE123456789" = {
            name = "My App";
            iconFile = ../../assets/icons/pwas/myapp.png;
          };
          "01K5ANOTHER987654321" = {
            name = "Web App";
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
    # Validate that each icon has either URL or file, not both
    assertions = mapAttrsToList (id: cfg: {
      assertion = (cfg ? iconUrl && cfg.iconUrl != null) != (cfg ? iconFile && cfg.iconFile != null);
      message = "PWA icon '${id}' must have either iconUrl or iconFile, not both or neither";
    }) finalIconMappings;

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