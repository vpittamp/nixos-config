# PWA Configuration Module for Home-Manager
# This module declaratively manages PWA desktop files and icons

{ config, lib, pkgs, ... }:

with lib;

let
  # Define all PWAs with their stable IDs and icon URLs
  pwas = {
    claude = {
      name = "Claude";
      url = "https://claude.ai";
      id = "01K63FXC9HKD0AS81V3P07NBC1";
      icon = "https://claude.ai/apple-touch-icon.png";
    };
    chatgpt = {
      name = "ChatGPT";
      url = "https://chatgpt.com";
      id = "01K63FXEJ8B7AV6A3CJB7W9DN2";
      icon = "https://cdn.oaistatic.com/_next/static/media/apple-touch-icon.82af6fe1.png";
    };
    gemini = {
      name = "Google Gemini";
      url = "https://gemini.google.com";
      id = "01K63FXAWFH80XQX260RP8FPGE";
      icon = "https://www.gstatic.com/lamda/images/gemini_favicon_f069958c85030456e93de685481c559f160ea06b.png";
    };
    github = {
      name = "GitHub";
      url = "https://github.com";
      id = "01K63FX9NK39YJS6DXX4WKBD32";
      icon = "https://github.githubassets.com/favicons/favicon-dark.png";
    };
    gmail = {
      name = "Gmail";
      url = "https://mail.google.com";
      id = "01K63FXMC4X923P036TRXDPFJ2";
      icon = "https://ssl.gstatic.com/ui/v1/icons/mail/rfr/gmail.ico";
    };
    argocd = {
      name = "ArgoCD";
      url = "https://argocd.tarnhelm.cloud";
      id = "01K63FX8DD5YH7V19VZQ6PNR5F";
      icon = "https://raw.githubusercontent.com/argoproj/argo-cd/master/docs/assets/logo.png";
    };
    backstage = {
      name = "Backstage";
      url = "https://backstage.tarnhelm.cloud";
      id = "01K63FXHP54ADP56PFRTBHB1VV";
      icon = "https://backstage.io/logo_assets/png/Icon_Teal.png";
    };
    youtube = {
      name = "YouTube";
      url = "https://youtube.com";
      id = "01K63FXJYHTC0FYYQ80364P1TE";
      icon = "https://www.youtube.com/s/desktop/12d6b690/img/favicon_144x144.png";
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