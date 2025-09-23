{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.programs.firefox-pwas;

  # Define custom icons for PWAs
  pwaIcons = {
    google = {
      name = "Google AI";
      icon = pkgs.fetchurl {
        url = "https://www.gstatic.com/images/branding/product/2x/googleg_96dp.png";
        sha256 = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="; # Replace with actual
      };
    };
    youtube = {
      name = "YouTube";
      icon = pkgs.fetchurl {
        url = "https://www.youtube.com/s/desktop/5e8e6962/img/favicon_144x144.png";
        sha256 = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="; # Replace with actual
      };
    };
    github = {
      name = "GitHub";
      icon = ./icons/github.png; # Local icon file
    };
    chatgpt = {
      name = "ChatGPT";
      icon = ./icons/chatgpt.png; # Local icon file
    };
    claude = {
      name = "Claude";
      icon = ./icons/claude.png; # Local icon file
    };
  };

  # Helper to install custom icons
  installIcon = name: iconPath: sizes: ''
    for size in ${toString sizes}; do
      mkdir -p $out/share/icons/hicolor/''${size}x''${size}/apps
      ${pkgs.imagemagick}/bin/convert ${iconPath} \
        -resize ''${size}x''${size} \
        $out/share/icons/hicolor/''${size}x''${size}/apps/${name}.png
    done
  '';

  # Package containing all custom PWA icons
  customIconsPackage = pkgs.stdenv.mkDerivation {
    name = "firefox-pwa-custom-icons";
    src = ./.;

    buildInputs = [ pkgs.imagemagick ];

    buildPhase = ''
      mkdir -p $out/share/icons

      # Install each custom icon in multiple sizes
      ${concatStringsSep "\n" (mapAttrsToList (name: cfg: ''
        if [ -f "${cfg.icon}" ]; then
          ${installIcon "FFPWA-${name}" cfg.icon [16 32 48 64 96 128 192 256 512]}
        fi
      '') pwaIcons)}
    '';

    installPhase = ''
      # Icons are already installed in buildPhase
      echo "Icons installed"
    '';
  };

in
{
  options.programs.firefox-pwas = {
    customIcons = mkOption {
      type = types.bool;
      default = true;
      description = "Enable custom icons for PWAs";
    };

    icons = mkOption {
      type = types.attrsOf (types.submodule {
        options = {
          name = mkOption {
            type = types.str;
            description = "Display name for the PWA";
          };
          iconUrl = mkOption {
            type = types.str;
            default = "";
            description = "URL to download the icon from";
          };
          iconPath = mkOption {
            type = types.path;
            default = null;
            description = "Local path to the icon file";
          };
        };
      });
      default = {};
      description = "Custom icons for PWAs";
    };
  };

  config = mkIf (cfg.enable && cfg.customIcons) {
    # Install custom icons package
    home.packages = [ customIconsPackage ];

    # Script to update PWA icons
    home.file.".local/bin/update-pwa-icons" = {
      executable = true;
      text = ''
        #!/usr/bin/env bash
        set -e

        update_icon() {
          local pwa_id="$1"
          local icon_source="$2"
          local name="$3"

          echo "Updating icon for $name (ID: $pwa_id)..."

          # Find all existing icon sizes
          for size in 16 32 48 64 96 128 192 256 512; do
            icon_dir="$HOME/.local/share/icons/hicolor/''${size}x''${size}/apps"
            icon_file="$icon_dir/FFPWA-$pwa_id.png"

            if [ -f "$icon_source" ]; then
              mkdir -p "$icon_dir"
              ${pkgs.imagemagick}/bin/convert "$icon_source" \
                -resize ''${size}x''${size} \
                "$icon_file"
            fi
          done

          # Update desktop file to ensure it uses the correct icon
          desktop_file="$HOME/.local/share/applications/FFPWA-$pwa_id.desktop"
          if [ -f "$desktop_file" ]; then
            ${pkgs.gnused}/bin/sed -i "s/^Icon=.*/Icon=FFPWA-$pwa_id/" "$desktop_file"
          fi
        }

        # Update specific PWA icons based on configuration
        ${concatStringsSep "\n" (mapAttrsToList (name: cfg: ''
          # Find PWA ID by name
          pwa_id=$(firefoxpwa profile list | grep -A1 "${cfg.name}" | grep "Apps:" -A1 | grep -oP '(?<=\()[A-Z0-9]+(?=\))' | head -1 || true)
          if [ -n "$pwa_id" ]; then
            if [ -f "${toString cfg.iconPath}" ]; then
              update_icon "$pwa_id" "${toString cfg.iconPath}" "${cfg.name}"
            elif [ -n "${cfg.iconUrl}" ]; then
              # Download icon and update
              temp_icon="/tmp/pwa-icon-${name}.png"
              ${pkgs.curl}/bin/curl -L "${cfg.iconUrl}" -o "$temp_icon"
              update_icon "$pwa_id" "$temp_icon" "${cfg.name}"
              rm -f "$temp_icon"
            fi
          fi
        '') cfg.icons)}

        # Refresh icon cache
        ${pkgs.gtk3}/bin/gtk-update-icon-cache -f -t ~/.local/share/icons/hicolor

        # Restart plasma to show new icons
        echo "Icons updated. Restarting Plasma shell..."
        systemctl --user restart plasma-plasmashell.service || true

        echo "PWA icons updated successfully!"
      '';
    };

    # Systemd service to update icons on activation
    systemd.user.services.update-pwa-icons = mkIf cfg.customIcons {
      Unit = {
        Description = "Update Firefox PWA custom icons";
        After = [ "graphical-session.target" ];
      };
      Service = {
        Type = "oneshot";
        ExecStart = "${config.home.homeDirectory}/.local/bin/update-pwa-icons";
        RemainAfterExit = true;
      };
      Install = {
        WantedBy = [ "default.target" ];
      };
    };
  };
}