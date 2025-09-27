# PWA Configuration Module for Home-Manager
# This module declaratively manages PWA desktop files and icons

{ config, lib, pkgs, ... }:

with lib;

let
  # Define all PWAs with their stable IDs and icon URLs
  pwas = {
    # These IDs must match the installed PWAs from firefoxpwa profile list
    google = {
      name = "Google";
      url = "https://www.google.com";
      id = "01D12288367E14F3D20D5C3274";  # From Google profile
      icon = "https://www.google.com/favicon.ico";
    };
    youtube = {
      name = "YouTube";
      url = "https://www.youtube.com";
      id = "019DB7F7C8868D4C4FA0121E19";  # From YouTube profile
      icon = "https://www.youtube.com/favicon.ico";
    };
    gitea = {
      name = "Gitea";
      url = "https://gitea.cnoe.localtest.me:8443";
      id = "01FEA664E5984E1A3E85E944F6";  # From Gitea profile
      icon = "https://raw.githubusercontent.com/go-gitea/gitea/main/assets/logo.png";
    };
    backstage = {
      name = "Backstage";
      url = "https://backstage.cnoe.localtest.me:8443";
      id = "0199D501A20B94AE3BB038B6BC";  # From Backstage profile
      icon = "https://backstage.io/img/logo-gradient-on-dark.svg";
    };
    kargo = {
      name = "Kargo";
      url = "https://kargo.cnoe.localtest.me:8443";
      id = "01738C30F3A05DAB2C1BC16C0A";  # From Kargo profile
      icon = "https://raw.githubusercontent.com/akuity/kargo/main/ui/public/kargo-icon.png";
    };
    argocd = {
      name = "ArgoCD";
      url = "https://argocd.cnoe.localtest.me:8443";
      id = "01CBD2EC47D2F8D8CF86034280";  # From ArgoCD profile
      icon = "https://raw.githubusercontent.com/argoproj/argo-cd/master/docs/assets/logo.png";
    };
    headlamp = {
      name = "Headlamp";
      url = "https://headlamp.cnoe.localtest.me:8443";
      id = "0167D0420CC8C9DFCD3751D068";  # From Headlamp profile
      icon = "https://backstage.io/logo_assets/png/Icon_Teal.png";
    };
  };

in {
  # Create desktop files for each PWA
  home.file = lib.mkMerge (lib.mapAttrsToList (name: pwa: {
    ".local/share/applications/FFPWA-${pwa.id}.desktop" = {
      text = ''
        [Desktop Entry]
        Type=Application
        Version=1.4
        Name=${pwa.name}
        Comment=Firefox Progressive Web App
        Icon=FFPWA-${pwa.id}
        Exec=${pkgs.firefoxpwa}/bin/firefoxpwa site launch ${pwa.id} --protocol %u
        Terminal=false
        StartupNotify=true
        StartupWMClass=FFPWA-${pwa.id}
        Categories=Network;
        MimeType=x-scheme-handler/https;x-scheme-handler/http;
      '';
    };
  }) pwas);

  # Download and install icons for each PWA
  home.activation.installPwaIcons = lib.hm.dag.entryAfter ["writeBoundary"] ''
    echo "Installing PWA icons declaratively..."
    ICON_DIR="$HOME/.local/share/icons/hicolor"

    ${lib.concatMapStringsSep "\n" (pwa: ''
      # Check and install icon for ${pwa.name}
      ICON_128="$ICON_DIR/128x128/apps/FFPWA-${pwa.id}.png"

      if [ ! -f "$ICON_128" ] || [ ! -s "$ICON_128" ]; then
        echo "  Installing icon for ${pwa.name}..."

        # Download icon to temp file
        TEMP_FILE="/tmp/pwa-icon-${pwa.id}-$$"
        if ${pkgs.curl}/bin/curl -sL --max-time 10 "${pwa.icon}" -o "$TEMP_FILE" 2>/dev/null && [ -s "$TEMP_FILE" ]; then

          # Install in all standard icon sizes
          for size in 16 22 24 32 48 64 128 256 512; do
            DIR="$ICON_DIR/''${size}x''${size}/apps"
            mkdir -p "$DIR"

            # Convert with proper handling for ICO and other formats
            ${pkgs.imagemagick}/bin/convert "$TEMP_FILE[0]" \
              -background none \
              -resize ''${size}x''${size} \
              -gravity center \
              -extent ''${size}x''${size} \
              "$DIR/FFPWA-${pwa.id}.png" 2>/dev/null || \
            ${pkgs.imagemagick}/bin/convert "$TEMP_FILE" \
              -resize ''${size}x''${size} \
              "$DIR/FFPWA-${pwa.id}.png" 2>/dev/null || \
            echo "    Warning: Could not create ''${size}x''${size} icon"
          done

          echo "    ✓ Icon installed for ${pwa.name}"
        else
          echo "    ✗ Failed to download icon for ${pwa.name}"
        fi

        rm -f "$TEMP_FILE"
      else
        echo "  ✓ Icon already present for ${pwa.name}"
      fi
    '') (lib.attrValues pwas)}

    # Update icon cache
    echo "Updating icon cache..."
    ${pkgs.gtk3}/bin/gtk-update-icon-cache -f -t "$ICON_DIR" 2>/dev/null || true

    # Update desktop database
    echo "Updating desktop database..."
    ${pkgs.desktop-file-utils}/bin/update-desktop-database "$HOME/.local/share/applications" 2>/dev/null || true

    # Update KDE's system cache
    echo "Updating KDE cache..."
    ${pkgs.kdePackages.kservice}/bin/kbuildsycoca6 --noincremental 2>/dev/null || true

    echo "PWA setup complete!"
  '';
}