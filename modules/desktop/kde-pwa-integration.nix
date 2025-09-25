# KDE Plasma PWA Integration Module
# This module provides proper KDE integration for Progressive Web Apps
# including taskbar icons, window rules, and activity support
{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.programs.kde-pwa-integration;


  # Create proper desktop file with KDE-specific fields
  mkKdePwaDesktopFile = name: pwa: pkgs.writeTextDir "share/applications/pwa-${name}.desktop" ''
    [Desktop Entry]
    Type=Application
    Name=${pwa.name}
    Comment=${pwa.description or "Progressive Web App"}
    Icon=pwa-${name}
    Exec=${if cfg.useFirefoxPwa
      then "${pkgs.firefoxpwa}/bin/firefoxpwa site launch ${generatePwaId name}"
      else "${pkgs.firefox}/bin/firefox --new-window --name='${pwa.name}' --class='firefox-pwa-${name}' '${pwa.url}'"}
    Terminal=false
    StartupNotify=true
    StartupWMClass=firefox-pwa-${name}
    Categories=${concatStringsSep ";" pwa.categories};
    Keywords=${concatStringsSep ";" (pwa.keywords or [])}

    # KDE-specific fields for better integration
    X-KDE-SubstituteUID=false
    X-KDE-Username=
    X-DBUS-StartupType=none
    X-KDE-StartupNotify=true
  '';

  # Generate PWA ID for firefoxpwa compatibility
  generatePwaId = name: let
    hash = builtins.hashString "sha256" name;
    chars = lib.stringToCharacters hash;
  in "01" + lib.toUpper (lib.concatStrings (lib.take 24 chars));

  # Create icon theme package with proper structure
  mkPwaIconTheme = name: pwa: pkgs.stdenv.mkDerivation {
    name = "pwa-${name}-icons";

    nativeBuildInputs = [ pkgs.imagemagick ];

    # Don't unpack, we'll handle the icon directly
    dontUnpack = true;

    installPhase = ''
      mkdir -p $out/share/icons/hicolor

      # Copy or download the icon
      ICON_SRC="${if builtins.isPath pwa.icon then pwa.icon else pkgs.fetchurl {
        url = pwa.icon;
        sha256 = pwa.iconHash or (builtins.hashString "sha256" pwa.icon);
      }}"

      # Determine source format
      if [[ "$ICON_SRC" == *.svg ]]; then
        # SVG - copy as scalable and generate PNGs
        mkdir -p $out/share/icons/hicolor/scalable/apps
        cp $ICON_SRC $out/share/icons/hicolor/scalable/apps/pwa-${name}.svg

        # Generate PNG sizes for KDE taskbar
        for size in 16 22 24 32 48 64 96 128 256 512; do
          mkdir -p $out/share/icons/hicolor/''${size}x''${size}/apps
          ${pkgs.imagemagick}/bin/magick $ICON_SRC \
            -background none -resize ''${size}x''${size} \
            $out/share/icons/hicolor/''${size}x''${size}/apps/pwa-${name}.png
        done
      else
        # PNG/other - generate all sizes
        for size in 16 22 24 32 48 64 96 128 256 512; do
          mkdir -p $out/share/icons/hicolor/''${size}x''${size}/apps
          ${pkgs.imagemagick}/bin/magick $ICON_SRC \
            -background none -resize ''${size}x''${size}! \
            -gravity center -extent ''${size}x''${size} \
            $out/share/icons/hicolor/''${size}x''${size}/apps/pwa-${name}.png
        done

        # Also copy largest as base
        mkdir -p $out/share/icons/hicolor/512x512/apps
        cp $ICON_SRC $out/share/icons/hicolor/512x512/apps/pwa-${name}.png 2>/dev/null || \
          ${pkgs.imagemagick}/bin/magick $ICON_SRC \
            -background none -resize 512x512 \
            $out/share/icons/hicolor/512x512/apps/pwa-${name}.png
      fi

      # Create icon theme index
      cat > $out/share/icons/hicolor/index.theme << EOF
      [Icon Theme]
      Name=Hicolor PWA ${name}
      Comment=PWA icons for ${name}
      Directories=16x16/apps,22x22/apps,24x24/apps,32x32/apps,48x48/apps,64x64/apps,96x96/apps,128x128/apps,256x256/apps,512x512/apps,scalable/apps
      EOF
    '';
  };

  # Combine all PWA components
  mkPwaPackage = name: pwa: pkgs.symlinkJoin {
    name = "kde-pwa-${name}";
    paths = [
      (mkKdePwaDesktopFile name pwa)
      (mkPwaIconTheme name pwa)
    ];
  };

in {
  options.programs.kde-pwa-integration = {
    enable = mkEnableOption "KDE Plasma PWA integration with proper taskbar icons";

    pwas = mkOption {
      type = types.attrsOf (types.submodule {
        options = {
          name = mkOption {
            type = types.str;
            description = "Display name for the PWA";
          };
          url = mkOption {
            type = types.str;
            description = "URL of the web application";
          };
          icon = mkOption {
            type = types.either types.path types.str;
            description = "Path to local icon file or URL";
          };
          iconHash = mkOption {
            type = types.nullOr types.str;
            default = null;
            description = "SHA256 hash for remote icon (optional)";
          };
          categories = mkOption {
            type = types.listOf types.str;
            default = ["Network"];
            description = "Desktop entry categories";
          };
          keywords = mkOption {
            type = types.listOf types.str;
            default = [];
            description = "Search keywords";
          };
          description = mkOption {
            type = types.nullOr types.str;
            default = null;
            description = "Description of the PWA";
          };
        };
      });
      default = {};
      description = "Progressive Web App definitions";
    };

    useFirefoxPwa = mkOption {
      type = types.bool;
      default = false;
      description = "Use firefoxpwa tool for launching PWAs";
    };

    autoConfigureWindowRules = mkOption {
      type = types.bool;
      default = true;
      description = "Automatically create KDE window rules for PWAs";
    };
  };

  config = mkIf cfg.enable {
    # Install PWA packages
    environment.systemPackages = (mapAttrsToList (name: pwa:
      mkPwaPackage name pwa
    ) cfg.pwas) ++ (with pkgs; [
      firefox
    ] ++ optionals cfg.useFirefoxPwa [ firefoxpwa ]);

    # KDE window rules configuration (if KDE is enabled)
    # Note: Window rules need to be configured per-user or via KDE settings

    # System activation script for KDE
    system.activationScripts.kde-pwa-setup = ''
      # Update KDE's application database
      if [ -x /run/current-system/sw/bin/kbuildsycoca6 ]; then
        /run/current-system/sw/bin/kbuildsycoca6 --noincremental 2>/dev/null || true
      elif [ -x /run/current-system/sw/bin/kbuildsycoca5 ]; then
        /run/current-system/sw/bin/kbuildsycoca5 --noincremental 2>/dev/null || true
      fi

      # Update icon caches
      for theme_dir in /run/current-system/sw/share/icons/*/; do
        if [ -d "$theme_dir" ]; then
          if [ -x /run/current-system/sw/bin/gtk-update-icon-cache ]; then
            /run/current-system/sw/bin/gtk-update-icon-cache -qf "$theme_dir" 2>/dev/null || true
          fi
        fi
      done

      # Update desktop database
      if [ -x /run/current-system/sw/bin/update-desktop-database ]; then
        /run/current-system/sw/bin/update-desktop-database -q /run/current-system/sw/share/applications 2>/dev/null || true
      fi
    '';

    # XDG paths are already configured by the system
    # Icons will be found via standard paths
  };
}